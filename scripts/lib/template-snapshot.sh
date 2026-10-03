#!/usr/bin/env bash
# Shared by the test scripts. Not rendered into generated repos.
#
# Builds a tagged snapshot of the template working tree.
#
# Two reasons this exists rather than rendering straight from the repo root:
#
# 1. Determinism. Copier reads the *latest tag* when a template is tagged, and
#    otherwise falls back to HEAD while including uncommitted changes. So
#    without a snapshot, adding a release tag to this repo would silently make
#    the suite test stale tagged content instead of the working tree.
#
# 2. `copier update` cannot work without one. With no tags, Copier records an
#    abbreviated SHA (e.g. `8204256`) in `.copier-answers.yml`. On update it
#    clones with a filtered transport, where an abbreviated SHA cannot be
#    resolved because you cannot `fetch` a short SHA. The result is:
#
#        error: pathspec '8204256' did not match any file(s) known to git
#
#    A tag is a fetchable ref, so it resolves. This is also why the design
#    requires pinning the template to a tag rather than HEAD.
#
# make_template_snapshot <root> <dest>
make_template_snapshot() {
  local root="${1:?make_template_snapshot: root required}"
  local dest="${2:?make_template_snapshot: dest required}"

  [ -d "$root" ] || { printf 'snapshot: %s is not a directory\n' "$root" >&2; return 1; }
  rm -rf "$dest"
  mkdir -p "$dest"
  # Exclude .build so the snapshot cannot recurse into itself.
  rsync -a --exclude .git --exclude .build "$root/" "$dest/"

  (
    cd "$dest"
    git init -q .
    git add -A
    git -c user.email=template@example.invalid \
      -c user.name="Template Snapshot" \
      commit -qm "snapshot of the template working tree"
    # A PEP 440-compatible tag, so Copier recognises it as the latest version
    # rather than falling back to HEAD.
    git tag v0.0.1
  )
}
