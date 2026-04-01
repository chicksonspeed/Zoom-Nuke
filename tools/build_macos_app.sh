#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

OUTPUT_DIR="${1:-$REPO_ROOT/dist}"
APP_NAME="Zoom Nuke.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"
APP_SOURCES_DIR="$REPO_ROOT/app"
MAIN_SCRIPT_SOURCE="$REPO_ROOT/zoom_nuke_overkill.sh"
TOOLS_SOURCE="$REPO_ROOT/tools"
ICON_NAME="ZoomNuke"
ICON_SOURCE="$REPO_ROOT/app/${ICON_NAME}.icns"
EXECUTABLE_NAME="Zoom Nuke"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
INFO_PLIST_PATH="$APP_PATH/Contents/Info.plist"
PKGINFO_PATH="$APP_PATH/Contents/PkgInfo"
MACOS_MIN_VERSION="12.0"

# Single source of truth: read version from VERSION file.
VERSION_FILE="$REPO_ROOT/VERSION"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "❌ VERSION file not found at $VERSION_FILE" >&2
  exit 1
fi
APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
# CFBundleVersion must be numeric-only; strip dots and non-digits.
BUNDLE_VERSION="$(echo "$APP_VERSION" | tr -d '.')"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This build step requires macOS (xcrun/swiftc)." >&2
  exit 1
fi

# Collect all Swift source files from app/.
# Use a glob rather than find+mapfile so it works on bash 3.2 (macOS default).
SWIFT_SOURCES=()
for f in "$APP_SOURCES_DIR"/*.swift; do
  [[ -f "$f" ]] && SWIFT_SOURCES+=("$f")
done
if [[ ${#SWIFT_SOURCES[@]} -eq 0 ]]; then
  echo "❌ No Swift source files found in $APP_SOURCES_DIR" >&2
  exit 1
fi
echo "Swift sources (${#SWIFT_SOURCES[@]}):"
for f in "${SWIFT_SOURCES[@]}"; do echo "  $f"; done

# Check all required source files before touching output.
if [[ ! -f "$MAIN_SCRIPT_SOURCE" ]]; then
  echo "Missing required file: $MAIN_SCRIPT_SOURCE" >&2
  exit 1
fi

# Icon: use the real .icns if present; otherwise generate a minimal placeholder
# so local/CI builds succeed without requiring the binary asset in the repo.
ICON_IS_PLACEHOLDER=false
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "⚠️  app/ZoomNuke.icns not found — generating a minimal placeholder icon."
  echo "   For a production build, add app/ZoomNuke.icns to the repository."
  ICONSET_TMP="$OUTPUT_DIR/.ZoomNuke_placeholder.iconset"
  mkdir -p "$ICONSET_TMP"
  # 1024×1024 solid blue square via sips (no ImageMagick required).
  local_icon_png="$ICONSET_TMP/icon_1024x1024.png"
  python3 - "$local_icon_png" <<'PYEOF'
import struct, zlib, sys
def make_png(w, h, color=(0x26, 0x89, 0xFF)):
    raw = b''.join(b'\x00' + bytes(color) * w for _ in range(h))
    def chunk(tag, data):
        c = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', c)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
with open(sys.argv[1], 'wb') as f:
    f.write(make_png(1024, 1024))
PYEOF
  # Populate required iconset sizes from the 1024px source.
  for size in 16 32 64 128 256 512 1024; do
    sips -z "$size" "$size" "$local_icon_png" \
      --out "$ICONSET_TMP/icon_${size}x${size}.png" >/dev/null 2>&1 || true
    if (( size <= 512 )); then
      sips -z "$((size*2))" "$((size*2))" "$local_icon_png" \
        --out "$ICONSET_TMP/icon_${size}x${size}@2x.png" >/dev/null 2>&1 || true
    fi
  done
  iconutil -c icns "$ICONSET_TMP" -o "$ICON_SOURCE" 2>/dev/null \
    || { echo "❌ Failed to generate placeholder icon." >&2; exit 1; }
  rm -rf "$ICONSET_TMP"
  ICON_IS_PLACEHOLDER=true
  echo "✅ Placeholder icon generated at: $ICON_SOURCE"
fi

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
mkdir -p "$APP_PATH/Contents/Resources/tools"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

# Build a universal binary (arm64 + x86_64) so the app runs natively on both
# Apple Silicon and Intel without Rosetta.
ARM64_TMP="$OUTPUT_DIR/.build_arm64_tmp"
X86_TMP="$OUTPUT_DIR/.build_x86_64_tmp"

echo "🔨 Compiling arm64..."
xcrun swiftc \
  "${SWIFT_SOURCES[@]}" \
  -parse-as-library \
  -sdk "$SDK_PATH" \
  -target "arm64-apple-macos$MACOS_MIN_VERSION" \
  -o "$ARM64_TMP"

echo "🔨 Compiling x86_64..."
xcrun swiftc \
  "${SWIFT_SOURCES[@]}" \
  -parse-as-library \
  -sdk "$SDK_PATH" \
  -target "x86_64-apple-macos$MACOS_MIN_VERSION" \
  -o "$X86_TMP"

echo "🔗 Merging into universal binary..."
lipo -create "$ARM64_TMP" "$X86_TMP" -output "$EXECUTABLE_PATH"
rm -f "$ARM64_TMP" "$X86_TMP"

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
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
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

# Copy the VERSION file into the bundle so the embedded script can read it.
cp "$VERSION_FILE" "$APP_PATH/Contents/Resources/VERSION"

# Copy the main script.
cp "$MAIN_SCRIPT_SOURCE" "$APP_PATH/Contents/Resources/zoom_nuke_overkill.sh"
chmod +x "$APP_PATH/Contents/Resources/zoom_nuke_overkill.sh"

# Copy all tool scripts that zoom_nuke_overkill.sh sources at runtime.
# _zoom_core.sh and mac_spoof.sh are MANDATORY — without them the script
# fails immediately at the library sourcing stage.
for tool_script in \
    "$TOOLS_SOURCE/_zoom_core.sh" \
    "$TOOLS_SOURCE/mac_spoof.sh" \
    "$TOOLS_SOURCE/zoom_protection.sh"; do
  if [[ -f "$tool_script" ]]; then
    cp "$tool_script" "$APP_PATH/Contents/Resources/tools/"
    chmod +x "$APP_PATH/Contents/Resources/tools/$(basename "$tool_script")"
    echo "   Bundled tool: $(basename "$tool_script")"
  else
    # _zoom_core.sh and mac_spoof.sh are hard requirements.
    case "$(basename "$tool_script")" in
      _zoom_core.sh|mac_spoof.sh)
        echo "❌ Required tool script not found: $tool_script" >&2
        exit 1
        ;;
      *)
        echo "⚠️  Optional tool script not found (skipping): $tool_script" >&2
        ;;
    esac
  fi
done

cp "$ICON_SOURCE" "$APP_PATH/Contents/Resources/${ICON_NAME}.icns"
chmod +x "$EXECUTABLE_PATH"

# ---------------------------------------------------------------------------
# Code signing
#
# Two modes are supported via environment variables:
#
#   DEVELOPER_ID   (optional) — e.g. "Developer ID Application: Your Name (TEAMID)"
#                  When set, the app is signed with that identity and submitted
#                  for notarization. Requires:
#                    - A valid cert in the keychain
#                    - APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID env vars
#                  for xcrun notarytool submission.
#
#   (default)      Ad-hoc signing (--sign -). Hardened Runtime is still enabled
#                  so TCC dialogs function correctly. Gatekeeper will quarantine
#                  the app on first launch; users must right-click → Open once.
#
# Failure is fatal: shipping an unsigned app causes a completely silent
# Gatekeeper block on macOS 15+.
# ---------------------------------------------------------------------------
if command -v codesign >/dev/null 2>&1; then
  ENTITLEMENTS_PLIST="$OUTPUT_DIR/.entitlements_tmp.plist"
  cat > "$ENTITLEMENTS_PLIST" <<'ENTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.automation.apple-events</key>
  <true/>
</dict>
</plist>
ENTEOF

  SIGN_IDENTITY="${DEVELOPER_ID:--}"
  SIGN_LABEL="ad-hoc"
  [[ "$SIGN_IDENTITY" != "-" ]] && SIGN_LABEL="Developer ID ($SIGN_IDENTITY)"

  echo "🔐 Signing app bundle ($SIGN_LABEL + Hardened Runtime)..."
  if codesign --force --sign "$SIGN_IDENTITY" --options runtime \
       --entitlements "$ENTITLEMENTS_PLIST" \
       --timestamp \
       "$APP_PATH" 2>&1; then
    echo "✅ Code signing succeeded ($SIGN_LABEL)"
  else
    echo "❌ codesign failed. The app will be blocked by Gatekeeper." >&2
    rm -f "$ENTITLEMENTS_PLIST"
    exit 1
  fi
  rm -f "$ENTITLEMENTS_PLIST"

  # Notarization — only attempted when a Developer ID is provided and the
  # required credentials are available in the environment.
  if [[ "$SIGN_IDENTITY" != "-" ]] \
     && [[ -n "${APPLE_ID:-}" ]] \
     && [[ -n "${APPLE_APP_PASSWORD:-}" ]] \
     && [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    echo "📤 Submitting for notarization..."
    NOTARIZE_ZIP="$OUTPUT_DIR/.notarize_tmp.zip"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
    if xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait; then
      xcrun stapler staple "$APP_PATH"
      echo "✅ Notarization and stapling succeeded."
    else
      echo "⚠️  Notarization submission failed. App is signed but not notarized." >&2
      echo "   Users on macOS 13+ will still need to right-click → Open once." >&2
    fi
    rm -f "$NOTARIZE_ZIP"
  elif [[ "$SIGN_IDENTITY" != "-" ]]; then
    echo "ℹ️  Notarization skipped (APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID not set)."
    echo "   Set those env vars and re-run to notarize, or staple manually."
  fi
else
  echo "⚠️  codesign not available — app will be unsigned." >&2
fi

echo ""
echo "✅ App bundle created: $APP_PATH"
echo "   Version:      $APP_VERSION"
echo "   Architecture: universal (arm64 + x86_64)"
if [[ "$ICON_IS_PLACEHOLDER" == "true" ]]; then
  echo "   Icon:         ⚠️  placeholder (add app/ZoomNuke.icns for a real icon)"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
  echo "  ⚠️  GATEKEEPER NOTICE"
  echo "  This build is ad-hoc signed (no Developer ID)."
  echo ""
  echo "  On first launch, macOS Gatekeeper will quarantine the app."
  echo "  Users must right-click → Open → Open to bypass this once."
  echo ""
  echo "  To remove quarantine manually (e.g. for MDM pre-deployment):"
  echo "    xattr -d com.apple.quarantine \"$APP_PATH\""
  echo ""
  echo "  For a fully trusted build, re-sign with a Developer ID:"
  echo "    DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\" \\"
  echo "    APPLE_ID=\"you@example.com\" \\"
  echo "    APPLE_APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\" \\"
  echo "    APPLE_TEAM_ID=\"YOURTEAMID\" \\"
  echo "    ./tools/build_macos_app.sh"
else
  echo "  ✅ Signed with Developer ID — Gatekeeper quarantine will not apply"
  echo "     if the app was notarized and stapled."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
