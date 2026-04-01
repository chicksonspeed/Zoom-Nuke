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
  "tools/mac_spoof.sh"
  "tools/zoom_protection.sh"
  "tools/build_macos_app.sh"
  "tools/build_release_bundle.sh"
  "tools/build_pkg_installer.sh"
  "tools/preflight_check.sh"
  "tools/validate.sh"
)
for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    _pass "Exists: $f"
  else
    _fail "Missing: $f"
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
