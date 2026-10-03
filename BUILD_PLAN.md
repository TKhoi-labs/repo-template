# Build Plan — `repo-template`

Source spec: [`repository_architecture_governance_design.md`](./repository_architecture_governance_design.md)

This file is a **planning artifact for this repo only**. It is not part of the generated
payload and must never reach a child repo.

---

## 1. What we are building

A **Copier template repo** whose product is *other repositories*. This repo contains no
application code. Its deliverables are:

1. A `copier.yml` questionnaire that turns 10 boolean module questions into a working repo.
2. A payload tree that renders conditionally — one owning module per file.
3. A health surface (`just health`) that reports every module in one of **four** states.
4. Its own CI that generates repos from itself across a matrix of module combinations and
   runs `just health` on each output.
5. A scheduled sync path (`copier update`) that propagates template changes into the fleet
   without re-cloning the template by hand.

Success criterion for the whole build: **`copier copy` of any module combination produces a
repo where `just health` exits 0 and prints a fully-classified manifest.**

---

## 2. System map

```text
                    ┌────────────────────────────────────────────────────────┐
                    │  THIS REPO — repo-template (built once, ~0.5 day)      │
                    │                                                        │
                    │  copier.yml        ← 10 module questions + settings    │
                    │  template/        ← the rendered payload (1 owner/file)│
                    │  includes/         ← _tasks helpers, Jinja macros,     │
                    │                     stub sentinels                     │
                    │  .github/workflows/template-test.yml  ← dogfood CI     │
                    └───────────────┬────────────────────────────────────────┘
                                    │
                 ┌──────────────────┴───────────────────┐
                 │  copier copy -d module_x=true ...    │   (per repo, 30–60 min)
                 │  answers recorded in:                │
                 │      .copier-answers.yml  ← SOURCE OF TRUTH / manifest
                 └──────────────────┬───────────────────┘
                                    ▼
        ┌───────────────────────────────────────────────────────────────┐
        │  CHILD REPO                                                   │
        │                                                               │
        │   just health ─────────► 4-state manifest report (exit code)  │
        │        reads: .copier-answers.yml   (which modules are ON)    │
        │        runs:  sentinel grep         (stub detection)          │
        │        prints: ADR-0001 trigger table                         │
        │                                                               │
        │   .github/settings.yml ─► Settings App ─► labels/branch rules │
        │   .github/workflows/copier-sync.yml ─► scheduled copier update│
        │                                        (GitHub App token)     │
        └───────────────────────────────────────────────────────────────┘
```

Three independent sources feed one report. That is the whole architecture.

---

## 3. Module dependency DAG

Modules have a **condition**, not a position. Dependencies are shallow and never chain.

```text
                          ┌──────┐
                          │ core │  always on, owns the health mechanism itself
                          └──┬───┘
        ┌───────────┬────────┼────────┬────────────┬─────────────┐
        ▼           ▼        ▼        ▼            ▼             ▼
   ┌─────────┐ ┌──────┐ ┌───────┐ ┌──────┐ ┌──────────────┐ ┌─────┐
   │ commits │ │  ci  │ │  env  │ │ docs │ │      deps    │ │ con │
   └─────────┘ └──┬───┘ └───────┘ └──────┘ └──────────────┘ │trib │
                  │                                          └─────┘
        ┌─────────┼──────────┐
        ▼         ▼          ▼
   ┌─────────┐ ┌───────┐ ┌─────┐
   │security │ │release│ │ ops │
   └─────────┘ └───────┘ └─────┘
```

**deps hangs off `core`, not `ci`** — Renovate needs no CI, and nesting it under `ci`
would create a false dependency (spec §Module Set note).

Each edge is a *file-level* requirement, not a runtime one: `security` ships workflows, so
it needs the `ci` scaffolding to exist; `release` ships a workflow caller, same.

### File ownership matrix — exactly one owner per path

| Module | Condition | Owns |
| :--- | :--- | :--- |
| **core** | always | `LICENSE`, `README.md` (stub), `.editorconfig`, `.gitignore`, `.gitattributes`, `justfile`, `lefthook.yml`, `scripts/health.sh`, `.github/settings.yml`, `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/{bug,task,feature}.yml` + `config.yml`, `docs/adr/0000-template.md`, `docs/adr/0001-initial-deferrals.md`, `.github/workflows/copier-sync.yml` |
| **commits** | wants enforced history | `.commitlintrc.json`, `.github/workflows/commitlint.yml` |
| **ci** | any automated check | `.github/workflows/ci.yml` (thin `workflow_call` caller) |
| **env** | reproducible local tooling | `.devcontainer/devcontainer.json` *(or `.envrc`)* |
| **docs** | architecture exists | `docs/architecture.md`, `docs/adr/README.md` (index) |
| **deps** | repo has a dependency | `renovate.json`, `.github/workflows/dependency-review.yml` |
| **security** | public / external users | `SECURITY.md`, `.gitleaks.toml`, `.github/workflows/scorecard.yml`, `.github/workflows/gitleaks.yml` |
| **contributing** | accepts outside contributions | `CONTRIBUTING.md`, `.github/CODEOWNERS` |
| **release** | publishes a versioned artifact | `cliff.toml` *(or `release-please-config.json`)*, `.github/workflows/release.yml` |
| **ops** | deployed / running | `docs/runbooks/*.md`, `observability/` config |
| **template-only** | this repo | `copier.yml`, `BUILD_PLAN.md`, `template-test.yml`, template repo's own README/CI/ADRs |

Any two modules claiming the same path is a **build-breaking defect** (spec §Guardrails):
it makes `copier update` produce silent bad merges. Enforce with a test.

### Shared-edit surfaces — where one-owner-per-file needs a convention

The spec's "Owns" column describes *capabilities*, but the guardrail is about *files*. Three
files are demanded by more than one module. They stay single-owned; other modules contribute
**conditional content only**, and a test enforces that no condition references an undeclared
contributor.

| File | Owner | Allowed contributors | What they add |
| :--- | :--- | :--- | :--- |
| `.github/settings.yml` | core | contributing | branch-protection / review hardening |
| `lefthook.yml` | **core** *(moved — see below)* | commits, security | commit-msg commitlint; pre-commit gitleaks |
| `justfile` | core | commits, docs, release, deps | `just changelog` (release), `just adr` (docs) |

**`lefthook.yml` must be owned by `core`, not `commits`.** The spec puts it under `commits`
while also requiring it to run "pre-push health" (core's concern). With `commits` OFF the file
would not exist at all, so core's health hook and security's gitleaks hook would vanish even
though both modules are ON. `core` is always present, so it is the only correct host.

**Implicit tooling coupling.** `env` installs the tools that `core` (`yq`, `just`),
`docs` (`adr-tools`) and `release` (`git-cliff`) invoke. With `env` OFF those
invocations must fail with a clear message naming the missing tool — never silently. Declare
the tool requirements in the `justfile` recipes themselves.

**Ownership rows for this repo are not ownership rows for the payload.** `copier.yml`,
`BUILD_PLAN.md` and `template-test.yml` live *outside* `template/`, so they are not module
ownership rows at all — the `template/` layout removes them from the rendered tree by
construction rather than by `_exclude`.

---

## 4. The health surface — four states, one command

```text
                     ┌──────────────────────────┐
                     │  .copier-answers.yml     │  module ON / OFF truth
                     └────────────┬─────────────┘
                                  │
        ┌─────────────────────────┼──────────────────────────────┐
        │ module OFF              │                       module ON
        ▼                         │                              ▼
 ┌──────────────┐                 │                    ┌──────────────────┐
 │ ADR-0001 row │                 │                    │ sentinel grep    │
 └──────┬───────┘                 │                    └────────┬─────────┘
        │                         │                    ┌────────┴─────────┐
  ┌─────┴──────┐                  │                    ▼                  ▼
  ▼            ▼                  │            stub sentinel        no sentinel
⛔ DECLINED  ⏸ DEFERRED           │            still present
(reason)     (trigger: ...)       │                    ▼                  ▼
  │            │                  │            🟡 ON–INCOMPLETE    ✅ ON–COMPLETE
  └────────────┴──────────────────┴────────────────────┴──────────────────┘
                                  │
                     unknown / unrecorded ⇒ ❓ and NON-ZERO exit
```

Glyph contract (`scripts/health.sh`):

| Glyph | State | Source of truth |
| :--- | :--- | :--- |
| `✅` | on — complete | sentinel absent from all of the module's files |
| `🟡` | on — incomplete | sentinel still present in a module-owned file |
| `⏸` | deferred | `ADR-0001` row with a **trigger** |
| `⛔` | declined | `ADR-0001` row with a **reason** |
| `❓` | unrecorded | OFF in answers, but absent from `ADR-0001` → fail |

`❓` is the forcing function from spec §Guardrails ("Write down declined as loudly as
deferred"). It is what stops ADR-0001 from silently rotting into a list nobody maintains.

`just health` must be a committed script, not an inline one-liner. **Stub detection is a
sentinel grep inside that script** (decision 7) — read-only, dependency-free, and not
sensitive to any tool being archived. Runtime dependencies are only `yq` (read
`.copier-answers.yml`) and `grep`; `jq` and a linter are needed only if an optional linter is
added later.

---

## 5. Rendered file tree (annotated)

```text
CHILD REPO
.
├── .copier-answers.yml                      generated   # module manifest — never hand-edit
├── .editorconfig  .gitattributes  .gitignore  core
├── LICENSE                                  core
├── README.md                                core        # adversarial stub — announces itself
├── justfile                                 core        # `just health` entry point
├── lefthook.yml                             core        # pre-push health; +commitlint/gitleaks
├── scripts/health.sh                        core        # 4-state manifest renderer (sentinel grep)
├── .github/
│   ├── settings.yml                         core        # Settings App: labels, protection
│   ├── pull_request_template.md             core        # Why / Scope / Evidence
│   ├── ISSUE_TEMPLATE/{bug,task,feature}.yml  core
│   ├── ISSUE_TEMPLATE/config.yml            core
│   ├── CODEOWNERS                           contributing
│   └── workflows/
│       ├── ci.yml                           ci           # thin reusable-workflow caller
│       ├── commitlint.yml                   commits
│       ├── dependency-review.yml            deps
│       ├── scorecard.yml                    security
│       ├── gitleaks.yml                     security
│       ├── release.yml                      release
│       └── copier-sync.yml                  core
├── docs/
│   ├── adr/0000-template.md                 core
│   ├── adr/0001-initial-deferrals.md        core        # rendered from module answers
│   └── architecture.md                      docs
├── .commitlintrc.json                       commits
├── renovate.json                            deps
├── SECURITY.md  .gitleaks.toml              security
├── CONTRIBUTING.md                          contributing
├── cliff.toml                               release
└── .devcontainer/devcontainer.json          env
```

---

## 6. Copier mechanics — the design decisions

### 6.1 Template payload lives in `template/` — **DECIDED**

```text
repo-template/
├── copier.yml
├── template/               ← ONLY this subtree is rendered into the child repo
│   ├── justfile.jinja
│   ├── .gitignore              (copied verbatim, no suffix)
│   └── .github/workflows/
│       ├── {% if module_ci %}ci.yml{% endif %}.jinja
│       └── {% if module_security %}gitleaks.yml{% endif %}.jinja
├── includes/               ← Jinja macros + `_tasks` helpers, never rendered
├── .github/workflows/template-test.yml   ← this repo's own CI
└── BUILD_PLAN.md
```

`_subdirectory: template` in `copier.yml`. Rationale: this repo's own CI, README, and
BUILD_PLAN.md must never leak into a child repo, and **"one owner per file" can be verified
by path** without an `_exclude` allowlist that drifts.

*Alternative (root-as-template)*: keep the payload at the repo root and `_exclude` the
template-only files. Rejected — the exclude list becomes a second thing to keep in sync
with reality.

### 6.2 Conditional files = conditional *filenames*, never conditional directories

Directories are shared across modules (`.github/workflows/` is owned by 6 modules). Gating
a directory would force false coupling. Instead every file is gated individually:

```text
template/.github/workflows/
├── {% if module_ci %}ci.yml{% endif %}.jinja
├── {% if module_commits %}commitlint.yml{% endif %}.jinja
├── {% if module_deps %}dependency-review.yml{% endif %}.jinja
├── {% if module_security %}scorecard.yml{% endif %}.jinja
└── {% if module_security %}gitleaks.yml{% endif %}.jinja
```

Core files carry no condition: `copier-sync.yml.jinja`.

Note the suffix sits **outside** the Jinja block, per Copier's rule — otherwise the file is
copied verbatim instead of templated.

### 6.3 Module dependencies are declared, not assumed

`copier.yml` questions use `when:` (e.g. `module_security` only asked when `module_ci`),
and the `_tasks` bootstrap asserts the DAG: a rendered repo with `security=1, ci=0` must
fail loudly at generation time, not silently at CI time.

### 6.4 `_tasks` — the seeds Copier cannot carry

`_tasks` runs after render, inside the destination, and owns what files cannot express:

- Create the bootstrap tracking issue (`gh issue create`, body rendered from `includes/`).
- Create placeholder Actions secrets / environments (`gh api`) — idempotent.
- Mark the destination git repo + initial commit (optional).

Guard the whole task block behind a `run_bootstrap` question so `template-test` runs
offline and deterministic. All tasks must be **idempotent** — `copier update` re-runs them.

### 6.5 Reusable workflows live in an org `.github` repo — **DECIDED**

`ci` (and the workflows owned by `security`, `release`, `ops`) are thin callers into a
central repo:

```yaml
# template/.github/workflows/{% if module_ci %}ci.yml{% endif %}.jinja
jobs:
  ci:
    uses: {{ org_slug }}/.github/.github/workflows/ci.yml@{{ workflow_ref }}
```

Consequences for `copier.yml`:

- New questions `org_slug` (e.g. `acme`) and `workflow_ref` (a **tag**, default `v1`).
- The central repo is a prerequisite of the `ci` module, not of this build: the `ci`
  module's ADR records it as an external dependency with a trigger if it does not exist yet.
- `workflow_ref` is pinned to a **full commit SHA**, never a tag or branch (`copier.yml`
  validators enforce the shape). A tag would let a moved ref repoint the workflow that every
  repository executes; see §11 and ADR-0009 for the evidence and the accepted cost.
- `template-test` runs with `run_bootstrap=false` and a fixture `org_slug`, so callers are
  rendered and `actionlint`-checked without needing the central repo to exist.

### 6.6 ADR tooling is `adr-tools` — **DECIDED**

- `docs/adr/0000-template.md` matches `adr-tools`' Nygard template shape so `adr new`
  appends in-convention.
- `docs/adr/0001-initial-deferrals.md` is **rendered by Copier** from module answers (not
  created by a `_task`) so the manifest and the deferral row are written in one pass and
  can never disagree at generation time.
- No `adr-tools` install is required to *use* a generated repo — it is a convenience for
  adding ADR-0002 onward, declared in the `env` module.

### 6.7 Release tool is `git-cliff` — **DECIDED**

- `cliff.toml` renders Keep-a-Changelog-style markdown from Conventional Commits.
- `.github/workflows/release.yml` runs git-cliff in CI; `just changelog` is the local
  equivalent for regenerating without a push.
- `release-please-config.json` is **not** shipped; the two are alternatives, not companions.

### 6.8 `copier update` conflict policy

- Generated files are **never hand-edited**; customizations live in files no module owns.
- Template versions are pinned to a **tag**, never HEAD.
- `_migrations` handle renames when a module is renamed or split.
- A repo that diverged gets a **failed sync**, which is the correct outcome.

---

### 6.9 The answers file is generated by the payload, not by Copier — **VERIFIED**

`_answers_file:` only tells Copier *where* the answers file lives; it does not create it. The
template must ship the file itself, and Copier renders it:

```text
template/{{ _copier_conf.answers_file }}.jinja
```

```jinja
# Changes here will be overwritten by Copier
{{ _copier_answers|to_nice_yaml -}}
```

Verified output (Copier 9.18.2, `copier copy --defaults`):

```yaml
# Changes here will be overwritten by Copier
_src_path: /tmp/spike
mod_a: true
mod_b: false
project_name: oE
```

Consequences:

- **This file is the manifest the entire health surface reads.** Without it, `.copier-answers.yml`
  silently never exists and `just health` has no source for module ON/OFF state. It is the
  single highest-risk file in the template.
- Answers are written as real booleans, so `yq '.module_ci' .copier-answers.yml` returns
  `true`/`false` directly.
- `_src_path` is always written; `_commit` is written only when the template is a Git repo
  with tags. Fleet sync pinning depends on that tag existing (decision 2, §6.5).
- A `template-test` assertion must fail if `.copier-answers.yml` is absent or lacks any module
  key — a template that renders without a manifest is worse than one that fails loudly.

### 6.10 Other verified Copier mechanics

| Behaviour | Verified result | Consequence |
| :--- | :--- | :--- |
| `{% if m %}f.yml{% endif %}.jinja` with `m=false` | file is skipped, no empty-name artifact | conditional filenames are safe for gating |
| `_subdirectory: template` | only that subtree renders | template-only files cannot leak |
| `default: "{{ _copier_conf.dst_path.name }}"` | resolves to the destination dir name | `project_slug` needs no prompt |
| `validator` under `-d`/`--defaults` | fires, exits **1**, `cleanup_on_error` removes the destination | negative DAG tests work with no `_tasks` needed |
| Boolean in file content | renders as `True` / `False` (capitalised) | compare with `= "True"`, or use `{{ 1 if x else 0 }}` |
| A directory whose files are all excluded | directory may still be created, empty | harmless, but do not assert absence of dirs |

## 7. Build phases

| # | Phase | Produce | Exit criteria |
| :-- | :--- | :--- | :--- |
| **0** | Decisions & dogfood | ADRs for this repo, resolved open decisions (§8) | Decisions locked in §8; written up as `docs/adr/0001..0006` in this repo |
| **1** | Bone structure | `copier.yml` with 10 module questions + `_subdirectory`; `template/` skeleton; `just` tasks `test-template`, `lint` | `copier copy` of an empty core renders without error |
| **2** | `core` module | All core files; adversarial stubs with sentinels; `justfile`; `settings.yml`; PR/issue templates | `just health` runs and classifies core as `✅`/`🟡` |
| **3** | Health surface | sentinel convention + per-module file lists; `scripts/health.sh` 4-state renderer | All five glyphs reachable in a fixture repo; `❓` exits non-zero |
| **4** | Conditional modules | `commits`, `ci`, `env`, `docs`, `deps`, `security`, `contributing`, `release`, `ops` | Each module renders alone on top of core; no path collision |
| **5** | Template self-test | `.github/workflows/template-test.yml` matrix + `just test-template` | ~14 module combinations generated and `just health` clean on each |
| **6** | Fleet sync | `copier-sync.yml`, GitHub App token, pinned tag, `create-pull-request`, canary | One canary repo syncs; re-run is a no-op; settings propagate |
| **7** | Validation & dogfood | Repolinter + `actionlint` + `yamllint`; this repo's own CI uses the same conventions | `just health` green on core-only, all-on, and 3 realistic bundles |
| **8** | Docs & handoff | This repo's `README.md`, `CONTRIBUTING.md`, `docs/architecture.md` | A new maintainer can generate a repo from the README alone |

### Test matrix — combinations, not the power set

10 modules ⇒ 1024 combinations is waste. Coverage is defined by what each config can
*detect*, across three axes.

**Axis 1 — generated configs (17):**

1. `core-only` — everything off (the all-declined path).
2. `all-on` — every module on. This is the **only** config exercising every ON–ON pair, so it
   is the collision detector. Verify it renders before trusting any other result.
3. **DAG-closure isolation (9)** — `core + closure(X)`. Plain `core + X` is *invalid* for three
   modules, because `security`, `release` and `ops` all depend on `ci`:

   | # | Config | Note |
   | :-- | :--- | :--- |
   | 1 | `core + commits` | |
   | 2 | `core + ci` | |
   | 3 | `core + env` | |
   | 4 | `core + docs` | |
   | 5 | `core + deps` | |
   | 6 | `core + contributing` | |
   | 7 | `core + ci + security` | security depends on ci |
   | 8 | `core + ci + release` | release depends on ci |
   | 9 | `core + ci + ops` | ops depends on ci |

4. **Realistic bundles (3):**
   - `lib-oss`: core, commits, ci, env, docs, deps, security, contributing, release
   - `internal-service`: core, commits, ci, env, deps, ops
   - `script`: core, commits, docs
5. **Negative DAG configs (3, must fail loudly):** `security` without `ci`, `release` without
   `ci`, `ops` without `ci`. Generation must exit non-zero. A silent render here is exactly the
   defect that `copier update` later turns into a bad merge.

**Axis 2 — update idempotency (applied to all 14 valid configs):**

For each rendered repo, `copier update --defaults` must produce **zero diff**. This is the
single highest-value property in the template — the whole reason Copier was chosen — and the
original matrix never tested it. It is a matrix *step*, not a new config.

**Axis 3 — health fixtures (5):** one fixture per glyph state, asserting glyph **and** exit code:

| Fixture | Expected glyph | Exit |
| :--- | :--- | :--- |
| module ON, sentinel removed | `✅` | 0 |
| module ON, sentinel still present | `🟡` | 0 |
| module OFF, ADR-0001 row with trigger | `⏸` | 0 |
| module OFF, ADR-0001 row with reason | `⛔` | 0 |
| module OFF, absent from ADR-0001 | `❓` | non-zero |

The last fixture is the only test that proves the anti-rot forcing function works.

Pairwise ON–ON coverage for non-dependency pairs comes from `all-on` plus the three bundles;
dependency pairs are covered by the closure configs. That is the deliberate trade against 1024.

---

## 8. Decisions — LOCKED (phase 0 complete)

| # | Decision | Resolution | Consequence locked in |
| :-- | :--- | :--- | :--- |
| 1 | Template layout | **`template/` subdirectory** | `_subdirectory: template`; this repo's CI/BUILD_PLAN can never leak (§6.1) |
| 2 | Reusable-workflow home | **org `.github` repo** | Questions `org_slug` + `workflow_ref`; `uses: …@<sha>` (ADR-0009), validator-enforced (§6.5, §11) |
| 3 | ADR tooling | **`adr-tools`** | `0000-template.md` is `adr new`-compatible; `0001` is Copier-rendered (§6.6) |
| 4 | Release tool | **`git-cliff`** | `cliff.toml` + `just changelog`; no `release-please-config.json` (§6.7) |
| 5 | Env module flavor | **devcontainer** (assumed) | `.devcontainer/devcontainer.json` owns `yq`, `just`, `adr-tools`, `git-cliff` |
| 6 | Host scope | **GitHub only** (assumed) | Settings App, Scorecard, GHAS dependency review are all GitHub-specific |
| 7 | Stub detection engine | **sentinel grep in `scripts/health.sh`** | Deviates from spec's "runs repolinter". No linter in the load-bearing path; a linter is an optional secondary check only (§10.2) |
| 8 | `lefthook.yml` owner | **`core`** | Deviates from spec's module table (which put it under `commits`). `commits` and `security` contribute conditional hook entries (§3) |

### Spec deviations introduced by this plan

Recorded here so the divergence from `repository_architecture_governance_design.md` is
intentional and reviewable. Each becomes an ADR in this repo during phase 0 cleanup.

| Spec says | This plan does | Why |
| :--- | :--- | :--- |
| `just health` runs `repolinter` for stub detection | sentinel grep in `scripts/health.sh` | repolinter archived Feb 2026; auto-fixes by default; spec's `.repolinter.json` filename not in its search list |
| core owns `.repolinter.json` | not shipped initially; recorded in ADR-0001 as declined with reason, or deferred with a trigger | no remaining job for it once health owns sentinel detection; spec guardrail: don't add what no trigger requires |
| `commits` owns `lefthook.yml` | `core` owns it | with `commits` OFF, core's health hook and security's gitleaks hook would not exist |

Phase 1 may start.

---

## 9. Risks & mitigations

| Risk | Mitigation |
| :--- | :--- |
| **Path collision between modules** breaks `copier update` silently | Phase 4 test asserts owner-per-path; `all-on` config is the detector |
| **`_tasks` re-run on update** and duplicate issues/secrets | Every task idempotent; `run_bootstrap` opt-in for tests |
| **repolinter is archived** (verified: `archived: true`, last push 2026-02-06, 32 open issues, v0.12.0) | **Resolved by decision 7** — removed from the load-bearing path; sentinel grep in `scripts/health.sh` is dependency-free and read-only |
| **repolinter auto-fixes by default** — a health check would mutate the working tree | Moot for the health surface; if a linter is ever added, it must run `check`-only by default or be invoked with `--dryRun` |
| **`.repolinter.json` is not in repolinter's config search list**, so it silently falls back to the default ruleset | Moot; if repolinter is ever adopted, the file must be `repolinter.json` or passed via `--rulesetFile` |
| **`lefthook.yml` under `commits` orphans core/security hooks** | **Resolved by decision 8** — owner moved to `core` (§3) |
| **`env`-off configs have no declared tool path** | `justfile` recipes assert tool presence and fail with the tool name |
| **Sync PRs never trigger CI** (branch protection deadlock) | GitHub App installation token, never `GITHUB_TOKEN`; canary repo first |
| **Sync volume** — 30 review-required PRs/week | Batch; auto-merge template-only diffs on green; pin tags |
| **Template rot** — the disease this repo treats | `template-test` runs on every template change; deferrals require triggers; no module without a trigger |
| **Dependency review on private repos** needs GHAS | `dependency-review.yml` gated on repo visibility; documented in the module's ADR |

---

## 10. Plan review — findings and revisions

Review performed against the spec text, the repolinter rule reference, and the npm/GitHub
metadata for each tool. Three material defects were found; §3, §7 and §9 above are revised.

### 10.1 Corrections applied

| # | Finding | Severity | Resolution |
| :-- | :--- | :--- | :--- |
| 1 | `core + X` isolation is **invalid** for security / release / ops (they require `ci`) — the matrix contradicted the DAG | high | §7 now uses DAG-closure isolation (`core + ci + X`) |
| 2 | No `copier update --defaults` idempotency test — the core property of the chosen tool was untested | high | §7 Axis 2 |
| 3 | No negative DAG tests and no health-state fixtures | medium | §7 Axis 1.5 and Axis 3 |
| 4 | `lefthook.yml` owned by `commits` orphans core's health hook and security's gitleaks hook | high | Owner moved to `core`; contributors declared (§3) |
| 5 | Shared-edit files (`settings.yml`, `lefthook.yml`, `justfile`) had no convention, so one-owner-per-file was unimplementable | high | Shared-edit surfaces table + contributor test (§3) |
| 6 | `env` tooling coupling was implicit | medium | Declared in `justfile` recipes (§3) |
| 7 | **`.copier-answers.yml` is never written by Copier** — the manifest the health surface reads was assumed to be automatic | **blocker** | Payload must ship `{{ _copier_conf.answers_file }}.jinja`; `template-test` asserts its presence and module keys (§6.9) |

### 10.2 Stub detection engine — **DECIDED: sentinel grep in `scripts/health.sh`**

Verified facts:

| | `repolinter` (spec's choice) | `alint` (alternative) | sentinel grep in `health.sh` |
| :--- | :--- | :--- | :--- |
| Maintenance | **archived 2026-02** | active (pushed 2026-10-02) | ours |
| Stub detection | `file-not-contents` | `file_content_forbidden` | `grep -L` |
| Health-check safety | **auto-fixes unless `--dryRun`** | `alint check` read-only by default | read-only by construction |
| Config file | `repolinter.json` (not `.repolinter.json`) | `.alint.yml` | none |
| Runtime | Node ≥12, EOL transitive deps | Rust single binary | shell |
| Maturity | mature, 465★, unmaintained | 6 months old, 74★ | trivial |
| Spec compliance | exact | deviates | deviates |

Recommended: **`scripts/health.sh` owns stub detection via sentinel grep.** The health script
is mandated as a committed script anyway; stub detection is "does this file still contain the
sentinel", which is a few lines; and it is read-only and dependency-free by construction. That
removes the archived tool from the load-bearing path entirely. A linter then becomes an
*optional secondary* convention check, and can be swapped without touching the four-state
model. Trade-off: greps are weaker than a ruleset (no `where:` conditions, no globs semantics),
so complex conventions lose expressiveness — which the health surface does not need, because
it only ever asks one question per module.

**Adopted.** Consequences: `.repolinter.json` is dropped from the shipped core set and
recorded in ADR-0001 as declined (engine archived) or deferred (trigger: a convention the
sentinel model cannot express). `just health` depends only on `yq` + `grep`. `alint` is
rejected for now on maturity grounds, not capability, and stays a named option if a linter is
ever warranted.


---

## 11. Deep analysis — pinning the reusable-workflow caller

**Question.** `ci.yml` is now the only `uses:` in the template that is not a commit SHA. ADR-0009
says tags are mutable and therefore unacceptable; decision 2 says the reusable workflow is
pinned to a tag. One of them is wrong.

### 11.1 Does anything actually measure or enforce this?

| Check | Finding | Source |
| :--- | :--- | :--- |
| Scorecard `Pinned-Dependencies` | **Yes, since 2025-06-30.** Issue #2174 reported a tag-pinned reusable workflow scoring 10/10; the maintainer confirmed "we assume every reference to an action will be as a step". PR #4681, *"include workflow uses when checking for unpinned dependencies"*, merged 2025-06-30, release note: "Check for unpinned dependencies in workflow jobs." | `ossf/scorecard` #2174, #4681 |
| GitHub allowed-actions policy | **Hard failure.** Since Aug 2025 the policy for "allowed actions and reusable workflows" has a SHA-pinning checkbox: "The policy will check for a full commit SHA, and any workflow that attempts to use an action that isn't pinned will fail." | GitHub changelog 2025-08-15 |
| GitHub docs | Guidance is framed as *"Using third-party actions"* and *"Reusing third-party workflows"*. It also warns: "there is risk to this approach even if you trust the author, because a tag can be moved or deleted if a bad actor gains access to the repository storing the action." | Secure use reference |

So the earlier premise was right, but only recently: before mid-2025 a tag-pinned reusable
workflow was **invisible** to Scorecard. A repo running an older Scorecard gets no signal at all.

Unverified: whether the org policy exempts same-org refs. That must be checked against the
actual org setting before relying on it either way.

### 11.2 The threat model is genuinely weaker for a first-party ref

GitHub's guidance is explicitly about third parties. For `org/.github`, the people who can move
`v1` are the org's maintainers, who can already push to every repository directly. SHA pinning
therefore does **not** defend against a malicious maintainer. It defends a narrower case: an
account compromised with write access to only the shared repo, or a malicious PR merged into the
shared repo by someone without per-repo access. That is real, but smaller than for a third-party
action. This is a legitimate argument for keeping the tag.

### 11.3 The strongest argument for a SHA — direction of failure

- **Tag:** if `v1` is moved to malicious code, **every** repository is compromised at job start,
  with no PR, no diff, and no review in any consuming repo. Nothing in this system can stop it;
  that is the one change path with no review anywhere.
- **SHA:** the same compromise is a **non-event** for every pinned repo. The bad commit is never
  used. Remediation is N reviewable PRs.

This is what GitHub means by "prevent malicious code added to a new or updated branch or tag
from being automatically used". It is also the only choice consistent with this architecture's
own premise: that change should flow through reviewable PRs.

### 11.4 The maintenance cost is close to zero

| Concern | Reality |
| :--- | :--- |
| "Hashes are unmaintainable by hand" | Renovate's `github-actions` manager has a `workflow` depType — "a reusable workflow referenced in a job-level `uses:` field" — so `helpers:pinGitHubActionDigests` already updates it. Dependabot has supported reusable workflows since 2023 and updates `@<sha> # <tag>` forms. |
| "Fleet rollout becomes N PRs" | True, and equally true for the tag: `copier update --defaults` does not re-ask questions, so a changed `workflow_ref` default does not propagate by itself. Either choice needs a `_migrations` entry plus the sync PR the plan already budgets for. |
| "Emergency fixes get slower" | Real, and it is the point. With a tag, "instant fleet-wide fix" and "instant fleet-wide exploit" are the same mechanism. They cannot be separated. |

### 11.5 The option that removes the problem instead of managing it

Because Copier already propagates files, the cross-repo reference is **optional**: render the
workflow body into each repository, either as the full `ci.yml` body or as a local reusable
workflow (`./.github/workflows/ci-shared.yml`).

- No cross-repo `uses:` ⇒ no pinning question, no Scorecard finding, no org-policy conflict.
- The `ci` module stops depending on an org `.github` repo that may not exist yet.
- Propagation uses the mechanism already built: the sync PR.
- Costs: a repository can edit its own CI (weaker central control); repos lagging their template
  version run older CI; upgrading CI costs N sync PRs, the same as SHA pinning.

Worth noting: the source design justified reusable workflows as "the root-cause fix for template
churn". That rationale predates having a working update path. Copier *is* the churn fix now, so a
shared reusable workflow buys central control and immediate consistency, not churn resistance.

### 11.6 Recommendation

**Pin to a commit SHA, enforced by a validator on `workflow_ref`.** Scorecard measures it, GitHub
can hard-fail it, tooling maintains it automatically, and it matches the architecture's premise
that change is reviewable. The weakened first-party threat model is a fair argument for the tag;
it is not an argument that the tooling makes expensive.

If the org does not enable SHA-pinning policy and accepts a `Pinned-Dependencies` finding, keeping
the tag is defensible — **but then ADR-0009 must record the exception explicitly**, because an
unexplained inconsistency is exactly the kind of thing this system exists to prevent.

**Status: DECIDED — pin to a commit SHA.** Scorecard measures it, GitHub can hard-fail it,
tooling maintains it automatically, and it matches the architecture's premise that change is
reviewable. Implemented as validators on `workflow_ref` and `module_ci`, so a tag cannot be
entered at generation time. ADR-0009 now covers job-level `uses:` explicitly, including the
first-party caveat and the accepted cost that a shared-workflow fix needs a migration plus sync
PRs. This supersedes the "pin to a tag" wording in decision 2.
