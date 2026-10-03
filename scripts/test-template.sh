#!/usr/bin/env bash
# Template-only tooling. Lives outside template/, so it is never rendered into
# a generated repo.
#
# Renders a matrix of module combinations and asserts the properties that
# copier update depends on. Phase 1 covers: the answers manifest exists and is
# complete, conditional files appear and disappear correctly, and DAG
# violations fail loudly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIER="${COPIER:-uvx copier}"
BUILD="$ROOT/.build"

MODULES=(commits ci deps docs contributing env security release ops)

pass=0
fail=0
ok() { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

expect_file() { [ -f "$1" ] && ok "exists  ${1#"$BUILD"/}" || bad "missing ${1#"$BUILD"/}"; }
expect_absent() { [ ! -e "$1" ] && ok "absent  ${1#"$BUILD"/}" || bad "present ${1#"$BUILD"/}"; }

# render <name> [extra -d args...]
render() {
  local name="$1"
  shift
  rm -rf "$BUILD/$name"
  # shellcheck disable=SC2086
  $COPIER copy --defaults -d "project_name=$name" "$@" "$ROOT" "$BUILD/$name" >/dev/null 2>&1
}

# Build the "everything off" argument list once.
off_args=()
for m in "${MODULES[@]}"; do off_args+=(-d "module_$m=false"); done

# ---------------------------------------------------------------------------
# 1. core-only: renders, manifest complete, no optional module files
# ---------------------------------------------------------------------------
echo "== core-only =="
render core-only "${off_args[@]}"
manifest="$BUILD/core-only/.copier-answers.yml"
expect_file "$manifest"

if [ -f "$manifest" ]; then
  for m in "${MODULES[@]}"; do
    if grep -q "^module_$m:" "$manifest"; then
      ok "manifest records module_$m"
    else
      bad "manifest missing module_$m"
    fi
  done
fi

expect_file "$BUILD/core-only/justfile"
expect_file "$BUILD/core-only/lefthook.yml"
expect_file "$BUILD/core-only/.github/settings.yml"
expect_absent "$BUILD/core-only/.github/workflows/ci.yml"
expect_absent "$BUILD/core-only/.github/workflows/commitlint.yml"
expect_absent "$BUILD/core-only/SECURITY.md"
expect_absent "$BUILD/core-only/CONTRIBUTING.md"
expect_absent "$BUILD/core-only/cliff.toml"

# ---------------------------------------------------------------------------
# 2. all-on: every conditional file appears, no directory-gating surprises
# ---------------------------------------------------------------------------
echo "== all-on =="
on_args=()
for m in "${MODULES[@]}"; do on_args+=(-d "module_$m=true"); done
render all-on "${on_args[@]}"
expect_file "$BUILD/all-on/.github/workflows/ci.yml"
expect_file "$BUILD/all-on/.github/workflows/commitlint.yml"
expect_file "$BUILD/all-on/.github/workflows/dependency-review.yml"
expect_file "$BUILD/all-on/.github/workflows/scorecard.yml"
expect_file "$BUILD/all-on/.github/workflows/gitleaks.yml"
expect_file "$BUILD/all-on/.github/workflows/release.yml"
expect_file "$BUILD/all-on/SECURITY.md"
expect_file "$BUILD/all-on/CONTRIBUTING.md"
expect_file "$BUILD/all-on/cliff.toml"
expect_file "$BUILD/all-on/.commitlintrc.json"
expect_file "$BUILD/all-on/renovate.json"
expect_file "$BUILD/all-on/.devcontainer/devcontainer.json"
expect_file "$BUILD/all-on/.github/CODEOWNERS"

# ---------------------------------------------------------------------------
# 3. DAG closure: security/release/ops each render with ci present
# ---------------------------------------------------------------------------
echo "== DAG closure (ci + dependent) =="
for m in security release ops; do
  render "core-ci-$m" -d module_ci=true -d "module_$m=true"
done
expect_file "$BUILD/core-ci-security/.github/workflows/scorecard.yml"
expect_file "$BUILD/core-ci-release/.github/workflows/release.yml"
expect_absent "$BUILD/core-ci-security/.github/workflows/release.yml"

# ---------------------------------------------------------------------------
# 4. Negative: a DAG violation must fail loudly and leave nothing behind
# ---------------------------------------------------------------------------
echo "== negative DAG =="
for m in security release ops; do
  rm -rf "$BUILD/negative-$m"
  if $COPIER copy --defaults -d "project_name=negative-$m" \
      -d module_ci=false -d "module_$m=true" "$ROOT" "$BUILD/negative-$m" \
      >/dev/null 2>&1; then
    bad "module_$m without ci should have failed"
  else
    ok "module_$m without ci fails"
  fi
  expect_absent "$BUILD/negative-$m"
done

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
