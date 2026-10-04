# 6. Detect stub completion with a sentinel grep, not repolinter

Date: 2026-10-03

## Status

Accepted

## Context

`just health` must distinguish *on — incomplete* from *on — complete*, which means asking, for
each enabled module, whether its files have been filled in or are still placeholders.

The source design specified `repolinter` for this. Investigation found three problems:

1. **The project is archived.** GitHub reports `archived: true`, last push 2026-02-06, 32 open
   issues. A linter that cannot be fixed is a poor foundation for the mechanism whose entire
   purpose is preventing rot.
2. **It fixes by default.** `repolinter lint` executes fixes described by the ruleset unless
   `--dryRun` is passed. A health command that mutates the working tree is not a health
   command.
3. **The specified config filename is not discovered.** The design names `.repolinter.json`,
   but repolinter only searches for `repolint.json`, `repolinter.json`, `repolint.yaml`, and
   `repolinter.yaml`. It would silently fall back to its built-in default ruleset.

Separately, every file the template creates as a placeholder already announces itself: the
sentinel `TEMPLATE-STUB` appears in its contents. So the question "is this module still a
stub?" is answerable without a ruleset engine at all.

## Decision

We will implement stub detection as a **sentinel grep inside the committed
`scripts/health.sh`**. A module is *on — complete* when no file it owns contains the literal
`TEMPLATE-STUB`; otherwise it is *on — incomplete*.

`repolinter` is **declined**, and `.repolinter.json` is not shipped. A linter remains an
option as a *secondary* convention check, but nothing in the five-state model depends on one.

## Consequences

- The health surface is read-only and dependency-free by construction. It cannot mutate the
  repo, and it cannot be broken by a tool being archived.
- Detection is weaker than a ruleset: no `where:` conditions, no glob semantics. This is
  accepted because the health surface asks exactly one question per module.
- Modules must maintain their own file lists in `health.sh`. A module that adds a file and
  forgets to list it will report *complete* while that file is still a stub. Mitigation: a
  `template-test` assertion cross-checks module file lists against the rendered tree.
- **Deferred:** a secondary linter for conventions beyond stub presence. Trigger: the first
  convention that must be enforced across modules and cannot be expressed as a per-module
  sentinel.
