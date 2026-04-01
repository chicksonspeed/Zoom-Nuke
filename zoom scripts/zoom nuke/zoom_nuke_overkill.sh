#!/usr/bin/env bash
# zoom_nuke_overkill.sh — macOS Zoom Nuke & Reinstall (full-featured edition)
#
# Usage:
#   zoom_nuke_overkill.sh [options]
#
# Options:
#   -f, --force              Skip confirmation prompts
#   -n, --dry-run            Preview actions without making any changes
#   -d, --deep-clean         Also wipe /var/folders Xcode/WebKit/Safari caches
#       --clear-browser-cache  Wipe entire browser caches (Chrome, Edge, Brave, Firefox, Safari)
#       --restore [DIR]      Restore a previous backup (interactive if DIR omitted)
#       --audit              Print a status report and exit (no changes)
#   -v, --version            Show version and exit
#   -h, --help               Show this help and exit

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Bootstrap: locate directories and source libraries
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
TOOLS_DIR="$SCRIPT_DIR/tools"
CORE_LIB="$TOOLS_DIR/_zoom_core.sh"
MAC_SPOOF_LIB="$TOOLS_DIR/mac_spoof.sh"
PROTECTION_SCRIPT_SRC="$TOOLS_DIR/zoom_protection.sh"
PROTECTION_SCRIPT="$HOME/.zoom_protection.sh"
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

# ---------------------------------------------------------------------------
# ERR trap — must be defined after sourcing so it doesn't shadow library errors.
# ---------------------------------------------------------------------------
_on_err() {
  local code=$? line=$1
  echo "❌ Something went wrong at line $line (exit $code). Exiting…"
  exit 1
}
trap '_on_err $LINENO' ERR

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
else
  VERSION="unknown"
fi

USAGE="Usage: $0 [-f|--force] [-n|--dry-run] [-d|--deep-clean] [--clear-browser-cache] [--restore [DIR]] [--audit] [-v|--version] [-h|--help]"

# ---------------------------------------------------------------------------
# parse_args()
# ---------------------------------------------------------------------------
parse_args() {
  FORCE=false
  DEEP_CLEAN=false
  DRY_RUN=false
  CLEAR_BROWSER_CACHE=false
  RESTORE_MODE=false
  RESTORE_DIR=""
  AUDIT_MODE=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      -f|--force)              FORCE=true;               shift ;;
      -d|--deep-clean)         DEEP_CLEAN=true;          shift ;;
      -n|--dry-run)            DRY_RUN=true;             shift ;;
      --clear-browser-cache)   CLEAR_BROWSER_CACHE=true; shift ;;
      --audit)                 AUDIT_MODE=true;          shift ;;
      --restore)
        RESTORE_MODE=true
        if [[ $# -gt 1 && "${2:-}" != -* && -n "${2:-}" ]]; then
          RESTORE_DIR="$2"; shift
        fi
        shift ;;
      -v|--version) echo "zoom_nuke_overkill.sh v$VERSION"; exit 0 ;;
      -h|--help)    echo "$USAGE"; exit 0 ;;
      *) echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Logging — set up after parse_args so --version/--help don't create the log.
# ---------------------------------------------------------------------------
setup_logging() {
  exec > >(tee -i "$LOG") 2>&1
  echo "zoom_nuke_overkill.sh v$VERSION — $(date)"
}

# ---------------------------------------------------------------------------
# audit_mode()
# ---------------------------------------------------------------------------
audit_mode() {
  local report
  report="$HOME/zoom_nuke_audit_$(date +%Y%m%d_%H%M%S).txt"
  {
    echo "═══════════════════════════════════════════════════"
    echo "  Zoom Nuke Audit Report"
    echo "  Generated: $(date)"
    echo "  Tool version: $VERSION"
    echo "  macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
    echo "═══════════════════════════════════════════════════"
    echo ""

    echo "── Zoom Application ──────────────────────────────"
    if [[ -d "/Applications/zoom.us.app" ]]; then
      local zoom_ver
      zoom_ver=$(defaults read "/Applications/zoom.us.app/Contents/Info.plist" \
        CFBundleShortVersionString 2>/dev/null || echo "unknown")
      echo "  Installed: YES (version $zoom_ver)"
    else
      echo "  Installed: NO"
    fi
    echo ""

    echo "── Zoom Data Directories ─────────────────────────"
    local dir
    for dir in "${ZOOM_DATA_DIRS[@]}"; do
      if [[ -e "$dir" ]]; then
        local sz
        sz=$(du -sh "$dir" 2>/dev/null | awk '{print $1}' || echo "?")
        echo "  PRESENT ($sz): $dir"
      else
        echo "  absent:         $dir"
      fi
    done
    echo ""

    echo "── Package Receipts ──────────────────────────────"
    local receipts
    receipts=$(pkgutil --pkgs 2>/dev/null | grep -i zoom || true)
    if [[ -n "$receipts" ]]; then
      echo "$receipts" | while IFS= read -r r; do echo "  $r"; done
    else
      echo "  (none)"
    fi
    echo ""

    echo "── MAC Address Status ────────────────────────────"
    local hports audit_if audit_itype
    hports=$(networksetup -listallhardwareports 2>/dev/null || true)
    if awk '/Wi-Fi/{found=1} END{exit !found}' <<< "$hports"; then
      audit_if=$(awk '/Wi-Fi/{found=1} found && /Device:/{print $2; exit}' <<< "$hports")
      audit_itype="Wi-Fi"
    else
      audit_if=$(awk '/Device:/ && $2 ~ /^en/ {print $2; exit}' <<< "$hports")
      audit_itype="Ethernet"
    fi
    local current_mac
    current_mac=$(ifconfig "${audit_if:-en0}" 2>/dev/null | awk '/ether/ {print $2}' || echo "unknown")
    echo "  Interface: ${audit_if:-unknown} ($audit_itype)"
    echo "  Current MAC: $current_mac"
    local mac_bkp="${MAC_BACKUP_PATH:-$HOME/.orig_mac_backup}"
    if [[ -f "$mac_bkp" ]]; then
      local bver biface bmac bts
      # bver and bts are read for format completeness; only biface and bmac are used.
      # shellcheck disable=SC2034
      IFS=$'\t' read -r bver biface bmac bts < "$mac_bkp" 2>/dev/null || true
      echo "  Backup: $mac_bkp"
      echo "    Original MAC: ${bmac:-?} (interface: ${biface:-?})"
      if [[ "${bmac:-}" == "$current_mac" ]]; then
        echo "    Status: not spoofed (matches backup)"
      else
        echo "    Status: possibly spoofed (differs from backup)"
      fi
    else
      echo "  Backup file: NOT FOUND ($mac_bkp)"
    fi
    echo ""

    echo "── Protection Script ─────────────────────────────"
    if [[ -f "$PROTECTION_SCRIPT" ]]; then
      echo "  EXISTS: $PROTECTION_SCRIPT"
    else
      echo "  NOT FOUND: $PROTECTION_SCRIPT"
    fi
    echo ""

    echo "── Backup Directories ────────────────────────────"
    shopt -s nullglob
    local bkps=("$HOME"/.zoomback.*)
    shopt -u nullglob
    if [[ ${#bkps[@]} -eq 0 ]]; then
      echo "  (none found matching $HOME/.zoomback.*)"
    else
      local b sz btime
      for b in "${bkps[@]}"; do
        sz=$(du -sh "$b" 2>/dev/null | awk '{print $1}' || echo "?")
        btime=$(stat -f '%SB' "$b" 2>/dev/null || stat -c '%y' "$b" 2>/dev/null || echo "?")
        echo "  $b  ($sz, created $btime)"
      done
    fi
    echo ""

    echo "── Hardware Fingerprint ──────────────────────────"
    system_profiler SPHardwareDataType 2>/dev/null \
      | grep -E "(Model Name|Model Identifier|Serial Number|Hardware UUID)" \
      | sed 's/^/  /' || echo "  (could not read)"
    echo ""
    echo "═══════════════════════════════════════════════════"
  } | tee "$report"
  echo ""
  echo "📋 Audit report saved to: $report"
}

# ---------------------------------------------------------------------------
# restore_mode()
# ---------------------------------------------------------------------------
restore_mode() {
  echo "🔄 Zoom Nuke — Restore Mode"
  echo ""

  if [[ -z "$RESTORE_DIR" ]]; then
    shopt -s nullglob
    local available=("$HOME"/.zoomback.*)
    shopt -u nullglob

    if [[ ${#available[@]} -eq 0 ]]; then
      echo "❌ No backup directories found matching $HOME/.zoomback.*"
      exit 1
    fi

    echo "Available backups (newest first):"
    local sorted=()
    while IFS= read -r bkp_entry; do
      sorted+=("$bkp_entry")
    done < <(ls -dt "${available[@]}" 2>/dev/null || true)
    local i
    for i in "${!sorted[@]}"; do
      local btime sz
      btime=$(stat -f '%SB' "${sorted[$i]}" 2>/dev/null \
        || stat -c '%y' "${sorted[$i]}" 2>/dev/null || echo "?")
      sz=$(du -sh "${sorted[$i]}" 2>/dev/null | awk '{print $1}' || echo "?")
      printf "  [%d] %s  (%s, %s)\n" $((i+1)) "${sorted[$i]}" "$sz" "$btime"
    done

    echo ""
    read -r -p "Enter number to restore (or q to quit): " choice
    [[ "$choice" == [Qq] ]] && { echo "❌ Restore aborted."; exit 1; }
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#sorted[@]} )); then
      echo "❌ Invalid choice."; exit 1
    fi
    RESTORE_DIR="${sorted[$((choice-1))]}"
  fi

  [[ -d "$RESTORE_DIR" ]] || { echo "❌ Backup directory not found: $RESTORE_DIR"; exit 1; }

  echo "📂 Restoring from: $RESTORE_DIR"
  read -r -p "⚠️  This will overwrite existing Zoom data. Proceed? (y/n): " confirm
  [[ "$confirm" == [Yy] ]] || { echo "❌ Restore aborted."; exit 1; }

  local count=0 skipped=0 dir basename src
  for dir in "${ZOOM_DATA_DIRS[@]}"; do
    basename="$(basename "$dir")"
    src="$RESTORE_DIR/$basename"
    if [[ -e "$src" ]]; then
      echo "♻️  Restoring: $dir"
      run mkdir -p "$(dirname "$dir")"
      run cp -r "$src" "$dir" && (( count++ )) || true
    else
      echo "   skipping (not in backup): $dir"
      (( skipped++ )) || true
    fi
  done

  echo ""
  echo "✅ Restore complete: $count items restored, $skipped not in backup."
  echo "   Relaunch Zoom to apply."
}

# ---------------------------------------------------------------------------
# capture_hardware_fingerprint()
# ---------------------------------------------------------------------------
capture_hardware_fingerprint() {
  echo "🔍 Capturing hardware fingerprint snapshot..."
  local info_file="$BACKUP_DIR/hardware_info.txt"
  {
    echo "=== HARDWARE FINGERPRINT ANALYSIS ==="
    echo "Date: $(date)"
    echo "macOS Version: $MACOS_VERSION"
    echo ""
    echo "=== SYSTEM INFO ==="
    system_profiler SPHardwareDataType 2>/dev/null \
      | grep -E "(Model Name|Model Identifier|Serial Number|Hardware UUID)" || true
    echo ""
    echo "=== NETWORK INTERFACES ==="
    ifconfig | grep -E "(ether|inet)" | head -10 || true
    echo ""
    echo "=== DISPLAY INFO ==="
    system_profiler SPDisplaysDataType 2>/dev/null \
      | grep -E "(Resolution|Pixel Depth)" || true
    echo ""
    echo "=== STORAGE INFO ==="
    system_profiler SPStorageDataType 2>/dev/null \
      | grep -E "(Capacity|Protocol)" || true
  } > "$info_file"
  echo "✅ Hardware fingerprint saved to: $info_file"
}

# ---------------------------------------------------------------------------
# deep_clean()
# ---------------------------------------------------------------------------
deep_clean() {
  echo "🔧 Deep clean: removing /var/folders entries..."
  run sudo rm -rf /var/folders/*/com.apple.dt.Xcode/*  2>/dev/null || true
  run sudo rm -rf /var/folders/*/com.apple.WebKit*      2>/dev/null || true
  run sudo rm -rf /var/folders/*/com.apple.Safari*      2>/dev/null || true

  echo "🔧 Deep Zoom artifact scan..."
  local roots=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Application Support"
    "/Library/Caches"
  )
  local root match
  for root in "${roots[@]}"; do
    check_cancel
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' match; do
      echo "🧹 Deep removing: $match"
      run rm -rf "$match" 2>/dev/null || true
    done < <(find "$root" -maxdepth 5 \
      \( -iname "*zoom*" -o -iname "*us.zoom*" \) -print0 2>/dev/null || true)
  done
  echo "✅ Deep artifact cleanup complete"
}

# ---------------------------------------------------------------------------
# install_protection_script()
# ---------------------------------------------------------------------------
install_protection_script() {
  echo "🔧 Installing hardware protection script..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "[DRY RUN] Would install protection script to $PROTECTION_SCRIPT"
    return 0
  fi

  if [[ -f "$PROTECTION_SCRIPT_SRC" ]]; then
    cp "$PROTECTION_SCRIPT_SRC" "$PROTECTION_SCRIPT"
    chmod +x "$PROTECTION_SCRIPT"
    echo "✅ Protection script installed from tools/: $PROTECTION_SCRIPT"
  else
    # Inline fallback when tools/ isn't present (e.g. inside the app bundle).
    cat > "$PROTECTION_SCRIPT" << 'PROTECTION_EOF'
#!/usr/bin/env bash
set -uo pipefail
ZOOM_BIN="/Applications/zoom.us.app/Contents/MacOS/zoom.us"
[[ -x "$ZOOM_BIN" ]] || { echo "❌ Zoom not found at $ZOOM_BIN" >&2; exit 1; }
_rand_hex3() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 3 2>/dev/null || true
  else
    od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true
  fi
}
SPOOF_NAME="MacBook-$(_rand_hex3)"
ORIG_HOSTNAME="$(scutil --get HostName 2>/dev/null || hostname 2>/dev/null || echo "")"
ORIG_COMPUTERNAME="$(scutil --get ComputerName 2>/dev/null || echo "")"
ORIG_LOCALHOSTNAME="$(scutil --get LocalHostName 2>/dev/null || echo "")"
_restore() {
  [[ -n "$ORIG_HOSTNAME" ]]      && sudo scutil --set HostName      "$ORIG_HOSTNAME"      2>/dev/null || true
  [[ -n "$ORIG_COMPUTERNAME" ]]  && sudo scutil --set ComputerName  "$ORIG_COMPUTERNAME"  2>/dev/null || true
  [[ -n "$ORIG_LOCALHOSTNAME" ]] && sudo scutil --set LocalHostName "$ORIG_LOCALHOSTNAME" 2>/dev/null || true
}
trap _restore EXIT INT TERM
sudo scutil --set HostName "$SPOOF_NAME" 2>/dev/null \
  && sudo scutil --set ComputerName "$SPOOF_NAME" 2>/dev/null \
  && sudo scutil --set LocalHostName "$SPOOF_NAME" 2>/dev/null \
  && echo "✅ Hostname spoofed to: $SPOOF_NAME" \
  || echo "⚠️  Hostname spoof failed (sudo required)."
rm -rf "$HOME/Library/Caches/us.zoom.xos" 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/zoom.us/data"/*.db 2>/dev/null || true
rm -f  "$HOME/Library/Application Support/zoom.us/data/viper.ini" 2>/dev/null || true
exec "$ZOOM_BIN" "$@"
PROTECTION_EOF
    chmod +x "$PROTECTION_SCRIPT"
    echo "✅ Protection script created (inline fallback): $PROTECTION_SCRIPT"
  fi
}

# ---------------------------------------------------------------------------
# print_summary()
# ---------------------------------------------------------------------------
print_summary() {
  echo ""
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "✅ Dry run complete — no changes were made."
  else
    echo "🎉 Zoom nuke & reinstall completed successfully!"
  fi
  echo ""
  echo "📋 Summary:"
  echo "   • Dry-run mode:           $(if [[ "${DRY_RUN:-false}" == "true" ]]; then echo "Yes (nothing changed)"; else echo "No"; fi)"
  echo "   • Deep clean:             $(if [[ "${DEEP_CLEAN:-false}" == "true" ]]; then echo "Yes"; else echo "No"; fi)"
  echo "   • Browser cache cleared:  $(if [[ "${CLEAR_BROWSER_CACHE:-false}" == "true" ]]; then echo "Yes"; else echo "No"; fi)"
  echo "   • MAC address spoofed:    $(if [[ "${MAC_SPOOFED:-false}" == "true" ]]; then echo "Yes"; else echo "No"; fi)"
  echo "   • Log:                    $LOG"
  if [[ "${DRY_RUN:-false}" == "false" ]]; then
    echo "   • Backup:                 $BACKUP_DIR"
    echo "   • Protection script:      $PROTECTION_SCRIPT"
    echo ""
    echo "   To restore this backup:"
    echo "     $0 --restore $BACKUP_DIR"
  fi
  echo ""
  echo "   To audit without changes:"
  echo "     $0 --audit"
  echo ""
}

# ---------------------------------------------------------------------------
# maybe_launch_zoom()
# ---------------------------------------------------------------------------
maybe_launch_zoom() {
  [[ "${FORCE:-false}" == "true" || "${DRY_RUN:-false}" == "true" ]] && return 0
  read -r -p "🚀 Launch Zoom with protection? (y/n): " launch_ans
  [[ $launch_ans == [Yy] ]] || return 0

  local data="$HOME/Library/Application Support/zoom.us/data"
  if [[ -d "$data" ]]; then
    local f
    for f in viper.ini zoomus.enc.db zoommeeting.enc.db; do
      [[ -f "$data/$f" ]] && { echo "⚠️  Removing $f"; rm -f "$data/$f"; }
    done
  fi

  echo "🚀 Launching Zoom (detached)..."
  nohup "$PROTECTION_SCRIPT" >>"$LOG" 2>&1 &
  local pid=$!
  sleep 2
  echo "✅ Zoom launch requested (PID: $pid)"
}

# ---------------------------------------------------------------------------
# main()
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  setup_logging

  if [[ "$AUDIT_MODE" == "true" ]]; then
    audit_mode
    exit 0
  fi

  if [[ "$RESTORE_MODE" == "true" ]]; then
    restore_mode
    exit 0
  fi

  core_check_requirements          # sets MACOS_VERSION
  core_detect_interface            # sets IF, INTERFACE_TYPE

  # Create backup dir here (after requirements check, before any removal).
  BACKUP_DIR=$(mktemp -d "$HOME/.zoomback.XXXXXXXX")
  capture_hardware_fingerprint

  # Build confirmation extras for deep-clean and browser-cache.
  local confirm_extras=()
  if [[ "$DEEP_CLEAN" == "true" ]]; then
    confirm_extras+=("• Deep clean: wipes Xcode/WebKit/Safari /var/folders caches")
  fi
  if [[ "$CLEAR_BROWSER_CACHE" == "true" ]]; then
    confirm_extras+=("• Browser cache: wipes Chrome, Edge, Brave, Firefox, Safari caches")
  fi
  core_confirm ${confirm_extras[@]+"${confirm_extras[@]}"}

  check_cancel
  core_kill_zoom
  core_remove_zoom_data            # check_cancel inside each loop iteration

  check_cancel
  core_forget_receipts
  core_spoof_mac
  core_clear_zoom_caches           # Zoom-only cache entries; check_cancel inside

  if [[ "$CLEAR_BROWSER_CACHE" == "true" ]]; then
    core_clear_browser_caches      # full browser caches; check_cancel inside
  fi

  if [[ "$DEEP_CLEAN" == "true" ]]; then
    deep_clean                     # check_cancel inside each scan root
  fi

  core_flush_dns
  core_restart_network
  core_test_connectivity

  check_cancel
  core_download_and_install_zoom
  install_protection_script

  print_summary
  maybe_launch_zoom
}

main "$@"
