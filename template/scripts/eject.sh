#!/usr/bin/env bash
# Leave the template.
#
# Removes the files that exist only to relate this repository to the template it
# was generated from, so the repository stands on its own. Copier cannot do this
# for you: `copier update` never deletes files, so no template answer can remove
# anything. The exit has to happen here, in the repository.
#
# What goes: the answers file, the sync workflow, the module health report, the
# ADR that records generation-time module decisions, this script, and the
# references to them that can be edited safely. The ADR skeleton stays — it is
# the blank form `docs/adr/README.md` tells you to copy.
#
# What stays: everything else. The workflows, the devcontainer, the justfile
# recipes that do not read the module manifest, the docs, the settings, the issue
# forms and your own files. This is a detach, not a cleanup.
#
# Usage:
#   scripts/eject.sh            # print what would change, touch nothing
#   scripts/eject.sh --yes      # apply
#
# Every step tolerates a file that is already gone, and the script removes itself
# last, so an interrupted run can simply be run again.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

apply=0
case "${1:-}" in
"" | --dry-run) ;;
--yes | -y) apply=1 ;;
*)
  printf 'usage: scripts/eject.sh [--dry-run|--yes]\n' >&2
  exit 2
  ;;
esac

if [ "$apply" -eq 1 ]; then
  verb="remove"
  editverb="edit"
else
  verb="would remove"
  editverb="would edit"
fi

# Files whose only purpose is the relationship with the template. 0000-template.md
# is deliberately absent: it is the ADR skeleton, so it is content.
BOOKKEEPING=(
  .copier-answers.yml
  .github/workflows/copier-sync.yml
  scripts/health.sh
  docs/adr/0001-initial-deferrals.md
  scripts/eject.sh
)

# Recipes that call scripts/health.sh, or that would call this script. Dropped
# from the justfile and from lefthook, which runs `just health` before a push.
RECIPES='health check eject'

# ---------------------------------------------------------------------------
# Drop whole blocks from a YAML or justfile file.
#
# A block is a comment run plus a `key:` line at column 0 plus its indented
# continuation, ending at the first blank line or the next top-level line. This is
# why the dry run exists: the caller sees which file changes before it is written.
# ---------------------------------------------------------------------------
drop_blocks() {
  local file="$1" keys="${2:-$RECIPES}"
  awk -v drop="$keys" -v dropcomment='`just health`' '
    BEGIN {
      n = split(drop, d, " ")
      for (i = 1; i <= n; i++) dropped[d[i]] = 1
      held = ""
      skipping = 0
    }
    /^[A-Za-z][A-Za-z0-9_-]*[^:]*:/ {
      key = $0
      sub(/[ \t].*/, "", key)
      sub(/:.*/, "", key)
      skipping = (key in dropped)
      if (!skipping) printf "%s", held
      held = ""
      if (!skipping) print
      next
    }
    /^[[:space:]]+/ { if (!skipping) print; next }
    /^#/ {
      if (skipping) next
      if (index($0, dropcomment) > 0) next
      held = held $0 ORS
      next
    }
    /^$/ {
      if (!skipping) { printf "%s", held; print }
      held = ""
      skipping = 0
      next
    }
    {
      if (!skipping) { printf "%s", held; print }
      held = ""
      skipping = 0
    }
  ' "$file"
}

# drop_matched <file> <extended regex of lines to drop>
drop_matched() {
  local file="$1" pattern="$2"
  grep -v -E "$pattern" "$file" || true
}

# edit_file <file> <label> <command producing the new contents>
edit_file() {
  local file="$1" label="$2"
  shift 2
  [ -f "$file" ] || return 0
  printf '  %-12s %-24s %s\n' "$editverb" "$file" "$label"
  [ "$apply" -eq 1 ] || return 0
  local tmp
  tmp="$(mktemp)"
  "$@" >"$tmp"
  mv "$tmp" "$file"
}

echo "Leaving the template."
echo

echo "Bookkeeping:"
removed=0
for f in "${BOOKKEEPING[@]}"; do
  [ -e "$f" ] || continue
  printf '  %-11s %s\n' "$verb" "$f"
  removed=$((removed + 1))
  [ "$apply" -eq 1 ] && rm -f "$f"
done
[ "$removed" -gt 0 ] || echo "  nothing left to remove"

echo
echo "References to it:"
edit_file justfile "drops the health, check and eject recipes" drop_blocks justfile "$RECIPES"
# The whole pre-push block goes, because in the template it holds the health hook
# and nothing else. It is named in the dry run, so any command added there is seen
# before it is lost.
edit_file lefthook.yml "drops its pre-push block (the health hook)" \
  drop_blocks lefthook.yml "pre-push"
# shellcheck disable=SC2016  # a CODEOWNERS path, not shell syntax
edit_file .github/CODEOWNERS "drops the /.copier-answers.yml line" \
  drop_matched .github/CODEOWNERS '^/\.copier-answers\.yml '
edit_file docs/adr/README.md "drops the row for the removed ADR" \
  drop_matched docs/adr/README.md '0001-initial-deferrals\.md'

echo
echo "Prose that still talks about the template, for you to edit:"
# The files about to be removed are excluded: in a dry run they are still on
# disk, and listing them would be noise.
#
# The stub marker is assembled from two pieces for the same reason health.sh does
# it: a file that contains the sentinel is reported as an unfinished stub, and this
# script is not one.
SENTINEL="TEMPLATE-""STUB"
REFS="copier|template sync|Generated files|just health|module manifest|$SENTINEL"
found=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  found=$((found + 1))
  printf '  review       %s\n' "$f"
  grep -n -m3 -E "$REFS" "$f" 2>/dev/null | sed 's/^/                 /' || true
done < <(grep -rl -E "$REFS" . --exclude-dir=.git \
  --exclude=.copier-answers.yml --exclude=copier-sync.yml --exclude=health.sh \
  --exclude=eject.sh --exclude=0001-initial-deferrals.md 2>/dev/null | sort)
[ "$found" -gt 0 ] || echo "  nothing — no reference to the template is left"

echo
if [ "$apply" -eq 1 ]; then
  # health.sh and this script were the only files in scripts/, and an empty
  # directory is noise that git would not even track.
  rmdir scripts 2>/dev/null || true
  echo "Done. This repository no longer syncs with the template and no longer"
  echo "tracks its modules. Nothing here is generated any more: edit freely."
  echo
  echo "Still to review: the prose listed above."
else
  echo "Dry run — nothing was changed. Apply with:"
  echo
  echo "  scripts/eject.sh --yes"
fi
