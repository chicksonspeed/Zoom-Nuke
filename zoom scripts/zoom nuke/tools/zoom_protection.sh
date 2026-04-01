#!/usr/bin/env bash
# zoom_protection.sh
#
# Hardware fingerprint protection wrapper for Zoom.
# Spoofs the system hostname via scutil (so gethostname(2) returns the spoofed
# value to all child processes, including Zoom). Restores the original names on
# EXIT via trap so no permanent change is made even if Zoom crashes.
#
# Usage: zoom_protection.sh [args forwarded to Zoom]
#
# Designed to be installed to ~/.zoom_protection.sh by zoom_nuke_overkill.sh.
# Keep this file in sync with that script.

set -uo pipefail

ZOOM_BIN="/Applications/zoom.us.app/Contents/MacOS/zoom.us"

if [[ ! -x "$ZOOM_BIN" ]]; then
  echo "❌ Zoom executable not found at $ZOOM_BIN" >&2
  exit 1
fi

# ── Generate spoofed hostname ──────────────────────────────────────────────
# Use openssl for cryptographically strong randomness; fall back to /dev/urandom
# bytes if openssl is absent. Never use $RANDOM (15-bit, time-seeded PRNG).
_rand_hex3() {
  # Always exit 0 so the command substitution on the next line never
  # propagates a non-zero status under set -uo pipefail and kills the script
  # before the _restore_hostname trap fires.
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 3 2>/dev/null || true
  else
    od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true
  fi
}
SPOOF_SUFFIX="$(_rand_hex3)"
SPOOF_NAME="MacBook-${SPOOF_SUFFIX:-$(date +%s)}"

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
exec "$ZOOM_BIN" "$@"
