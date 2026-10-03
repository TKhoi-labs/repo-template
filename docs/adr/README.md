# Architecture decision records

These are the decisions behind **this template repository**. A repository generated from the
template gets its own set: `0000-template.md`, a rendered `0001-initial-deferrals.md` covering
the modules that were not enabled, and an index like this one if the `docs` module is on.

A decision that is not written down gets re-litigated, and usually reverted to the failure
mode it was made to avoid. These records are deliberately short: the value is in the context
and the consequences, not the ceremony.

## Adding one

Copy `0000-template.md` to the next free number, or run `adr new "<title>"` if you have
`adr-tools` installed. Leave the status as **Proposed** until the decision is actually taken.

## Records

| ADR | Decision | Status |
| :--- | :--- | :--- |
| [0000](0000-template.md) | Template for new records | — |
| [0001](0001-use-copier-for-repository-scaffolding.md) | Use Copier to scaffold and update repositories | Accepted |
| [0002](0002-keep-the-template-payload-in-a-subdirectory.md) | Keep the Copier payload in a `template/` subdirectory | Accepted |
| [0003](0003-host-reusable-workflows-in-an-org-github-repo.md) | Host shared CI in an org-wide `.github` repository | Accepted |
| [0004](0004-record-decisions-with-adr-tools-compatible-records.md) | Record decisions as adr-tools-compatible Nygard ADRs | Accepted |
| [0005](0005-use-git-cliff-for-release-notes.md) | Use git-cliff to generate release notes | Accepted |
| [0006](0006-detect-stub-completion-with-a-sentinel-grep.md) | Detect stub completion with a sentinel grep, not repolinter | Accepted |
| [0007](0007-core-owns-the-lefthook-file.md) | The `core` module owns `lefthook.yml` | Accepted |
| [0008](0008-assume-github-with-a-devcontainer-env-module.md) | Assume GitHub, and satisfy local tooling with a devcontainer | Accepted |
| [0009](0009-pin-github-actions-to-commit-shas.md) | Pin GitHub Actions to commit SHAs | Accepted |
| [0010](0010-treat-code-scanning-and-code-quality-as-organisation-state.md) | Treat code scanning and code quality as organisation-owned state | Accepted |

## The rule for deferrals

Every record that defers something must name the **trigger** that would revisit it. A
deferral without a trigger is a hope. This applies to ADR-0001 in generated repositories,
where `just health` treats a `deferred` row with no trigger as undecided and exits non-zero.

## Decisions not yet taken

Recorded as **Proposed** only when there is a real open question. None at present: the
questions that arose during the build were resolved and folded into the records above, and
each one is listed, with its evidence, in `BUILD_PLAN.md` §10.1.
