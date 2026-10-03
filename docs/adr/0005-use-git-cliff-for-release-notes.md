# 5. Use git-cliff to generate release notes

Date: 2026-10-03

## Status

Accepted

## Context

Repos that publish a versioned artifact need a changelog. Because the `commits` module already
enforces Conventional Commits, the commit history is already structured data — a changelog can
be derived from it rather than maintained by hand.

Two candidates were considered: `git-cliff`, which generates from history via a config file,
and `release-please`, which mediates releases through pull requests.

## Decision

We will use **git-cliff**, configured by `cliff.toml`, and expose its local form as
`just changelog`. `release-please-config.json` is deliberately **not** shipped: the two are
alternatives, not companions, and shipping both would be a no-op configuration.

## Consequences

- No bot participates in the release path. A release is a workflow run over history.
- Release quality is a function of commit-message quality, which makes the `commits` module a
  soft prerequisite: `release` is far less useful without it, though not broken.
- **Deferred:** PR-gated releases with human review of version bumps. Trigger: the first time a
  bad version is published, or a consumer requires a reviewable release PR.
