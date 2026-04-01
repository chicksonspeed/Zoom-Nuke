#!/usr/bin/env bash
# tools/preflight_check.sh — Environment preflight check for Zoom Nuke.
#
# Detects restricted/managed macOS environments before the main script runs
# any destructive operations. Reports capabilities and limitations clearly,
# then exits with an appropriate code:
#
#   0  — All checks passed; full functionality expected.
#   1  — Hard blockers found (e.g. not macOS, missing critical tools).
#   2  — Degraded mode: some features will be skipped (e.g. MAC spoofing),
#        but the core nuke + reinstall will still work.
#
# Usage:
#   source tools/preflight_check.sh          # sets PREFLIGHT_EXIT_CODE
#   bash tools/preflight_check.sh            # standalone report; exits with code above
#   bash tools/preflight_check.sh --json     # machine-readable JSON to stdout

set -uo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_BOLD="\033[1m"
_RED="\033[0;31m"
_YELLOW="\033[0;33m"
_GREEN="\033[0;32m"
_RESET="\033[0m"

_ok()   { printf "  ${_GREEN}✅ OK${_RESET}    %s\n" "$*"; }
_warn() { printf "  ${_YELLOW}⚠️  WARN${_RESET}  %s\n" "$*"; }
_fail() { printf "  ${_RED}❌ FAIL${_RESET}  %s\n" "$*"; }

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

HARD_FAIL=0    # set to 1 if any blocker found
SOFT_WARN=0    # set to 1 if degraded-mode warnings found

# Results accumulator for JSON output.
declare -a _json_results=()
_json_add() {
  local status="$1" key="$2" msg="$3"
  _json_results+=("{\"status\":\"$status\",\"check\":\"$key\",\"message\":$(printf '%s' "\"$msg\"")}")
}

# ---------------------------------------------------------------------------
# 1. Platform
# ---------------------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
  _fail "Not macOS — this tool only supports macOS."
  _json_add "fail" "platform" "Not macOS"
  HARD_FAIL=1
else
  MACOS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
  _ok "macOS $MACOS_VERSION"
  _json_add "ok" "platform" "macOS $MACOS_VERSION"
fi

# ---------------------------------------------------------------------------
# 2. Architecture
# ---------------------------------------------------------------------------
ARCH=$(uname -m 2>/dev/null || echo "unknown")
_ok "Architecture: $ARCH"
_json_add "ok" "arch" "$ARCH"

# ---------------------------------------------------------------------------
# 3. SIP status
# ---------------------------------------------------------------------------
SIP_STATUS=$(csrutil status 2>/dev/null || echo "unknown")
if echo "$SIP_STATUS" | grep -q "enabled"; then
  _warn "SIP is ENABLED. MAC spoofing and some sudo operations may be restricted."
  _warn "  This is expected on most Macs. Core cleanup will still work."
  _json_add "warn" "sip" "SIP enabled — MAC spoofing may fail"
  SOFT_WARN=1
elif echo "$SIP_STATUS" | grep -q "disabled"; then
  _ok "SIP is disabled (custom/dev configuration)."
  _json_add "ok" "sip" "SIP disabled"
else
  _warn "Could not determine SIP status: $SIP_STATUS"
  _json_add "warn" "sip" "Unknown SIP status: $SIP_STATUS"
  SOFT_WARN=1
fi

# ---------------------------------------------------------------------------
# 4. MDM / managed device detection
# ---------------------------------------------------------------------------
MDM_ENROLLED=false
if command -v profiles >/dev/null 2>&1; then
  if profiles status -type enrollment 2>/dev/null | grep -q "MDM enrollment: Yes"; then
    MDM_ENROLLED=true
    _warn "MDM enrolled — administrator/MDM policies may prevent some operations."
    _warn "  MAC spoofing, network changes, and sudo access may be blocked."
    _warn "  Consult your IT department before running on a managed device."
    _json_add "warn" "mdm" "MDM enrolled — some operations may be blocked by policy"
    SOFT_WARN=1
  else
    _ok "No MDM enrollment detected."
    _json_add "ok" "mdm" "Not MDM enrolled"
  fi
else
  _warn "'profiles' command not available — cannot check MDM enrollment."
  _json_add "warn" "mdm" "Cannot check MDM status (profiles command missing)"
  SOFT_WARN=1
fi

# ---------------------------------------------------------------------------
# 5. sudo availability
# ---------------------------------------------------------------------------
if sudo -n true 2>/dev/null; then
  _ok "sudo access (passwordless / cached credentials)."
  _json_add "ok" "sudo" "Available (no password needed)"
elif command -v sudo >/dev/null 2>&1; then
  # sudo is installed; credentials aren't cached, but the main script will
  # prompt interactively. This is normal and not a hard blocker.
  _warn "sudo available but will require your password at runtime."
  _json_add "warn" "sudo" "Available — password will be prompted at runtime"
  SOFT_WARN=1
else
  _fail "sudo binary not found. Several steps require root access."
  _json_add "fail" "sudo" "sudo binary not found"
  HARD_FAIL=1
fi

# ---------------------------------------------------------------------------
# 6. Required tools
# ---------------------------------------------------------------------------
REQUIRED_TOOLS=(curl openssl networksetup pkgutil)
for cmd in "${REQUIRED_TOOLS[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    _ok "Required tool: $cmd"
    _json_add "ok" "tool_$cmd" "found"
  else
    _fail "Required tool missing: $cmd"
    _json_add "fail" "tool_$cmd" "not found"
    HARD_FAIL=1
  fi
done

# ---------------------------------------------------------------------------
# 7. MAC spoofing capability
# ---------------------------------------------------------------------------
MAC_SPOOF_OK=false
PRIMARY_IF=""
if command -v networksetup >/dev/null 2>&1; then
  HPORTS=$(networksetup -listallhardwareports 2>/dev/null || true)
  if echo "$HPORTS" | grep -q "Wi-Fi"; then
    PRIMARY_IF=$(awk '/Wi-Fi/{found=1} found && /Device:/{print $2; exit}' <<< "$HPORTS")
  else
    PRIMARY_IF=$(awk '/Device:/ && $2 ~ /^en/ {print $2; exit}' <<< "$HPORTS")
  fi
fi

if [[ -n "$PRIMARY_IF" ]]; then
  # Test with a no-op: try reading the current MAC.
  CURRENT_MAC=$(ifconfig "$PRIMARY_IF" 2>/dev/null | awk '/ether/ {print $2}' || echo "")
  if [[ -n "$CURRENT_MAC" ]]; then
    # Apple Silicon Wi-Fi: macOS Private Address makes ifconfig spoofing a no-op.
    if [[ "$ARCH" == "arm64" ]] && echo "$HPORTS" | grep -q "Wi-Fi"; then
      _warn "MAC spoofing: Apple Silicon + Wi-Fi detected."
      _warn "  ifconfig MAC changes are silently ignored by macOS on this hardware."
      _warn "  Spoofing will be attempted but is expected to fail. Use --dry-run to verify."
      _json_add "warn" "mac_spoof" "Apple Silicon Wi-Fi — spoofing unreliable"
      SOFT_WARN=1
    else
      _ok "MAC spoofing should work on $PRIMARY_IF (current: $CURRENT_MAC)."
      _json_add "ok" "mac_spoof" "Interface $PRIMARY_IF available"
      MAC_SPOOF_OK=true
    fi
  else
    _warn "Could not read MAC from $PRIMARY_IF — spoofing may fail."
    _json_add "warn" "mac_spoof" "Cannot read current MAC for $PRIMARY_IF"
    SOFT_WARN=1
  fi
else
  _warn "No primary network interface found — MAC spoofing will be skipped."
  _json_add "warn" "mac_spoof" "No primary interface detected"
  SOFT_WARN=1
fi

# ---------------------------------------------------------------------------
# 8. Network connectivity
# ---------------------------------------------------------------------------
if curl -fsS --max-time 5 https://zoom.us >/dev/null 2>&1; then
  _ok "Network: zoom.us is reachable."
  _json_add "ok" "network" "zoom.us reachable"
else
  _warn "Network: zoom.us not reachable. Zoom download will fail without connectivity."
  _json_add "warn" "network" "zoom.us unreachable"
  SOFT_WARN=1
fi

# ---------------------------------------------------------------------------
# 9. Disk space
# ---------------------------------------------------------------------------
FREE_MB=$(df -m "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
if (( FREE_MB >= 500 )); then
  _ok "Disk space: ${FREE_MB}MB free (≥500 MB required)."
  _json_add "ok" "disk_space" "${FREE_MB}MB free"
elif (( FREE_MB >= 50 )); then
  _warn "Disk space: only ${FREE_MB}MB free. 500 MB recommended; download may fail."
  _json_add "warn" "disk_space" "${FREE_MB}MB free (low)"
  SOFT_WARN=1
else
  _fail "Disk space: ${FREE_MB}MB free — insufficient. Need at least 50 MB."
  _json_add "fail" "disk_space" "${FREE_MB}MB free (critical)"
  HARD_FAIL=1
fi

# ---------------------------------------------------------------------------
# 10. Quarantine / Gatekeeper check on the script itself
# ---------------------------------------------------------------------------
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
if command -v xattr >/dev/null 2>&1; then
  QT=$(xattr -p com.apple.quarantine "$SCRIPT_PATH" 2>/dev/null || echo "")
  if [[ -n "$QT" ]]; then
    _warn "This script has a Gatekeeper quarantine flag set."
    _warn "  If launch is blocked, run: xattr -d com.apple.quarantine \"$SCRIPT_PATH\""
    _json_add "warn" "quarantine" "Quarantine flag present on script"
    SOFT_WARN=1
  else
    _ok "No quarantine flag on this script."
    _json_add "ok" "quarantine" "No quarantine flag"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ $HARD_FAIL -eq 1 ]]; then
  printf "${_BOLD}${_RED}PREFLIGHT RESULT: BLOCKED${_RESET}\n"
  printf "  Hard failures detected. Zoom Nuke will not run correctly.\n"
  printf "  Fix the ❌ items above before proceeding.\n\n"
  PREFLIGHT_EXIT_CODE=1
elif [[ $SOFT_WARN -eq 1 ]]; then
  printf "${_BOLD}${_YELLOW}PREFLIGHT RESULT: DEGRADED MODE${_RESET}\n"
  printf "  Some features (MAC spoofing, network) may not work fully.\n"
  printf "  Core nuke + reinstall should still succeed.\n\n"
  PREFLIGHT_EXIT_CODE=2
else
  printf "${_BOLD}${_GREEN}PREFLIGHT RESULT: ALL CLEAR${_RESET}\n"
  printf "  Full functionality expected.\n\n"
  PREFLIGHT_EXIT_CODE=0
fi

# JSON output to stdout when requested.
if $JSON_MODE; then
  printf '{"exit_code":%d,"results":[' "$PREFLIGHT_EXIT_CODE"
  IFS=','
  echo "${_json_results[*]}"
  unset IFS
  printf ']}\n'
fi

# When sourced, export the code for callers; when run directly, exit with it.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  exit "$PREFLIGHT_EXIT_CODE"
fi
