#!/usr/bin/env bash
# mac_spoof.sh
#
# MAC address spoofing utilities for Zoom Nuke.
#
# Design goals:
# - Best-effort spoofing with clear logging and reasons when unsupported.
# - No silent expansion of behavior beyond current intent.
# - Easy to audit: all external commands are obvious and centralized.
# - Works as a library: relies only on arguments and documented globals.

# IMPORTANT: Do NOT use `set -e`/`set -u` here; this file is sourced by
# other scripts that control shell options.

MAC_BACKUP_PATH="${MAC_BACKUP_PATH:-$HOME/.orig_mac_backup}"
MAC_SPOOF_COMPONENT_TAG="[mac-spoof]"
MAC_SPOOF_RESTART_SLEEP_DOWN="${MAC_SPOOF_RESTART_SLEEP_DOWN:-1}"
MAC_SPOOF_RESTART_SLEEP_UP="${MAC_SPOOF_RESTART_SLEEP_UP:-2}"
MAC_SPOOF_MIN_MACOS_VERSION="${MAC_SPOOF_MIN_MACOS_VERSION:-10.15.0}"

# Globals set by spoof_mac_address for callers to inspect.
MAC_SPOOFED=${MAC_SPOOFED:-false}
MAC_SPOOF_REASON="${MAC_SPOOF_REASON:-}"

_mac_log() {
  local level="$1"; shift
  printf '%s [%s] %s\n' "$MAC_SPOOF_COMPONENT_TAG" "$level" "$*" 1>&2
}

mac_log_info()  { _mac_log "INFO"  "$*"; }
mac_log_warn()  { _mac_log "WARN"  "$*"; }
mac_log_error() { _mac_log "ERROR" "$*"; }
mac_log_debug() { _mac_log "DEBUG" "$*"; }

# Use existing version_to_number if the caller defines it, otherwise provide
# a local implementation.
if ! command -v version_to_number >/dev/null 2>&1; then
  version_to_number() {
    local version="$1"
    local IFS='.'
    local parts
    read -r -a parts <<< "$version"
    printf "%03d%03d%03d" "${parts[0]:-0}" "${parts[1]:-0}" "${parts[2]:-0}"
  }
fi

mac_spoof_detect_platform() {
  PLATFORM_CPU="$(uname -m 2>/dev/null || echo "unknown")"
  PLATFORM_MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
}

mac_spoof_supported_for_interface() {
  # Usage: mac_spoof_supported_for_interface INTERFACE_TYPE
  # INTERFACE_TYPE: "Wi-Fi" or "Ethernet"
  #
  # Returns 0 if we should attempt spoofing (best-effort),
  # sets MAC_SPOOF_REASON with an explanation when spoofing is unlikely.
  local iface_type="$1"

  mac_spoof_detect_platform

  if [[ "$PLATFORM_CPU" == arm64 && "$iface_type" == "Wi-Fi" ]]; then
    MAC_SPOOF_REASON="Wi-Fi MAC spoofing is heavily restricted on Apple Silicon; attempts are likely to fail even with sudo."
    mac_log_warn "$MAC_SPOOF_REASON"
    return 0
  fi

  local current_num min_num
  current_num="$(version_to_number "$PLATFORM_MACOS_VERSION" 2>/dev/null || echo "000000000")"
  min_num="$(version_to_number "$MAC_SPOOF_MIN_MACOS_VERSION" 2>/dev/null || echo "000000000")"

  if ((10#$current_num < 10#$min_num)); then
    MAC_SPOOF_REASON="macOS $PLATFORM_MACOS_VERSION is older than supported $MAC_SPOOF_MIN_MACOS_VERSION; spoofing behavior is untested."
    mac_log_warn "$MAC_SPOOF_REASON"
    return 0
  fi

  MAC_SPOOF_REASON=""
  return 0
}

get_interface_mac() {
  # Usage: get_interface_mac IFACE
  # Prints current MAC or empty string on failure.
  local iface="$1"
  ifconfig "$iface" 2>/dev/null | awk '/ether/ {print $2; exit}' || true
}

generate_random_laa_mac() {
  # Generates a locally administered MAC (02:xx:xx:xx:xx:xx).
  printf '02:%02x:%02x:%02x:%02x:%02x' \
    $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
    $((RANDOM%256)) $((RANDOM%256))
}

backup_original_mac_if_needed() {
  # Usage: backup_original_mac_if_needed IFACE
  # Reads current MAC and stores it in MAC_BACKUP_PATH if not already present.
  # No-op if current MAC cannot be determined.
  local iface="$1"

  if [[ -f "$MAC_BACKUP_PATH" ]]; then
    mac_log_debug "Original MAC backup already exists at $MAC_BACKUP_PATH"
    return 0
  fi

  local orig
  orig="$(get_interface_mac "$iface")"
  if [[ -z "$orig" ]]; then
    MAC_SPOOF_REASON="Could not determine current MAC address for $iface; skipping backup."
    mac_log_warn "$MAC_SPOOF_REASON"
    return 1
  fi

  printf '%s\n' "$orig" > "$MAC_BACKUP_PATH" || {
    mac_log_warn "Failed to write MAC backup to $MAC_BACKUP_PATH"
    return 1
  }
  mac_log_info "Backed up original MAC for $iface to $MAC_BACKUP_PATH"
}

restore_original_mac() {
  # Best-effort rollback using MAC_BACKUP_PATH if it exists.
  # Usage: restore_original_mac IFACE
  local iface="$1"

  if [[ ! -f "$MAC_BACKUP_PATH" ]]; then
    mac_log_debug "No MAC backup found at $MAC_BACKUP_PATH; nothing to restore."
    return 0
  fi

  local orig
  orig="$(cat "$MAC_BACKUP_PATH" 2>/dev/null || true)"
  if [[ -z "$orig" ]]; then
    mac_log_warn "MAC backup at $MAC_BACKUP_PATH is empty; cannot restore."
    return 1
  fi

  mac_log_info "Restoring original MAC for $iface -> $orig"
  if sudo ifconfig "$iface" ether "$orig" 2>/dev/null; then
    mac_log_info "Successfully restored original MAC for $iface"
    return 0
  fi

  mac_log_warn "Failed to restore original MAC for $iface via 'ether'."
  return 1
}

spoof_mac_ifconfig() {
  # Usage: spoof_mac_ifconfig IFACE NEW_MAC
  # Tries standard 'ether' then 'lladdr'. Returns 0 on success, 1 on failure.
  local iface="$1"
  local new_mac="$2"

  if sudo ifconfig "$iface" ether "$new_mac" 2>/dev/null; then
    mac_log_info "MAC spoofed on $iface via 'ether' syntax"
    return 0
  fi

  if sudo ifconfig "$iface" lladdr "$new_mac" 2>/dev/null; then
    mac_log_info "MAC spoofed on $iface via 'lladdr' syntax"
    return 0
  fi

  return 1
}

spoof_mac_restart_ethernet() {
  # Usage: spoof_mac_restart_ethernet IFACE NEW_MAC
  # Ethernet-only strategy: down -> change -> up -> verify.
  # Returns 0 on success, 1 on failure.
  local iface="$1"
  local new_mac="$2"

  mac_log_info "Trying Ethernet restart method for $iface..."
  sudo ifconfig "$iface" down 2>/dev/null || mac_log_debug "ifconfig down failed for $iface (continuing)"
  sleep "$MAC_SPOOF_RESTART_SLEEP_DOWN"
  sudo ifconfig "$iface" ether "$new_mac" 2>/dev/null || mac_log_debug "ifconfig ether failed during restart for $iface"
  sudo ifconfig "$iface" up 2>/dev/null || mac_log_debug "ifconfig up failed for $iface"
  sleep "$MAC_SPOOF_RESTART_SLEEP_UP"

  local current
  current="$(get_interface_mac "$iface")"
  if [[ "$current" == "$new_mac" ]]; then
    mac_log_info "MAC spoofed on $iface via restart method"
    return 0
  fi

  mac_log_debug "Restart method did not change MAC on $iface (current=$current, expected=$new_mac)"
  return 1
}

spoof_mac_address() {
  # Usage: spoof_mac_address IFACE INTERFACE_TYPE
  #
  # IFACE          : e.g. "en0"
  # INTERFACE_TYPE : "Wi-Fi" or "Ethernet"
  #
  # Effects:
  #   - Sets MAC_SPOOFED=true|false
  #   - Sets MAC_SPOOF_REASON with human-readable explanation on failure.
  #   - Returns 0 if spoof was successful, 1 otherwise.
  #
  # Notes:
  # - This is best-effort; on modern macOS and Apple Silicon, spoofing may
  #   be effectively blocked by system protections.

  local iface="$1"
  local iface_type="$2"

  MAC_SPOOFED=false
  MAC_SPOOF_REASON=""

  mac_log_info "Attempting MAC spoofing on $iface ($iface_type)..."

  if [[ -z "$iface" ]]; then
    MAC_SPOOF_REASON="Interface name is empty; cannot spoof MAC."
    mac_log_error "$MAC_SPOOF_REASON"
    return 1
  fi

  mac_spoof_supported_for_interface "$iface_type" || true

  local orig_mac
  orig_mac="$(get_interface_mac "$iface")"
  if [[ -z "$orig_mac" ]]; then
    MAC_SPOOF_REASON="Could not read current MAC address for $iface; aborting spoof attempt."
    mac_log_error "$MAC_SPOOF_REASON"
    return 1
  fi

  backup_original_mac_if_needed "$iface" || true

  local new_mac
  new_mac="$(generate_random_laa_mac)"
  mac_log_info "Planned MAC change on $iface: $orig_mac -> $new_mac"

  if spoof_mac_ifconfig "$iface" "$new_mac"; then
    MAC_SPOOFED=true
    MAC_SPOOF_REASON="MAC spoof succeeded via direct ifconfig."
    return 0
  fi

  if [[ "$iface_type" == "Ethernet" ]]; then
    if spoof_mac_restart_ethernet "$iface" "$new_mac"; then
      MAC_SPOOFED=true
      MAC_SPOOF_REASON="MAC spoof succeeded via Ethernet restart method."
      return 0
    fi
  fi

  MAC_SPOOFED=false
  MAC_SPOOF_REASON="Failed to spoof MAC on $iface. This is common on modern macOS due to Private Wi-Fi Address, SIP, and driver restrictions."
  mac_log_warn "$MAC_SPOOF_REASON"
  return 1
}

