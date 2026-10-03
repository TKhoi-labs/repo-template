# 1. Use Copier to scaffold and update repositories

Date: 2026-10-03

## Status

Accepted

## Context

Repositories in this organisation drift. Files that should be identical everywhere (CI entry
points, linters, PR templates, settings-as-code) diverge because each repo was copied once and
then edited by hand. Plain `git clone`-and-rename templates cannot push improvements back out:
there is no supported update path, so the only way to fix 30 repos is 30 pull requests written
by hand. That cost is what makes the per-repo setup time unacceptable.

The requirement is therefore not "generate a repo" but "generate a repo **and** be able to
update it later without clobbering local customisation".

## Decision

We will use [Copier](https://copier.readthedocs.io) as the scaffolding engine.

- Conditional inclusion is expressed with **conditional filenames**
  (`{% if module_ci %}ci.yml{% endif %}.jinja`), not conditional directories — directories are
  shared across modules, so gating one would force false coupling.
- The template declares `_answers_file: .copier-answers.yml`, and the payload ships
  `{{ _copier_conf.answers_file }}.jinja` so the answers file is actually rendered. Copier does
  not create it by itself (see ADR-0002 and the build plan, §6.9).
- Template versions are pinned to Git **tags**; `copier update` never syncs against HEAD.

## Consequences

- A Python tool (`copier`) is now a build dependency of the template repo, run via `pipx` or
  `uvx`. It is not a dependency of generated repos.
- `copier update` requires the destination to be a Git repository. A generated repo must be
  committed before it can ever be updated — this is a real, unavoidable constraint.
- Generated files must never be hand-edited, or the next update produces a conflict. This
  forces local customisation into files no module owns, which is a discipline worth having.
- **Deferred:** `_migrations` for renaming modules. Trigger: the first time a module is renamed
  or split after repos have been generated from an earlier tag.
