#!/usr/bin/env bash
# tools/build_pkg_installer.sh — Build a macOS .pkg installer for Zoom Nuke.
#
# The .pkg installs Zoom Nuke.app into /Applications and places the shell
# scripts + README in /usr/local/share/zoom-nuke/ for CLI use.
#
# Usage:
#   ./tools/build_pkg_installer.sh [version]
#
# Environment variables (all optional):
#   INSTALLER_SIGN_ID   "Developer ID Installer: Your Name (TEAMID)"
#                       When set, the pkg is signed with that identity.
#                       Without it, the pkg is unsigned (for local/CI use).
#   APP_BUNDLE_DIR      Directory containing the pre-built "Zoom Nuke.app".
#                       Defaults to dist/ (built by build_macos_app.sh).
#   KEEP_STAGE          Set to "1" to keep the staging directory after build
#                       (useful for debugging).
#
# Prerequisites:
#   - macOS with Xcode Command Line Tools (for pkgbuild + productbuild)
#   - tools/build_macos_app.sh must have already been run (or APP_BUNDLE_DIR
#     must point to a directory containing "Zoom Nuke.app")
#
# Enterprise deployment notes:
#   The resulting .pkg supports:
#     sudo installer -pkg Zoom-Nuke-macOS-vX.Y.Z.pkg -target /
#   Silent install (no GUI):
#     sudo installer -pkg Zoom-Nuke-macOS-vX.Y.Z.pkg -target / -verboseR
#   MDM push (Jamf, Mosyle, Kandji, Intune, etc.):
#     Upload the signed .pkg as a standard macOS package payload.
#
# Gatekeeper note:
#   An unsigned .pkg will be blocked by Gatekeeper on macOS 13+ unless the
#   quarantine attribute is cleared first:
#     xattr -d com.apple.quarantine Zoom-Nuke-macOS-vX.Y.Z.pkg
#   Sign with a Developer ID Installer identity to avoid this.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
DIST_DIR="$REPO_ROOT/dist"

VERSION_FILE="$REPO_ROOT/VERSION"
[[ -f "$VERSION_FILE" ]] || { echo "❌ VERSION file not found." >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

VERSION_RAW="${1:-$VERSION}"
VERSION_SAFE="${VERSION_RAW//[^A-Za-z0-9._-]/_}"
PKG_NAME="Zoom-Nuke-macOS-${VERSION_SAFE}.pkg"
PKG_PATH="$DIST_DIR/$PKG_NAME"

APP_BUNDLE_DIR="${APP_BUNDLE_DIR:-$DIST_DIR}"
APP_PATH="$APP_BUNDLE_DIR/Zoom Nuke.app"

BUNDLE_ID="com.chicksonspeed.zoomnuke"
INSTALL_LOCATION_APP="/Applications"
INSTALL_LOCATION_SHARE="/usr/local/share/zoom-nuke"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ .pkg building requires macOS (pkgbuild/productbuild)." >&2
  exit 1
fi

for tool in pkgbuild productbuild; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "❌ Required tool not found: $tool (install Xcode Command Line Tools)" >&2
    exit 1
  }
done

if [[ ! -d "$APP_PATH" ]]; then
  echo "❌ App bundle not found: $APP_PATH" >&2
  echo "   Run ./tools/build_macos_app.sh first, or set APP_BUNDLE_DIR." >&2
  exit 1
fi

echo "📦 Building .pkg installer: $PKG_NAME"
echo "   App:     $APP_PATH"
echo "   Version: $VERSION_RAW"

mkdir -p "$DIST_DIR"
rm -f "$PKG_PATH"

STAGE_DIR="$(mktemp -d)"
cleanup() { [[ "${KEEP_STAGE:-0}" == "1" ]] || rm -rf "$STAGE_DIR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Component 1: App bundle → /Applications
# ---------------------------------------------------------------------------
STAGE_APP="$STAGE_DIR/app_component"
mkdir -p "$STAGE_APP/$INSTALL_LOCATION_APP"
cp -R "$APP_PATH" "$STAGE_APP/$INSTALL_LOCATION_APP/"

APP_PKG="$STAGE_DIR/ZoomNukeApp.pkg"
pkgbuild \
  --root "$STAGE_APP" \
  --identifier "${BUNDLE_ID}.app" \
  --version "$VERSION_RAW" \
  --install-location "/" \
  "$APP_PKG"
echo "✅ Component pkg (app): $APP_PKG"

# ---------------------------------------------------------------------------
# Component 2: Shell scripts + README → /usr/local/share/zoom-nuke/
# ---------------------------------------------------------------------------
STAGE_SHARE="$STAGE_DIR/share_component"
mkdir -p "$STAGE_SHARE/$INSTALL_LOCATION_SHARE"
cp "$REPO_ROOT/zoom_nuke_overkill.sh" "$STAGE_SHARE/$INSTALL_LOCATION_SHARE/"
cp "$REPO_ROOT/zoom_nuke.sh"          "$STAGE_SHARE/$INSTALL_LOCATION_SHARE/"
cp "$REPO_ROOT/README.md"             "$STAGE_SHARE/$INSTALL_LOCATION_SHARE/"
cp -R "$REPO_ROOT/tools/"             "$STAGE_SHARE/$INSTALL_LOCATION_SHARE/tools/"
chmod +x "$STAGE_SHARE/$INSTALL_LOCATION_SHARE/zoom_nuke_overkill.sh"
chmod +x "$STAGE_SHARE/$INSTALL_LOCATION_SHARE/zoom_nuke.sh"

SHARE_PKG="$STAGE_DIR/ZoomNukeShare.pkg"
pkgbuild \
  --root "$STAGE_SHARE" \
  --identifier "${BUNDLE_ID}.scripts" \
  --version "$VERSION_RAW" \
  --install-location "/" \
  "$SHARE_PKG"
echo "✅ Component pkg (scripts): $SHARE_PKG"

# ---------------------------------------------------------------------------
# Distribution XML — binds components, sets title, sets macOS requirement.
# ---------------------------------------------------------------------------
DIST_XML="$STAGE_DIR/distribution.xml"
cat > "$DIST_XML" <<DISTEOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Zoom Nuke ${VERSION_RAW}</title>
  <organization>com.chicksonspeed</organization>
  <domains enable_localSystem="true"/>
  <options require-scripts="false" customize="never" allow-external-scripts="no"/>
  <welcome file="welcome.rtf"/>
  <readme file="readme.rtf"/>

  <pkg-ref id="${BUNDLE_ID}.app"   version="${VERSION_RAW}" auth="root">#ZoomNukeApp.pkg</pkg-ref>
  <pkg-ref id="${BUNDLE_ID}.scripts" version="${VERSION_RAW}" auth="root">#ZoomNukeShare.pkg</pkg-ref>

  <choices-outline>
    <line choice="${BUNDLE_ID}.app"/>
    <line choice="${BUNDLE_ID}.scripts"/>
  </choices-outline>

  <choice id="${BUNDLE_ID}.app" title="Zoom Nuke.app" description="Installs Zoom Nuke.app into /Applications.">
    <pkg-ref id="${BUNDLE_ID}.app"/>
  </choice>
  <choice id="${BUNDLE_ID}.scripts" title="Command-line scripts" description="Installs shell scripts to /usr/local/share/zoom-nuke/.">
    <pkg-ref id="${BUNDLE_ID}.scripts"/>
  </choice>

  <os-version min="12.0"/>
</installer-gui-script>
DISTEOF

# Minimal welcome / readme RTF strings.
cat > "$STAGE_DIR/welcome.rtf" <<'RTFEOF'
{\rtf1\ansi
{\b Zoom Nuke} completely removes Zoom and all associated data, optionally spoofs your MAC address, and reinstalls a fresh copy of Zoom.\par
\par
Click Continue to proceed with the installation.\par
}
RTFEOF

cat > "$STAGE_DIR/readme.rtf" <<'RTFEOF'
{\rtf1\ansi
{\b What is installed}\par
\par
{\b /Applications/Zoom Nuke.app} — GUI launcher with live output.\par
\par
{\b /usr/local/share/zoom-nuke/} — Shell scripts for CLI use:\par
\tab zoom_nuke_overkill.sh — full-featured edition\par
\tab zoom_nuke.sh — simple edition\par
\par
{\b Requirements}\par
macOS 12.0 or later, administrator privileges.\par
\par
{\b Uninstall}\par
Delete /Applications/Zoom Nuke.app and /usr/local/share/zoom-nuke/.\par
\par
{\b Enterprise / MDM deployment}\par
This .pkg can be pushed silently via any MDM solution:\par
\tab sudo installer -pkg <this file> -target /\par
Quarantine must be cleared if unsigned:\par
\tab xattr -d com.apple.quarantine <this file>\par
}
RTFEOF

# ---------------------------------------------------------------------------
# Build the final product .pkg
# ---------------------------------------------------------------------------
SIGN_ARGS=()
if [[ -n "${INSTALLER_SIGN_ID:-}" ]]; then
  SIGN_ARGS=(--sign "$INSTALLER_SIGN_ID" --timestamp)
  echo "🔐 Signing pkg with: $INSTALLER_SIGN_ID"
else
  echo "⚠️  No INSTALLER_SIGN_ID set — building unsigned pkg."
fi

productbuild \
  --distribution "$DIST_XML" \
  --package-path "$STAGE_DIR" \
  --resources "$STAGE_DIR" \
  "${SIGN_ARGS[@]}" \
  "$PKG_PATH"

echo ""
echo "✅ Installer package: $PKG_PATH"
echo "   Size: $(du -sh "$PKG_PATH" | awk '{print $1}')"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Double-click:  open \"$PKG_PATH\""
echo "  Silent/MDM:    sudo installer -pkg \"$PKG_PATH\" -target /"
echo ""
if [[ -z "${INSTALLER_SIGN_ID:-}" ]]; then
  echo "  ⚠️  GATEKEEPER: This .pkg is unsigned."
  echo "     Clear quarantine before distributing:"
  echo "     xattr -d com.apple.quarantine \"$PKG_PATH\""
  echo ""
  echo "  To sign, set INSTALLER_SIGN_ID and re-run:"
  echo "    INSTALLER_SIGN_ID=\"Developer ID Installer: Your Name (TEAMID)\" \\"
  echo "    ./tools/build_pkg_installer.sh"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
