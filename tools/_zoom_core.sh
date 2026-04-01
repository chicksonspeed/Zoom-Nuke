#!/usr/bin/env bash
# _zoom_core.sh — Shared library for zoom_nuke.sh and zoom_nuke_overkill.sh.
#
# This file is SOURCED, not executed. It must not contain top-level side effects.
# Callers set these globals before sourcing (or accept the defaults):
#
#   DRY_RUN          "true"|"false"   — skip destructive commands
#   FORCE            "true"|"false"   — skip confirmation prompts
#   BACKUP_DIR       path             — where to back up removed data
#   LOG              path             — log file path
#   ZOOM_DATA_DIRS   array            — list of Zoom user-data paths to remove
#
# Globals exported to callers after sourcing:
#   IF               detected network interface (e.g. "en0")
#   INTERFACE_TYPE   "Wi-Fi" or "Ethernet"
#   MACOS_VERSION    output of sw_vers -productVersion
#   MAC_SPOOFED      "true"|"false"
#   MAC_SPOOF_REASON human-readable string
#
# IMPORTANT: Do NOT set -e / -u / -o pipefail here; callers control those.

# ---------------------------------------------------------------------------
# Constants shared by both scripts
# ---------------------------------------------------------------------------
ZOOM_URL="${ZOOM_URL:-https://zoom.us/client/latest/Zoom.pkg}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-10.15.0}"
MIN_FREE_MB="${MIN_FREE_MB:-500}"

ZOOM_DATA_DIRS=(
  "$HOME/Library/Application Support/zoom.us"
  "$HOME/Library/Caches/us.zoom.xos"
  "$HOME/Library/Preferences/us.zoom.xos.plist"
  "$HOME/Library/Logs/zoom.us"
  "$HOME/Library/LaunchAgents/us.zoom.xos.plist"
  "$HOME/Library/Preferences/zoom.us.conf"
  "$HOME/Library/Containers/us.zoom.xos"
  "$HOME/Library/Saved Application State/us.zoom.xos.savedState"
)

# ---------------------------------------------------------------------------
# run() — dry-run wrapper used by all destructive commands.
# Callers must set DRY_RUN before sourcing (defaults to false).
# ---------------------------------------------------------------------------
DRY_RUN="${DRY_RUN:-false}"

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# check_cancel() — sentinel for UI-driven cancellation.
# If ZOOM_NUKE_CANCEL_FILE is set and the file exists, exit 130.
# Call this after every major destructive block.
# ---------------------------------------------------------------------------
check_cancel() {
  if [[ -n "${ZOOM_NUKE_CANCEL_FILE:-}" && -f "$ZOOM_NUKE_CANCEL_FILE" ]]; then
    echo "🛑 Cancellation requested. Stopping cleanup..."
    exit 130
  fi
}

# ---------------------------------------------------------------------------
# core_check_requirements()
# Validates OS, macOS version, required tools, and free disk space.
# Exits on failure; sets MACOS_VERSION on success.
# ---------------------------------------------------------------------------
core_check_requirements() {
  echo "🔍 Checking system requirements..."
  [[ "$(uname)" == "Darwin" ]] || { echo "❌ Only macOS supported."; exit 1; }

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "⚠️  DRY RUN mode — no destructive changes will be made."
  fi

  MACOS_VERSION=$(sw_vers -productVersion)
  local current_num min_num
  current_num=$(version_to_number "$MACOS_VERSION")
  min_num=$(version_to_number "$MIN_MACOS_VERSION")
  if (( 10#$current_num < 10#$min_num )); then
    echo "❌ Unsupported macOS version: $MACOS_VERSION (minimum: $MIN_MACOS_VERSION)"
    exit 1
  fi
  echo "✅ macOS version: $MACOS_VERSION"

  local cmd
  for cmd in sudo curl openssl networksetup pkgutil; do
    command -v "$cmd" &>/dev/null || { echo "❌ Missing required tool: $cmd"; exit 1; }
  done

  local free_mb
  free_mb=$(df -m "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
  if (( free_mb < MIN_FREE_MB )); then
    echo "❌ Insufficient disk space: ${free_mb}MB free, ${MIN_FREE_MB}MB required."
    exit 1
  fi
  echo "✅ Disk space: ${free_mb}MB available"
}

# ---------------------------------------------------------------------------
# core_detect_interface()
# Sets IF and INTERFACE_TYPE. Exits if no en* interface is found.
# ---------------------------------------------------------------------------
core_detect_interface() {
  echo "🌐 Detecting network interface..."
  local hardware_ports
  hardware_ports=$(networksetup -listallhardwareports 2>/dev/null || true)
  if awk '/Wi-Fi/{found=1} END{exit !found}' <<< "$hardware_ports"; then
    IF=$(awk '/Wi-Fi/{found=1} found && /Device:/{print $2; exit}' <<< "$hardware_ports")
    INTERFACE_TYPE="Wi-Fi"
  else
    IF=$(awk '/Device:/ && $2 ~ /^en/ {print $2; exit}' <<< "$hardware_ports")
    INTERFACE_TYPE="Ethernet"
  fi
  [[ -n "$IF" ]] || { echo "❌ Could not find any en* interface."; exit 1; }
  echo "✅ Interface: $IF ($INTERFACE_TYPE)"
}

# ---------------------------------------------------------------------------
# core_confirm()
# Interactive confirmation prompt. Skipped when FORCE=true or DRY_RUN=true.
# Takes optional extra lines to display in the warning (passed as arguments).
# ---------------------------------------------------------------------------
core_confirm() {
  if [[ "${FORCE:-false}" == "false" && "${DRY_RUN:-false}" == "false" ]]; then
    echo ""
    echo "⚠️  This script will:"
    echo "   • Kill all Zoom processes"
    echo "   • Remove Zoom app and all data"
    echo "   • Spoof MAC address"
    echo "   • Clear system caches and fingerprints"
    echo "   • Flush DNS and restart network"
    echo "   • Download and reinstall Zoom"
    # Print any caller-supplied extra lines.
    local line
    for line in "$@"; do
      echo "   $line"
    done
    echo ""
    read -r -p "🗑️  Proceed? (y/n): " ans
    [[ $ans == [Yy] ]] || { echo "❌ Aborted."; exit 1; }
  fi
}

# ---------------------------------------------------------------------------
# core_kill_zoom()
# Gracefully kills Zoom processes; force-kills stragglers.
# ---------------------------------------------------------------------------
core_kill_zoom() {
  echo "🚀 Killing Zoom processes..."
  run killall zoom.us Zoom zoom 2>/dev/null || true
  sleep 3

  if pgrep -f "zoom" >/dev/null 2>&1; then
    echo "⚠️  Some Zoom processes still running, force killing..."
    run sudo killall -9 zoom.us Zoom zoom 2>/dev/null || true
    sleep 2
  fi
}

# ---------------------------------------------------------------------------
# core_remove_zoom_data()
# Removes the app bundle and each ZOOM_DATA_DIRS entry.
# Backs up each item to BACKUP_DIR before deletion.
# Calls check_cancel after each removal.
# ---------------------------------------------------------------------------
core_remove_zoom_data() {
  echo "🧹 Removing app + preferences..."
  run sudo rm -rf /Applications/zoom.us.app

  local dir
  for dir in "${ZOOM_DATA_DIRS[@]}"; do
    check_cancel
    if [[ -e "$dir" ]]; then
      echo "🗑️  Backing up and removing: $dir"
      if [[ -n "${BACKUP_DIR:-}" ]]; then
        cp -r "$dir" "$BACKUP_DIR/" 2>/dev/null || true
      fi
      run rm -rf "$dir"
    fi
  done
}

# ---------------------------------------------------------------------------
# core_forget_receipts()
# Removes Zoom pkgutil receipts and any Homebrew cask installations.
# ---------------------------------------------------------------------------
core_forget_receipts() {
  echo "📦 Cleaning package receipts..."
  local zoom_pkg
  while IFS= read -r zoom_pkg; do
    [[ -n "$zoom_pkg" ]] || continue
    echo "🗑️  Forgetting: $zoom_pkg"
    run sudo pkgutil --forget "$zoom_pkg" || true
  done < <(pkgutil --pkgs 2>/dev/null | grep -i zoom || true)

  if command -v brew &>/dev/null; then
    echo "🍺 Checking Homebrew installations..."
    local cask
    while IFS= read -r cask; do
      [[ -n "$cask" ]] || continue
      echo "🍺 Uninstalling cask: $cask"
      run brew uninstall --cask "$cask" || true
    done < <(brew list --cask 2>/dev/null | grep -i zoom || true)
  fi
}

# ---------------------------------------------------------------------------
# core_spoof_mac()
# Calls the shared mac_spoof library if available; sets MAC_SPOOFED.
# Requires IF and INTERFACE_TYPE to be set (by core_detect_interface).
# ---------------------------------------------------------------------------
core_spoof_mac() {
  echo "🔧 Attempting MAC address spoofing..."
  MAC_SPOOFED=false

  if command -v spoof_mac_address >/dev/null 2>&1; then
    spoof_mac_address "$IF" "$INTERFACE_TYPE" || true
    if [[ "${MAC_SPOOFED:-false}" == "true" ]]; then
      echo "✅ MAC address spoofed"
    else
      echo "⚠️  Failed to spoof MAC on $IF (common on modern macOS)."
      [[ -n "${MAC_SPOOF_REASON:-}" ]] && echo "   Reason: $MAC_SPOOF_REASON"
      echo "   Continuing with other cleanup methods..."
    fi
  else
    echo "⚠️  MAC spoofing library not available; skipping."
  fi
}

# ---------------------------------------------------------------------------
# core_clear_zoom_caches()
# Removes Zoom-named entries from system cache directories.
# Does NOT touch full browser caches — callers that want browser-cache
# clearing should call core_clear_browser_caches() explicitly.
# Calls check_cancel after each cache directory.
# ---------------------------------------------------------------------------
core_clear_zoom_caches() {
  echo "🔧 Removing Zoom fingerprint artifacts from system caches..."
  local cache_dirs=(
    "$HOME/Library/Caches"
    "$HOME/Library/Application Support/Caches"
    "/Library/Caches"
  )

  local cache_dir
  for cache_dir in "${cache_dirs[@]}"; do
    check_cancel
    if [[ -d "$cache_dir" ]]; then
      echo "🧹 Clearing Zoom cache entries in: $cache_dir"
      run find "$cache_dir" \
        \( -name "*zoom*" -o -name "*Zoom*" -o -name "*us.zoom*" \) \
        -not -path "*/System/Library/*" \
        -type f -delete 2>/dev/null || true
    fi
  done

  # Zoom-specific Safari LocalStorage entries (not the full Safari cache).
  local safari_items=(
    "$HOME/Library/Safari/LocalStorage/https_zoom.us_0.localstorage"
    "$HOME/Library/Safari/LocalStorage/https_us04web.zoom.us_0.localstorage"
  )
  local item
  for item in "${safari_items[@]}"; do
    check_cancel
    if [[ -f "$item" ]]; then
      echo "🧹 Removing Zoom browser storage: $item"
      run rm -f "$item" 2>/dev/null || true
    fi
  done
}

# ---------------------------------------------------------------------------
# core_clear_browser_caches()
# Wipes entire browser cache directories for Chrome, Edge, Brave, Firefox,
# and Safari. Only called when the caller passes --clear-browser-cache.
# Calls check_cancel after each browser cache.
# ---------------------------------------------------------------------------
core_clear_browser_caches() {
  echo "🌐 Clearing browser caches (--clear-browser-cache requested)..."
  local browser_caches=(
    "$HOME/Library/Application Support/Google/Chrome/Default/Cache"
    "$HOME/Library/Application Support/Google/Chrome/Default/Code Cache"
    "$HOME/Library/Application Support/Microsoft Edge/Default/Cache"
    "$HOME/Library/Application Support/Microsoft Edge/Default/Code Cache"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Code Cache"
    "$HOME/Library/Safari/LocalStorage"
    "$HOME/Library/Safari/WebpageIcons.db"
  )

  # Append Firefox profile caches safely (nullglob prevents empty expansions).
  shopt -s nullglob
  local firefox_cache
  for firefox_cache in "$HOME"/Library/Application\ Support/Mozilla/Firefox/Profiles/*/cache2; do
    browser_caches+=("$firefox_cache")
  done
  shopt -u nullglob

  local bc
  for bc in "${browser_caches[@]}"; do
    check_cancel
    if [[ -d "$bc" ]]; then
      echo "🧹 Clearing browser cache dir: $bc"
      run find "${bc:?}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    elif [[ -f "$bc" ]]; then
      echo "🧹 Removing browser cache file: $bc"
      run rm -f "$bc" 2>/dev/null || true
    fi
  done
}

# ---------------------------------------------------------------------------
# core_flush_dns()
# Flushes DNS caches and clears dns-related /Library/Caches entries.
# ---------------------------------------------------------------------------
core_flush_dns() {
  echo "🌐 Flushing DNS and network caches..."
  run sudo dscacheutil -flushcache
  run sudo killall -HUP mDNSResponder 2>/dev/null || true
  run sudo killall -HUP lookupd 2>/dev/null || true
  run sudo rm -rf /Library/Caches/com.apple.dns* 2>/dev/null || true
  run sudo rm -rf /var/folders/*/com.apple.dns* 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# core_restart_network()
# Toggles the primary Wi-Fi or Ethernet service off then on.
# ---------------------------------------------------------------------------
core_restart_network() {
  echo "🔄 Restarting network services..."
  local serv
  serv=$(networksetup -listallnetworkservices 2>/dev/null \
    | sed '1d; s/^\* //' \
    | grep -E "^(Wi-Fi|Ethernet)$" \
    | head -n1 || true)

  if [[ -n "$serv" ]]; then
    echo "🔄 Restarting: $serv"
    run sudo networksetup -setnetworkserviceenabled "$serv" off
    sleep 3
    run sudo networksetup -setnetworkserviceenabled "$serv" on
    sleep 2
    echo "✅ Network service restarted"
  else
    echo "⚠️  No primary network service found; skipping restart"
  fi
}

# ---------------------------------------------------------------------------
# core_test_connectivity()
# Non-fatal network connectivity check with one retry.
# ---------------------------------------------------------------------------
core_test_connectivity() {
  echo "🌐 Testing network connectivity..."
  local attempt ok=false
  for attempt in 1 2; do
    if curl -s --connect-timeout 10 --max-time 30 "https://www.google.com" >/dev/null 2>&1; then
      ok=true; break
    fi
    [[ $attempt -lt 2 ]] && { echo "⚠️  Network not ready, waiting 10s..."; sleep 10; }
  done
  if [[ "$ok" == "true" ]]; then
    echo "✅ Network connectivity confirmed"
  else
    echo "⚠️  Network connectivity test failed. Proceeding anyway..."
  fi
}

# ---------------------------------------------------------------------------
# core_download_and_install_zoom()
# Downloads Zoom.pkg (or falls back to Installomator), verifies signature
# and size, installs, then verifies the installed app.
# No-op when DRY_RUN=true.
# Requires: ZOOM_URL, INSTALLOMATOR_URL, INSTALLOMATOR_BIN
# ---------------------------------------------------------------------------
INSTALLOMATOR_URL="${INSTALLOMATOR_URL:-https://github.com/Installomator/Installomator/releases/latest/download/Installomator.pkg}"
INSTALLOMATOR_BIN="${INSTALLOMATOR_BIN:-/usr/local/Installomator/Installomator.sh}"

core_download_and_install_zoom() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "[DRY RUN] Would download and install Zoom from $ZOOM_URL"
    return 0
  fi

  local pkg installomator_pkg="" used_installomator=false
  pkg=$(mktemp "${TMPDIR:-/tmp}/Zoom.XXXXXXXX.pkg")

  echo "⬇️  Downloading Zoom from official source..."
  if ! curl -L --fail --silent --show-error --connect-timeout 30 --max-time 300 \
       -o "$pkg" "$ZOOM_URL"; then
    echo "❌ Zoom download failed. Trying Installomator fallback..."
    installomator_pkg=$(mktemp "${TMPDIR:-/tmp}/Installomator.XXXXXXXX.pkg")

    if ! curl -L --fail --silent --show-error --connect-timeout 30 --max-time 300 \
         -o "$installomator_pkg" "$INSTALLOMATOR_URL"; then
      echo "❌ Failed to download Installomator."
      rm -f "$pkg" "$installomator_pkg"
      return 1
    fi

    echo "🔍 Verifying Installomator signature..."
    local sig
    if ! sig=$(pkgutil --check-signature "$installomator_pkg" 2>&1); then
      echo "❌ Installomator signature check failed:"
      echo "$sig"
      rm -f "$pkg" "$installomator_pkg"
      return 1
    fi
    echo "✅ Installomator signature verified"

    echo "📦 Installing Installomator..."
    if ! sudo installer -pkg "$installomator_pkg" -target /; then
      echo "❌ Installomator installation failed."
      rm -f "$pkg" "$installomator_pkg"
      return 1
    fi
    rm -f "$installomator_pkg"; installomator_pkg=""

    [[ -x "$INSTALLOMATOR_BIN" ]] || {
      echo "❌ Installomator binary not found at $INSTALLOMATOR_BIN"
      rm -f "$pkg"
      return 1
    }

    echo "📦 Installing Zoom via Installomator..."
    if ! sudo "$INSTALLOMATOR_BIN" zoom; then
      echo "❌ Installomator failed to install Zoom."
      rm -f "$pkg"
      return 1
    fi
    used_installomator=true
  fi

  if [[ "$used_installomator" == "false" ]]; then
    echo "🔍 Verifying package signature..."
    local sig_info
    if ! sig_info=$(pkgutil --check-signature "$pkg" 2>&1); then
      echo "❌ Package signature verification failed:"
      echo "$sig_info"
      rm -f "$pkg"
      return 1
    fi
    echo "✅ Package signature verified"

    local pkg_size
    pkg_size=$(stat -f%z "$pkg" 2>/dev/null || stat -c%s "$pkg" 2>/dev/null || echo "0")
    if (( pkg_size < 10000000 )); then
      echo "❌ Package is only $((pkg_size/1024/1024))MB — likely corrupted."
      rm -f "$pkg"
      return 1
    fi

    echo "📦 Installing Zoom..."
    if ! sudo installer -pkg "$pkg" -target /; then
      echo "❌ Installation failed."
      rm -f "$pkg"
      return 1
    fi
  fi

  rm -f "$pkg"

  echo "✅ Verifying installation..."
  if [[ ! -d "/Applications/zoom.us.app" ]]; then
    echo "❌ Zoom app not found after install."
    return 1
  fi
  local zoom_ver
  zoom_ver=$(defaults read "/Applications/zoom.us.app/Contents/Info.plist" \
    CFBundleShortVersionString 2>/dev/null || echo "unknown")
  echo "✅ Zoom installed (version: $zoom_ver)"
}

# ---------------------------------------------------------------------------
# core_wipe_residual_data()
# Zeros and chmod 400 the known identity-bearing data files so a fresh
# Zoom launch gets a clean slate without the full data directory being absent.
# ---------------------------------------------------------------------------
core_wipe_residual_data() {
  local data_dir="$HOME/Library/Application Support/zoom.us/data"
  [[ -d "$data_dir" ]] || return 0

  local f
  for f in viper.ini zoomus.enc.db zoommeeting.enc.db; do
    if [[ -f "$data_dir/$f" ]]; then
      echo "⚠️  Wiping $f"
      : > "$data_dir/$f"
      chmod 400 "$data_dir/$f"
    fi
  done
}
