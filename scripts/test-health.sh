#!/usr/bin/env bash
# Template-only tooling. Exercises scripts/health.sh against the five states.
#
# The five-state model is the forcing function that keeps ADR-0001 honest, so
# it is tested directly rather than inferred from a rendered repository.
#
# shellcheck disable=SC2016  # fixture rows contain Markdown `code spans`; those
# backticks are literal data, not command substitution.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIER="${COPIER:-uvx copier}"
BUILD="$ROOT/.build/health"

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

# ---------------------------------------------------------------------------
# Fixtures are built from one real render, then mutated. Rendering is the slow
# part, so it happens once.
# ---------------------------------------------------------------------------
off_args=()
for m in $MODULES; do off_args+=(-d "module_$m=false"); done

rm -rf "$BUILD"
mkdir -p "$BUILD"
make_template_snapshot "$ROOT" "$TEMPLATE"
$COPIER copy --defaults -d project_name=health-base "${off_args[@]}" \
  "$TEMPLATE" "$BUILD/base" >/dev/null 2>&1

fixture() {
  rm -rf "${BUILD:?}/$1"
  cp -r "$BUILD/base" "$BUILD/$1"
  printf '# %s\n\nA documented repository.\n' "$1" >"$BUILD/$1/README.md"
}

# write_deferrals <dir> [rows...]
write_deferrals() {
  local dir="$1"
  shift
  {
    printf '# 1. Initial deferrals and declines\n\n## Decision\n\n'
    printf '| Module | Condition | Deferred (with trigger) or declined (with reason) |\n'
    printf '| :--- | :--- | :--- |\n'
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
  } >"$dir/docs/adr/0001-initial-deferrals.md"
}

decline_all() {
  local dir="$1" m
  local rows=()
  for m in $MODULES; do
    rows+=("| \`$m\` | condition | declined — reason: not needed for this fixture |")
  done
  write_deferrals "$dir" "${rows[@]}"
}

run_health() {
  set +e
  HEALTH_OUT="$(cd "$1" && bash scripts/health.sh 2>&1)"
  HEALTH_RC=$?
  set -e
}

# line_for <module> -> the report row
line_for() { printf '%s\n' "$HEALTH_OUT" | grep -E "[[:space:]]$1[[:space:]]" | head -n 1; }

expect_row() { # module, glyph, label
  local line
  line="$(line_for "$1")"
  if printf '%s' "$line" | grep -q "$2"; then
    ok "$3: $1 -> $2"
  else
    bad "$3: expected $2 for $1, got: ${line:-<no row>}"
  fi
}

expect_rc() { # expected, label
  if [ "$HEALTH_RC" -eq "$1" ]; then
    ok "$2: exit $1"
  else
    bad "$2: expected exit $1, got $HEALTH_RC"
  fi
}

expect_output() { # substring, label
  if printf '%s' "$HEALTH_OUT" | grep -q -- "$1"; then
    ok "$2"
  else
    bad "$2 (output did not contain: $1)"
  fi
}

# ---------------------------------------------------------------------------
# 1. complete: core finished, every optional module declined
# ---------------------------------------------------------------------------
echo "== complete =="
fixture complete
decline_all "$BUILD/complete"
run_health "$BUILD/complete"
expect_rc 0 "complete"
expect_row core "✅" "complete"

# ---------------------------------------------------------------------------
# 2. incomplete: core finished except the README, which is a stub by design
# ---------------------------------------------------------------------------
echo "== incomplete =="
fixture incomplete
printf '<!-- TEMPLATE-STUB: placeholder -->\n# incomplete\n' >"$BUILD/incomplete/README.md"
decline_all "$BUILD/incomplete"
run_health "$BUILD/incomplete"
expect_rc 2 "incomplete"
expect_row core "🟡" "incomplete"
expect_row core "README.md" "incomplete"

# ---------------------------------------------------------------------------
# 3. deferred: a disabled module with a trigger is a decision, not a gap
# ---------------------------------------------------------------------------
echo "== deferred =="
fixture deferred
write_deferrals "$BUILD/deferred" \
  '| `commits` | wants enforced history | deferred — trigger: when a second contributor joins |' \
  '| `ci` | any automated check | declined — reason: not needed for this fixture |' \
  '| `deps` | repo has any dependency | declined — reason: not needed for this fixture |' \
  '| `docs` | architecture exists | declined — reason: not needed for this fixture |' \
  '| `contributing` | accepts outside contributions | declined — reason: not needed for this fixture |' \
  '| `env` | reproducible local tooling | declined — reason: not needed for this fixture |' \
  '| `security` | public / external users | declined — reason: not needed for this fixture |' \
  '| `release` | publishes a versioned artifact | declined — reason: not needed for this fixture |' \
  '| `ops` | deployed / running | declined — reason: not needed for this fixture |'
run_health "$BUILD/deferred"
expect_rc 0 "deferred"
expect_row commits "⏸" "deferred"
expect_row commits "second contributor" "deferred carries its trigger"
expect_row ci "⛔" "deferred companion declined"

# ---------------------------------------------------------------------------
# 4. unrecorded: a disabled module with no row at all is an omission
# ---------------------------------------------------------------------------
echo "== unrecorded =="
fixture unrecorded
write_deferrals "$BUILD/unrecorded" \
  '| `commits` | wants enforced history | declined — reason: not needed for this fixture |' \
  '| `ci` | any automated check | declined — reason: not needed for this fixture |' \
  '| `deps` | repo has any dependency | declined — reason: not needed for this fixture |' \
  '| `docs` | architecture exists | declined — reason: not needed for this fixture |' \
  '| `contributing` | accepts outside contributions | declined — reason: not needed for this fixture |' \
  '| `security` | public / external users | declined — reason: not needed for this fixture |' \
  '| `release` | publishes a versioned artifact | declined — reason: not needed for this fixture |' \
  '| `ops` | deployed / running | declined — reason: not needed for this fixture |'
run_health "$BUILD/unrecorded"
expect_rc 1 "unrecorded"
expect_row env "❓" "unrecorded"

# a resolved-looking row that names no trigger is still undecided
fixture vague
write_deferrals "$BUILD/vague" \
  '| `env` | reproducible local tooling | deferred — someday |' \
  '| `commits` | wants enforced history | declined — reason: not needed for this fixture |' \
  '| `ci` | any automated check | declined — reason: not needed for this fixture |' \
  '| `deps` | repo has any dependency | declined — reason: not needed for this fixture |' \
  '| `docs` | architecture exists | declined — reason: not needed for this fixture |' \
  '| `contributing` | accepts outside contributions | declined — reason: not needed for this fixture |' \
  '| `security` | public / external users | declined — reason: not needed for this fixture |' \
  '| `release` | publishes a versioned artifact | declined — reason: not needed for this fixture |' \
  '| `ops` | deployed / running | declined — reason: not needed for this fixture |'
run_health "$BUILD/vague"
expect_rc 1 "deferred without a trigger"
expect_row env "❓" "deferred without a trigger"

# ---------------------------------------------------------------------------
# 5. missing-file: an enabled module whose file is absent is incomplete
# ---------------------------------------------------------------------------
echo "== missing file =="
fixture missing
sed -i 's/^module_ci: false/module_ci: true/' "$BUILD/missing/.copier-answers.yml"
decline_all "$BUILD/missing"
run_health "$BUILD/missing"
expect_rc 2 "missing file"
expect_row ci "🟡" "missing file"
expect_row ci "missing" "missing file names the file"

# ---------------------------------------------------------------------------
# 6. codeowners_team gates its file
#
# The contributing module ships CODEOWNERS only when an owner is named, so
# health has to read that answer rather than require the file unconditionally:
# otherwise every repository generated with the default would report itself
# incomplete for a file it was never meant to have.
# ---------------------------------------------------------------------------
echo "== codeowners gating =="
fixture coownerless
sed -i 's/^module_contributing: false/module_contributing: true/' "$BUILD/coownerless/.copier-answers.yml"
printf '# Contributing\n\nHow to contribute.\n' >"$BUILD/coownerless/CONTRIBUTING.md"
decline_all "$BUILD/coownerless"
run_health "$BUILD/coownerless"
expect_rc 0 "codeowners: no owner named"
expect_row contributing "✅" "codeowners: complete without the file"

fixture coowner
sed -i 's/^module_contributing: false/module_contributing: true/' "$BUILD/coowner/.copier-answers.yml"
# The key is absent when the module was off, and `sed s///` on a missing line is a
# silent no-op, so delete then append rather than substitute.
sed -i '/^codeowners_team:/d' "$BUILD/coowner/.copier-answers.yml"
printf "codeowners_team: '@example/maintainers'\n" >>"$BUILD/coowner/.copier-answers.yml"
printf '# Contributing\n\nHow to contribute.\n' >"$BUILD/coowner/CONTRIBUTING.md"
decline_all "$BUILD/coowner"
run_health "$BUILD/coowner"
expect_rc 2 "codeowners: owner named, file absent"
expect_row contributing "🟡" "codeowners: incomplete with an owner and no file"
expect_row contributing "CODEOWNERS" "codeowners: names the missing file"

printf '* @example/maintainers\n' >"$BUILD/coowner/.github/CODEOWNERS"
run_health "$BUILD/coowner"
expect_rc 0 "codeowners: owner named and file present"
expect_row contributing "✅" "codeowners: complete once the file exists"

# ---------------------------------------------------------------------------
# 7. missing manifest is fatal, not silently "all complete"
# ---------------------------------------------------------------------------
echo "== missing manifest =="
fixture nomanifest
rm -f "$BUILD/nomanifest/.copier-answers.yml"
run_health "$BUILD/nomanifest"
expect_rc 1 "missing manifest"
expect_output "not found" "missing manifest explains itself"

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
