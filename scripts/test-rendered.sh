#!/usr/bin/env bash
# Template-only tooling. Lints the *rendered* workflows rather than the
# template sources, because Jinja, {% raw %} blocks and ${{ }} expressions make
# the templates unparseable as YAML.
#
# Both tools are optional: they are skipped with a notice when unavailable, so
# the suite still runs on a machine without them. They earn their place:
# actionlint found nothing, but zizmor found three high-severity
# excessive-permissions findings and a secrets-inherit on the first run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIER="${COPIER:-uvx copier}"
BUILD="$ROOT/.build/workflows"
WORKFLOW_SHA=1111111111111111111111111111111111111111

# shellcheck source=scripts/lib/template-snapshot.sh
source "$ROOT/scripts/lib/template-snapshot.sh"
TEMPLATE="$BUILD/template-src"

pass=0
fail=0
ok() { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  skip  %s\n' "$1"; }

MODULES="commits ci deps docs contributing env security release ops"

rm -rf "$BUILD"
mkdir -p "$BUILD"
make_template_snapshot "$ROOT" "$TEMPLATE"

# One render with everything enabled: every workflow the template can produce.
args=(-d project_name=workflows -d org_slug=example -d workflow_ref="$WORKFLOW_SHA")
for m in $MODULES; do args+=(-d "module_$m=true"); done
# shellcheck disable=SC2086
$COPIER copy --defaults "${args[@]}" "$TEMPLATE" "$BUILD/all-on" >/dev/null 2>&1
WF="$BUILD/all-on/.github/workflows"

echo "== actionlint =="
ACTIONLINT=""
if command -v actionlint >/dev/null 2>&1; then
  ACTIONLINT="actionlint"
elif command -v go >/dev/null 2>&1 && [ -x "$(go env GOPATH)/bin/actionlint" ]; then
  ACTIONLINT="$(go env GOPATH)/bin/actionlint"
fi
if [ -n "$ACTIONLINT" ]; then
  # shellcheck disable=SC2086
  if $ACTIONLINT "$WF"/*.yml >"$BUILD/actionlint.log" 2>&1; then
    ok "actionlint clean across $(find "$WF" -name '*.yml' | wc -l | tr -d ' ') workflows"
  else
    bad "actionlint findings"
    sed 's/^/        /' "$BUILD/actionlint.log"
  fi
else
  skip "actionlint unavailable (go install github.com/rhysd/actionlint/cmd/actionlint@latest)"
fi

echo "== zizmor =="
ZIZMOR=""
if command -v zizmor >/dev/null 2>&1; then
  ZIZMOR="zizmor"
elif command -v uvx >/dev/null 2>&1; then
  ZIZMOR="uvx zizmor"
fi
if [ -n "$ZIZMOR" ]; then
  # Default audit level. Pedantic mode reports the informational
  # `superfluous-actions` finding that create-pull-request is deliberate about.
  # shellcheck disable=SC2086
  if (cd "$BUILD/all-on" && $ZIZMOR --format plain .github/workflows/) \
    >"$BUILD/zizmor.log" 2>&1; then
    ok "zizmor clean (default audit level)"
  else
    bad "zizmor findings"
    grep -vE '^ INFO|^ WARN' "$BUILD/zizmor.log" | sed 's/^/        /' | head -40
  fi
else
  skip "zizmor unavailable (uvx zizmor)"
fi

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
