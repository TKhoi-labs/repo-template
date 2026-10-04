# repo-template

A [Copier](https://copier.readthedocs.io) template that scaffolds a governed GitHub
repository: a chosen set of modules, a health surface that reports what is still
unfinished, and a scheduled sync that keeps repositories aligned with the template.

It exists because the alternative is a checklist. A checklist is followed once, at
creation, and then decays. Here, the module set is recorded in the repository itself
(`.copier-answers.yml`), `just health` reports the gap between what is enabled and what is
still a stub, and a workflow opens a pull request when the template changes.

## Status

| | |
| :--- | :--- |
| Version | `v0.5.3` |
| Local checks | `just test` — six suites, see [Working on this template](#working-on-this-template) |
| Adapts to the account | renders for an **organisation** or a **personal account**; asserted for both, since the shared workflow, the CODEOWNERS owner and the security features differ |
| Can be left | `just eject` in a generated repository detaches it: no sync, no module tracking, nothing generated any more |
| Verified against a live org | **14 of 15 items fully verified**, with item 3 partly: the Settings app applies the repository feature block and the labels, but not `branches:` (§5.10). All on a free-plan org — see the execution record in [`docs/validation-runbook.md`](docs/validation-runbook.md) |

**Copier copies the latest Git tag, not the working tree.** A change merged to `main` does
not reach any repository generated from this template until a new tag is pushed. This is a
correctness property, not a convention: without a tag, `copier update` cannot resolve the
recorded ref at all and fails outright.

## Generate a repository

### 1. Prerequisites

| Requirement | Why |
| :--- | :--- |
| `copier` 9.0+ (`pipx install copier`) | the generator |
| An org or user `.github` repository with a `workflow_call` workflow | the `ci` module calls it; the `security`, `release` and `ops` modules are CI jobs |
| The **commit SHA** of that workflow | `workflow_ref` is pinned to a SHA, never a tag (ADR-0009) |
| `just` and `grep` in the generated repo | `just health` needs nothing else — no `yq`, no `jq`, no linter |

Get the SHA:

```bash
gh api repos/<org>/.github/commits/main --jq .sha
```

If that repository has no callable workflow yet, [runbook P2](docs/validation-runbook.md) has a
minimal `workflow_call` workflow to start from.

**On a personal account**, the same flow works with a few translations:

- Set `org_slug` to your username. `<you>/.github` fills the shared-workflow role, so `ci` still
  resolves; if you would rather not maintain one, turn `ci` off — which also turns off
  `security`, `release` and `ops`, because they are CI jobs.
- `codeowners_team` can stay empty, and on a personal account it normally should: the default is
  no owner, which generates no `.github/CODEOWNERS` at all. A valid owner is a team or a user — an
  organisation handle on its own is not one, and a personal account has no teams — so nothing is
  guessed. Naming yourself is legal but does no work: you cannot approve your own pull request.
- Lower `required_approving_review_count` from `2`. You cannot approve your own pull request on
  a personal repository, so a rule asking for two approvals blocks every merge.
- `deps`: dependency review is free on public repositories; a **private** personal repository
  needs GitHub Advanced Security, and the job is skipped otherwise (`GHAS_ENABLED`).
- `security`: gitleaks needs no licence on a personal account, and Scorecard does not publish
  results for a private repository.
- Branch protection on a **private** personal repository needs a paid plan; public is free.
- The sync GitHub App is created under your account and installed on it; `COPIER_SYNC_*` live on
  the repository rather than the organisation.

### 2. Copy the template

```bash
copier copy --trust gh:<org>/repo-template /path/to/new-repo
```

Copier asks for:

| Question | Notes |
| :--- | :--- |
| `project_name` | defaults to the destination directory name |
| `project_slug` | derived from `project_name`; lowercase, hyphenated |
| `description` | one line |
| `org_slug` | **required if `ci` is on** — the shared workflow lives in `<org>/.github` |
| `workflow_ref` | **required if `ci` is on** — a full 40-character commit SHA. A tag or branch is rejected with a validation error, deliberately |
| `license` | `MIT`, `Proprietary`, or `None` |
| `copyright_holder` | who the LICENSE names; defaults to `org_slug`; skipped when `license` is `None` |
| `license_year` | defaults to `2026`; skipped when `license` is `None` |
| `module_commits`, `module_ci`, `module_deps`, `module_docs`, `module_contributing`, `module_env`, `module_security`, `module_release`, `module_ops` | the nine modules — see the table below |
| `codeowners_team` | asked only when `contributing` is on; **empty by default**, and empty means no `.github/CODEOWNERS` is generated, because no owner is valid for both an organisation and a personal account |

If you do name a team, it has to exist, be visible and be granted write access before GitHub will
accept the file — none of which this repository can derive, and the most common way to get it
wrong is to name a team nobody created:

```bash
gh api -X POST /orgs/<org>/teams -f name=maintainers -f privacy=closed
gh api -X PUT /orgs/<org>/teams/maintainers/repos/<org>/<repo> -f permission=push
```

`privacy: closed` is "visible to the org"; a `secret` team cannot own files. Write access is per
repository, so grant it on each one that carries the file. Check any repository with
`gh api repos/<org>/<repo>/codeowners/errors` — it answers `Unknown owner` until all three hold.

The template refuses to render an inconsistent answer set. `--defaults` will **fail** on
purpose, because `ci` defaults to on and `workflow_ref` has no safe default:

```text
Validation error for question 'module_ci':
module_ci requires workflow_ref to be a full 40-character commit SHA.
```

Enable a module only when its condition is true. A module with no trigger is maintenance
you now own, permanently.

### 3. The module set

`core` is always present. The rest are opt-in.

| Module | Enable when | Adds |
| :--- | :--- | :--- |
| **core** | always | `justfile`, `scripts/health.sh`, `lefthook.yml`, `settings.yml`, issue forms, the deferrals ADR |
| **commits** | you want enforced history | commitlint config + a `commitlint` workflow |
| **ci** | any automated check at all | a thin caller of the org's shared workflow |
| **deps** | the repo has any dependency | Renovate config + dependency review. The config only works with the [Renovate app](https://github.com/apps/renovate) installed — the file alone updates nothing, which is the gap this template had itself until it added its own `renovate.json`. **In an organisation**, dependency review also needs the org's Advanced Security features applied to repositories — see below |
| **docs** | architecture exists | `docs/architecture.md` and an ADR index |
| **contributing** | you accept outside contributions | `CONTRIBUTING.md`, branch-protection hardening, and `.github/CODEOWNERS` **only when you name an owner** |
| **env** | contributors need reproducibility | a devcontainer |
| **security** | public repo or external users | gitleaks, OpenSSF Scorecard *(requires `ci`)* |
| **release** | you publish a versioned artifact | `cliff.toml`, a release workflow *(requires `ci`)* |
| **ops** | the repo is deployed or running | runbooks, observability config *(requires `ci`)* |

**In an organisation, gitleaks needs a free licence key.** A personal account does not:

```bash
gh secret set GITLEAKS_LICENSE --org <org> --visibility all
```

Request one from [gitleaks.io](https://gitleaks.io) (a short form, and the key arrives by
email). Without it the job fails on every push with *"`<org>` is an organization. License key is
required."* The key is free, but it is validated by a third-party service which receives the
repository name and owner — no code leaves GitHub. Note the split: the **action** is
commercially licensed, while the **gitleaks CLI** is MIT.

**In an organisation, dependency review also needs the org's security features enabled.**
Free for public repositories is not the same as switched on. In the organisation's **Advanced
Security → Global settings**, apply Secret scanning, Code scanning and Dependabot to **All
repositories**. Until that is done the job fails with a message that names a setting you cannot
find:

```text
Dependency review is not supported on this repository.
Please ensure that Dependency graph is enabled
```

There is no *Dependency graph* toggle anywhere in the UI, and a public repository has nothing to
enable locally — the graph arrives with Dependabot, which is why applying the features org-wide
is the fix.

**Code scanning and code quality are not managed here, deliberately.** Both complement this
module but cannot be part of it, because both are settings rather than files: no repository
workflow can enable either one — the automatic token is refused with `403`, and code scanning's
state cannot even be *read* — and a `codeql.yml` shipped alongside an org-wide default setup is
disabled by GitHub **without failing**.

Enable code scanning in the organisation's **Advanced Security → Global settings**. Code quality
is enabled per repository when the organisation lets repositories decide; note that it is
generally available on **GitHub Team and Enterprise Cloud**, not on Free. The reasoning, the
evidence and the revisit trigger are in
[ADR-0010](docs/adr/0010-treat-code-scanning-and-code-quality-as-organisation-state.md).

### 4. Finish the repository

The generated repository is deliberately incomplete, and says so:

```bash
cd /path/to/new-repo
just health
```

```text
Module health

  ✅ complete   🟡 incomplete   ⏸ deferred   ⛔ declined   ❓ unrecorded
  Decisions live in docs/adr/0001-initial-deferrals.md

  🟡  core         on — incomplete: README.md (stub)
  ❓  commits      unrecorded — enable the module, or record a decision for it
  ...
0 complete, 1 incomplete, 0 deferred, 0 declined, 9 unrecorded
health: 9 module(s) undecided.
```

Two things to do, in order:

1. **Replace `README.md`.** It is a stub that announces itself. `just health` reports `core`
   as incomplete until you do.
2. **Fill in `docs/adr/0001-initial-deferrals.md`.** Every module you did not enable needs a
   row saying `deferred — trigger: <what has to happen first>` or
   `declined — reason: <why not>`. A row left as `TODO` keeps `just health` failing.

`just health` exits `1` while any module is unrecorded, so the pre-push hook blocks the first
push until that file is honest. That is the point. To disable the hook:

```bash
git push --no-verify
```

### 5. The health surface

One command, five states, derived from three sources of truth.

| Glyph | State | Source |
| :--- | :--- | :--- |
| `✅` | on — complete | no stub sentinel in any of the module's files |
| `🟡` | on — incomplete | a stub sentinel is still present |
| `⏸` | deferred | an ADR-0001 row **with a trigger** |
| `⛔` | declined | an ADR-0001 row **with a reason** |
| `❓` | unrecorded | off in the answers, absent from ADR-0001 → exits non-zero |

Exit codes: `0` everything complete or recorded, `1` something is unrecorded or the answers
file is missing, `2` something is enabled but unfinished.

## Keeping a repository in sync

Each generated repository carries `.github/workflows/copier-sync.yml`. It runs on a schedule,
runs `copier update`, and opens or updates a pull request on `chore/copier-sync`.

| Prerequisite | Why |
| :--- | :--- |
| `COPIER_SYNC_APP_ID` variable + `COPIER_SYNC_APP_PRIVATE_KEY` secret from a **GitHub App** | a PR opened with the default `GITHUB_TOKEN` triggers no workflows, so required checks never report and the PR is blocked forever. The token is minted per run because installation tokens expire after one hour, so it cannot be stored as a secret. The App needs **Contents**, **Pull requests** and **Workflows** read/write: without the last, the sync PR is rejected the moment it touches `.github/workflows/` ([runbook §5.3](docs/validation-runbook.md)) |
| The [Settings app](https://github.com/apps/settings) installed | optional, and narrower than it looks: it applies the `repository:` feature block and the label colours and descriptions, but **not** the `branches:` protection block ([runbook §5.10](docs/validation-runbook.md)), and installing it does nothing to existing repositories until something pushes `settings.yml`. The sync PR does not depend on it — `create-pull-request` creates a missing `template-sync` label itself |
| Required status checks configured | `COPIER_SYNC_AUTO_MERGE=true` means *merge when checks pass*; with no required checks it means **merge immediately** |
| Repository variables `COPIER_SYNC_ENABLED`, `COPIER_SYNC_AUTO_MERGE`, `GHAS_ENABLED` | see the runbook |

**The sync never deletes files.** `copier update` renders the new template over the old one but
removes nothing, so turning a module off, or clearing an answer that used to generate a file,
stops that file being rendered and leaves the existing copy in place. Delete it in the same
commit. Verified in `scripts/test-matrix.sh` by turning a module off and watching its files
survive the update.

**A repository can leave.** `just eject` in a generated repository detaches it: the answers file,
the sync workflow, the health report and the generation-time ADR go, and the references to them
in the justfile, the git hooks, `CODEOWNERS` and the ADR index are edited away. Everything else
stays, prose it cannot safely rewrite is listed for the maintainer, and `copier update` no longer
runs afterwards. See [ADR-0011](docs/adr/0011-provide-an-exit-from-the-template.md) and
`scripts/test-eject.sh`, which runs the whole thing against disposable renders.

### Branch protection is applied by hand

`.github/settings.yml` declares its protection block, and the Settings app does **not** currently
apply it ([runbook §5.10](docs/validation-runbook.md)) — nothing reports that. Apply it from the
file's values until that changes, substituting the check name if your organisation renamed the
shared workflow:

```bash
gh api -X PUT repos/<owner>/<repo>/branches/main/protection --input - <<'JSON'
{
  "required_pull_request_reviews": {"required_approving_review_count": 2, "dismiss_stale_reviews": true},
  "required_status_checks": {"strict": false, "contexts": ["ci / ci"]},
  "enforce_admins": false,
  "restrictions": null
}
JSON
```

The check name is `"<workflow> / <job>"` from the shared reusable workflow, which uses `ci` for
both (`ci / ci`). Requiring a check that never reports blocks every pull request, so if you disable
the `ci` module, set `required_status_checks` to `null` instead — which is what the template
generates in that case.

Set `COPIER_SYNC_ENABLED=false` to pause scheduled syncs for a repository. A manual
`workflow_dispatch` still runs, so a paused repository can still be synced deliberately.

If a repository has diverged from the template in a way that cannot be merged, the sync
**fails** and prints the conflicting files rather than committing conflict markers. Fix the
conflict locally and re-run.

## Working on this template

```bash
just test     # every check: rendering, module gating, health, matrix, rendered artifacts, docs, the exit path
just lint     # yamllint + shellcheck + shfmt
just clean
```

| Recipe | Checks |
| :--- | :--- |
| `test-template` | renders core-only and all-on, asserts module content, lints rendered YAML |
| `test-health` | the five health states against fixtures, including the CODEOWNERS answer gating its file |
| `test-matrix` | 15 configurations including a personal account, ownership disjointness, SHA pinning, `copier update` idempotency, answer migration |
| `test-rendered` | actionlint, zizmor, git-cliff, `just`, and the conflict guard, against rendered output |
| `test-docs` | the README's own commands, run; every question, module and ADR checked against the tree; the `Version` row checked against the tags |
| `test-eject` | what `scripts/eject.sh` removes, what it keeps, and that a detached repository cannot be updated back into a generated one |

CI runs the same suites on every push and pull request
(`.github/workflows/template-ci.yml`) — so a change is checked without anyone remembering to run
them — plus a separate job that builds the devcontainer and verifies its toolchain, the one
thing that cannot be checked locally without a container runtime.

**The pins are kept fresh by Renovate.** `renovate.json` covers the action pins in this repository
*and* in the payload's `.jinja` workflows — which the built-in manager cannot read, so those are
the pins Renovate would otherwise never have seen — plus the CLI versions inside `pipx install`
and `go install` command strings. It does its work once the
[Renovate app](https://github.com/apps/renovate) is installed on the organisation; until then the
configuration is inert.

A read-only lookup on 2026-10-04, before that config existed, found **four of the seven action pins
behind their newest major**: `actions/checkout` v4→v7, `peter-evans/create-pull-request` v6→v8,
`gitleaks/gitleaks-action` v2→v3, and `actions/dependency-review-action` v4→v5. Those are the pins
every generated repository receives, so the cost of having no updater was never theoretical. When
Renovate raises a pull request for a payload pin, the change reaches consumers through a sync, so
reviewing it means reviewing what a generated repository will run — `test-rendered` lints the
rendered workflows, which catches structure and security findings but not changed behaviour.

Rendering in the suites runs from a tagged snapshot of the working tree, so the tests see
uncommitted work and are not affected by tags placed on this repository.

**After merging a change, tag it** — otherwise no generated repository receives it:

```bash
git tag -a v0.5.3 -m "..." && git push --follow-tags
```

Bump the `Version` row at the top of this README in the same commit. `test-docs` asserts that it
is not behind the latest tag, and CI runs *after* the tag exists — which is precisely when the
check fires and a local run cannot see it.

Then read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing module content.

## Documentation

| Document | Contents |
| :--- | :--- |
| [`docs/architecture.md`](docs/architecture.md) | how this template is put together, and why |
| [`docs/adr/`](docs/adr/README.md) | the decisions, individually |
| [`BUILD_PLAN.md`](BUILD_PLAN.md) | the build plan, the verified Copier mechanics, and every correction found during the build |
| [`docs/validation-runbook.md`](docs/validation-runbook.md) | what is verified locally, and the org prerequisites for what is not |
| `repository_architecture_governance_design.md` | the original design spec this implements |
