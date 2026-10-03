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
| Version | `v0.1.0` |
| Local checks | `just test` — four suites, see [Working on this template](#working-on-this-template) |
| Verified against a live org | **11 of 14 items**, on a free-plan org — see the execution record in [`docs/validation-runbook.md`](docs/validation-runbook.md). The devcontainer build, the Settings app install and the fleet-wide `workflow_ref` bump are outstanding |

**Copier copies the latest Git tag, not the working tree.** A change merged to `main` does
not reach any repository generated from this template until a new tag is pushed. This is a
correctness property, not a convention: without a tag, `copier update` cannot resolve the
recorded ref at all and fails outright.

## Generate a repository

### 1. Prerequisites

| Requirement | Why |
| :--- | :--- |
| `copier` 9.0+ (`pipx install copier`) | the generator |
| An org `.github` repository with a `workflow_call` workflow | the `ci` module calls it; the `security`, `release` and `ops` modules are CI jobs |
| The **commit SHA** of that workflow | `workflow_ref` is pinned to a SHA, never a tag (ADR-0009) |
| `just` and `grep` in the generated repo | `just health` needs nothing else — no `yq`, no `jq`, no linter |

Get the SHA:

```bash
gh api repos/<org>/.github/commits/main --jq .sha
```

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
| `codeowners_team` | asked only when `contributing` is on |

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
| **deps** | the repo has any dependency | Renovate config + dependency review |
| **docs** | architecture exists | `docs/architecture.md` and an ADR index |
| **contributing** | you accept outside contributions | `CONTRIBUTING.md`, `CODEOWNERS`, branch-protection hardening |
| **env** | contributors need reproducibility | a devcontainer |
| **security** | public repo or external users | gitleaks, OpenSSF Scorecard *(requires `ci`)* |

**In an organisation, gitleaks needs a free licence key.** A personal account does not:

```bash
gh secret set GITLEAKS_LICENSE --org <org> --visibility all
```

Request one from [gitleaks.io](https://gitleaks.io) (a short form, and the key arrives by
email). Without it the job fails on every push with *"`<org>` is an organization. License key is
required."* The key is free, but it is validated by a third-party service which receives the
repository name and owner — no code leaves GitHub. Note the split: the **action** is
commercially licensed, while the **gitleaks CLI** is MIT.
| **release** | you publish a versioned artifact | `cliff.toml`, a release workflow *(requires `ci`)* |
| **ops** | the repo is deployed or running | runbooks, observability config *(requires `ci`)* |

### 4. Finish the repository

The generated repository is deliberately incomplete, and says so:

```bash
cd /path/to/new-repo
just health
```

```text
Module health
  ✅ complete   🟡 incomplete   ⏸ deferred   ⛔ declined   ❓ unrecorded
  core      🟡 incomplete
      README.md (stub)
  commits   ❓ unrecorded
  ...
26 modules need a decision — see docs/adr/0001-initial-deferrals.md
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
| `COPIER_SYNC_APP_ID` variable + `COPIER_SYNC_APP_PRIVATE_KEY` secret from a **GitHub App** | a PR opened with the default `GITHUB_TOKEN` triggers no workflows, so required checks never report and the PR is blocked forever. The token is minted per run because installation tokens expire after one hour, so it cannot be stored as a secret |
| The [Settings app](https://github.com/apps/settings) installed | the sync PR uses the `template-sync` label, which only exists once settings are applied |
| Required status checks configured | `COPIER_SYNC_AUTO_MERGE=true` means *merge when checks pass*; with no required checks it means **merge immediately** |
| Repository variables `COPIER_SYNC_ENABLED`, `COPIER_SYNC_AUTO_MERGE`, `GHAS_ENABLED` | see the runbook |

Set `COPIER_SYNC_ENABLED=false` to pause scheduled syncs for a repository. A manual
`workflow_dispatch` still runs, so a paused repository can still be synced deliberately.

If a repository has diverged from the template in a way that cannot be merged, the sync
**fails** and prints the conflicting files rather than committing conflict markers. Fix the
conflict locally and re-run.

## Working on this template

```bash
just test     # 155 checks: rendering, module gating, health, matrix, rendered artifacts
just lint     # yamllint + shellcheck
just clean
```

| Recipe | Checks |
| :--- | :--- |
| `test-template` | renders core-only and all-on, asserts module content, lints rendered YAML |
| `test-health` | the five health states against fixtures |
| `test-matrix` | 14 configurations, ownership disjointness, SHA pinning, `copier update` idempotency, answer migration |
| `test-rendered` | actionlint, zizmor, git-cliff, `just`, and the conflict guard, against rendered output |

Rendering in the suites runs from a tagged snapshot of the working tree, so the tests see
uncommitted work and are not affected by tags placed on this repository.

**After merging a change, tag it** — otherwise no generated repository receives it:

```bash
git tag -a v0.1.1 -m "..." && git push --follow-tags
```

Then read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing module content.

## Documentation

| Document | Contents |
| :--- | :--- |
| [`docs/architecture.md`](docs/architecture.md) | how this template is put together, and why |
| [`docs/adr/`](docs/adr/README.md) | the decisions, individually |
| [`BUILD_PLAN.md`](BUILD_PLAN.md) | the build plan, the verified Copier mechanics, and every correction found during the build |
| [`docs/validation-runbook.md`](docs/validation-runbook.md) | what is verified locally, and the org prerequisites for what is not |
| `repository_architecture_governance_design.md` | the original design spec this implements |
