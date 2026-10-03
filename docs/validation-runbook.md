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
org-owned, revocable, auditable, and not tied to a person's account.

- Repository permissions: **Contents: read and write**, **Pull requests: read and write**,
  Metadata: read.
- Install it on the probe repository, or on the whole org.
- Store its installation token as the Actions secret `COPIER_SYNC_TOKEN`.

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
| **item 3 → item 5** | the sync workflow labels its PR `template-sync`, and that label exists only once the Settings app has applied `settings.yml` |
| **P7 → item 7** | auto-merge with no required checks merges instantly rather than on green |

---

## 4. Item procedures

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

- **Expected:** `_commit: v0.1.0` (a tag, never a SHA or `HEAD`); core reports
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

## 5. Two defects found by planning, and fixed

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

---

## 6. Evidence and exit criteria

Phase 7 is complete when:

1. Every item above has a recorded result: pass, or a fix plus a re-run.
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
