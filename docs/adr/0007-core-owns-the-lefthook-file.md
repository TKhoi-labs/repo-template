# 7. The core module owns `lefthook.yml`

Date: 2026-10-03

## Status

Accepted

## Context

The source design assigned `lefthook.yml` to the `commits` module while also describing it as
running "pre-push health, commit-msg commitlint". Those two statements conflict:

- **pre-push health** is a `core` concern — `core` owns `just health` and `justfile`.
- **pre-commit gitleaks** is a `security` concern.
- **commit-msg commitlint** is a `commits` concern.

With `commits` as the owner, a repo that enables `core` and `security` but not `commits` gets
**no** `lefthook.yml` at all, so the health hook and the secret-scanning hook silently vanish
even though both owning modules are enabled. Worse, `security` would have to edit a file owned
by `commits` to add its hook — a violation of one-owner-per-file.

## Decision

We will make **`core` the owner** of `lefthook.yml`, because `core` is always present and is
therefore the only module that can host a file other modules must contribute to.

`commits` and `security` contribute **conditional content** to that file, guarded by their own
module flags, rather than owning files of their own.

## Consequences

- Hook availability no longer depends on which optional modules happen to be enabled.
- `lefthook.yml` joins `.github/settings.yml` and `justfile` as a *shared-edit surface*: one
  owner, several declared contributors. A test asserts that no file references a contributing
  module that is not declared for it, so ownership cannot erode silently.
- **Deferred:** migrating hooks to a per-language tool (e.g. `pre-commit`) if lefthook proves
  inadequate. Trigger: a language ecosystem that lefthook cannot hook correctly.
