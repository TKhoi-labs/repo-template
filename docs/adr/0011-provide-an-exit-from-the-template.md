# 11. Provide an exit from the template

Date: 2026-10-04

## Status

Accepted

## Context

A generated repository is coupled to this template in three ways: `.copier-answers.yml` names the
template and records the answers, `.github/workflows/copier-sync.yml` consumes that binding on a
schedule, and `scripts/health.sh` reads it to report which modules are enabled but unfinished.

That coupling is the point of the template — it is what keeps a fleet moving together — but it is
not what every repository wants forever. A repository can outlive the need for it: the team
changes, conventions diverge, or the sync's pull requests become noise. Until now the only answers
were to live with the coupling, or to delete files by hand and hope nothing else referred to them.

Two measured properties of Copier decide what an exit can look like:

- **Copier never deletes files.** `copier update` renders the new template over the old one and
  removes nothing — checked in `scripts/test-matrix.sh`, where turning a module off leaves that
  module's files behind. So an exit cannot be a template answer: no answer can remove anything,
  and "set the module to false" does not either.
- **The binding is a file.** Removing `.copier-answers.yml` is what stops `copier update`, because
  that path resolves the template through the recorded `_src_path` and `_commit`. There is no other
  state to clear.

## Decision

The payload ships `scripts/eject.sh`, with a `just eject` recipe. Applied with `--yes` it:

- removes `.copier-answers.yml`, `.github/workflows/copier-sync.yml`, `scripts/health.sh`,
  `docs/adr/0001-initial-deferrals.md`, and the script itself;
- edits the references it can rewrite deterministically — the `health`, `check` and `eject`
  recipes and the header comment in the justfile, the `pre-push` hook in `lefthook.yml`, the
  `/.copier-answers.yml` line in `.github/CODEOWNERS`, and the removed ADR's row in the ADR index;
- removes `scripts/` when those deletions empty it;
- prints the prose that still refers to the template, which it does not rewrite.

It is a dry run by default, prints what it will do before doing it, tolerates files that are
already gone, and removes itself last.

Two boundaries are deliberate. **The ADR skeleton stays**: `docs/adr/README.md` tells the reader to
copy `0000-template.md`, so it is content, not bookkeeping. **The tooling stays**: the workflows,
the devcontainer, `cliff.toml`, the gitleaks config, Renovate, lefthook and every recipe that does
not read the manifest belong to the adopter now, and removing them is a different decision from
leaving the template.

## Consequences

Ejecting is one-way, and the suite says so: after an eject, `copier update` fails and nothing is
recreated. A repository that wants the template back has to re-render it and reconcile by hand.

Prose is reported rather than rewritten. The README's next steps, the architecture document's
health section and the contributing guide's "Generated files" section cannot be edited without
judging meaning, and a machine that deletes a paragraph it half-understands is worse than one that
names it.

Every future payload change must keep two states coherent: the repository as generated, and the
repository after ejecting. `scripts/test-eject.sh` renders both — a full configuration and a
core-only one — ejects each, and asserts what survives, so a payload file that assumes the module
manifest fails there instead of in a maintainer's repository six months later.

This is also what makes the module list, the answers file and the health report shippable without
being permanent: they are scaffolding with a documented way out, not furniture.
