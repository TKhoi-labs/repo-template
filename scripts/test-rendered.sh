#!/usr/bin/env bash
# Template-only tooling. Verifies *rendered* artifacts using the real tools the
# generated repository depends on. These checks cannot be written against the
# template sources: Jinja, {% raw %} blocks and ${{ }} expressions make them
# unparseable, and several of these tools only reveal a problem when run.
#
# Every tool is optional. A missing tool is skipped with a notice rather than
# failing the suite, so this runs on a machine without them.
#
# What this caught that reading the files did not:
#   * zizmor: three high-severity excessive-permissions findings, a
#     secrets-inherit in ci.yml, and a redundant permissions: read-all
#   * git-cliff: `timestamp | date(...)` in the unreleased section fails the
#     whole run, so `just changelog` was broken
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIER="${COPIER:-uvx copier}"
BUILD="$ROOT/.build/rendered"
WORKFLOW_SHA=1111111111111111111111111111111111111111

# shellcheck source=scripts/lib/template-snapshot.sh
source "$ROOT/scripts/lib/template-snapshot.sh"
TEMPLATE="$BUILD/template-src"

MODULES="commits ci deps docs contributing env security release ops"

pass=0
fail=0
ok() {
  printf '  ok    %s\n' "$1"
  pass=$((pass + 1))
}
bad() {
  printf '  FAIL  %s\n' "$1"
  fail=$((fail + 1))
}
skip() { printf '  skip  %s\n' "$1"; }

# If/then/else rather than `grep && ok || bad`: with that form, a failing report
# also runs the failure branch, which has silently broken a check before now.
expect_grep() { # pattern, file, label
  if grep -q -- "$1" "$2" 2>/dev/null; then
    ok "$3"
  else
    bad "$3"
  fi
}

render() { # name, enable-all(true/false)
  local name="$1" all="$2"
  local args=(-d "project_name=$name" -d org_slug=example -d workflow_ref="$WORKFLOW_SHA") m
  for m in $MODULES; do
    if [ "$all" = "true" ]; then args+=(-d "module_$m=true"); else args+=(-d "module_$m=false"); fi
  done
  rm -rf "${BUILD:?}/${name:?}"
  # shellcheck disable=SC2086
  $COPIER copy --defaults "${args[@]}" "$TEMPLATE" "$BUILD/$name" >/dev/null 2>&1
}

rm -rf "$BUILD"
mkdir -p "$BUILD"
make_template_snapshot "$ROOT" "$TEMPLATE"

render all-on true
render core-only false
WF="$BUILD/all-on/.github/workflows"

# ---------------------------------------------------------------------------
# 1. actionlint — the workflows are valid GitHub Actions
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 2. zizmor — workflow security posture
# ---------------------------------------------------------------------------
echo "== zizmor =="
ZIZMOR=""
if command -v zizmor >/dev/null 2>&1; then
  ZIZMOR="zizmor"
elif command -v uvx >/dev/null 2>&1; then
  ZIZMOR="uvx zizmor"
fi
if [ -n "$ZIZMOR" ]; then
  # Default audit level. Pedantic mode additionally reports the informational
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
# 3. git-cliff renders the generated cliff.toml
#
# Both modes matter: release.yml runs `--current`, and the justfile's
# `changelog` recipe renders the full changelog *including* the Unreleased
# section, which is where `timestamp` is undefined.
# ---------------------------------------------------------------------------
echo "== git-cliff =="
if command -v git-cliff >/dev/null 2>&1; then
  CLIFF="$BUILD/cliff"
  rm -rf "$CLIFF"
  mkdir -p "$CLIFF"
  (
    cd "$CLIFF"
    git init -q .
    echo a >a.txt && git add -A
    git -c user.email=t@example.invalid -c user.name=T commit -qm "feat: add the first thing"
    echo b >b.txt && git add -A
    git -c user.email=t@example.invalid -c user.name=T commit -qm "fix: repair the second thing"
    git tag v0.1.0
    echo c >c.txt && git add -A
    git -c user.email=t@example.invalid -c user.name=T commit -qm "feat: add the third thing"
  ) >/dev/null 2>&1
  cp "$BUILD/all-on/cliff.toml" "$CLIFF/cliff.toml"

  if (cd "$CLIFF" && git-cliff --config cliff.toml) >"$BUILD/cliff-full.md" 2>"$BUILD/cliff-full.err"; then
    ok "git-cliff renders the full changelog (unreleased included)"
    expect_grep '### Features' "$BUILD/cliff-full.md" "changelog groups commits by type"
  else
    bad "git-cliff failed on the full changelog"
    grep -o 'ERROR.*' "$BUILD/cliff-full.err" | head -3 | sed 's/^/        /'
  fi

  if (cd "$CLIFF" && git-cliff --config cliff.toml --current) >"$BUILD/cliff-cur.md" 2>"$BUILD/cliff-cur.err"; then
    ok "git-cliff renders --current, as release.yml invokes it"
    expect_grep '0\.1\.0' "$BUILD/cliff-cur.md" "--current output names the release"
  else
    bad "git-cliff failed on --current"
    grep -o 'ERROR.*' "$BUILD/cliff-cur.err" | head -3 | sed 's/^/        /'
  fi
else
  skip "git-cliff unavailable"
fi

# ---------------------------------------------------------------------------
# 4. The generated justfile is valid
# ---------------------------------------------------------------------------
echo "== just =="
JUST=""
if command -v just >/dev/null 2>&1; then
  JUST="just"
elif command -v uvx >/dev/null 2>&1; then
  JUST="uvx --from rust-just just"
fi
if [ -n "$JUST" ]; then
  for cfg in core-only all-on; do
    # shellcheck disable=SC2086
    if $JUST --justfile "$BUILD/$cfg/justfile" --list >"$BUILD/just-$cfg.log" 2>&1; then
      ok "$cfg: just parses the generated justfile"
      expect_grep '^    health' "$BUILD/just-$cfg.log" "$cfg: health recipe is listed"
    else
      bad "$cfg: just could not parse the generated justfile"
      sed 's/^/        /' "$BUILD/just-$cfg.log" | head -10
    fi
  done
  # a recipe contributed by an optional module must appear in the all-on render
  expect_grep '^    changelog' "$BUILD/just-all-on.log" \
    "all-on: release contributes the changelog recipe"
else
  skip "just unavailable (uvx --from rust-just just)"
fi

# ---------------------------------------------------------------------------
# 5. A conflicted update is detectable
#
# This is the guardrail behind "repos that diverge get a failed sync, not a
# silent bad merge". Copier's --conflict=rej EXITS 0 even when it conflicts, so
# the sync workflow's `find . -name '*.rej'` check is the only signal — which is
# exactly why it is a separate step. This asserts the signal appears.
# ---------------------------------------------------------------------------
echo "== conflict detection =="
CONF="$BUILD/conflict"
CONFSRC="$CONF/src"
CONFDST="$CONF/dst"
rm -rf "$CONF"
mkdir -p "$CONFSRC"
rsync -a --exclude .git --exclude .build "$ROOT/" "$CONFSRC/"
(
  cd "$CONFSRC"
  git init -q .
  git add -A
  git -c user.email=test@example.invalid -c user.name=Tester commit -qm v1
  git tag v0.1.0
) >/dev/null 2>&1

args=(-d project_name=conflict -d org_slug=example -d workflow_ref="$WORKFLOW_SHA")
for m in $MODULES; do args+=(-d "module_$m=false"); done
# shellcheck disable=SC2086
$COPIER copy --defaults "${args[@]}" "$CONFSRC" "$CONFDST" >/dev/null 2>&1

# A human hand-edits a generated file, against the rule.
sed -i 's/^# Report the five-state module manifest\.$/# Hand-edited by a human./' \
  "$CONFDST/justfile"
(
  cd "$CONFDST"
  git init -q .
  git add -A
  git -c user.email=test@example.invalid -c user.name=Tester commit -qm initial
) >/dev/null 2>&1

conflict_markers() { find "$1" -name '*.rej' -not -path '*/.git/*'; }

if [ -z "$(conflict_markers "$CONFDST")" ]; then
  ok "no .rej before a template change (guard does not fire spuriously)"
else
  bad ".rej present before any template change"
fi

# The template now changes the same line, so the two edits collide.
sed -i 's/^# Report the five-state module manifest\.$/# Report module health./' \
  "$CONFSRC/template/justfile.jinja"
(
  cd "$CONFSRC"
  git add -A
  git -c user.email=test@example.invalid -c user.name=Tester commit -qm v2
  git tag v0.2.0
) >/dev/null 2>&1

# shellcheck disable=SC2086
(cd "$CONFDST" && $COPIER update --defaults --trust --conflict=rej .) \
  >"$CONF/update.log" 2>&1 || true

if [ -n "$(conflict_markers "$CONFDST")" ]; then
  ok "a conflicted update leaves .rej files, which the sync guard detects"
else
  bad "a conflicted update left no .rej files; the sync guard would miss it"
fi

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
