#!/usr/bin/env bash
# Template-only tooling. Matrix-level properties that the structural suite
# (test-template.sh) does not cover:
#
#   1. realistic module bundles render
#   2. no file is owned by two modules — the "exactly one owning module per
#      file" guardrail, proven by counting rather than by inspecting
#   3. every `uses:` is pinned to a commit SHA (ADR-0009) — otherwise the
#      guarantee decays the moment someone hand-writes a workflow
#   4. `copier update --defaults` produces a zero diff on every configuration,
#      which is the entire reason Copier was chosen over a copy-and-rename
#      template
#
# Property 4 is the one that cannot be checked by reading the template.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIER="${COPIER:-uvx copier}"
BUILD="$ROOT/.build/matrix"
WORKFLOW_SHA=1111111111111111111111111111111111111111

# shellcheck source=scripts/lib/template-snapshot.sh
source "$ROOT/scripts/lib/template-snapshot.sh"
TEMPLATE="$BUILD/template-src"

MODULES="commits ci deps docs contributing env security release ops"

# name|modules to enable
CONFIGS=(
  "core-only|"
  "all-on|$MODULES"
  "core+commits|commits"
  "core+ci|ci"
  "core+deps|deps"
  "core+docs|docs"
  "core+contributing|contributing"
  "core+env|env"
  "core+ci+security|ci security"
  "core+ci+release|ci release"
  "core+ci+ops|ci ops"
  "lib-oss|commits ci deps docs contributing env security release"
  "internal-service|commits ci deps env ops"
  "script|commits docs"
)

pass=0
fail=0
ok() { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

count_files() { find "$1" -type f | wc -l | tr -d ' '; }

render_config() { # name, enabled-modules
  local name="$1"
  local enable="$2"
  local args=() m
  for m in $MODULES; do
    case " $enable " in
      *" $m "*) args+=(-d "module_$m=true") ;;
      *) args+=(-d "module_$m=false") ;;
    esac
  done
  rm -rf "${BUILD:?}/$name"
  # shellcheck disable=SC2086
  $COPIER copy --defaults \
    -d "project_name=$(printf '%s' "$name" | tr '+' '-')" \
    -d org_slug=example -d workflow_ref="$WORKFLOW_SHA" \
    "${args[@]}" "$TEMPLATE" "$BUILD/$name" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Render every configuration once; the checks below all reuse these trees.
# ---------------------------------------------------------------------------
rm -rf "$BUILD"
mkdir -p "$BUILD"
make_template_snapshot "$ROOT" "$TEMPLATE"

echo "== render 14 configurations =="
for entry in "${CONFIGS[@]}"; do
  name="${entry%%|*}"
  enable="${entry#*|}"
  if render_config "$name" "$enable"; then
    ok "rendered $name"
  else
    bad "could not render $name"
  fi
done

# ---------------------------------------------------------------------------
# 1. Ownership: no file is produced by two modules
#
# If two modules owned the same path, the all-on render would contain fewer
# files than the sum of each module's contributions. Counting proves
# disjointness without parsing the template.
# ---------------------------------------------------------------------------
echo "== ownership disjointness =="
c_core=$(count_files "$BUILD/core-only")
c_ci=$(count_files "$BUILD/core+ci")
total_added=$((c_ci - c_core)) # ci contributes on its own

add_module() { # dir, base-count, module
  local added
  added=$(( $(count_files "$1") - $2 ))
  if [ "$added" -le 0 ]; then
    bad "module $3 contributes no files (added=$added)"
  fi
  total_added=$((total_added + added))
}

for m in commits deps docs contributing env; do
  add_module "$BUILD/core+$m" "$c_core" "$m"
done
for m in security release ops; do
  add_module "$BUILD/core+ci+$m" "$c_ci" "$m"
done

all_added=$(( $(count_files "$BUILD/all-on") - c_core ))
if [ "$total_added" -eq "$all_added" ]; then
  ok "modules own disjoint file sets ($all_added files, no overlap)"
else
  bad "file ownership overlaps: sum of per-module files=$total_added, all-on=$all_added"
fi

# ---------------------------------------------------------------------------
# 2. Every uses: is pinned to a commit SHA (ADR-0009)
# ---------------------------------------------------------------------------
echo "== action pinning =="
for entry in "${CONFIGS[@]}"; do
  name="${entry%%|*}"
  dir="$BUILD/$name/.github/workflows"
  [ -d "$dir" ] || continue
  if grep -rhoE 'uses: [^ ]+' "$dir" | grep -qvE '@[0-9a-f]{40}$'; then
    bad "$name has an unpinned uses:"
    grep -rhnE 'uses: [^ ]+' "$dir" | grep -vE '@[0-9a-f]{40}$' | sed 's/^/        /'
  else
    ok "$name: all uses: pinned"
  fi
done

# ---------------------------------------------------------------------------
# 3. copier update --defaults is a no-op
#
# A tag is required: with no tags Copier records an abbreviated SHA, which
# cannot be fetched from the filtered clone it uses on update.
# ---------------------------------------------------------------------------
echo "== update idempotency =="
for entry in "${CONFIGS[@]}"; do
  name="${entry%%|*}"
  dir="$BUILD/$name"
  [ -d "$dir" ] || continue

  recorded="$(sed -n 's/^_commit: *//p' "$dir/.copier-answers.yml")"
  case "$recorded" in
    v[0-9]*) ;;
    *) bad "$name recorded a non-tag _commit: $recorded" ;;
  esac

  rm -rf "$dir/.git"
  (
    cd "$dir"
    git init -q .
    git add -A
    git -c user.email=test@example.invalid -c user.name=Tester commit -qm "initial"
  ) >/dev/null 2>&1

  rc=0
  # shellcheck disable=SC2086
  ( cd "$dir" && $COPIER update --defaults --trust . ) \
    >"$BUILD/update-$(printf '%s' "$name" | tr '+' '-').log" 2>&1 || rc=$?

  dirty="$(cd "$dir" && git status --porcelain)"
  if [ "$rc" -ne 0 ]; then
    bad "$name: copier update exited $rc"
    tail -3 "$BUILD/update-$(printf '%s' "$name" | tr '+' '-').log" | sed 's/^/        /'
  elif [ -n "$dirty" ]; then
    bad "$name: copier update was not a no-op"
    printf '%s\n' "$dirty" | sed 's/^/        /'
  else
    ok "$name: update is a no-op"
  fi
done

# ---------------------------------------------------------------------------
# 4. A _migrations entry rewrites a recorded answer on update
#
# This is the documented way to roll a new workflow_ref across a fleet:
# `copier update --defaults` never re-asks a question, so a new SHA has to be
# migrated into .copier-answers.yml explicitly (ADR-0009). Verified rather than
# assumed, because the decision to pin workflow_ref to a SHA depends on it.
# ---------------------------------------------------------------------------
echo "== answer migration =="
MIG="$BUILD/migrate"
SHA_A=1111111111111111111111111111111111111111
SHA_B=2222222222222222222222222222222222222222
MIGSRC="$MIG/src"
MIGDST="$MIG/dst"

rm -rf "$MIG"
mkdir -p "$MIGSRC"
rsync -a --exclude .git --exclude .build "$ROOT/" "$MIGSRC/"
(
  cd "$MIGSRC"
  git init -q .
  git add -A
  git -c user.email=test@example.invalid -c user.name=Tester commit -qm v0.1
  git tag v0.1.0
) >/dev/null 2>&1

# shellcheck disable=SC2086
$COPIER copy --defaults -d project_name=migrate -d org_slug=example \
  -d workflow_ref="$SHA_A" -d module_commits=false -d module_deps=false \
  -d module_docs=false -d module_contributing=false -d module_env=false \
  -d module_security=false -d module_release=false -d module_ops=false \
  "$MIGSRC" "$MIGDST" >/dev/null 2>&1
(
  cd "$MIGDST"
  git init -q .
  git add -A
  git -c user.email=test@example.invalid -c user.name=Tester commit -qm initial
) >/dev/null 2>&1

# The template moves on: a new release adds a migration that rewrites the
# recorded answer before the project is re-rendered.
cat >>"$MIGSRC/copier.yml" <<'YAML'

# Fleet rollout: copier update --defaults never re-asks a question, so a new
# workflow_ref has to be migrated into the recorded answers explicitly.
_migrations:
  - version: v0.2.0
    before:
      - >-
        sed -i "s/^workflow_ref:.*/workflow_ref: '__SHA__'/" .copier-answers.yml
YAML
sed -i "s/__SHA__/$SHA_B/" "$MIGSRC/copier.yml"
(
  cd "$MIGSRC"
  git add -A
  git -c user.email=test@example.invalid -c user.name=Tester commit -qm v0.2
  git tag v0.2.0
) >/dev/null 2>&1

rc=0
# shellcheck disable=SC2086
(cd "$MIGDST" && $COPIER update --defaults --trust .) >"$MIG/update.log" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "migration: copier update exits 0"
else
  bad "migration: copier update exited $rc"
  tail -3 "$MIG/update.log" | sed 's/^/        /'
fi

if grep -q "$SHA_B" "$MIGDST/.copier-answers.yml"; then
  ok "migration: recorded answer rewritten"
else
  bad "migration: answers still record the old SHA"
fi

if grep -q "$SHA_B" "$MIGDST/.github/workflows/ci.yml"; then
  ok "migration: ci.yml re-rendered with the new SHA"
else
  bad "migration: ci.yml still uses the old SHA"
fi

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
