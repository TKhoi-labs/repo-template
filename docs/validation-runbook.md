# Phase 7 — validation runbook

Phase 7 exists because the local suite proves everything that *can* be proven without a
GitHub organisation, and nothing that cannot. This document is the procedure for converting
the remaining claims into verified ones.

`just test` currently runs **155 checks**: rendering, module gating, the DAG, file ownership,
action pinning, the four-state health surface, `copier update` idempotency, answer migration,
workflow linting, and the rendered-artifact guards in §1.

---

## 1. Phase 7 splits into two halves

| | Items | Requires | Who |
| :--- | :--- | :--- | :--- |
| **7a** | conflict detection, `cliff.toml` rendering, generated `justfile` | only local tools | **done** — these are now part of `just test` |
| **7b** | everything that touches GitHub's servers, plus the devcontainer build | an org, a GitHub App, the Settings app, a container runtime | a human with org admin, roughly half a day |

### 7a — done, and it paid for itself immediately

| # | Claim | Status |
| :--- | :--- | :--- |
| a1 | A conflicted update is detectable by the sync guard | ✅ `scripts/test-rendered.sh` |
| a2 | `cliff.toml` actually renders | ✅ found a real bug — see below |
| a3 | The generated `justfile` parses, and optional modules add their recipes | ✅ `scripts/test-rendered.sh` |
| a4 | `devcontainer.json` validates | ➡ **moved to 7b item 1**: the devcontainer CLI needs a container runtime (`spawn docker ENOENT`), so it is not locally checkable here |

**a1 corrected a claim in this document.** The original text said a diverged update "produces
`.rej` files **and a failing exit**". It produces `.rej` files and exits **0**. Copier reports
success, having taken the template's version of the file and dropped the human's edit, with the
conflict recorded only in the `.rej`. That is precisely why the sync workflow needs an explicit
`find . -name '*.rej'` step: the exit code carries no signal at all. The suite now asserts that
signal, and asserts it is *absent* before any template change so the guard cannot fire falsely.

**a2 found a bug that would have broken every release.** The shipped `cliff.toml` rendered
`{{ timestamp | date(...) }}` unconditionally. `timestamp` is only populated for a *tagged*
release, so the Unreleased section failed the whole run with `Filter call 'date' failed` — and
`just changelog` renders the full changelog, so that recipe was broken. `release.yml` would have
failed too, or produced nothing, on the first real tag. Fixed by adopting git-cliff's documented
`{% if version %}` guard, with both modes now asserted: the full changelog and `--current`.

This is the argument for 7a existing: two of the four claims were wrong when written down, and
neither was visible by reading the files.

---

## 2. Prerequisites for 7b — one-time, in order

**P1. Publish the template with tags.** Without a tag, `copier update` is broken
(§6.10 of the build plan). This is not optional.

```bash
git remote add origin git@github.com:<org>/repo-template.git
git push -u origin main --follow-tags
gh api repos/<org>/repo-template/tags --jq '.[].name'   # must list v0.1.0
```

**P2. Create `<org>/.github` with a callable workflow.** The `ci` module is meaningless until
this exists. Minimal probe:

```yaml
# <org>/.github/.github/workflows/ci.yml
on: workflow_call
jobs:
  ok:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
```

It must declare `workflow_call` and must not require inputs or secrets the caller does not
pass. Record the commit: `gh api repos/<org>/.github/commits/main --jq .sha`.

**P3. Create a GitHub App for the sync token** — preferred over a PAT because it is
org-owned, revocable, auditable, and not tied to a person's account. Create it under the
**organisation** (`github.com/organizations/<org>/settings/apps/new`), not a personal
account.

- Repository permissions: **Contents: read and write**, **Pull requests: read and write**,
  Metadata: read.
- **Workflows: read and write** — without it the sync pull request is rejected the moment it
  touches `.github/workflows/`, which the template always does
  (`refusing to allow a GitHub App to create or update workflow … without workflows
  permission`).
- Webhook: **deactivate it**. Nothing consumes events, and an active webhook needs a URL.
- "Where can this app be installed": **Only on this account**, so it stays org-scoped.
- Install it on the repository or the whole org.

**Do not store the installation token as a secret.** Installation access tokens expire after
one hour, so a repository secret cannot hold one. Record the **App ID** and generate a
**private key**; the sync workflow mints a token per run:

```bash
gh variable set COPIER_SYNC_APP_ID --body "<app-id>" --repo <org>/<repo>
gh secret   set COPIER_SYNC_APP_PRIVATE_KEY < private-key.pem --repo <org>/<repo>
```

The default `GITHUB_TOKEN` must not be used: pull requests it opens do not trigger workflows,
so branch protection blocks the sync PR forever. This is the single most likely reason item 5
fails.

**P4. Install the Settings app** once for the org, with admin access to the repositories.

**P5. Set repository variables** on each probe repository:

```bash
gh variable set COPIER_SYNC_ENABLED   --body true  --repo <org>/<probe>
gh variable set COPIER_SYNC_AUTO_MERGE --body false --repo <org>/<probe>   # see P7
gh variable set GHAS_ENABLED          --body true  --repo <org>/<probe>   # private + GHAS only
```

**P6. Resolve the org Actions policy.** Confirm the pinned action SHAs are allowed, and check
whether **SHA-pinning enforcement** is enabled. If it is, every `uses:` must be a full commit
SHA — the template already satisfies this, including the reusable-workflow caller.

**P7. Configure required status checks before enabling auto-merge.** `settings.yml` sets
`required_status_checks: null`, and `gh pr merge --auto` merges **immediately** when nothing
is required. See §5.1: enabling auto-merge first means merging unreviewed and unchecked.

**P8. A container runtime** for item 1, or run that item in CI instead.

---

## 3. Execution order

```text
P1 ─► P2 ─► item 4 ─► item 2 ─► P4 ─► item 3 ─► P3 ─► item 5 ─► item 6 ─► P5·P7 ─► item 7 ─► item 8 ─► item 9 ─► item 10
item 1 (devcontainer) is independent of everything above
```

Three gates are worth stating explicitly, because each fails in a confusing way if skipped:

| Gate | Why |
| :--- | :--- |
| **P1 → item 5** | an untagged template makes `copier update` fail with `pathspec … did not match any file(s) known to git` |
| **item 3 → item 5** | ~~a gate~~ **not a gate** — see §5.7. The label is defined by `settings.yml`, but `create-pull-request` **creates a missing label itself**, so the sync PR opens and its checks run without the Settings app. The app supplies colour and description, not existence |
| **P7 → item 7** | auto-merge with no required checks merges instantly rather than on green |

---

## 4. Item procedures

### Execution record — 2026-10-03, organisation `TKhoi-labs`

Run against a new organisation on the **free** plan, template `v0.2.1`. Probes: `probe-min`
(`core` + `commits` + `ci` + `deps`), `probe-allon` (all modules), `probe-conflict`
(deliberately diverged). Items 5–7 were only reachable after two template fixes (§5.3, §5.4).

| Item | Result | Evidence |
| :--- | :--- | :--- |
| 1 devcontainer | **not run** — no container runtime on this machine | — |
| 2 tagged copy | **pass** | `_commit: v0.1.1` over `gh:TKhoi-labs/repo-template`; core 🟡 for `README.md`; six ❓; exit 1 |
| 3 Settings app | **not run** — web-UI install; the gate is softer than this document claimed (§5.7) | label auto-created, no colour or description |
| 4 SHA resolves | **pass** | `ci / ci` check ran and passed in both probes |
| 5 sync PR triggers CI | **pass** | PR #1 in `probe-min`, author `app/tkhoi-labs-copier-sync`; commitlint and `ci / ci` **ran on it** |
| 6 divergence fails | **pass** | `probe-conflict`: `##[error]Repository has diverged.` + `./CONTRIBUTING.md.rej`; PR and auto-merge steps skipped; **0 PRs created** |
| 7 auto-merge | **pass** | PR #1 merged; `probe-min` main advanced to `v0.2.1` |
| 8 fleet `workflow_ref` bump | **not run live** — verified locally in `test-matrix.sh` | — |
| 9 release notes | **pass** | release `v0.1.0`; notes render `## [0.1.0] - 2026-10-03` |
| 10 Scorecard publishes | **pass** | score 5.5 published to the OpenSSF API; **Pinned-Dependencies 10/10** — "4 out of 4 third-party GitHubAction dependencies pinned" — with **no finding for the reusable-workflow caller** |
| P1 publish with tags | **pass** | `v0.1.0` … `v0.2.1` |
| P2 shared workflow | **pass** | `TKhoi-labs/.github`, SHA `19f45b68e4ca46d42d881caee72f998f353ccaaf` |
| P5 variables | **pass** | `COPIER_SYNC_ENABLED`, `COPIER_SYNC_AUTO_MERGE`, `GHAS_ENABLED` |
| P6 org Actions policy | **pass** | `enabled_repositories: all`, `allowed_actions: all`, **`sha_pinning_required: false`** |
| P7 required checks | **pass** | `ci / ci` required on both probes; auto-merge then merged on green |

Two by-products worth keeping. **Item 9 is the live proof that the `cliff.toml` fix in §1
works** — the original would have died on that tag. And **item 10 is the live proof of
ADR-0009**, including that Scorecard now inspects job-level `uses:`, which is the reason the
reusable-workflow caller is pinned to a SHA and not a tag.

Item 7 also confirmed §5.1 from the other direction: the sync PR merged **while
dependency-review was failing**, because auto-merge honours only *required* checks. That is
exactly why "no required checks" means "merge immediately".

### Item 1 — the devcontainer builds

The least verified file in the repository: valid JSON, structurally sound, never built.

```bash
copier copy --vcs-ref v0.1.0 gh:<org>/repo-template /tmp/dcprobe   # module_env=true
code /tmp/dcprobe            # "Reopen in Container"
# inside the container:
just --version && git-cliff --version && copier --version && just health
```

- **Expected:** all four succeed.
- **Failure signature:** a feature reference that does not resolve, `sudo` unavailable in
  `postCreateCommand`, or the `just` installer writing to a directory not on `PATH`.
- **Evidence:** the command output. **Fix:** adjust `postCreateCommand`; consider promoting
  this to a CI job using the devcontainer CLI.

### Item 2 — a tagged copy produces a working repository

```bash
copier copy --vcs-ref v0.1.0 gh:<org>/repo-template /tmp/probe
cd /tmp/probe && git init && git add -A && git commit -m "chore: initial"
just health
```

- **Expected:** `_commit:` holds the **latest template tag** (never a SHA or `HEAD`); core reports
  `🟡 on — incomplete` for `README.md`; every disabled module reports `❓`; exit code 1.
- **Failure signature:** `_commit` holding a SHA, or `just health` exiting 0 on a fresh repo.
- **Evidence:** `.copier-answers.yml`, the health table, the exit code.

### Item 3 — the Settings app applies `settings.yml`

Push a change to `.github/settings.yml` on the probe repository.

- **Expected:** labels appear, merge strategy changes, branch protection is applied, with no
  per-repository work after the initial app install.
- **Failure signature:** the app silently rejects a malformed file, so labels referenced by
  workflows (`template-sync`, `dependency`) do not exist.
- **Evidence:** `gh label list --repo <org>/<probe>` and the branch protection API output.

### Item 4 — the shared workflow SHA resolves

```bash
gh api repos/<org>/.github/commits/<sha> --jq .sha
```

- **Expected:** the SHA is returned.
- **Failure signature:** a `workflow_ref` that was force-pushed away, or belongs to a private
  repository the caller cannot read.
- **Evidence:** the API response.

### Item 5 — the sync PR triggers CI

```bash
gh workflow run copier-sync --repo <org>/<probe>
gh pr list --head chore/copier-sync --repo <org>/<probe>
gh pr checks <number> --repo <org>/<probe>
```

- **Expected:** a PR appears **and its checks run**. Re-running the workflow produces no new
  commit and no new PR.
- **Failure signature:** a PR with no checks — the `GITHUB_TOKEN` deadlock (P3).
- **Evidence:** the PR URL with a green check list, plus the second run's empty diff.

### Item 6 — a diverged repository fails instead of merging badly

Hand-edit a generated file in the probe, commit, then run `copier-sync` after the template has
also changed that file.

- **Expected:** the workflow fails with *"Template sync conflicted"*, prints `.rej` files, and
  opens no PR.
- **Failure signature:** merge markers committed inside a file, or a PR opened regardless.
- **Evidence:** the failed run log.

### Item 7 — canary rollout and auto-merge

1. Sync one repository and review the PR by hand.
2. Ensure required status checks are configured (P7), then set `COPIER_SYNC_AUTO_MERGE=true`.
3. Confirm the next sync PR auto-merges **only after checks pass**.
4. Set `COPIER_SYNC_ENABLED=false`; confirm the schedule no longer syncs while
   `gh workflow run` still does.

- **Expected:** as above.
- **Failure signature:** a merge before checks report, or a switch that does not switch.
- **Evidence:** the merged PR with its checks, and two scheduled runs, one before and one
  after disabling.

### Item 8 — a `workflow_ref` bump reaches the fleet

Verified locally in `test-matrix.sh` against real tags (`v0.1.0` → `v0.2.0`). Remaining: the
same across a live sync.

- **Expected:** the sync PR changes the SHA in both `.copier-answers.yml` and
  `.github/workflows/ci.yml`.
- **Failure signature:** the fleet stays on the old shared workflow because a migration's
  `version:` did not compare against the recorded tag.

### Item 9 — release notes on a real tag

```bash
git tag v0.0.1 && git push origin v0.0.1
```

- **Expected:** a GitHub release whose notes are grouped by Conventional Commit type.
- **Failure signature:** `git-cliff`'s Tera template failing to render, or `gh release create`
  lacking `contents: write`.

### Item 10 — Scorecard publishes a result

Confirm the first scheduled run uploads SARIF and that Pinned-Dependencies is satisfied.

- **Expected:** no Pinned-Dependencies finding, in particular **none for the reusable-workflow
  caller** in `ci.yml` — the reason that reference is a commit SHA (ADR-0009).
- **Failure signature:** a finding for the caller (pinning regression), or a hard failure
  because the org's Actions policy enforces SHA pinning and something is not pinned.
- **Evidence:** the Scorecard run URL, the SARIF upload, the check result.

---

## 5. Defects found during phase 7, and their status

### 5.1 Auto-merge with no required checks merges immediately — **resolved by documentation**

`settings.yml` sets:

```yaml
required_status_checks: null
```

`gh pr merge --auto` merges as soon as required checks pass **and** required approvals are
met. With no required checks and `module_contributing` off (0 required approvals), that is
*immediately* — so `COPIER_SYNC_AUTO_MERGE=true` does not mean "merge on green", it means
"merge without looking".

The template cannot name the check itself: it depends on the shared workflow's job names,
which live in another repository.

**Resolution:** auto-merge stays opt-in and off by default, so the safe path is the default
path, and the prerequisite is now stated in the workflow itself as well as here (P7 and
item 7). A questionnaire field was rejected: a wrong check name blocks every pull request
forever on a check that never reports.

A runtime guard was also considered and rejected: reading branch protection needs admin or a
fine-grained Administration permission that `COPIER_SYNC_TOKEN` may not have, so the guard
would itself be an untested failure mode. If it is added later, it must be verified against a
real token first.

**Until required checks exist, keep `COPIER_SYNC_AUTO_MERGE=false`.**

### 5.2 Scorecard on a private repository — **fixed, and the original claim was wrong**

The first version of this document asserted that `publish_results: true` fails on private
repositories. That was **not accurate**. The action README states private repositories are
supported when the organisation has GitHub Advanced Security, and documents a different,
real failure:

> Additional permissions for private repositories … Without them you may see errors like
> `Resource not accessible by integration` (e.g., during GraphQL ListCommits)

The job was missing exactly those reads. It is also worth recording that this workflow is
subject to the OpenSSF API's publishing restrictions, which **fail the run** rather than
warning when violated: no workflow-level env or defaults, no workflow-level write
permissions, only the scorecard job may hold `id-token: write`, no job-level env or
containers, an Ubuntu runner, and only five approved actions in that job.

The template already satisfied those restrictions — the earlier zizmor fix that reduced
workflow-level permissions to `{}` is what made it compliant — but nothing said so, so an
innocent extra step in that job would have broken publishing with a confusing error.

**Fix applied:** added `issues: read`, `pull-requests: read` and `checks: read`; made
`publish_results` visibility-dependent so a private repository analyses and uploads SARIF
without publishing to a public dataset; and documented the restrictions in the workflow.

### 5.3 Installation tokens expire, so the sync token could not be stored — **fixed in `v0.2.0`**

This document told operators to *"store its installation token as the Actions secret
`COPIER_SYNC_TOKEN`"*. That is **impossible**. GitHub's documentation says it twice:

> The installation access token will expire after 1 hour.

A one-hour token cannot be a repository secret. Nothing caught it because the sync had never
run against a real App: the first live run reached `Open a pull request` and stopped with
`Input 'token' not supplied`.

**Fix applied:** the workflow mints a token per run with `actions/create-github-app-token`,
pinned to a commit SHA per ADR-0009. Deployment changes from one secret to an app id variable
plus a private key secret:

```bash
gh variable set COPIER_SYNC_APP_ID          --body "<app-id>" --repo <org>/<repo>
gh secret   set COPIER_SYNC_APP_PRIVATE_KEY < private-key.pem --repo <org>/<repo>
```

The minted token is scoped to the repository being synced and to `contents` +
`pull-requests` write, rather than inheriting the installation's blanket permissions
(`zizmor: github-app`, reported at high severity).

### 5.4 The generated CODEOWNERS was invalid — **fixed in `v0.2.1`**

`codeowners_team` defaults to `@<org>/maintainers`, and nothing creates that team. GitHub then
reports the file as broken:

```text
"kind":"Unknown owner","message":"Unknown owner on line 2: make sure the team
@TKhoi-labs/maintainers exists, is publicly visible, and has write access to the repository"
```

The requirement is stronger than "the team must exist": it must also be **visible** and have
**write access**. A branch protection rule requiring code owner review then blocks every pull
request, because GitHub cannot resolve the owner at all.

**Fix applied:** the payload's `CONTRIBUTING.md` now states the requirement where the person
who must satisfy it will read it, and points out that an owner which does not exist is worse
than none — the file is *invalid* rather than advisory.

Still open as a design question: whether the default should remain a team (a guess that may
not exist) or become the organisation handle, which is always a valid CODEOWNERS owner.

### 5.5 `gitleaks` requires a licence for organisations — **OPEN**

Every push in an org-owned repository fails:

```text
[TKhoi-labs] is an organization. License key is required.
##[error]🛑 missing gitleaks license. Go grab one at gitleaks.io and store it as a GitHub
Secret named GITLEAKS_LICENSE.
```

`gitleaks-action` is free for personal accounts and licensed for organisations. The `security`
module therefore ships a workflow that fails out of the box for exactly the audience its own
condition describes ("public repo or external users"). Reading and linting the workflow could
never reveal this; only running it in an org could.

| Option | Effect |
| :--- | :--- |
| Take a licence; set secret `GITLEAKS_LICENSE` | keeps the action; adds a paid dependency and one more prerequisite |
| Run the `gitleaks` **CLI** in the workflow | no licence, no third-party action, one more tool to install and pin |
| Make the job conditional on the secret existing | module appears to work while scanning nothing — the precise failure mode this build has rejected at every other step |

### 5.6 `dependency-review` fails on a fresh organisation — **OPEN**

The workflow's guard is:

```yaml
if: ${{ !github.event.repository.private || vars.GHAS_ENABLED == 'true' }}
```

with the comment *"Public repositories always have it"*. That is wrong. The run failed with:

```text
##[error]Dependency review is not supported on this repository.
Please ensure that Dependency graph is enabled
```

Root cause, read from the organisation object:

```text
dependency_graph_enabled_for_new_repositories = False
```

New organisations disable the dependency graph for new repositories. Being public is not
sufficient, and adding a dependency manifest does not help — the setting is the gate, and
`security_and_analysis` does not report `dependency_graph` for a public repository at all, so
it cannot be enabled per repository through the API.

| Option | Effect |
| :--- | :--- |
| Enable the graph org-wide; document it as a prerequisite | module works; adds an org-admin step, and does not retro-fit existing repositories |
| Guard the job on a variable, like `GHAS_ENABLED` already guards the private case | explicit skip instead of a confusing failure; the guard must be set honestly or it hides a real gap |
| Drop the workflow from the `deps` module | Renovate still covers updates; loses vulnerability review on pull requests |

### 5.7 Corrections to this runbook, from running it

| Was | Now |
| :--- | :--- |
| P3 listed Contents, Pull requests and Metadata | also **Workflows: read and write**. Without it the sync pull request is rejected the moment it touches `.github/workflows/`, which the template always does (`refusing to allow a GitHub App to create or update workflow … without workflows permission`) |
| "item 3 gates item 5: the `template-sync` label only exists once the Settings app has run" | **not a gate.** `create-pull-request` created the missing label; it appeared with an empty description, which is what an auto-created label looks like |
| item 2 expected `_commit: v0.1.0` | the **latest tag**, whatever that is. It read `v0.1.1` when this ran. Hard-coding a version in an expectation is how that line went stale in a day |
| *assumed during the run:* required status checks block direct pushes to a protected branch | they **warn and permit** when `enforce_admins: false`. GitHub printed `Required status check "ci / ci" is expected` and the admin push succeeded — worth knowing before concluding a check is enforced |

---

## 6. Evidence and exit criteria

Phase 7 is complete when:

1. Every item above has a recorded result: pass, or a fix plus a re-run. The record is the
table in §4.
2. The evidence is attached to the tracking issue (§9) — a run URL, command output, or
   screenshot per item.
3. This document is updated so that every remaining item is either ticked with a link to its
   evidence, or reclassified with the reason it cannot be checked.
4. Any item that turned out to be locally checkable has been **promoted into `just test`**,
   so it cannot regress.

A claim without attached evidence stays unverified, and this document says so.

---

## 7. What to do with a failure

Failures here are more valuable than passes. Route each one the way the rest of this build has
been run:

| Kind of failure | Where it goes |
| :--- | :--- |
| A local-checkable property that slipped through | a new assertion in `just test` |
| A decision that was wrong | a new ADR, or an amendment to an existing one |
| A defect in the template | a plan correction, as in §10.1 |
| An environment quirk (org policy, entitlement) | a prerequisite note in §2 |

---

## 8. Fleet rollout staging

Do not point the sync at every repository on day one.

1. **One canary.** A repository nobody depends on. Sync it, review the PR by hand, check that
   the Settings app applied the settings diff.
2. **A small cohort.** Five to ten repositories, different module combinations, so the
   `all-on` and `core-only` shapes are both exercised in the wild.
3. **Widen.** At this point auto-merge may be enabled, if `required_status_checks` names the
   CI check (§5.1).
4. **Watch the volume.** One sync PR per repository per template release. If that is too much
   to review, batch by syncing on a schedule rather than per release, and lean on auto-merge
   for template-only diffs.

---

## 9. Tracking

Create one bootstrap issue in the template repository, with the item list from §4 as a task
list, and link the evidence as it is collected. This mirrors the per-repository workflow in
the source design (step 5): the checklist lives somewhere durable, not in someone's head.
