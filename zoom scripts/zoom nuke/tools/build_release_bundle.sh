#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
DIST_DIR="$REPO_ROOT/dist"
BUNDLE_ROOT="Zoom-Nuke"
APP_BUILDER="$REPO_ROOT/tools/build_macos_app.sh"

VERSION_RAW="${1:-}"
VERSION_SUFFIX=""
if [[ -n "$VERSION_RAW" ]]; then
  VERSION_SAFE="${VERSION_RAW//[^A-Za-z0-9._-]/_}"
  VERSION_SUFFIX="-$VERSION_SAFE"
fi

ARCHIVE_NAME="Zoom-Nuke-macOS${VERSION_SUFFIX}.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

REQUIRED_FILES=(
  "$REPO_ROOT/zoom_nuke_overkill.sh"
  "$REPO_ROOT/zoom_nuke.sh"
  "$REPO_ROOT/Start Zoom Nuke.command"
  "$REPO_ROOT/README.md"
  "$APP_BUILDER"
  "$REPO_ROOT/tools/preflight_check.sh"
)

for required_file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required file: $required_file" >&2
    exit 1
  fi
done

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Release bundling now requires macOS to build Zoom Nuke.app." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$ARCHIVE_PATH"

STAGE_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR/$BUNDLE_ROOT"
mkdir -p "$STAGE_DIR/$BUNDLE_ROOT/cli"

bash "$APP_BUILDER" "$STAGE_DIR/$BUNDLE_ROOT"

# Shell scripts go into cli/ so they don't clutter the top level for normal users
cp "$REPO_ROOT/zoom_nuke_overkill.sh" "$STAGE_DIR/$BUNDLE_ROOT/cli/"
cp "$REPO_ROOT/zoom_nuke.sh"          "$STAGE_DIR/$BUNDLE_ROOT/cli/"
cp "$REPO_ROOT/Start Zoom Nuke.command" "$STAGE_DIR/$BUNDLE_ROOT/cli/"
cp "$REPO_ROOT/tools/preflight_check.sh" "$STAGE_DIR/$BUNDLE_ROOT/cli/"
cp "$REPO_ROOT/README.md"             "$STAGE_DIR/$BUNDLE_ROOT/cli/"

chmod +x "$STAGE_DIR/$BUNDLE_ROOT/cli/zoom_nuke_overkill.sh"
chmod +x "$STAGE_DIR/$BUNDLE_ROOT/cli/zoom_nuke.sh"
chmod +x "$STAGE_DIR/$BUNDLE_ROOT/cli/Start Zoom Nuke.command"
chmod +x "$STAGE_DIR/$BUNDLE_ROOT/cli/preflight_check.sh"

cat > "$STAGE_DIR/$BUNDLE_ROOT/START_HERE.txt" <<'EOF'
Zoom Nuke - Quick Start
=======================

1) Double-click "Zoom Nuke.app"
2) Choose Standard Clean or Deep Clean.
3) Click "Run Cleanup" and enter your Mac password when prompted.
4) Live output streams directly in the app window.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMPORTANT: Gatekeeper (First Launch)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
This app is not signed with an Apple Developer ID.
macOS may block it on the first launch with:
  "cannot be opened because the developer cannot be verified"

FIX: Right-click "Zoom Nuke.app" → Open → Open
     (You only need to do this once.)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Advanced / Command Line
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The "cli" folder contains shell scripts for power users and IT pros.
Most users can ignore it entirely.

Log file: ~/zoom_fix.log
EOF

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR/$BUNDLE_ROOT" "$ARCHIVE_PATH"

# Copy the built app bundle into dist/ so downstream steps (e.g.
# build_pkg_installer.sh) can reference it after this script exits and the
# temporary staging directory is cleaned up by the EXIT trap.
APP_BUNDLE_DIST="$DIST_DIR/$BUNDLE_ROOT"
rm -rf "$APP_BUNDLE_DIST"
cp -R "$STAGE_DIR/$BUNDLE_ROOT/Zoom Nuke.app" "$DIST_DIR/"

echo "Created release bundle:"
echo "  $ARCHIVE_PATH"
echo "App bundle (for downstream pkg build):"
echo "  $DIST_DIR/Zoom Nuke.app"
