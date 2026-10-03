# 10. Treat code scanning and code quality as organisation-owned state

Date: 2026-10-03

## Status

Accepted

## Context

Code scanning (CodeQL) and code quality are the two security-adjacent controls this template
deliberately does not ship, for the same reason: they are **GitHub-owned state**, not
repository content.

Every other control in the `security` module is a file. gitleaks scans from a workflow.
Scorecard runs in a workflow. `SECURITY.md` and `.gitleaks.toml` are files. All of them are
pinned to commit SHAs (ADR-0009), reviewed through sync pull requests, and visible to
`just health` through the stub sentinel.

Neither of these two can be any of those things. For code scanning, GitHub offers two setups
and the conflict between them resolves against us — from GitHub's documentation:

> When you enable default setup, this disables the existing CodeQL workflow file and blocks
> any CodeQL workflow

and the documented symptom of having both is *"code scanning results are different than you
expected"* — a confusing-result failure, not an error. Code quality has no file-based setup at
all: it is a repository setting that runs CodeQL analyses through GitHub-managed workflows.

Six observations from a live organisation settled it (2026-10-03; org on the **free** plan;
code scanning applied org-wide; code quality set to "let repositories decide"):

| Attempt | Result |
| :--- | :--- |
| Change code-scanning default setup per repository, as an org admin | `422 Code scanning default setup cannot be modified. This setting is controlled by organization administrators.` |
| Read code-scanning default setup from a workflow, `GITHUB_TOKEN` + `security-events: write` | `403 Resource not accessible by integration` |
| Ship `codeql.yml` while the org applies default setup | disabled by GitHub, silently |
| Enable code quality per repository, as a repo admin | **works** — `{"run_id":0}`, then `state: configured` |
| Enable code quality from a workflow, `GITHUB_TOKEN` + `security-events: write` | `403 Resource not accessible by integration` |
| Code quality on a repository containing no code | `languages: []`, and no analysis run produced |

Two things follow. Only a human with repository or organisation administration can change
either control, so **no repository workflow can enable them** — and because the automatic token
cannot even *read* code scanning's state, no workflow can verify it either. There is no version
of these controls the template can express, and none it can honestly check. The last row
matters practically: a repository generated from this template contains no code to analyse
until someone writes some.

It is also worth recording that code quality is **generally available on GitHub Team and
Enterprise Cloud**, and the organisation here is on Free. It is not merely awkward to manage
from the template; on a lower plan it may not be available at all.

The silent-disable row is the dangerous one. A shipped `codeql.yml` would not fail. It would be
present, it would survive review, and it would do nothing — the same shape as the conditional
gitleaks scan rejected in ADR-0010's context above, and the same failure mode this project has
rejected at every other step.

## Decision

The template ships **no CodeQL workflow, no code-quality configuration, and no module for
either**. Both are documented as organisation or repository prerequisites, in the same place
and the same form as the gitleaks licence and the dependency-review org setting.

A repository generated from this template gets code scanning when its organisation enables it,
and gets code quality when a repository administrator enables it under a "let repositories
decide" policy. The generated `SECURITY.md` states that the organisation owns code scanning, so
the boundary is not something a reader has to infer.

## Consequences

- **Both controls are invisible to `just health`.** The health surface reports on files. This is
  the one place where "the module is complete" means something narrower than it does elsewhere.
- **A repository cannot enable either one by itself.** Code scanning needs an organisation
  administrator. Code quality needs an administrator too — just of the repository rather than
  the organisation.
- **An organisation that manages code scanning per repository may add `codeql.yml` by hand.** It
  would be a file no module owns, so `copier update` will leave it alone. That is a supported
  outcome, but not a supported *module*: the template cannot know which posture an organisation
  takes, and guessing wrong produces a workflow that is silently disabled.
- **A reviewer should reject either as a "fix".** Adding a CodeQL workflow to a repository whose
  organisation uses default setup makes things look better without being better.
- **It is worth revisiting** if GitHub ever exposes this state to `GITHUB_TOKEN`, or makes code
  quality available on lower plans, since a verification job — "this repository has code
  scanning" — would then be expressible as a pinned, reviewable check, which is how every other
  control here is handled.
