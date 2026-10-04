#!/usr/bin/env bash
# Template-only tooling. Makes Phase 8's exit criterion executable:
#
#     "A new maintainer can generate a repo from the README alone."
#
# That is a claim about documentation, and prose cannot verify it. So this suite
# takes the commands out of README.md and runs them, and cross-checks the docs
# against copier.yml so a table cannot quietly go stale.
#
# The source path is substituted for a local tagged snapshot of the working
# tree, because fetching `gh:<org>/repo-template` needs a published repository.
# Everything else — the flags, the answers, the resulting repository, the
# documented failure — is exercised as written.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIER="${COPIER:-uvx copier}"
BUILD="$ROOT/.build/docs"
WORKFLOW_SHA=1111111111111111111111111111111111111111
SNAPSHOT_TAG=v0.0.1

# shellcheck source=scripts/lib/template-snapshot.sh
source "$ROOT/scripts/lib/template-snapshot.sh"
TEMPLATE="$BUILD/template-src"

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

expect_grep() { # pattern, file, label
  if grep -qE -- "$1" "$2" 2>/dev/null; then
    ok "$3"
  else
    bad "$3"
  fi
}

rm -rf "$BUILD"
mkdir -p "$BUILD"
make_template_snapshot "$ROOT" "$TEMPLATE"

README="$ROOT/README.md"
CONTRIBUTING="$ROOT/CONTRIBUTING.md"
ARCH="$ROOT/docs/architecture.md"

# ---------------------------------------------------------------------------
# 1. The README's own copy command
# ---------------------------------------------------------------------------
echo "== README: the documented copy flow =="

readme_cmd="$(grep -m1 -E '^copier copy ' "$README" || true)"
if [ -z "$readme_cmd" ]; then
  bad "README contains no 'copier copy' command"
else
  ok "README documents a copier copy command"
  case "$readme_cmd" in
    *'gh:'*) ok "the command copies from the published template" ;;
    *) bad "the command does not use the gh: form: $readme_cmd" ;;
  esac
  # Everything between `copy` and the source is the flag set under test.
  flags="$(printf '%s\n' "$readme_cmd" | sed -E 's/^copier copy +//; s#gh:[^ ]*.*##')"
  ok "README flags under test: ${flags:-<none>}"

  DST="$BUILD/from-readme"
  rm -rf "$DST"
  # shellcheck disable=SC2086
  if $COPIER copy $flags --defaults \
    -d project_name=from-readme -d org_slug=example -d workflow_ref="$WORKFLOW_SHA" \
    "$TEMPLATE" "$DST" >"$BUILD/copy.log" 2>&1; then
    ok "the README's command renders a repository"
  else
    bad "the README's command failed"
    tail -5 "$BUILD/copy.log" | sed 's/^/        /'
  fi

  if [ -f "$DST/justfile" ] && [ -f "$DST/scripts/health.sh" ] &&
    [ -f "$DST/.copier-answers.yml" ]; then
    ok "the result is a coherent repository (justfile, health.sh, answers)"
  else
    bad "the result is missing core files"
  fi

  # The README's central warning: copy uses the latest tag, not the working tree.
  recorded="$(sed -n 's/^_commit: *//p' "$DST/.copier-answers.yml" 2>/dev/null | head -1)"
  if [ "$recorded" = "$SNAPSHOT_TAG" ]; then
    ok "the copy recorded the tag $recorded, not a commit SHA (README states this)"
  else
    bad "recorded _commit is '$recorded', expected the tag $SNAPSHOT_TAG"
  fi
fi

# ---------------------------------------------------------------------------
# 2. The failure the README promises
# ---------------------------------------------------------------------------
echo "== README: the documented failure =="
if $COPIER copy --defaults -d project_name=probe -d org_slug=example \
  "$TEMPLATE" "$BUILD/should-fail" >"$BUILD/fail.log" 2>&1; then
  bad "--defaults without workflow_ref succeeded; the README says it must fail"
else
  ok "--defaults without workflow_ref fails, as the README states"
  expect_grep 'workflow_ref' "$BUILD/fail.log" \
    "the error names workflow_ref, as the README quotes"
fi

# ---------------------------------------------------------------------------
# 3. Every questionnaire answer is documented
# ---------------------------------------------------------------------------
echo "== questionnaire coverage =="
questions="$(grep -oE '^[a-z][a-z0-9_]*:' "$ROOT/copier.yml" | tr -d ':' | sort -u)"
for q in $questions; do
  if grep -qE "\`$q\`" "$README"; then
    ok "README documents '$q'"
  else
    bad "README does not document the question '$q'"
  fi
done

# ---------------------------------------------------------------------------
# 4. Every module is documented, consistently
# ---------------------------------------------------------------------------
echo "== module coverage =="
modules="$(grep -oE '^module_[a-z]+:' "$ROOT/copier.yml" | sed 's/^module_//; s/:$//' | sort -u)"
for m in $modules; do
  if grep -qE "\`$m\`|\*\*$m\*\*" "$README"; then
    ok "README documents module '$m'"
  else
    bad "README does not document module '$m'"
  fi
done

missing_arch=""
for m in $modules; do
  grep -qE "\b$m\b" "$ARCH" || missing_arch="$missing_arch $m"
done
if [ -z "$missing_arch" ]; then
  ok "docs/architecture.md mentions every module"
else
  bad "docs/architecture.md is missing modules:$missing_arch"
fi

# ---------------------------------------------------------------------------
# 5. Relative links resolve
#
# Written after a README draft linked docs/adr/README.md, which did not exist:
# the index was shipped to generated repos but absent from this one.
# ---------------------------------------------------------------------------
echo "== links =="
check_links() { # file
  local file="$1" dir target broken=""
  dir="$(dirname "$file")"
  while IFS= read -r target; do
    case "$target" in
      http* | mailto:* | '#'* | '') continue ;;
    esac
    target="${target%%#*}"
    [ -e "$dir/$target" ] || broken="$broken $target"
  done < <(grep -oE '\]\([^)]+\)' "$file" | sed 's/^](//; s/)$//')
  if [ -z "$broken" ]; then
    ok "$(basename "$file"): relative links resolve"
  else
    bad "$(basename "$file"): broken links:$broken"
  fi
}
for f in "$README" "$CONTRIBUTING" "$ARCH" "$ROOT/docs/adr/README.md"; do
  if [ -f "$f" ]; then
    check_links "$f"
  else
    bad "$(basename "$f") is missing"
  fi
done

# ---------------------------------------------------------------------------
# 6. Every ADR is indexed
# ---------------------------------------------------------------------------
echo "== ADR index =="
missing_adr=""
for f in "$ROOT"/docs/adr/[0-9]*.md; do
  base="$(basename "$f")"
  grep -q "($base)" "$ROOT/docs/adr/README.md" || missing_adr="$missing_adr $base"
done
if [ -z "$missing_adr" ]; then
  ok "docs/adr/README.md links every record"
else
  bad "unindexed ADRs:$missing_adr"
fi

# ---------------------------------------------------------------------------
# 7. The documented behaviour of a freshly generated repository
#
# The README tells a maintainer to expect a failing `just health` and why.
# ---------------------------------------------------------------------------
echo "== documented fresh-repository behaviour =="
JUST=""
if command -v just >/dev/null 2>&1; then
  JUST="just"
elif command -v uvx >/dev/null 2>&1; then
  JUST="uvx --from rust-just just"
fi
if [ -n "$JUST" ] && [ -d "$BUILD/from-readme" ]; then
  rc=0
  # shellcheck disable=SC2086
  out="$(cd "$BUILD/from-readme" && $JUST health 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ]; then
    ok "just health exits 1 on a freshly generated repository, as documented"
  else
    bad "just health exited $rc on a fresh repository, expected 1"
  fi
  case "$out" in
    *core*) ok "the report names core, as the README shows" ;;
    *) bad "the report does not mention core" ;;
  esac
else
  skip "just unavailable — cannot exercise the documented health output"
fi

for code in 0 1 2; do
  expect_grep "exit codes.*\`$code\`|\`$code\`" "$README" \
    "README documents exit code $code"
done

# ---------------------------------------------------------------------------
# 8. The README's Version row does not fall behind the tags
#
# The row read `v0.1.0` while the template had reached `v0.3.3`: a status table
# that quietly lied. The invariant is deliberately *monotonic*, not equality. A
# release tag is pushed after the merge it releases, and a preparation commit
# may name the next version before its tag exists; requiring equality would fail
# both of those ordinary states, which is a release-process dependency rather
# than a documentation check.
# ---------------------------------------------------------------------------
echo "== version row =="
readme_version="$(grep -m1 -oE '^\| Version \|[^0-9]*v[0-9]+\.[0-9]+\.[0-9]+' "$README" |
  grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
latest_tag="$(git -C "$ROOT" tag --list 'v*' --sort=-v:refname | head -n1)"
if [ -z "$readme_version" ]; then
  bad "README has no readable Version row (expected '| Version | vX.Y.Z |')"
elif [ -z "$latest_tag" ]; then
  skip "version row: no version tags in this checkout (shallow clone?)"
elif [ "$(printf '%s\n%s\n' "$readme_version" "$latest_tag" | sort -V | head -n1)" = "$latest_tag" ]; then
  ok "README Version $readme_version is not behind the latest tag $latest_tag"
else
  bad "README Version is $readme_version but the latest tag is $latest_tag"
fi

# ---------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
