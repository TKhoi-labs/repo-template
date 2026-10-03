# 3. Host shared CI in an org-wide `.github` repository

Date: 2026-10-03

## Status

Accepted

## Context

Every generated repo needs roughly the same CI: checkout, set up the toolchain, run checks. If
each repo carries the full workflow body, then changing that body means changing it in every
repo — which is precisely the template-churn problem the whole system exists to eliminate.
Copier cannot fix this on its own, because workflow bodies change far more often than the
file layout does.

GitHub supports reusable workflows via `workflow_call`, which lets a caller job reference a
workflow in another repository.

## Decision

We will host the shared workflow bodies in an **org-wide `.github` repository** at
`{{ org_slug }}/.github/.github/workflows/*.yml`, and each generated repo's `ci.yml` will be a
thin caller:

```yaml
jobs:
  ci:
    uses: <org>/.github/.github/workflows/ci.yml@<tag>
```

The questionnaire asks for `org_slug` and `workflow_ref`. `workflow_ref` is pinned to a tag,
never a branch.

## Consequences

- A workflow fix propagates by bumping one tag reference per repo, or by one template sync PR,
  instead of by rewriting every repo's workflow body.
- The org `.github` repository becomes a hard external dependency of the `ci` module. If it
  does not exist yet, `ci` cannot be meaningfully enabled. This is recorded as a prerequisite
  in the module's documentation.
- Pinning to a tag means a worker repo does not silently pick up a broken shared workflow, but
  it also means improvements do not arrive automatically. Both are intended.
- **Deferred:** Renovate rules to bump `workflow_ref` automatically. Trigger: once the shared
  workflows repo has more than a handful of tagged releases.
