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

The same applies to a **job-level** `uses:`, which calls a reusable workflow in another
repository. Two facts were verified before relying on this:

- Scorecard did **not** check job-level `uses:` until PR #4681, *"include workflow uses when
  checking for unpinned dependencies"*, merged 2025-06-30. Before that, a tag-pinned reusable
  workflow scored 10/10, so the check was silently absent, not merely lenient.
- Since August 2025 GitHub can **enforce** SHA pinning through the organisation's allowed-actions
  policy for "actions and reusable workflows": a workflow that uses an action which is not
  pinned to a full commit SHA **fails**. That is a hard failure, not a warning.

The first-party case is acknowledged to be weaker. For a workflow in the organisation's own
`.github` repository, whoever can move the tag can already push to every repository directly, so
pinning does not defend against a malicious maintainer. It defends the narrower case of an
account compromised with write access to only the shared repository. The deciding argument is
the direction of failure, not the size of the threat: a moved tag compromises every caller with
no pull request, diff or review anywhere, which is the one change path in this system with no
review at all.

## Decision

We will pin every `uses:` reference to a full 40-character commit SHA, with the human-readable
version as a trailing comment. This includes job-level `uses:` that call reusable workflows:

```yaml
- uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4

jobs:
  ci:
    uses: acme/.github/.github/workflows/ci.yml@4f9c1a0e6b3d2c8e5a7b1f0d9c3e2a4b6d8f0c1e
```

The trailing comment is not decoration: it is how Renovate identifies which version a digest
corresponds to, so pins stay updatable rather than being frozen by hand. Renovate's
`github-actions` manager has a dedicated `workflow` dependency type for job-level `uses:`, and
Dependabot has updated reusable workflow references since 2023.

The template enforces this at generation time rather than relying on review: `workflow_ref` and
`module_ci` both carry validators requiring a full commit SHA, so a tag cannot be entered.

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
  (which updates them). The template learned the cost of that coupling itself: with no updater of
  its own, four of its seven action pins had fallen behind their newest major by the time one was
  added, and those are the pins every generated repository receives.
- A shared-workflow fix can no longer be rolled out by moving a tag. It requires a `_migrations`
  entry plus the sync pull requests. This is accepted deliberately: with a mutable tag, "roll out
  a fix to the whole fleet instantly" and "compromise the whole fleet instantly" are the same
  mechanism, and cannot be separated.
- Repositories calling the shared workflow must supply a 40-character SHA, because
  `copier update --defaults` does not re-ask questions and therefore never refreshes it on its
  own.
- **Resolved — and not by automating the resolution.** The organisation sets
  `sha_pinning_required`, so GitHub itself refuses an action that is not a full-length SHA. Verified
  by a probe rather than by reading the flag back: a step using `actions/checkout@v4` was rejected
  with *"The action actions/checkout@v4 is not allowed in TKhoi-labs/repo-template because all
  actions must be pinned to a full-length commit SHA."* This is stronger than resolving SHAs for
  the author, because the mistake cannot land at all. It is the owning organisation's policy,
  though: a generated repository inherits it only if its own organisation sets the same flag, so
  the runbook's P6 keeps the step and the evidence for that.
