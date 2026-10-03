# Architecture

This document describes **this template repository**. A repository generated from it gets its
own `docs/architecture.md`, rendered from the module answers.

## The problem it solves

Files that should be identical in every repository — CI entry points, linters, PR templates,
settings-as-code — diverge, because each repository was copied once and then edited locally.
A checklist is followed at creation and then decays.

So the design goal is not "generate a repository". It is **make the gap between intention and
reality visible, continuously**. That is what the health surface is for.

## Three sources of truth, one report

```text
                  .copier-answers.yml
                  which modules are ON          ← recorded at generation time
                            │
   docs/adr/0001-initial-deferrals.md           ← written by a human, enforced
   why the OFF modules are off (trigger/reason)   (a TODO row fails `just health`)
                            │
   TEMPLATE-STUB sentinel in every file          ← written by whoever scaffolds
   is this enabled module still a stub?            (removed when the file is authored)
                            │
                            ▼
                    just health ──► ✅ 🟡 ⏸ ⛔ ❓ and an exit code
```

Three independent sources, none of which can be derived from the others. That is the whole
architecture; everything below exists to support it.

`scripts/health.sh` reads all three with `grep` and coreutils only. It deliberately does not
depend on `yq`, `jq`, or a linter — the stub-detection engine in the original spec was
repolinter, which was archived in 2026 (ADR-0006). A dependency-free read-only check cannot be
unmaintained out from under us.

## Layout: what renders and what does not

```text
repo-template/
├── copier.yml                    the questionnaire (10 modules + identity)
├── template/                     ── THE PAYLOAD. Everything here is rendered.
│   ├── justfile.jinja            core owns it; other modules contribute recipes
│   ├── scripts/health.sh.jinja   core — the four-state report
│   ├── .github/
│   │   ├── settings.yml.jinja    core
│   │   └── workflows/
│   │       ├── copier-sync.yml   core — the scheduled update
│   │       ├── {% if module_ci %}ci.yml{% endif %}.jinja
│   │       └── … one per module that ships a workflow
│   └── docs/adr/
│       ├── 0000-template.md      core
│       └── 0001-initial-deferrals.md.jinja   rendered from the answers
├── README.md  CONTRIBUTING.md    ── tooling. Never rendered.
├── docs/  BUILD_PLAN.md
├── scripts/                      this repo's four test suites
└── justfile                      this repo's own recipes
```

`_subdirectory: template` (ADR-0002) draws the line. It is structural, not an exclusion list:
there is no way to accidentally ship `BUILD_PLAN.md` to a customer, and no way to accidentally
keep a payload file out.

## The questionnaire

`copier.yml` asks for identity (name, slug, description, org, `workflow_ref`, license) and then
nine module booleans, each with its **condition** stated in the help text. A module is enabled
when its condition is true, not when it sounds useful.

Two properties are load-bearing:

- **Question order.** A validator can only see answers already given, so `ci` is asked before
  the modules that require it (`security`, `release`, `ops`).
- **Validators, not documentation.** A tag in `workflow_ref` is rejected with an error, and
  `--defaults` fails outright, because `ci` defaults on while `workflow_ref` has no safe
  default. A rule that lives only in a README is not a rule.

## Module dependency DAG

Modules have a condition, not a position. Dependencies are shallow and never chain.

```text
                    core  (always on — owns the health mechanism)
        ┌──────────┬──────┼───────┬────────────┬──────────────┐
        ▼          ▼      ▼       ▼            ▼              ▼
     commits      ci     env    docs        deps        contributing
                  │
        ┌─────────┼──────────┐
        ▼         ▼          ▼
     security   release     ops        ← file-level need: these ship workflows,
                                        so the ci scaffolding must exist
```

`deps` hangs off `core`, not `ci`: Renovate needs no CI, and nesting it under `ci` would be a
false dependency.

## Ownership: one owner per path

Every payload file has exactly one owning module. Overlap is a build-breaking defect, because
it makes `copier update` produce a silently wrong merge. `just test-matrix` proves
disjointness by arithmetic rather than inspection: the files each module adds to a core render
must sum to the all-on total, so overlap is impossible to miss.

Three files are demanded by more than one module. They stay single-owned; the others
contribute conditional content:

| File | Owner | Contributors | Contribute |
| :--- | :--- | :--- | :--- |
| `.github/settings.yml` | core | contributing | review hardening |
| `lefthook.yml` | core | commits, security | commitlint, gitleaks hooks |
| `justfile` | core | release, docs | `changelog`, `adr` recipes |

`lefthook.yml` is owned by `core`, not `commits` (ADR-0007). With `commits` off, a
`commits`-owned `lefthook.yml` would not exist, and `core`'s own pre-push health hook and
`security`'s gitleaks hook would silently vanish with it.

## The health surface

| Glyph | State | Determined by |
| :--- | :--- | :--- |
| `✅` | on — complete | no sentinel in any file the module owns |
| `🟡` | on — incomplete | a sentinel is still present |
| `⏸` | deferred | an ADR-0001 row **with a trigger** |
| `⛔` | declined | an ADR-0001 row **with a reason** |
| `❓` | unrecorded | off in the answers, absent from ADR-0001 → exits non-zero |

Exit codes: `0` clean, `1` something unrecorded or the manifest is missing, `2` something
enabled but unfinished.

`❓` is the forcing function. A deferral without a trigger is reported as unrecorded and
exits non-zero, because "deferred — someday" is a hope, not a decision.

A consequence worth knowing before you first run it: **a freshly generated repository fails
`just health`.** Every module that was not enabled is an unrecorded row in ADR-0001, so the
pre-push hook blocks the first push until that file is honest. `git push --no-verify` is the
escape hatch; filling in the file is the intended path.

## Copier mechanics that shaped the design

Each of these was verified by experiment, and each one changed the design. The full table is
in `BUILD_PLAN.md` §6.10.

| Property | Consequence |
| :--- | :--- |
| **Copy uses the latest tag, not the working tree** | A change reaches generated repositories only after it is tagged. Merging to `main` is not enough |
| A template with no tag breaks `copier update` | Copier records an abbreviated SHA, which cannot be resolved from its filtered clone. Tagging is a hard requirement, not a convention |
| Conditional **filenames** work; conditional directories do not | `{% if module_x %}file{% endif %}.jinja`, which forces the `.jinja` suffix and therefore Jinja processing |
| `.copier-answers.yml` is written by the **payload**, not by Copier | The payload ships `{{ _copier_conf.answers_file }}.jinja`; without it the manifest the health surface reads never exists |
| `undefined: StrictUndefined` | Any `${{ }}` in a workflow must be inside `{% raw %}`, or rendering fails |
| A conflict with `--conflict=rej` exits **0** | The sync workflow cannot rely on the exit code. It greps for `.rej` files and fails explicitly |
| A destination records the tag it came from | `copier update` moves it to the *latest* tag, so rollout control is an explicit per-repository gate, not a side effect |
| `_migrations` rewrites recorded answers | How a `workflow_ref` bump is rolled out. `before:`/`after:` take command **strings**, not mappings |

## Synchronisation

`.github/workflows/copier-sync.yml` (core) runs on a schedule:

```text
schedule ──► copier update --conflict=rej ──► any .rej? ──► FAIL, print the files
                     │
                     └──► create-pull-request on chore/copier-sync
                              │
                              └──► optional auto-merge, gated on
                                   COPIER_SYNC_AUTO_MERGE == 'true'
```

Two deliberate choices:

- **Failing on conflict rather than merging.** Copier's default `inline` mode leaves merge
  markers *inside* the files, which `create-pull-request` would commit as a plausible-looking
  bad merge. A diverged repository should get a failed sync and a human.
- **The sync PR must be opened by a GitHub App token.** A pull request opened with the default
  `GITHUB_TOKEN` triggers no workflows, so required checks never report and branch protection
  blocks it forever.

`COPIER_SYNC_ENABLED=false` pauses scheduled syncs for one repository while leaving
`workflow_dispatch` working, so a paused repository can still be synced deliberately.

## Testing

Four suites, all in `scripts/`, orchestrated by `just test`. Their design rule is that a check
must be able to fail for a reason you can act on — so each one covers a class of defect that
reading the files did not catch.

| Suite | Proves |
| :--- | :--- |
| `test-template` | 14 configurations render; module content is authored; rendered YAML lints |
| `test-health` | every health state and exit code, against fixtures |
| `test-matrix` | ownership disjointness, SHA pinning across all configs, `copier update` idempotency, `_migrations` |
| `test-rendered` | actionlint, zizmor, git-cliff, `just`, and the conflict guard, against rendered output |

Two properties of the harness are worth knowing:

- **Renders come from a tagged snapshot of the working tree**, not from this repository. So the
  suites see uncommitted work, and tagging this repository cannot silently change what they
  test.
- **A missing tool is skipped, not failed.** A green run on a machine without `actionlint`,
  `zizmor` or `git-cliff` does not mean those checks passed.

## Verification status

The sync pull request, the settings-gated label, Scorecard publishing and release notes on a
real tag were verified against a live organisation on 2026-10-03. The execution record, with
its evidence, is [`docs/validation-runbook.md`](validation-runbook.md) §4.

Three items remain unverified: the **devcontainer build** (needs a container runtime), the
**Settings app install** (a web-UI step, and its real effect is narrower than assumed — labels
are created by the sync itself, the app only styles them), and the **fleet-wide `workflow_ref`
bump**.

That document also records the four defects the live run found. All four share a shape: they
are invisible to rendering, linting and unit tests, and appear only in an organisation, on a
real run. Two are fixed and two are open decisions.

A claim without attached evidence stays marked unverified there, and should stay that way
until it is.
