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
  "$REPO_ROOT/Screw1132_Overkill.sh"
  "$REPO_ROOT/Start Zoom Nuke.command"
  "$REPO_ROOT/README.md"
  "$APP_BUILDER"
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

bash "$APP_BUILDER" "$STAGE_DIR/$BUNDLE_ROOT"
cp "$REPO_ROOT/Screw1132_Overkill.sh" "$STAGE_DIR/$BUNDLE_ROOT/"
cp "$REPO_ROOT/Start Zoom Nuke.command" "$STAGE_DIR/$BUNDLE_ROOT/"
cp "$REPO_ROOT/README.md" "$STAGE_DIR/$BUNDLE_ROOT/"

cat > "$STAGE_DIR/$BUNDLE_ROOT/START_HERE.txt" <<'EOF'
Zoom Nuke - Quick Start
=======================

1) Double-click "Zoom Nuke.app"
2) Choose:
   - Standard Clean (normal cleanup)
   - Deep Clean (more aggressive cleanup)
3) Click Start to open Terminal and run the script
4) Enter your Mac password when asked
5) If macOS blocks opening:
   - Right-click the file
   - Click Open
   - Click Open again in the prompt

Notes:
- "Start Zoom Nuke.command" is included as a fallback launcher.
- A full log is saved to: ~/zoom_fix.log
EOF

chmod +x "$STAGE_DIR/$BUNDLE_ROOT/Screw1132_Overkill.sh"
chmod +x "$STAGE_DIR/$BUNDLE_ROOT/Start Zoom Nuke.command"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR/$BUNDLE_ROOT" "$ARCHIVE_PATH"

echo "Created release bundle:"
echo "  $ARCHIVE_PATH"
