# Contributing to `repo-template`

This repository generates other repositories. A change here reaches every repository
generated from it, so the bar is higher than for ordinary content: a mistake does not fail
loudly in one place, it is copied.

Read [`docs/architecture.md`](docs/architecture.md) first if you have not. It is short, and it
explains why the layout is what it is.

## Setup

```bash
just test          # every check — this must pass before you push
just lint          # yamllint + shellcheck
```

Required: `just`, `copier` 9+, `yamllint`, `shellcheck`, and `bash`.
Optional, and used when present: `actionlint`, `zizmor`, `git-cliff`.

The suites skip a check with a `skip` notice when a tool is missing rather than failing, so
run them somewhere with the tools installed before you rely on a green result. The total
number of checks therefore depends on the machine; what matters is that nothing failed and
nothing was unexpectedly skipped.

## The one rule that matters

**Everything under `template/` is rendered into generated repositories. Nothing outside it
ever is.**

| Path | Rendered? | Contents |
| :--- | :--- | :--- |
| `template/` | yes — this is the payload | module content |
| `copier.yml` | no | the questionnaire |
| `scripts/`, `justfile` | no | this repo's own tests |
| `docs/`, `README.md`, `CONTRIBUTING.md`, `BUILD_PLAN.md` | no | this repo's own docs |

This is enforced by `_subdirectory: template` (ADR-0002), not by an exclusion list. If you put
a file outside `template/` it cannot leak, and if you put tooling inside `template/` it will.

## Conventions

Each of these exists because breaking it caused a real defect. The evidence is in
`BUILD_PLAN.md` §10.1.

### One owner per path

Every file in the payload is owned by exactly one module. Two modules claiming a path makes
`copier update` produce a silently wrong merge, so `just test-matrix` proves disjointness by
arithmetic: the files each module adds must sum to the all-on total.

Three files legitimately need several modules' contributions. They stay single-owned, and the
other modules contribute conditional content only:

| File | Owner | Contributors |
| :--- | :--- | :--- |
| `.github/settings.yml` | core | contributing |
| `lefthook.yml` | core | commits, security |
| `justfile` | core | commits, docs, release, deps |

### Conditional filenames, never conditional directories

```text
template/.github/workflows/{% if module_ci %}ci.yml{% endif %}.jinja
```

A conditional directory cannot be expressed, and a file whose rendered name is empty is a
Copier error. Note that a conditional filename always needs the `.jinja` suffix, which means
the file's body is processed by Jinja whether you want it or not — see the next rule.

### Raw-wrap anything containing `${{ }}` or Tera `{{ }}`

Jinja runs with `StrictUndefined`, so a workflow's `${{ github.event... }}` would be treated
as a Jinja expression and fail. Wrap the body:

```jinja
{% raw %}---
name: CI
{% endraw -%}
```

`cliff.toml` needs this too, because git-cliff uses Tera, whose syntax is near-identical to
Jinja's. `just test-template` asserts that Tera-only constructs (`trim_start_matches`) survive.

### The Jinja whitespace seam

Use `{%- if cond %}` with the blank line *after* the tag, and close with `{%- endif %}`. This
keeps exactly one blank line between blocks and one trailing newline at EOF. Getting it wrong
produces `too many blank lines` and `no newline at end of file` from yamllint.

### Stub sentinel

An unfinished payload file carries `TEMPLATE-STUB`. `just health` finds it, which is how a
generated repository reports a module as incomplete.

`scripts/health.sh` must never contain the marker literally, or it flags itself and `core` can
never be complete. It is assembled from two pieces instead:

```bash
SENTINEL="TEMPLATE-""STUB"
```

### Pin every `uses:` to a commit SHA

With the human-readable version as a trailing comment, which is the form Renovate reads:

```yaml
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
```

This applies to job-level `uses:` calling a reusable workflow too. A tag is rejected by a
Copier validator for the same reason. See ADR-0009 for the threat model.

### Workflow permissions and injection

- Workflow level is `permissions: {}`; every job declares its own scope with a comment
  explaining why.
- Never interpolate `${{ }}` inside a `run:` body — pass the value through `env`. zizmor
  reports this as `template-injection`.
- `secrets: inherit` is not used. Pass what the job needs.
- `zizmor --pedantic` should be clean apart from the one documented informational finding.

## Adding a module

A module is not finished until all of these are done:

1. `copier.yml` — a `module_<name>` bool with its **condition** in the help text, and a
   validator if it depends on another module. Question order matters: a validator can only
   see answers already given, which is why `ci` is asked early.
2. `template/` — the module's files, conditional filenames where needed.
3. `template/scripts/health.sh.jinja` — add every owned path to the module's list, or `just
   health` cannot see it.
4. `docs/architecture.md` — the module table.
5. `README.md` — the module table.
6. `BUILD_PLAN.md` — the ownership matrix.
7. A test in `scripts/test-template.sh` asserting the module's content renders.

A module with no trigger is maintenance the project now owns permanently. If you cannot write
its condition as a sentence, it is not a module yet.

## Adding a decision

Copy `docs/adr/0000-template.md`, or run `adr new "<title>"`. Status `Proposed` until taken,
then `Accepted`. Add it to the index in `docs/adr/README.md`.

If a change corrects the plan, add a row to the correction table in `BUILD_PLAN.md` §10.1 with
the evidence. That table is the record of every assumption that turned out to be wrong, and it
is more useful than a changelog.

## Commits

Conventional Commits:

```text
feat: author the core module content
fix: correct the release-notes template, which broke every release
docs: record the workflow-lint findings
test: verify rendered artifacts with the tools they depend on
```

The body should say what was wrong and how it was found, not just what changed.

## Release discipline

**A change merged to `main` does not reach any generated repository until it is tagged.**

Copier copies the latest Git tag, not the working tree, and a repository's `.copier-answers.yml`
records the tag it came from. So:

```bash
git tag -a v0.1.1 -m "fix: correct the release-notes template" && git push --follow-tags
```

Patch a bug fix, minor for a new module or question, major for a change that breaks
`copier update` for existing repositories.

Rolling a change out to repositories already generated is a separate, deliberate act: bump the
template tag, then let the scheduled sync open a pull request per repository. See
[`docs/validation-runbook.md`](docs/validation-runbook.md) for the staged rollout.

## Before you push

```bash
just test && just lint
```

CI runs the same suites on every push and pull request, so this is a courtesy to yourself rather
than a requirement — but the devcontainer job is worth knowing about: it renders a repository,
builds its devcontainer and checks the toolchain inside it, which is the only place that is
verified at all.

If you changed a workflow, run `just test-rendered`, which is the only suite that actually
executes actionlint and zizmor against rendered output. Reading a workflow is not verification
— that is how three high-severity permission findings and a broken `cliff.toml` survived
review until a tool was pointed at them.
