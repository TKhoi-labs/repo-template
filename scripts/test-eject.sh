#!/usr/bin/env bash
# Template-only tooling. Exercises scripts/eject.sh — the exit from the template.
#
# Ejecting is one-way and deletes files, so it is tested against disposable
# renders rather than described: what goes, what stays, and that a detached
# repository cannot be updated back into a generated one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIER="${COPIER:-uvx copier}"
BUILD="$ROOT/.build/eject"

# shellcheck source=scripts/lib/template-snapshot.sh
source "$ROOT/scripts/lib/template-snapshot.sh"
TEMPLATE="$BUILD/template-src"

MODULES=(commits ci deps docs contributing env security release ops)
SHA=1111111111111111111111111111111111111111

pass=0
fail=0
ok() { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() {
  printf '  FAIL  %s\n' "$1"
  fail=$((fail + 1))
}

exists() { [ -e "$1" ]; }
expect_present() { if exists "$1"; then ok "present  $2"; else bad "missing  $2"; fi; }
expect_gone() { if exists "$1"; then bad "still there  $2"; else ok "gone     $2"; fi; }
expect_contains() {
  if grep -q -- "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3"; fi
}
expect_absent() {
  if grep -q -- "$2" "$1" 2>/dev/null; then bad "$3"; else ok "$3"; fi
}
expect_exec() {
  if [ -x "$1" ]; then ok "executable  $2"; else bad "not executable  $2"; fi
}

rm -rf "$BUILD"
mkdir -p "$BUILD"
make_template_snapshot "$ROOT" "$TEMPLATE"

# render <dir> [key=value...] — every module on, so the optional recipes exist.
render() {
  local dir="$1"
  shift
  local args=()
  local m
  for m in "${MODULES[@]}"; do args+=(-d "module_$m=true"); done
  rm -rf "$dir"
  # shellcheck disable=SC2086
  $COPIER copy --defaults -d project_name=eject-test -d org_slug=example \
    -d workflow_ref="$SHA" -d codeowners_team=@example/maintainers \
    "${args[@]}" "$@" "$TEMPLATE" "$dir" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 1. the dry run changes nothing
# ---------------------------------------------------------------------------
echo "== dry run =="
D="$BUILD/all-on"
render "$D"
expect_exec "$D/scripts/eject.sh" "the script ships executable"

rc=0
DRY="$(cd "$D" && bash scripts/eject.sh 2>&1)" || rc=$?
if [ "$rc" -eq 0 ]; then ok "dry run exits 0"; else bad "dry run exited $rc"; fi
expect_present "$D/.copier-answers.yml" "the dry run kept .copier-answers.yml"
expect_present "$D/scripts/health.sh" "the dry run kept scripts/health.sh"
if printf '%s' "$DRY" | grep -q 'would remove .copier-answers.yml'; then
  ok "the dry run names what it would remove"
else
  bad "the dry run does not say what it would remove"
fi
if printf '%s' "$DRY" | grep -q -- '--yes'; then
  ok "the dry run says how to apply"
else
  bad "the dry run does not say how to apply"
fi

# ---------------------------------------------------------------------------
# 2. applying removes the bookkeeping and nothing else of substance
# ---------------------------------------------------------------------------
echo "== apply =="
rc=0
APPLY="$(cd "$D" && bash scripts/eject.sh --yes 2>&1)" || rc=$?
if [ "$rc" -eq 0 ]; then ok "apply exits 0"; else bad "apply exited $rc"; fi

for f in .copier-answers.yml .github/workflows/copier-sync.yml scripts/health.sh \
  docs/adr/0001-initial-deferrals.md scripts/eject.sh; do
  expect_gone "$D/$f" "$f"
done

# The ADR skeleton is content, not bookkeeping: docs/adr/README.md tells you to
# copy it, so ejecting must not take it.
expect_present "$D/docs/adr/0000-template.md" "docs/adr/0000-template.md (the ADR skeleton)"
for f in .github/workflows/ci.yml .github/settings.yml lefthook.yml cliff.toml \
  .devcontainer/devcontainer.json docs/architecture.md README.md SECURITY.md \
  .github/ISSUE_TEMPLATE/bug.yml; do
  expect_present "$D/$f" "$f (content, kept)"
done

# ---------------------------------------------------------------------------
# 3. the references that can be edited safely are edited
# ---------------------------------------------------------------------------
echo "== references =="
expect_absent "$D/justfile" '^health:' "justfile: no health recipe"
expect_absent "$D/justfile" '^check:' "justfile: no check recipe"
expect_absent "$D/justfile" '^eject' "justfile: no eject recipe"
expect_contains "$D/justfile" '^default:' "justfile: default recipe kept"
expect_contains "$D/justfile" '^secrets:' "justfile: secrets recipe kept"
expect_contains "$D/justfile" '^changelog:' "justfile: changelog recipe kept"

expect_absent "$D/lefthook.yml" '^pre-push:' "lefthook: pre-push hook dropped"
expect_contains "$D/lefthook.yml" '^commit-msg:' "lefthook: commit-msg hook kept"

expect_absent "$D/.github/CODEOWNERS" '\.copier-answers\.yml' \
  "CODEOWNERS: the answers-file line dropped"
expect_contains "$D/.github/CODEOWNERS" '^/\.github/workflows/' \
  "CODEOWNERS: the workflows line kept"

expect_absent "$D/docs/adr/README.md" '0001-initial-deferrals' "ADR index: removed row dropped"
expect_contains "$D/docs/adr/README.md" '0000-template.md' "ADR index: skeleton row kept"

# An empty scripts/ directory would be left behind by the two deletions.
if [ -d "$D/scripts" ]; then bad "scripts/ was left behind empty"; else ok "gone     scripts/ (emptied)"; fi

# ---------------------------------------------------------------------------
# 4. the prose it cannot safely rewrite is reported instead
# ---------------------------------------------------------------------------
echo "== report =="
for f in docs/architecture.md CONTRIBUTING.md README.md; do
  if printf '%s' "$APPLY" | grep -q "$f"; then
    ok "the report names $f for review"
  else
    bad "the report does not mention $f"
  fi
done
if printf '%s' "$APPLY" | grep -q 'no longer syncs with the template'; then
  ok "the report states the repository is detached"
else
  bad "the report does not state what happened"
fi

# ---------------------------------------------------------------------------
# 5. detached means detached: the update path is gone
# ---------------------------------------------------------------------------
echo "== detached =="
(
  cd "$D"
  git init -q .
  git add -A
  git -c user.email=test@example.invalid -c user.name=Tester commit -qm ejected
) >/dev/null 2>&1

rc=0
( cd "$D" && $COPIER update --defaults --trust . ) >"$BUILD/update.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  ok "copier update refuses in an ejected repository"
else
  bad "copier update still succeeded after eject"
fi
expect_gone "$D/.copier-answers.yml" "no answers file was recreated"
expect_gone "$D/.github/workflows/copier-sync.yml" "no sync workflow was recreated"

# ---------------------------------------------------------------------------
# 6. a core-only render ejects just as cleanly
# ---------------------------------------------------------------------------
echo "== core only =="
C="$BUILD/core-only"
rm -rf "$C"
off_args=()
for m in "${MODULES[@]}"; do off_args+=(-d "module_$m=false"); done
# shellcheck disable=SC2086
$COPIER copy --defaults -d project_name=eject-min -d org_slug=example \
  -d workflow_ref="$SHA" "${off_args[@]}" "$TEMPLATE" "$C" >/dev/null 2>&1

rc=0
MIN="$(cd "$C" && bash scripts/eject.sh --yes 2>&1)" || rc=$?
if [ "$rc" -eq 0 ]; then ok "core-only apply exits 0"; else bad "core-only apply exited $rc"; fi
expect_gone "$C/.copier-answers.yml" "core-only: answers file"
expect_present "$C/justfile" "core-only: justfile kept"
expect_absent "$C/justfile" '^health:' "core-only: health recipe dropped"
expect_contains "$C/justfile" '^default:' "core-only: default recipe kept"
# No security module, so there is no secrets recipe: the block dropper must not
# invent one, nor leave a comment pointing at a recipe that is not there.
expect_absent "$C/justfile" '^secrets:' "core-only: no secrets recipe"
if printf '%s' "$MIN" | grep -q 'no longer syncs with the template'; then
  ok "core-only: the report still runs"
else
  bad "core-only: the report did not run"
fi

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
