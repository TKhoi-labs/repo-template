# 9. Pin GitHub Actions to commit SHAs

Date: 2026-10-03

## Status

Accepted

## Context

GitHub Actions are referenced by a version tag (`actions/checkout@v4`). A tag is a mutable
pointer: whoever controls the upstream repository can move it to point at different code after
this repository has reviewed and merged it. That makes every `uses:` line an unpinned
dependency with arbitrary code execution in CI.

This template exists to make repository posture machine-checkable and consistent, and the
`security` module ships OpenSSF Scorecard, whose Pinned-Dependencies check scores exactly this.
Shipping unpinned actions in the template would mean every generated repository starts with a
Scorecard finding in the category the template is meant to improve.

## Decision

We will pin every `uses:` reference to a full 40-character commit SHA, with the human-readable
version as a trailing comment:

```yaml
- uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
```

The trailing comment is not decoration: it is how Renovate identifies which version a digest
corresponds to, so pins stay updatable rather than being frozen by hand.

Because a SHA-pinned `uses:` line cannot be wrapped in YAML, the template repo sets
`line-length: max: 100` in `.yamllint` rather than disabling the rule.

Additionally, `actions/checkout` sets `persist-credentials: false` in jobs that do not need to
push, so the job's `GITHUB_TOKEN` is not left in the local git config.

## Consequences

- Generated repositories start with pinned dependencies and no Pinned-Dependencies finding.
- `uses:` lines are no longer human-readable at a glance; the trailing comment carries that,
  and a reviewer checking a pin bump should verify the SHA matches the claimed version.
- Pin updates require the `deps` module. Without Renovate, pins silently age. This is an
  explicit coupling: `security` (which measures the pins) is more useful alongside `deps`
  (which updates them).
- **Deferred:** automating the SHA resolution so hand-written workflows cannot accidentally use
  a tag. Trigger: the first time a tag reference reaches the default branch by mistake.
