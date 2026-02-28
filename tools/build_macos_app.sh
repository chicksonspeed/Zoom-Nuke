#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

OUTPUT_DIR="${1:-$REPO_ROOT/dist}"
APP_NAME="Zoom Nuke.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"
APP_SOURCE="$REPO_ROOT/app/ZoomNukeUI.swift"
MAIN_SCRIPT_SOURCE="$REPO_ROOT/Screw1132_Overkill.sh"
EXECUTABLE_NAME="Zoom Nuke"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
INFO_PLIST_PATH="$APP_PATH/Contents/Info.plist"
PKGINFO_PATH="$APP_PATH/Contents/PkgInfo"
MACOS_MIN_VERSION="12.0"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This build step requires macOS (xcrun/swiftc)." >&2
  exit 1
fi

for required_file in "$APP_SOURCE" "$MAIN_SCRIPT_SOURCE"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required file: $required_file" >&2
    exit 1
  fi
done

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required but not available." >&2
  exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "swiftc is required but not available via xcrun." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_PATH"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_ARCH="$(uname -m)"
TARGET_TRIPLE="$TARGET_ARCH-apple-macos$MACOS_MIN_VERSION"

xcrun swiftc \
  "$APP_SOURCE" \
  -parse-as-library \
  -sdk "$SDK_PATH" \
  -target "$TARGET_TRIPLE" \
  -o "$EXECUTABLE_PATH"

cat > "$INFO_PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Zoom Nuke</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.chicksonspeed.zoomnuke</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Zoom Nuke</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MACOS_MIN_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

printf 'APPL????' > "$PKGINFO_PATH"

cp "$MAIN_SCRIPT_SOURCE" "$APP_PATH/Contents/Resources/Screw1132_Overkill.sh"
chmod +x "$APP_PATH/Contents/Resources/Screw1132_Overkill.sh"
chmod +x "$EXECUTABLE_PATH"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_PATH" >/dev/null 2>&1 || true
fi

echo "Created app bundle:"
echo "  $APP_PATH"
