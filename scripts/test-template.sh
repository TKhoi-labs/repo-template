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
expect_contains() {
  if grep -q -- "$2" "$1" 2>/dev/null; then
    ok "$(basename "$1") contains: $2"
  else
    bad "$(basename "$1") missing: $2"
  fi
}

# Assert exactly which files in a rendered repo are still stubs. Anything not
# listed must have been authored, so a forgotten file cannot pass by rendering
# as a placeholder.
expect_stub_set() {
  local dir="$1"
  shift
  local expected actual
  expected="$(printf '%s\n' "$@" | sort)"
  actual="$(grep -rl 'TEMPLATE-STUB' "$dir" 2>/dev/null | sed "s#^$dir/##" | sort)"
  if [ "$actual" = "$expected" ]; then
    ok "stub set matches: $(printf '%s' "$expected" | tr '\n' ' ')"
  else
    bad "stub set mismatch"
    printf '        expected: %s\n        actual:   %s\n' \
      "$(printf '%s' "$expected" | tr '\n' ' ')" \
      "$(printf '%s' "$actual" | tr '\n' ' ')"
  fi
}

# render <name> [extra -d args...]
render() {
  local name="$1"
  shift
  rm -rf "$BUILD/$name"
  # shellcheck disable=SC2086
  $COPIER copy --defaults -d "project_name=$name" -d org_slug=example \
    -d workflow_ref=1111111111111111111111111111111111111111 "$@" \
    "$ROOT" "$BUILD/$name" >/dev/null 2>&1
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
# 5. Every module's content is authored, not stubbed
#
# Only two kinds of file may still be a stub: the README, because a repository
# without a real README is genuinely unfinished, and the ops documents, whose
# content is site-specific by nature.
# ---------------------------------------------------------------------------
echo "== module content =="
expect_stub_set "$BUILD/core-only" "README.md"
expect_stub_set "$BUILD/all-on" "README.md" \
  "docs/runbooks/README.md" "observability/README.md"

expect_contains "$BUILD/all-on/.commitlintrc.json" "config-conventional"
expect_contains "$BUILD/all-on/.github/workflows/ci.yml" "uses: example/.github"
expect_contains "$BUILD/all-on/.github/workflows/ci.yml" \
  "@1111111111111111111111111111111111111111"
expect_contains "$BUILD/all-on/.github/workflows/commitlint.yml" "@commitlint/cli"
expect_contains "$BUILD/all-on/.github/workflows/commitlint.yml" "base.sha"
expect_contains "$BUILD/all-on/.github/workflows/scorecard.yml" "ossf/scorecard-action"
expect_contains "$BUILD/all-on/.github/workflows/gitleaks.yml" "gitleaks/gitleaks-action"
expect_contains "$BUILD/all-on/.github/workflows/dependency-review.yml" "dependency-review-action"
expect_contains "$BUILD/all-on/.github/workflows/release.yml" "git-cliff"
expect_contains "$BUILD/all-on/renovate.json" "pinGitHubActionDigests"
expect_contains "$BUILD/all-on/cliff.toml" "conventional_commits"
expect_contains "$BUILD/all-on/.gitleaks.toml" "useDefault"
expect_contains "$BUILD/all-on/.devcontainer/devcontainer.json" "devcontainers/base"
expect_contains "$BUILD/all-on/.github/CODEOWNERS" "@example/maintainers"
expect_contains "$BUILD/all-on/CONTRIBUTING.md" "Conventional Commits"
expect_contains "$BUILD/all-on/SECURITY.md" "private vulnerability reporting"
expect_contains "$BUILD/all-on/docs/architecture.md" "Repository state"
expect_contains "$BUILD/all-on/docs/adr/README.md" "deferrals"
# Tera syntax in cliff.toml must survive Copier untouched
expect_contains "$BUILD/all-on/cliff.toml" '{{ version }}'
# GitHub expressions in workflows must survive Copier untouched
expect_contains "$BUILD/all-on/.github/workflows/gitleaks.yml" 'secrets.GITHUB_TOKEN'
expect_contains "$BUILD/core-only/justfile" "scripts/health.sh"
expect_contains "$BUILD/core-only/lefthook.yml" "just health"
expect_contains "$BUILD/core-only/.github/workflows/copier-sync.yml" "copier update --defaults"
expect_contains "$BUILD/core-only/.github/ISSUE_TEMPLATE/bug.yml" "required: true"
expect_contains "$BUILD/core-only/.github/ISSUE_TEMPLATE/config.yml" "blank_issues_enabled: false"

# contributing contributes only to the core-owned settings file
expect_contains "$BUILD/core-only/.github/settings.yml" "required_approving_review_count: 0"
expect_contains "$BUILD/all-on/.github/settings.yml" "required_approving_review_count: 2"
expect_contains "$BUILD/all-on/.github/settings.yml" "no merge without review"

# commits and security contribute only to the core-owned hook file
expect_contains "$BUILD/core-only/lefthook.yml" "pre-push:"
expect_contains "$BUILD/all-on/lefthook.yml" "commitlint"
expect_contains "$BUILD/all-on/lefthook.yml" "gitleaks"

# ---------------------------------------------------------------------------
# 6. License rendering
# ---------------------------------------------------------------------------
echo "== license =="
render core-none "${off_args[@]}" -d license=None
expect_absent "$BUILD/core-none/LICENSE"
render core-prop "${off_args[@]}" -d license=Proprietary
expect_contains "$BUILD/core-prop/LICENSE" "All rights reserved"
expect_contains "$BUILD/core-prop/LICENSE" "Copyright (c) 2026"

# ---------------------------------------------------------------------------
# 7. Rendered output is lint-clean
#
# Jinja conditionals in YAML are where whitespace bugs hide: a stray blank
# line at end of file is an error, and it is invisible in the template.
# ---------------------------------------------------------------------------
echo "== rendered lint =="
YAMLLINT="${YAMLLINT:-}"
if [ -z "$YAMLLINT" ]; then
  if command -v yamllint >/dev/null 2>&1; then
    YAMLLINT="yamllint"
  elif command -v uvx >/dev/null 2>&1; then
    YAMLLINT="uvx yamllint"
  fi
fi
if [ -n "$YAMLLINT" ]; then
  # shellcheck disable=SC2086
  if $YAMLLINT -s "$BUILD/core-only" "$BUILD/all-on" >"$BUILD/yamllint.log" 2>&1; then
    ok "yamllint clean on core-only and all-on"
  else
    bad "yamllint findings in rendered output"
    sed 's/^/        /' "$BUILD/yamllint.log"
  fi
else
  printf '  skip  yamllint unavailable (set YAMLLINT=... to enable)\n'
fi

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
