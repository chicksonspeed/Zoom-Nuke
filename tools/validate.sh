#!/usr/bin/env bash
# tools/validate.sh — Smoke-tests and dry-run validation for Zoom Nuke.
#
# Runs a minimal set of checks that can be executed without sudo, without
# touching any Zoom data, and without downloading anything. Designed to be
# safe to run in CI (GitHub Actions) and on any developer machine.
#
# Exit codes:
#   0  — all checks passed
#   1  — one or more checks failed
#
# Usage:
#   ./tools/validate.sh
#   ./tools/validate.sh --verbose    # print more output

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

PASS=0
FAIL=0

_pass() { PASS=$((PASS+1)); printf "  ✅ %s\n" "$*"; }
_fail() { FAIL=$((FAIL+1)); printf "  ❌ %s\n" "$*"; }
_info() { printf "     %s\n" "$*"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Zoom Nuke — Validation Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ---------------------------------------------------------------------------
# 1. Repository structure
# ---------------------------------------------------------------------------
echo "── 1. Repository structure ───────────────────────"
REQUIRED_FILES=(
  "VERSION"
  "zoom_nuke.sh"
  "zoom_nuke_overkill.sh"
  "Start Zoom Nuke.command"
  "README.md"
  "tools/_zoom_core.sh"
  "tools/_shared_logging.sh"
  "tools/mac_spoof.sh"
  "tools/zoom_protection.sh"
  "tools/build_macos_app.sh"
  "tools/build_release_bundle.sh"
  "tools/build_pkg_installer.sh"
  "tools/preflight_check.sh"
  "tools/validate.sh"
  "app/DiagnosticLogger.swift"
  "app/DiagnosticReport.swift"
  "Sources/ZoomNukeCore/DiagnosticLogEntry.swift"
  "Sources/ZoomNukeCore/DiagnosticRedactor.swift"
)
for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    _pass "Exists: $f"
  else
    _fail "Missing: $f"
  fi
done

# Files that must NOT exist in app/ — they live in Sources/ZoomNukeCore/ only.
BANNED_FROM_APP=(
  "app/DiagnosticLogEntry.swift"
  "app/DiagnosticRedactor.swift"
)
for f in "${BANNED_FROM_APP[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    _fail "Found duplicate in app/ (canonical copy is Sources/ZoomNukeCore/): $f"
  else
    _pass "Not duplicated in app/: $f"
  fi
done

# Executables that must have their x bit set.
REQUIRED_EXECUTABLES=(
  "zoom_nuke.sh"
  "zoom_nuke_overkill.sh"
  "Start Zoom Nuke.command"
  "tools/build_macos_app.sh"
  "tools/build_release_bundle.sh"
  "tools/build_pkg_installer.sh"
  "tools/preflight_check.sh"
  "tools/validate.sh"
)
for f in "${REQUIRED_EXECUTABLES[@]}"; do
  fp="$REPO_ROOT/$f"
  if [[ -x "$fp" ]]; then
    _pass "Executable: $f"
  else
    _fail "Not executable: $f  (run: chmod +x \"$f\")"
  fi
done

# VERSION must be a valid semver-like string.
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION" 2>/dev/null || echo "")"
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  _pass "VERSION format valid: $VERSION"
else
  _fail "VERSION format invalid or unreadable: '$VERSION' (expected X.Y.Z)"
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Shell syntax checks (bash -n)
# ---------------------------------------------------------------------------
echo "── 2. Shell syntax (bash -n) ─────────────────────"
SHELL_SCRIPTS=(
  "zoom_nuke.sh"
  "zoom_nuke_overkill.sh"
  "Start Zoom Nuke.command"
  "tools/_zoom_core.sh"
  "tools/_shared_logging.sh"
  "tools/mac_spoof.sh"
  "tools/zoom_protection.sh"
  "tools/build_macos_app.sh"
  "tools/build_release_bundle.sh"
  "tools/build_pkg_installer.sh"
  "tools/preflight_check.sh"
  "tools/validate.sh"
)
for f in "${SHELL_SCRIPTS[@]}"; do
  fp="$REPO_ROOT/$f"
  if [[ ! -f "$fp" ]]; then
    _fail "Skipping syntax check (file missing): $f"
    continue
  fi
  if bash -n "$fp" 2>/dev/null; then
    _pass "Syntax OK: $f"
  else
    _fail "Syntax error in: $f"
    bash -n "$fp" 2>&1 | sed 's/^/     /' || true
  fi
done
echo ""

# ---------------------------------------------------------------------------
# 3. CLI flag validation (--version / --help)
# ---------------------------------------------------------------------------
echo "── 3. CLI flag validation ────────────────────────"
if [[ "$(uname)" != "Darwin" ]]; then
  _info "Skipping CLI checks (not macOS — library sourcing requires macOS tools)"
else
  # zoom_nuke_overkill.sh --version
  VER_OUT=$(bash "$REPO_ROOT/zoom_nuke_overkill.sh" --version 2>&1 || true)
  if echo "$VER_OUT" | grep -q "zoom_nuke_overkill.sh v"; then
    _pass "zoom_nuke_overkill.sh --version: $VER_OUT"
  else
    _fail "zoom_nuke_overkill.sh --version failed: $VER_OUT"
  fi

  # zoom_nuke_overkill.sh --help
  if bash "$REPO_ROOT/zoom_nuke_overkill.sh" --help >/dev/null 2>&1; then
    _pass "zoom_nuke_overkill.sh --help exits cleanly"
  else
    _fail "zoom_nuke_overkill.sh --help exited non-zero"
  fi

  # zoom_nuke.sh --version
  SIMPLE_VER=$(bash "$REPO_ROOT/zoom_nuke.sh" --version 2>&1 || true)
  if echo "$SIMPLE_VER" | grep -q "zoom_nuke.sh v"; then
    _pass "zoom_nuke.sh --version: $SIMPLE_VER"
  else
    _fail "zoom_nuke.sh --version failed: $SIMPLE_VER"
  fi

  # preflight_check.sh --json (smoke test only, exit 2 is acceptable)
  PREFLIGHT_JSON=$(bash "$REPO_ROOT/tools/preflight_check.sh" --json 2>/dev/null || true)
  if echo "$PREFLIGHT_JSON" | grep -q '"exit_code"'; then
    _pass "preflight_check.sh --json output is valid"
    $VERBOSE && echo "$PREFLIGHT_JSON" | sed 's/^/     /'
  else
    _fail "preflight_check.sh --json produced unexpected output"
  fi
fi
echo ""

# ---------------------------------------------------------------------------
# 4. Audit mode: zoom_nuke_overkill.sh --audit
# ---------------------------------------------------------------------------
echo "── 4. Audit mode ─────────────────────────────────"
if [[ "$(uname)" != "Darwin" ]]; then
  _info "Skipping audit (not macOS)"
else
  AUDIT_TMPLOG="$(mktemp)"
  if LOG="$AUDIT_TMPLOG" bash "$REPO_ROOT/zoom_nuke_overkill.sh" --audit \
       > /dev/null 2>&1; then
    # Cleanup the audit report it writes to ~/zoom_nuke_audit_*.txt.
    shopt -s nullglob
    for ar in "$HOME"/zoom_nuke_audit_*.txt; do
      rm -f "$ar"
    done
    shopt -u nullglob
    _pass "--audit mode exited cleanly"
  else
    _fail "--audit mode exited non-zero"
  fi
  rm -f "$AUDIT_TMPLOG"
fi
echo ""

# ---------------------------------------------------------------------------
# 5. Preflight check (non-interactive)
# ---------------------------------------------------------------------------
echo "── 5. Preflight check ────────────────────────────"
if [[ "$(uname)" != "Darwin" ]]; then
  _info "Skipping preflight (not macOS)"
else
  PREFLIGHT_OUT=$(bash "$REPO_ROOT/tools/preflight_check.sh" 2>&1) || PREFLIGHT_CODE=$?
  PREFLIGHT_CODE=${PREFLIGHT_CODE:-0}
  if (( PREFLIGHT_CODE == 0 )); then
    _pass "Preflight: all clear (exit 0)"
  elif (( PREFLIGHT_CODE == 2 )); then
    _pass "Preflight: degraded mode (exit 2) — expected on many Macs"
    $VERBOSE && echo "$PREFLIGHT_OUT" | sed 's/^/     /'
  else
    _fail "Preflight: hard failure (exit $PREFLIGHT_CODE)"
    echo "$PREFLIGHT_OUT" | sed 's/^/     /'
  fi
fi
echo ""

# ---------------------------------------------------------------------------
# 6. Diagnostic logging library smoke tests
# ---------------------------------------------------------------------------
echo "── 6. Diagnostic logging (_shared_logging.sh) ────"
SHARED_LOG="$REPO_ROOT/tools/_shared_logging.sh"
if [[ ! -f "$SHARED_LOG" ]]; then
  _fail "Missing: tools/_shared_logging.sh"
else
  _pass "Exists: tools/_shared_logging.sh"

  # Verify it sources without error.
  if bash -c ". '$SHARED_LOG' 2>/dev/null"; then
    _pass "tools/_shared_logging.sh sources cleanly in bash"
  else
    _fail "tools/_shared_logging.sh failed to source"
  fi

  if [[ "$(uname)" == "Darwin" ]]; then
    # Verify log directory creation and latest.log write via _diag_open / _diag_close.
    DIAG_TMPDIR="$(mktemp -d)"
    bash -c "
      . '$SHARED_LOG'
      _diag_open '$DIAG_TMPDIR' 'test-1.0'
      log_info 'unit test entry' 'test'
      log_error 'simulated error' 'test' 'exit=1'
      _diag_close
    " 2>/dev/null
    if [[ -f "$DIAG_TMPDIR/latest.log" ]]; then
      _pass "Diagnostic log file created by _diag_open"
      if grep -q "\[INFO\]" "$DIAG_TMPDIR/latest.log" 2>/dev/null; then
        _pass "Structured INFO entry written to log"
      else
        _fail "Structured INFO entry missing from log"
      fi
      if grep -q "\[ERROR\]" "$DIAG_TMPDIR/latest.log" 2>/dev/null; then
        _pass "Structured ERROR entry written to log"
      else
        _fail "Structured ERROR entry missing from log"
      fi
    else
      _fail "Diagnostic log file NOT created by _diag_open"
    fi
    rm -rf "$DIAG_TMPDIR"

    # Verify redaction of home path.
    REDACT_OUT="$(bash -c ". '$SHARED_LOG'; redact_log_line '/Users/testuser/secret.txt'" 2>/dev/null || true)"
    if echo "$REDACT_OUT" | grep -q "testuser"; then
      _fail "redact_log_line did NOT redact /Users/testuser"
    else
      _pass "redact_log_line correctly redacts home paths"
    fi

    # Verify write_diagnostic_summary emits the required header.
    SUMMARY_OUT="$(bash -c "
      . '$SHARED_LOG'
      DIAG_RESULT='FAILED'
      DIAG_FAILED_STEP='Download Zoom'
      DIAG_EXIT_CODE='1'
      write_diagnostic_summary
    " 2>/dev/null || true)"
    if echo "$SUMMARY_OUT" | grep -q "Diagnostic Summary"; then
      _pass "write_diagnostic_summary produces summary block"
    else
      _fail "write_diagnostic_summary did not produce expected output"
    fi
    if echo "$SUMMARY_OUT" | grep -q "FAILED"; then
      _pass "write_diagnostic_summary includes DIAG_RESULT"
    else
      _fail "write_diagnostic_summary missing DIAG_RESULT"
    fi
  else
    _info "Skipping runtime diagnostic tests (not macOS)"
  fi
fi
echo ""

# ---------------------------------------------------------------------------
# 7. Secret / credential leak scan
# ---------------------------------------------------------------------------
# Grep shell scripts for patterns that suggest a hardcoded credential was
# accidentally logged or echoed.  False-positive rate is low because we only
# match known dangerous key-value patterns in echo/log_* call sites.
# This is a static scan — it does NOT execute any code.
# ---------------------------------------------------------------------------
echo "── 7. Secret / credential scan ───────────────────"
SECRET_PATTERN='(echo|printf|log_info|log_step|log_error|log_warn|log_debug).*\b(PASSWORD|TOKEN|SECRET|API_KEY|COOKIE|CREDENTIAL|PRIVATE_KEY|ACCESS_KEY)\b\s*='
SHELL_SCRIPTS_ALL=(
  "zoom_nuke.sh"
  "zoom_nuke_overkill.sh"
  "Start Zoom Nuke.command"
  "tools/_zoom_core.sh"
  "tools/_shared_logging.sh"
  "tools/mac_spoof.sh"
  "tools/zoom_protection.sh"
  "tools/build_macos_app.sh"
  "tools/build_release_bundle.sh"
  "tools/build_pkg_installer.sh"
  "tools/preflight_check.sh"
  "tools/validate.sh"
)
SECRET_HITS=0
for f in "${SHELL_SCRIPTS_ALL[@]}"; do
  fp="$REPO_ROOT/$f"
  [[ -f "$fp" ]] || continue
  if grep -qiE "$SECRET_PATTERN" "$fp" 2>/dev/null; then
    SECRET_HITS=$((SECRET_HITS + 1))
    _fail "Possible credential leak in: $f"
    grep -inE "$SECRET_PATTERN" "$fp" | head -5 | sed 's/^/     /'
  fi
done
if (( SECRET_HITS == 0 )); then
  _pass "No hardcoded credential patterns found in shell scripts"
fi

# Also scan shell test files if they exist.
TEST_SHELL_DIR="$REPO_ROOT/tests/shell"
if [[ -d "$TEST_SHELL_DIR" ]]; then
  for f in "$TEST_SHELL_DIR"/*.sh; do
    [[ -f "$f" ]] || continue
    if grep -qiE "$SECRET_PATTERN" "$f" 2>/dev/null; then
      _fail "Possible credential leak in test file: $(basename "$f")"
    fi
  done
  _pass "No credential leaks in shell test files"
fi
echo ""

# ---------------------------------------------------------------------------
# 8. Test infrastructure check
# ---------------------------------------------------------------------------
echo "── 8. Test infrastructure ────────────────────────"
TEST_SWIFT_DIR="$REPO_ROOT/tests/swift"
TEST_SHELL_DIR="$REPO_ROOT/tests/shell"
SOURCES_CORE_DIR="$REPO_ROOT/Sources/ZoomNukeCore"

# Swift test sources
if [[ -d "$TEST_SWIFT_DIR" ]]; then
  swift_test_count=$(find "$TEST_SWIFT_DIR" -name '*Tests.swift' | wc -l | tr -d ' ')
  if (( swift_test_count > 0 )); then
    _pass "Swift tests present: ${swift_test_count} file(s) in tests/swift/"
  else
    _fail "tests/swift/ exists but contains no *Tests.swift files"
  fi
else
  _fail "Missing: tests/swift/ directory"
fi

# ZoomNukeCore library mirror
if [[ -d "$SOURCES_CORE_DIR" ]]; then
  core_file_count=$(find "$SOURCES_CORE_DIR" -name '*.swift' | wc -l | tr -d ' ')
  if (( core_file_count > 0 )); then
    _pass "ZoomNukeCore library present: ${core_file_count} file(s) in Sources/ZoomNukeCore/"
  else
    _fail "Sources/ZoomNukeCore/ exists but contains no Swift files"
  fi
else
  _fail "Missing: Sources/ZoomNukeCore/ directory"
fi

# Shell test runner
if [[ -f "$TEST_SHELL_DIR/run_tests.sh" ]]; then
  _pass "Shell test runner present: tests/shell/run_tests.sh"
  shell_test_count=$(find "$TEST_SHELL_DIR" -name 'test_*.sh' | wc -l | tr -d ' ')
  if (( shell_test_count > 0 )); then
    _pass "Shell test files present: ${shell_test_count} file(s)"
  else
    _fail "tests/shell/ present but no test_*.sh files found"
  fi
else
  _fail "Missing: tests/shell/run_tests.sh"
fi

# Package.swift must reference ZoomNukeTests
if [[ -f "$REPO_ROOT/Package.swift" ]]; then
  if grep -q "ZoomNukeTests" "$REPO_ROOT/Package.swift" 2>/dev/null; then
    _pass "Package.swift declares ZoomNukeTests target"
  else
    _fail "Package.swift does not declare a ZoomNukeTests test target"
  fi
else
  _fail "Missing: Package.swift"
fi
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if (( FAIL > 0 )); then
  echo "  ❌ Validation FAILED — fix the items above."
  exit 1
else
  echo "  ✅ All checks passed."
  exit 0
fi
