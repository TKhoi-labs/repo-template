# 8. Assume GitHub, and satisfy local tooling with a devcontainer

Date: 2026-10-03

## Status

Accepted

## Context

Several decisions in this design are only meaningful on one host: the Settings app reading
`.github/settings.yml`, OpenSSF Scorecard, and GitHub's dependency-review action with GHAS on
private repos. The local-environment module has the same shape of choice — a devcontainer or
`direnv`.

These are assumptions rather than questions because presenting them as prompts would imply a
portability the rest of the system does not actually have.

## Decision

We will assume **GitHub** as the only supported host, and implement the `env` module as a
**devcontainer** (`.devcontainer/devcontainer.json`).

The devcontainer installs the tools the other modules invoke — `just`, `yq`, `git-cliff`, and
`adr-tools` — so that `env` is the single place where tool availability is satisfied.

## Consequences

- Host-specific modules need no abstraction layer, and no prompt asks a question whose only
  honest answer is "GitHub".
- Dependency review on **private** repositories requires GitHub Advanced Security. The
  `deps` module's workflow must therefore tolerate a missing GHAS entitlement rather than fail.
- The `env` module is the heaviest module in the set. It is off by default, per the rule that
  no module is enabled without a trigger.
- Because `env` satisfies tooling for `core`, `docs`, and `release`, `justfile` recipes must
  assert that their tools exist and name the missing tool when they do not. Without `env`,
  those recipes fail clearly instead of mysteriously.
- **Deferred:** `direnv` as a lighter alternative. Trigger: a contributor environment where a
  container runtime is unavailable.
