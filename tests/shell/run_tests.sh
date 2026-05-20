#!/usr/bin/env bash
# tests/shell/run_tests.sh — Shell test runner for Zoom Nuke.
#
# Usage:
#   bash tests/shell/run_tests.sh
#   bash tests/shell/run_tests.sh --verbose
#
# Each test_*.sh file in the same directory must define a run_tests() function.
# This runner sources each file in the same process so that global PASS/FAIL
# counters are shared without subshell boundary issues.
#
# Exit codes:
#   0  — all tests passed (or all skipped)
#   1  — one or more tests failed
#
# SAFETY: all tests run in temporary directories and never touch real user data.
# DRY_RUN=true is exported globally to prevent destructive commands in any
# accidentally sourced library functions.

set -uo pipefail

export ZOOM_NUKE_TEST_MODE=1   # signal to any sourced scripts that this is a test run
export DRY_RUN=true            # prevent any destructive core library operations

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# ---------------------------------------------------------------------------
# Global counters — written by assert_* helpers below
# ---------------------------------------------------------------------------
_PASS=0
_FAIL=0
_SKIP=0
_CURRENT_FILE="(unknown)"

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-(unnamed)}"
  if [[ "$expected" == "$actual" ]]; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] %s\n" "$_CURRENT_FILE" "$msg"
    printf "           expected: %q\n" "$expected"
    printf "           actual:   %q\n" "$actual"
  fi
}

assert_contains() {
  local needle="$1" haystack="$2" msg="${3:-(unnamed)}"
  if [[ "$haystack" == *"$needle"* ]]; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] %s\n" "$_CURRENT_FILE" "$msg"
    printf "           needle:   %q\n" "$needle"
    printf "           haystack: %s\n" "$haystack"
  fi
}

assert_not_contains() {
  local needle="$1" haystack="$2" msg="${3:-(unnamed)}"
  if [[ "$haystack" != *"$needle"* ]]; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] %s\n" "$_CURRENT_FILE" "$msg"
    printf "           must NOT contain: %q\n" "$needle"
    printf "           haystack: %s\n" "$haystack"
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-(unnamed)}"
  if [[ -f "$path" ]]; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] %s — file not found: %s\n" \
      "$_CURRENT_FILE" "$msg" "$path"
  fi
}

assert_match() {
  local pattern="$1" string="$2" msg="${3:-(unnamed)}"
  if echo "$string" | grep -qE "$pattern" 2>/dev/null; then
    _PASS=$((_PASS + 1))
    $VERBOSE && printf "    ✅ %s\n" "$msg"
  else
    _FAIL=$((_FAIL + 1))
    printf "    ❌ FAIL  [%s] %s\n" "$_CURRENT_FILE" "$msg"
    printf "           pattern: %s\n" "$pattern"
    printf "           input:   %s\n" "$string"
  fi
}

skip() {
  _SKIP=$((_SKIP + 1))
  printf "    ⚠️  SKIP: %s\n" "$*"
}

# ---------------------------------------------------------------------------
# Discover and run each test_*.sh file
# ---------------------------------------------------------------------------

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Zoom Nuke — Shell Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

FILE_COUNT=0
for _test_file in "$SCRIPT_DIR"/test_*.sh; do
  [[ -f "$_test_file" ]] || continue
  FILE_COUNT=$((FILE_COUNT + 1))
  _CURRENT_FILE="$(basename "$_test_file")"
  printf "── %s ──────────────────────\n" "$_CURRENT_FILE"

  # Source the test file to bring its run_tests() function into scope.
  # shellcheck source=/dev/null
  source "$_test_file"

  # Call the test function.
  if declare -f run_tests >/dev/null 2>&1; then
    run_tests
    # Unset so the next file's run_tests doesn't shadow it on error.
    unset -f run_tests
  else
    printf "    ⚠️  No run_tests() found in %s — skipping file\n" "$_CURRENT_FILE"
    _SKIP=$((_SKIP + 1))
  fi
  echo ""
done

if [[ "$FILE_COUNT" -eq 0 ]]; then
  echo "  ⚠️  No test files found (test_*.sh) in $SCRIPT_DIR"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  Results: %d passed, %d failed, %d skipped\n" \
  "$_PASS" "$_FAIL" "$_SKIP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if (( _FAIL > 0 )); then
  echo "  ❌ Shell tests FAILED."
  exit 1
fi
echo "  ✅ All shell tests passed."
exit 0
