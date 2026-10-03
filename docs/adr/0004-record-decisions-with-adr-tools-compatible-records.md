# 4. Record architecture decisions as adr-tools-compatible Nygard ADRs

Date: 2026-10-03

## Status

Accepted

## Context

The design of this template rests on a chain of decisions, most of them made because a simpler
option failed for a specific, discoverable reason. Without a record, the next maintainer sees
only the current shape and re-litigates settled questions — or worse, "simplifies" it back into
the failure mode it was designed to avoid.

We need the lightest possible tooling: the value is in the prose, not in a generated site.

## Decision

We will record decisions as Nygard-format ADRs under `docs/adr/`, numbered sequentially, with a
status lifecycle whose normal resting state is **Accepted** and whose initial state is
**Proposed**. The template in `0000-template.md` matches the shape `adr-tools` generates, so
`adr new` appends in-convention without a custom wrapper.

Each ADR must record, in its Consequences section, anything it leaves **deferred** together
with the **trigger** that would revisit it.

## Consequences

- Adding a decision is a text edit; no build step, no site, no service.
- `adr-tools` is a convenience, not a requirement. A generated repo can add ADR-0002 onwards by
  copying `0000-template.md` by hand.
- Sequential numbering creates merge conflicts when two PRs add an ADR concurrently. Accepted:
  the fix is to renumber, which is cheap and rare.
- **Deferred:** `log4brains` or a static published index. Trigger: readers outside the
  contributing team need to browse decisions without cloning the repo.
