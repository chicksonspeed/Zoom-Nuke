#!/usr/bin/env bash
# zoom_protection.sh
#
# Hostname-spoofing launch wrapper for Zoom.
# Spoofs the system hostname via scutil (so gethostname(2) returns the spoofed
# value to all child processes, including Zoom). Restores the original names on
# EXIT via trap so no permanent change is made even if Zoom crashes.
#
# Usage: zoom_protection.sh [args forwarded to Zoom]
#
# Designed to be installed to ~/.zoom_protection.sh by zoom_nuke_overkill.sh.
# Keep this file in sync with that script.

set -uo pipefail

ZOOM_BIN="${ZOOM_BIN:-/Applications/zoom.us.app/Contents/MacOS/zoom.us}"

if [[ ! -x "$ZOOM_BIN" ]]; then
  echo "❌ Zoom executable not found at $ZOOM_BIN" >&2
  exit 1
fi

# ── Generate spoofed hostname ──────────────────────────────────────────────
# Use openssl for cryptographically strong randomness; fall back to /dev/urandom
# bytes if openssl is absent. Never use $RANDOM (15-bit, time-seeded PRNG).
_rand_hex4() {
  # Always exit 0 so the command substitution on the next line never
  # propagates a non-zero status under set -uo pipefail and kills the script
  # before the _restore_hostname trap fires.
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 4 2>/dev/null || true
  else
    od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true
  fi
}

# Return the current macOS account name sanitized for hostname use.
# id -un is used (not $USER) because $USER can be overridden in the
# environment. We strip anything that isn't alphanumeric so the result
# is safe for LocalHostName (which allows only [A-Za-z0-9-]).
_get_username() {
  local raw
  raw="$(id -un 2>/dev/null || echo "${USER:-user}")"
  printf '%s' "$raw" | tr -cd 'A-Za-z0-9' | cut -c1-16
}

# Return a human-readable Mac model string sanitized for hostname use.
#
# sysctl hw.model returns Apple's internal chassis identifier, e.g.:
#   MacBookPro18,3  →  strip trailing digits/comma  →  MacBookPro  ✓
#   MacBookAir10,1  →  strip trailing digits/comma  →  MacBookAir  ✓
#   iMac21,1        →  strip trailing digits/comma  →  iMac        ✓
#   Macmini9,1      →  strip trailing digits/comma  →  Macmini     ✓
#   Mac14,12        →  strip trailing digits/comma  →  Mac         (bare)
#
# For bare "Mac" results (newer Apple Silicon chassis IDs), we fall back to
# system_profiler SPHardwareDataType to get the marketing name, e.g.
# "Mac Studio" → strip spaces/non-alnum → "MacStudio".
_get_mac_model() {
  local raw model
  raw="$(sysctl -n hw.model 2>/dev/null || echo "")"
  # Strip the numeric suffix including comma: "MacBookPro18,3" → "MacBookPro"
  model="$(printf '%s' "$raw" | sed 's/[0-9,].*$//')"
  # If the result is empty or the unhelpful bare "Mac" (Apple Silicon chassis),
  # ask system_profiler for the human-readable marketing name instead.
  if [[ -z "$model" || "$model" == "Mac" ]]; then
    local sp
    sp="$(system_profiler SPHardwareDataType 2>/dev/null \
          | awk -F': ' '/Model Name[[:space:]]*:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')"
    if [[ -n "$sp" ]]; then
      # "Mac Studio" → strip spaces and non-alphanumeric → "MacStudio"
      model="$(printf '%s' "$sp" | tr -cd 'A-Za-z0-9')"
    fi
  fi
  printf '%s' "${model:-Mac}"
}

SPOOF_SUFFIX="$(_rand_hex4)"
_SPOOF_USER="$(_get_username)"
_SPOOF_MODEL="$(_get_mac_model)"
# Build the spoofed name; fall back to epoch seconds if the hex generator
# somehow returns empty (e.g. both openssl and od are missing).
SPOOF_NAME="${_SPOOF_USER}-${_SPOOF_MODEL}-${SPOOF_SUFFIX:-$(date +%s | cut -c-8)}"

# ── Capture originals (tolerate scutil not being available) ───────────────
ORIG_HOSTNAME="$(scutil --get HostName 2>/dev/null || hostname 2>/dev/null || echo "")"
ORIG_COMPUTERNAME="$(scutil --get ComputerName 2>/dev/null || echo "")"
ORIG_LOCALHOSTNAME="$(scutil --get LocalHostName 2>/dev/null || echo "")"

# ── Restore trap ──────────────────────────────────────────────────────────
_restore_hostname() {
  [[ -n "$ORIG_HOSTNAME" ]]      && sudo scutil --set HostName      "$ORIG_HOSTNAME"      2>/dev/null || true
  [[ -n "$ORIG_COMPUTERNAME" ]]  && sudo scutil --set ComputerName  "$ORIG_COMPUTERNAME"  2>/dev/null || true
  [[ -n "$ORIG_LOCALHOSTNAME" ]] && sudo scutil --set LocalHostName "$ORIG_LOCALHOSTNAME" 2>/dev/null || true
}
trap _restore_hostname EXIT INT TERM

# ── Apply spoof ───────────────────────────────────────────────────────────
if sudo scutil --set HostName      "$SPOOF_NAME" 2>/dev/null && \
   sudo scutil --set ComputerName  "$SPOOF_NAME" 2>/dev/null && \
   sudo scutil --set LocalHostName "$SPOOF_NAME" 2>/dev/null; then
  echo "✅ System hostname spoofed to: $SPOOF_NAME"
else
  echo "⚠️  Could not spoof hostname via scutil (sudo required). Continuing without hostname spoof."
fi

# ── Wipe Zoom residual state before launch ────────────────────────────────
ZOOM_DATA="$HOME/Library/Application Support/zoom.us/data"
rm -rf "$HOME/Library/Caches/us.zoom.xos"         2>/dev/null || true
rm -rf "$ZOOM_DATA"/*.db                            2>/dev/null || true
rm -f  "$ZOOM_DATA/viper.ini"                       2>/dev/null || true

# ── Launch Zoom (replaces this process; trap still fires on its exit) ─────
echo "🚀 Launching Zoom..."
"$ZOOM_BIN" "$@"
