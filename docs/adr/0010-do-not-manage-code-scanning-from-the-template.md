# 10. Do not manage code scanning from the template

Date: 2026-10-03

## Status

Accepted

## Context

Code scanning (CodeQL) is the one security control this template deliberately does **not**
ship, and the reason is a property of GitHub rather than a preference. Every other control in
the `security` module is a file: gitleaks scans from a workflow, Scorecard runs in a workflow,
`SECURITY.md` and `.gitleaks.toml` are files. All of them are pinned to commit SHAs
(ADR-0009), reviewed through sync pull requests, and visible to `just health` through the stub
sentinel.

Code scanning cannot be any of those things. GitHub offers two setups, and neither fits:

- **Default setup** — GitHub generates and manages the workflow. It is a repository *setting*,
  not a file, so it cannot be pinned, reviewed, or seen by the sentinel grep.
- **Advanced setup** — a `codeql.yml` workflow, which would fit the template's model.

They are mutually exclusive, and the conflict resolves against us. From GitHub's
documentation:

> When you enable default setup, this disables the existing CodeQL workflow file and blocks
> any CodeQL workflow

and the documented symptom of having both is *"code scanning results are different than you
expected"* — a confusing-result failure, not an error.

Three observations from a live organisation settled it (2026-10-03, org on the free plan,
CodeQL default setup applied to all repositories):

| Attempt | Result |
| :--- | :--- |
| Change default setup per repository, as an org admin with a `repo`-scoped token | `422 Code scanning default setup cannot be modified. This setting is controlled by organization administrators.` |
| Read default setup from a workflow using `GITHUB_TOKEN` with `security-events: write` | `403 Resource not accessible by integration` |
| Ship `codeql.yml` while the org applies default setup | disabled by GitHub, silently |

The first two matter more than they look. The setting is **locked to organisation
administrators**, so no repository workflow can enable it — not with the automatic token, not
with `security-events: write`. And because the automatic token cannot even *read* the state, a
workflow cannot verify it either. There is no version of this control that the template can
express, and no honest version it can check.

The third observation is the dangerous one. A shipped `codeql.yml` would not fail; it would be
present, appear correct in review, and do nothing. That is the failure mode this build has
rejected at every other step — the conditional gitleaks scan that "appears to work while
scanning nothing", the auto-merge that merges without looking.

## Decision

The template does not ship a CodeQL workflow, and does not add a `codeql` module. Code
scanning is documented as an **organisation prerequisite**, in the same place and in the same
form as the gitleaks licence and the dependency-review org setting.

A repository generated from this template gets code scanning when its organisation enables it,
and gets nothing when it does not. The generated `SECURITY.md` states that ownership, so the
boundary is not something a reader has to infer.

## Consequences

- **Code scanning is invisible to `just health`.** The health surface reports on files. A
  control that is a setting cannot appear in it, and this is the one place where "the module
  is complete" means something narrower than it does elsewhere.
- **A generated repository cannot opt in.** Enabling it needs an organisation administrator or
  the repository's own settings page. The template's answer is a documented prerequisite, not
  a workflow.
- **An organisation that manages code scanning per repository may add `codeql.yml` by hand.**
  It would be a file no module owns, so `copier update` will leave it alone. That is a
  supported outcome, not a supported *module*: the template cannot know which posture an
  organisation takes, and guessing wrong produces a silently disabled workflow.
- **It is worth revisiting** if GitHub ever exposes the default-setup state to `GITHUB_TOKEN`,
  since a verification job — "this repository has code scanning" — would then be expressible
  as a pinned, reviewable check, which is how every other control here is handled.
