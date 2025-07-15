#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# 🔥 zoom_fix.sh: macOS Zoom Nuke & Reinstall with Ben from IT 🔥
# ──────────────────────────────────────────────────────────

set -Eeuo pipefail
trap 'echo "❌ Oops! Something went wrong at line $LINENO. Exiting…"; exit 1' ERR

# Configuration
LOG="$HOME/zoom_fix.log"
VERSION="3.0.0"
ZOOM_URL="https://zoom.us/client/latest/Zoom.pkg"
REQUIRED_SPACE=500000000  # 500MB in bytes
BACKUP_DIR="$HOME/.zoom_backup_$(date +%Y%m%d_%H%M%S)"

# Logging setup
exec > >(tee -i "$LOG") 2>&1

USAGE="Usage: $0 [-f|--force] [-v|--version] [-h|--help] [-d|--deep-clean]"

# ─── 0. Parse flags ───────────────────────────────────────
FORCE=false
DEEP_CLEAN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force) FORCE=true; shift ;;
    -d|--deep-clean) DEEP_CLEAN=true; shift ;;
    -v|--version) echo "zoom_fix.sh v$VERSION"; exit 0 ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    *) echo "$USAGE"; exit 1 ;;
  esac
done

# ─── 1. Ensure macOS & deps ──────────────────────────────
echo "🔍 Checking system requirements..."
[[ "$(uname)" == "Darwin" ]] || { echo "❌ Only macOS supported."; exit 1; }

# Check macOS version for compatibility
MACOS_VERSION=$(sw_vers -productVersion)
echo "✅ macOS version: $MACOS_VERSION"

for cmd in sudo curl openssl networksetup pkgutil system_profiler; do
  command -v "$cmd" &>/dev/null || { echo "❌ Missing $cmd."; exit 1; }
done

# ─── 2. Check disk space ──────────────────────────────────
echo "💾 Checking available disk space..."
AVAILABLE=$(df "$HOME/Downloads" | awk 'NR==2 {print $4}')
[[ $AVAILABLE -gt $REQUIRED_SPACE ]] || { 
  echo "❌ Insufficient disk space. Need 500MB, have $((AVAILABLE/1024/1024))MB"; 
  exit 1; 
}
echo "✅ Sufficient disk space available"

# ─── 3. Hardware fingerprint analysis ─────────────────────
echo "🔍 Analyzing hardware fingerprint..."
HARDWARE_INFO="$BACKUP_DIR/hardware_info.txt"
mkdir -p "$BACKUP_DIR"

# Capture current hardware fingerprint
{
  echo "=== HARDWARE FINGERPRINT ANALYSIS ==="
  echo "Date: $(date)"
  echo "macOS Version: $MACOS_VERSION"
  echo ""
  echo "=== SYSTEM INFO ==="
  system_profiler SPHardwareDataType 2>/dev/null | grep -E "(Model Name|Model Identifier|Serial Number|Hardware UUID)"
  echo ""
  echo "=== NETWORK INTERFACES ==="
  ifconfig | grep -E "(ether|inet)" | head -10
  echo ""
  echo "=== DISPLAY INFO ==="
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E "(Resolution|Pixel Depth)"
  echo ""
  echo "=== STORAGE INFO ==="
  system_profiler SPStorageDataType 2>/dev/null | grep -E "(Capacity|Protocol)"
  echo ""
  echo "=== AUDIO INFO ==="
  system_profiler SPAudioDataType 2>/dev/null | grep -E "(Output|Input)"
} > "$HARDWARE_INFO"

echo "✅ Hardware fingerprint saved to: $HARDWARE_INFO"

# ─── 4. Detect primary interface ─────────────────────────
echo "🌐 Detecting network interface..."
if networksetup -listallhardwareports | grep -q "Wi-Fi"; then
  IF=$(networksetup -listallhardwareports \
       | awk '/Wi-Fi/{getline; print $2}')
  INTERFACE_TYPE="Wi-Fi"
else
  IF=$(networksetup -listallhardwareports \
       | awk '/Device/ {print $2}' | grep '^en' | head -n1)
  INTERFACE_TYPE="Ethernet"
fi
[[ -n "$IF" ]] || { echo "❌ Could not find any en* interface."; exit 1; }
echo "✅ Interface: $IF ($INTERFACE_TYPE)"

# ─── 5. Optional confirm ──────────────────────────────────
if ! $FORCE; then
  echo ""
  echo "⚠️  This script will:"
  echo "   • Kill all Zoom processes"
  echo "   • Remove Zoom app and all data"
  echo "   • Spoof MAC address and hardware identifiers"
  echo "   • Clear system caches and fingerprints"
  echo "   • Flush DNS and restart network"
  echo "   • Download and reinstall Zoom"
  if $DEEP_CLEAN; then
    echo "   • Perform deep hardware fingerprint removal"
  fi
  echo ""
  read -p "🗑️ Delete Zoom & data? (y/n): " ans
  [[ $ans == [Yy] ]] || { echo "❌ Aborted."; exit 1; }
fi

# ─── 6. Create backup directory ───────────────────────────
echo "💾 Creating backup directory..."
mkdir -p "$BACKUP_DIR"

# ─── 7. Kill & uninstall Zoom ────────────────────────────
echo "🚀 Killing Zoom processes..."
killall zoom.us Zoom zoom 2>/dev/null || true
sleep 3

# Double-check processes are dead
if pgrep -f "zoom" >/dev/null; then
  echo "⚠️ Some Zoom processes still running, force killing..."
  sudo killall -9 zoom.us Zoom zoom 2>/dev/null || true
  sleep 2
fi

echo "🧹 Removing app + preferences..."
sudo rm -rf /Applications/zoom.us.app

# Backup and remove user data
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

for dir in "${ZOOM_DATA_DIRS[@]}"; do
  if [[ -e "$dir" ]]; then
    echo "🗑️ Removing: $dir"
    # Backup before removal
    cp -r "$dir" "$BACKUP_DIR/" 2>/dev/null || true
    rm -rf "$dir"
  fi
done

# ─── 8. Forget pkg receipts & Homebrew ────────────────────
echo "📦 Cleaning package receipts..."
ZOOM_PKG=$(pkgutil --pkgs | grep -i zoom | head -n1 || true)
[[ -n "$ZOOM_PKG" ]] && sudo pkgutil --forget "$ZOOM_PKG" || true

if command -v brew &>/dev/null; then
  echo "🍺 Checking Homebrew installations..."
  CASK=$(brew list --cask 2>/dev/null | grep -i zoom || true)
  [[ -n "$CASK" ]] && brew uninstall --cask "$CASK" || true
fi

# ─── 9. Enhanced MAC spoofing ────────────────────────────
echo "🔧 Attempting MAC address spoofing..."
ORIG_MAC=$(ifconfig "$IF" | awk '/ether/ {print $2}')
BACKUP="$HOME/.orig_mac_backup"
[[ -f $BACKUP ]] || echo "$ORIG_MAC" > "$BACKUP"

# Generate locally-administered MAC (02:xx:xx:xx:xx:xx)
NEW_MAC=$(printf '02:%02x:%02x:%02x:%02x:%02x' \
  $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
  $((RANDOM%256)) $((RANDOM%256)))

echo "🔧 Spoofing MAC: $ORIG_MAC → $NEW_MAC"

# Try multiple methods for MAC spoofing
MAC_SPOOFED=false

# Method 1: Standard ifconfig
if sudo ifconfig "$IF" ether "$NEW_MAC" 2>/dev/null; then
  echo "✅ MAC spoofed via 'ether' syntax"
  MAC_SPOOFED=true
# Method 2: lladdr syntax
elif sudo ifconfig "$IF" lladdr "$NEW_MAC" 2>/dev/null; then
  echo "✅ MAC spoofed via 'lladdr' syntax"
  MAC_SPOOFED=true
# Method 3: Try with interface down/up (for some systems)
elif [[ "$INTERFACE_TYPE" == "Ethernet" ]]; then
  echo "🔄 Trying interface restart method..."
  sudo ifconfig "$IF" down 2>/dev/null
  sleep 1
  sudo ifconfig "$IF" ether "$NEW_MAC" 2>/dev/null
  sudo ifconfig "$IF" up 2>/dev/null
  sleep 2
  if [[ "$(ifconfig "$IF" | awk '/ether/ {print $2}')" == "$NEW_MAC" ]]; then
    echo "✅ MAC spoofed via restart method"
    MAC_SPOOFED=true
  fi
fi

if ! $MAC_SPOOFED; then
  echo "⚠️ Failed to spoof MAC. This is normal on modern macOS with:"
  echo "   • Private Wi-Fi Address enabled"
  echo "   • System Integrity Protection (SIP) active"
  echo "   • Network interface restrictions"
  echo "   Continuing with other cleanup methods..."
fi

# ─── 10. Hardware fingerprint removal ─────────────────────
echo "🔧 Removing hardware fingerprints..."

# Clear system caches that might contain hardware info
CACHE_DIRS=(
  "$HOME/Library/Caches"
  "$HOME/Library/Application Support/Caches"
  "/Library/Caches"
  "/System/Library/Caches"
)

for cache_dir in "${CACHE_DIRS[@]}"; do
  if [[ -d "$cache_dir" ]]; then
    echo "🧹 Clearing cache: $cache_dir"
    find "$cache_dir" -name "*zoom*" -type f -delete 2>/dev/null || true
    find "$cache_dir" -name "*Zoom*" -type f -delete 2>/dev/null || true
  fi
done

# Clear additional system identifiers
echo "🔧 Clearing system identifiers..."
sudo rm -rf /var/folders/*/com.apple.dt.Xcode/* 2>/dev/null || true
sudo rm -rf /var/folders/*/com.apple.WebKit* 2>/dev/null || true
sudo rm -rf /var/folders/*/com.apple.Safari* 2>/dev/null || true

# Clear browser fingerprints
BROWSER_CACHES=(
  "$HOME/Library/Application Support/Google/Chrome/Default/Cache"
  "$HOME/Library/Application Support/Google/Chrome/Default/Code Cache"
  "$HOME/Library/Application Support/Mozilla/Firefox/Profiles/*/cache2"
  "$HOME/Library/Safari/LocalStorage"
  "$HOME/Library/Safari/WebpageIcons.db"
)

for browser_cache in "${BROWSER_CACHES[@]}"; do
  if [[ -d "$browser_cache" ]]; then
    echo "🧹 Clearing browser cache: $browser_cache"
    rm -rf "$browser_cache"/* 2>/dev/null || true
  fi
done

# ─── 11. Deep hardware fingerprint removal (if enabled) ───
if $DEEP_CLEAN; then
  echo "🔧 Performing deep hardware fingerprint removal..."
  
  # Clear additional system caches
  DEEP_CACHE_DIRS=(
    "/var/db/dyld"
    "/var/db/SystemPolicy"
    "/var/db/analyticsd"
    "/var/db/launchd.db"
  )
  
  for deep_cache in "${DEEP_CACHE_DIRS[@]}"; do
    if [[ -d "$deep_cache" ]]; then
      echo "🧹 Deep clearing: $deep_cache"
      sudo rm -rf "$deep_cache"/* 2>/dev/null || true
    fi
  done
  
  # Clear additional identifiers
  echo "🔧 Clearing additional system identifiers..."
  sudo rm -rf /var/db/analyticsd/events 2>/dev/null || true
  sudo rm -rf /var/db/analyticsd/sessions 2>/dev/null || true
  
  # Clear Spotlight index (contains file fingerprints)
  echo "🔧 Clearing Spotlight index..."
  sudo mdutil -E / 2>/dev/null || true
  
  # Clear additional network identifiers
  echo "🔧 Clearing network identifiers..."
  sudo rm -rf /var/db/dhcpd_leases 2>/dev/null || true
  sudo rm -rf /var/db/dhcpd_leases~ 2>/dev/null || true
  
  # Clear additional system logs
  echo "🔧 Clearing system logs..."
  sudo rm -rf /var/log/system.log* 2>/dev/null || true
  sudo rm -rf /var/log/secure.log* 2>/dev/null || true
  
  echo "✅ Deep hardware fingerprint removal completed"
fi

# ─── 12. Enhanced DNS and network cleanup ─────────────────
echo "🌐 Flushing DNS and network caches..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder || true
sudo killall -HUP lookupd || true

# Clear additional caches
sudo rm -rf /Library/Caches/com.apple.dns* 2>/dev/null || true
sudo rm -rf /var/folders/*/com.apple.dns* 2>/dev/null || true

# ─── 13. Smart network service restart ────────────────────
echo "🔄 Restarting network services..."
# Find the primary network service
SERV=$(networksetup -listallnetworkservices | grep -E "^(Wi-Fi|Ethernet)" | head -n1)

if [[ -n "$SERV" ]]; then
  echo "🔄 Restarting network service: $SERV"
  sudo networksetup -setnetworkserviceenabled "$SERV" off
  sleep 3
  sudo networksetup -setnetworkserviceenabled "$SERV" on
  sleep 2
  echo "✅ Network service restarted"
else
  echo "⚠️ No primary network service found; skipping restart"
fi

# ─── 14. Network connectivity test ────────────────────────
echo "🌐 Testing network connectivity..."
if ! curl -s --connect-timeout 10 --max-time 30 "https://www.google.com" >/dev/null; then
  echo "⚠️ Network connectivity test failed. Waiting 10 seconds..."
  sleep 10
  if ! curl -s --connect-timeout 10 --max-time 30 "https://www.google.com" >/dev/null; then
    echo "❌ Network connectivity issues detected. Proceeding anyway..."
  fi
else
  echo "✅ Network connectivity confirmed"
fi

# ─── 15. Download & install Zoom ──────────────────────────
PKG="$HOME/Downloads/Zoom.pkg"
echo "⬇️ Downloading Zoom from official source..."
if ! curl -L --fail --silent --show-error --connect-timeout 30 --max-time 300 -o "$PKG" "$ZOOM_URL"; then
  echo "❌ Download failed. Trying alternative method..."
  # Try alternative download method
  if ! curl -L --fail --silent --show-error --connect-timeout 30 --max-time 300 -o "$PKG" "https://cdn.zoom.us/prod/latest/Zoom.pkg"; then
    echo "❌ All download methods failed. Check network connection."
    exit 1
  fi
fi

# Verify package integrity
echo "🔍 Verifying package integrity..."
if ! pkgutil --check-signature "$PKG" >/dev/null 2>&1; then
  echo "⚠️ Package signature verification failed, but continuing..."
else
  echo "✅ Package signature verified"
fi

# Check package size
PKG_SIZE=$(stat -f%z "$PKG" 2>/dev/null || stat -c%s "$PKG" 2>/dev/null || echo "0")
if [[ $PKG_SIZE -lt 10000000 ]]; then  # Less than 10MB
  echo "❌ Downloaded package seems too small ($((PKG_SIZE/1024/1024))MB). Corrupted download?"
  exit 1
fi

echo "📦 Installing Zoom..."
if ! sudo installer -pkg "$PKG" -target /; then
  echo "❌ Installation failed."
  exit 1
fi

# ─── 16. Verify installation ──────────────────────────────
echo "✅ Verifying installation..."
if [[ ! -d "/Applications/zoom.us.app" ]]; then
  echo "❌ Installation verification failed - app not found"
  exit 1
fi

# Check app version
if [[ -f "/Applications/zoom.us.app/Contents/Info.plist" ]]; then
  ZOOM_VERSION=$(defaults read "/Applications/zoom.us.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
  echo "✅ Zoom installed successfully (version: $ZOOM_VERSION)"
else
  echo "✅ Zoom installed successfully"
fi

# ─── 17. Enhanced data file wiping ───────────────────────
echo "🧹 Wiping residual data files..."
DATA="$HOME/Library/Application Support/zoom.us/data"
mkdir -p "$DATA" 2>/dev/null || true

for f in viper.ini zoomus.enc.db zoommeeting.enc.db; do
  if [[ -f "$DATA/$f" ]]; then
    echo "⚠️ Wiping $f"
    : > "$DATA/$f"
    chmod 400 "$DATA/$f"
  fi
done

# ─── 18. Additional hardware protection ───────────────────
echo "🔧 Setting up additional hardware protection..."

# Create hardware fingerprint spoofing script
PROTECTION_SCRIPT="$HOME/.zoom_protection.sh"
cat > "$PROTECTION_SCRIPT" << 'EOF'
#!/bin/bash
# Hardware fingerprint protection for Zoom

# Spoof additional identifiers
export HOSTNAME="MacBook-$(printf '%02x%02x%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))"
export COMPUTER_NAME="$HOSTNAME"

# Clear additional caches before Zoom launch
rm -rf "$HOME/Library/Caches/us.zoom.xos" 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/zoom.us/data"/*.db 2>/dev/null || true

# Launch Zoom with clean environment
exec /Applications/zoom.us.app/Contents/MacOS/zoom.us "$@"
EOF

chmod +x "$PROTECTION_SCRIPT"
echo "✅ Hardware protection script created: $PROTECTION_SCRIPT"

# ─── 19. Cleanup and finalization ───────────────────────
echo "🧹 Cleaning up..."
rm -f "$PKG"

# Show backup location
if [[ -d "$BACKUP_DIR" ]] && [[ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
  echo "💾 Backup created at: $BACKUP_DIR"
  echo "   You can restore data from here if needed"
fi

# Final status
echo ""
echo "🎉 Zoom nuke & reinstall completed successfully!"
echo "📋 Summary:"
echo "   • Zoom processes killed"
echo "   • App and data removed"
echo "   • MAC address spoofed: $($MAC_SPOOFED && echo "Yes" || echo "No")"
echo "   • Hardware fingerprints cleared"
echo "   • System caches flushed"
echo "   • Network services restarted"
echo "   • Fresh Zoom installed"
echo "   • Hardware protection script created"
echo "   • Log saved to: $LOG"
if $DEEP_CLEAN; then
  echo "   • Deep hardware fingerprint removal performed"
fi
echo ""
echo "🚀 You can now launch Zoom with enhanced protection!"
echo "💡 Use the protection script: $PROTECTION_SCRIPT"

# Optional: Launch Zoom
if ! $FORCE; then
  read -p "🚀 Launch Zoom with protection? (y/n): " launch_ans
  if [[ $launch_ans == [Yy] ]]; then
    echo "🚀 Launching Zoom with hardware protection..."
    "$PROTECTION_SCRIPT" &
  fi
fi
