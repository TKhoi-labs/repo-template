# 2. Keep the Copier payload in a `template/` subdirectory

Date: 2026-10-03

## Status

Accepted

## Context

The template repository needs its own CI, its own README, its own build plan, and its own
ADRs. Every one of those is a file that must **not** appear in a generated repository. The
question is how to keep the two sets apart: an `_exclude` allowlist, or structural separation.

An exclude list is a second source of truth. It drifts, and when it drifts the failure is
silent — a template-only file quietly appears in every generated repo. We have already been
bitten by silent scaffold failures (see ADR-0006).

## Decision

We will set `_subdirectory: template` and keep the entire rendered payload under `template/`.

Template-only artifacts — `copier.yml`, `BUILD_PLAN.md`, this `docs/adr/` directory, the
template's own CI, and `scripts/test-template.sh` — all live **outside** `template/` and are
therefore unreachable by the renderer by construction.

## Consequences

- "One owner per file" is verifiable by path, with no allowlist to maintain.
- Jinja `include`/`import` paths are resolved relative to `template/`, so shared macros, when
  they are introduced, must live under `template/` and be excluded from rendering explicitly.
- The payload is one level deeper than a root-as-template layout. This is a small readability
  cost accepted in exchange for making file leakage structurally impossible.
- **Deferred:** Jinja macros/partials for shared snippets. Trigger: the third time the same
  block of template content is duplicated across two modules.
