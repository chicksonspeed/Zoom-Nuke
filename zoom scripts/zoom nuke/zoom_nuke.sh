#!/usr/bin/env bash
# zoom_nuke.sh — macOS Zoom Nuke & Reinstall (simple edition)
#
# A streamlined wrapper around the shared _zoom_core.sh library.
# For advanced options (deep-clean, dry-run, restore, audit) use
# zoom_nuke_overkill.sh instead.
#
# Usage: zoom_nuke.sh [-f|--force] [-v|--version] [-h|--help]

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
TOOLS_DIR="$SCRIPT_DIR/tools"
CORE_LIB="$TOOLS_DIR/_zoom_core.sh"
MAC_SPOOF_LIB="$TOOLS_DIR/mac_spoof.sh"
LOG="$HOME/zoom_fix.log"

# Both libraries are mandatory: mac_spoof.sh owns version_to_number, which
# _zoom_core.sh calls unconditionally inside core_check_requirements(). A
# missing file is a hard error — silently skipping it causes a later crash.
if [[ -f "$MAC_SPOOF_LIB" ]]; then
  # shellcheck source=/dev/null
  . "$MAC_SPOOF_LIB"
else
  echo "❌ Required library not found: $MAC_SPOOF_LIB" >&2
  exit 1
fi

if [[ -f "$CORE_LIB" ]]; then
  # shellcheck source=/dev/null
  . "$CORE_LIB"
else
  echo "❌ Required library not found: $CORE_LIB" >&2
  exit 1
fi

trap 'echo "❌ Something went wrong at line $LINENO (exit $?). Exiting…"; exit 1' ERR

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
else
  VERSION="unknown"
fi

USAGE="Usage: $0 [-f|--force] [-v|--version] [-h|--help]"

# ---------------------------------------------------------------------------
# main()
# ---------------------------------------------------------------------------
main() {
  # FORCE is consumed by core_confirm() in the sourced _zoom_core.sh library.
  # shellcheck disable=SC2034
  FORCE=false
  # shellcheck disable=SC2034
  while [[ $# -gt 0 ]]; do
    case $1 in
      -f|--force)   FORCE=true; shift ;;
      -v|--version) echo "zoom_nuke.sh v$VERSION"; exit 0 ;;
      -h|--help)    echo "$USAGE"; exit 0 ;;
      *) echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
    esac
  done

  # Logging — after flag parsing so --version/--help skip it.
  exec > >(tee -i "$LOG") 2>&1
  echo "zoom_nuke.sh v$VERSION — $(date)"

  core_check_requirements          # sets MACOS_VERSION; exits on failure
  core_detect_interface            # sets IF, INTERFACE_TYPE

  # Simple edition: a minimal backup dir (no hardware fingerprint snapshot).
  BACKUP_DIR=$(mktemp -d "$HOME/.zoomback.XXXXXXXX")

  core_confirm                     # asks "Proceed? (y/n)" unless FORCE=true

  check_cancel
  core_kill_zoom
  core_remove_zoom_data            # check_cancel inside each loop iteration

  echo "✅ Zoom deleted."

  core_forget_receipts
  core_spoof_mac
  core_flush_dns
  core_restart_network

  echo "💨 Quick break…"; sleep 2

  core_download_and_install_zoom
  core_wipe_residual_data

  echo ""
  echo "🎉 All done! Details in $LOG."
  if [[ -d "$BACKUP_DIR" ]]; then
    echo "   Backup at: $BACKUP_DIR"
  fi
}

main "$@"
