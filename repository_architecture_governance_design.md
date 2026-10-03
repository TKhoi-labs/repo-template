# Repository Architecture & Governance Design

## Design Principles

1. **Ask only for what the artifact can't tell you** — Why, Scope, Evidence. Everything derivable from the diff is noise.
2. **Modules, not stages** — A module has a condition, not a position. Dependencies form a shallow DAG, never a chain.
3. **Rigid at the boundary, free in the body** — Enforce what automation consumes (type, scope, links, labels); liberate prose.
4. **When you defer something, design its forcing function in the same breath** — Deferral without a trigger is a hope.

---

## Tool Stack

| Concern | Tool | Note |
| :--- | :--- | :--- |
| **Scaffold files** | Copier | `copier update` is the reason; no official `copier-org` Action exists |
| **Run Copier in CI** | `pipx install copier` + `copier update --defaults` | Not an Action |
| **Repo settings** | Settings app + `.github/settings.yml` | Settings-as-code, in-repo, idempotent |
| **Commit format** | Conventional Commits + `@commitlint/cli` | `commitlint` alone is not the CLI |
| **Review vocabulary** | Conventional Comments | `nitpick:`, `issue:` (blocking), `praise:`, … |
| **Git hooks** | lefthook | Convenience only — bypassable, so not a gate |
| **Shared CI** | GitHub reusable workflows (`workflow_call`) | The root-cause fix for template churn |
| **Dependency updates** | Renovate | |
| **Dependency review** | `actions/dependency-review-action` | Free on public; needs GHAS on private |
| **Secret scanning** | gitleaks + GitHub native push protection | `gitleaks` = the local check |
| **Posture** | OpenSSF Scorecard | Machine-readable health |
| **File conventions** | repolinter | npm package `repolinter`, not `@repolinter/cli` |
| **Decisions** | ADR (Nygard) via adr-tools / log4brains | Status: Proposed is the lifecycle |
| **Local env** | devcontainer (or direnv) | Heaviest module — budget for it |
| **Task runner** | just | One `just health` entry point |
| **Release** | git-cliff or release-please | |
| **Fleet sync** | Actions + Copier + GitHub App token | Default `GITHUB_TOKEN` won't trigger CI |
| **Org scale (later)** | Backstage, Terraform GitHub provider | Only past ~dozens of repos |

---

## Module Set

| Module | Condition | Depends on | Owns |
| :--- | :--- | :--- | :--- |
| **core** | always | — | `LICENSE`, `README` stub, `.editorconfig`, `.gitignore`, `.gitattributes`, `.repolinter.json`, `justfile`, `scripts/health.*`, `.github/settings.yml`, PR template, issue forms, `docs/adr/0000-template.md`, `docs/adr/0001-initial-deferrals.md` |
| **commits** | wants enforced history | core | `.commitlintrc.*`, `lefthook.yml`, commitlint caller workflow |
| **ci** | any automated check | core | `.github/workflows/ci.yml` (thin `workflow_call` caller) |
| **env** | reproducible local tooling | core | `.devcontainer/devcontainer.json` (or `.envrc`) |
| **docs** | architecture exists | core | `docs/adr/` index, `docs/architecture.md` |
| **deps** | repo has any dependency | core | `renovate.json`, `dependency-review.yml` |
| **security** | public / external users | ci | `SECURITY.md`, `.gitleaks.toml`, `scorecard.yml`, `gitleaks.yml` |
| **contributing** | accepts outside contributions | core | `CONTRIBUTING.md`, `.github/CODEOWNERS`, settings hardening |
| **release** | publishes a versioned artifact | ci | `cliff.toml` or `release-please-config.json`, `release.yml` |
| **ops** | deployed / running | ci | runbooks, observability config |

> **Note:** `deps` hangs off `core`, not `ci`. Renovate needs no CI, and putting it under `ci` forces a false dependency.

---

## Per-Repo Workflow

### One-Time Setup (~half a day)
Build the template repo, including its own CI that generates repos from itself across module combinations and runs `just health` on the output. This is the amortization — it's the only honest way the per-repo cost stays under an hour.

### Per Repo (~30–60 min)
1. `copier copy gh:you/repo-template ./new-thing` — Answer module prompts.
2. `just health` — Run repolinter locally; fix stubs before pushing.
3. `gh repo create` + push, or use the template on GitHub directly.
4. **Install the Settings app once per org** — It reads each repo's `.github/settings.yml` and applies labels, branch protection, merge strategy. Zero per-repo work after the first install.
5. Create the bootstrap tracking issue from the template, checklist in the body, assigned to a milestone.
6. Write `docs/adr/0001-initial-deferrals.md` — Every module that's off is marked deferred (with trigger) or declined.
7. Confirm `_tasks` ran — The seeds files can't carry (secrets, environments) via `gh api`. Then read the first Scorecard result and the first PR's checks.

---

## Scaffolded File Tree

```text
.
├── .copier-answers.yml                 core      # module manifest — source of truth
├── .editorconfig / .gitattributes / .gitignore   core
├── .repolinter.json                    core
├── LICENSE                             core
├── README.md                           core      # adversarial stub — announces itself
├── justfile                            core
├── scripts/health.sh                   core      # renders the 4-state manifest report
├── .github/
│   ├── settings.yml                    core      # Settings app: labels, branch protection
│   ├── pull_request_template.md        core      # Why / Scope / Evidence
│   ├── ISSUE_TEMPLATE/{bug,task,feature}.yml  core  # Issue Forms, required fields
│   ├── ISSUE_TEMPLATE/config.yml       core
│   ├── CODEOWNERS                      contributing
│   └── workflows/
│       ├── ci.yml                      ci        # thin reusable-workflow caller
│       ├── commitlint.yml              commits
│       ├── dependency-review.yml        deps
│       ├── scorecard.yml               security
│       ├── gitleaks.yml                security
│       ├── release.yml                 release
│       ├── copier-sync.yml             core
│       └── template-test.yml           # template repo only
├── docs/
│   ├── adr/0000-template.md            core
│   ├── adr/0001-initial-deferrals.md   core
│   └── architecture.md                 docs
├── lefthook.yml                        commits   # pre-push health, commit-msg commitlint
├── .commitlintrc.json                  commits
├── renovate.json                       deps
├── SECURITY.md / .gitleaks.toml        security
├── CONTRIBUTING.md                     contributing
├── cliff.toml | release-please-config.json  release
└── .devcontainer/devcontainer.json     env
```

---

## Health Surface — Four States

| State | Meaning | Detected by |
| :--- | :--- | :--- |
| **declined** | Decided against | Recorded in `ADR-0001` |
| **deferred** | Will happen; trigger recorded | `ADR-0001` trigger table |
| **on — incomplete** | Enabled, files still stubs | `repolinter` |
| **on — complete** | Enabled and satisfied | `repolinter` |

`just health` reads `.copier-answers.yml` for the manifest, runs `repolinter` for stub detection, and prints `ADR-0001`'s trigger table. Three sources, four states, one command. Implement it as a committed script (`scripts/health.sh`) — not an inline Python one-liner, and the glyph must distinguish all four, not just ON/OFF.

---

## Fleet Sync (Corrected)

Scheduled workflow in each child repo: `actions/checkout` $\rightarrow$ `pipx install copier` $\rightarrow$ `copier update --defaults` $\rightarrow$ `peter-evans/create-pull-request`.

- **Use a GitHub App installation token or PAT**, not `GITHUB_TOKEN`, or the PR never triggers CI and branch protection blocks it forever.
- **Pin the template version to a tag**; never sync against HEAD.
- **Canary first** — Sync one repo, verify, then widen.
- **Resolve conflicts by policy**: Generated files are never hand-edited; customizations live outside generated paths. Repos that diverge get a failed sync, not a silent bad merge.
- **Handle volume**: Batch, or auto-merge on green for template-only changes, or you'll generate 30 review-required PRs a week.
- **Free win**: Because `settings.yml` is a file, the sync PR also propagates labels and branch protection across the fleet via the Settings app.

---

## Guardrails

- **Exactly one owning module per file** — Collisions break `copier update`.
- **Hooks are convenience, not gates.** Enforcement lives in CI; `--no-verify` always wins.
- **Declare module dependencies explicitly**; don't let them couple implicitly.
- **Write down declined as loudly as deferred** — A list that can't empty gets ignored.
- **Don't add modules you haven't hit a trigger for.** Every conditional is maintenance you now own, and the template is itself subject to the rot problem it exists to prevent.