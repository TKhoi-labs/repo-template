# Validation checklist — what the local suite cannot prove

The test suite (`just test`, 143 checks) verifies everything that can be verified without a
GitHub organisation: rendering, module gating, the DAG, file ownership, action pinning, the
four-state health surface, `copier update` idempotency, and answer migration.

The items below need a real org, a real runner, or a container runtime, and are therefore
**unverified**. Each names the failure it would catch, so an item is only ticked off once
someone has actually run it.

---

## 1. Devcontainer builds and installs the tools

`template/.devcontainer/devcontainer.json` is valid JSON and structurally sound, but **no
container runtime was available when it was written**, so it has never been built. It is the
least verified file in the repository.

```bash
copier copy <template> /tmp/dcprobe        # answer module_env=true
code /tmp/dcprobe                          # "Reopen in Container"
```

Then inside the container:

```bash
just --version && git-cliff --version && copier --version
just health                                # must run, not "command not found"
```

Catches: a feature reference that does not resolve, a `postCreateCommand` that needs a
privilege the container user lacks, and the `just` installer writing somewhere not on `PATH`.

## 2. A tagged copy produces a working repository

```bash
copier copy --vcs-ref v0.1.0 gh:<org>/repo-template /tmp/probe
cd /tmp/probe && git init && git add -A && git commit -m "chore: initial"
just health
```

Expected: `.copier-answers.yml` records `_commit: v0.1.0` (a **tag**, never a SHA or `HEAD`),
and `just health` reports core as `🟡 on — incomplete` for `README.md` plus `❓` for every
disabled module. Exit code 1 is correct at this point.

Catches: an untagged template, which breaks `copier update` outright (see ADR-0009 and the
build plan §6.10).

## 3. The settings app applies `.github/settings.yml`

Install the Settings app once per organisation, then push a change to `.github/settings.yml`
on a probe repository.

Expected: labels appear, merge strategy changes, branch protection is applied — with no
per-repository work after the app install.

Catches: a malformed settings file that the app silently rejects, and labels referenced by
workflows (`template-sync`, `dependency`) that do not actually exist.

## 4. The shared reusable workflow exists and the SHA resolves

`ci.yml` calls `https://github.com/<org>/.github/.github/workflows/ci.yml@<sha>`. The `ci`
module is meaningless until that repository exists and that commit is reachable.

```bash
gh api repos/<org>/.github/commits/<sha> --jq .sha
```

Catches: a `workflow_ref` SHA that does not exist, was force-pushed away, or belongs to a
private repository the caller cannot read. A reusable workflow at an unreachable SHA fails
with a less obvious error than a missing tag.

## 5. The sync pull request triggers CI

```bash
gh workflow run copier-sync            # on the probe repository
gh pr list --head chore/copier-sync
```

Expected: a pull request appears **and its checks run**. Then re-run the workflow: the second
run must produce **no new commit and no new pull request**.

Catches: the deadlock this design exists to avoid — a PR opened with the default
`GITHUB_TOKEN` does not trigger workflows, so branch protection blocks it forever. Needs
`COPIER_SYNC_TOKEN` to be a GitHub App installation token or a PAT.

## 6. A diverged repository fails the sync instead of merging badly

Edit a generated file by hand (for example add a line to `justfile`), commit, then run
`copier-sync`.

Expected: the workflow **fails** with *"Template sync conflicted"*, and prints the `.rej`
files. No pull request is opened.

Catches: the silent bad merge. Copier's default conflict mode leaves merge markers in the
files, which `create-pull-request` would commit without complaint.

## 7. Canary rollout and auto-merge

1. Sync one repository first and review the PR by hand.
2. Set repository variable `COPIER_SYNC_AUTO_MERGE=true`.
3. Confirm the next sync PR auto-merges **only after checks pass**.
4. Set `COPIER_SYNC_ENABLED=false` and confirm the schedule no longer syncs, while
   `gh workflow run copier-sync` still does.

Catches: a rollout switch that does not actually switch, and auto-merge that fires before
checks report.

## 8. A `workflow_ref` bump reaches the fleet

Locally verified in `test-matrix.sh`, but not across real tags. Publish a template release
that adds a `_migrations` entry rewriting `workflow_ref`, then sync a probe repository.

Expected: the sync PR contains the new SHA in both `.copier-answers.yml` and
`.github/workflows/ci.yml`.

Catches: a migration whose `version:` does not compare correctly against the recorded tag, so
the fleet silently stays on an old shared workflow.

## 9. Release notes are generated on a real tag

```bash
git tag v0.0.1 && git push origin v0.0.1
```

Expected: a GitHub release whose notes are grouped by Conventional Commit type.

Catches: `git-cliff`'s Tera template failing to render, and `gh release create` lacking
`contents: write`. Neither is exercised by the local suite, which only proves the file
survives Copier untouched.

## 10. Scorecard publishes a result

The `security` module's job requests `id-token: write` in order to publish. Confirm the first
scheduled run uploads SARIF and that the Pinned-Dependencies check is satisfied.

Expected: no Pinned-Dependencies finding, and in particular **no finding for the
reusable-workflow caller in `ci.yml`** — the reason that reference is pinned to a commit SHA
(ADR-0009).

Catches: a regression in the pinning convention, and an org policy with SHA-pinning
enforcement enabled, which turns a tag-pinned caller into a hard failure.
