#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# 📦 build_app_bundle.sh: Convert Screw1132_Overkill.sh to macOS App Bundle
# ──────────────────────────────────────────────────────────
# 
# This script automates the process of converting the Bash script
# Screw1132_Overkill.sh into a proper macOS app bundle that can be
# launched from Finder.
#
# Usage: ./build_app_bundle.sh
#
# Creates: Screw1132_Overkill.app/ with proper bundle structure
# ──────────────────────────────────────────────────────────

set -Eeuo pipefail
trap 'echo "❌ Error at line $LINENO. Exiting..."; exit 1' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/Screw1132_Overkill.sh"
APP_NAME="Screw1132_Overkill"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
VERSION="1.0.0"

echo "🔧 Building macOS App Bundle for $APP_NAME"
echo "📂 Source script: $SOURCE_SCRIPT"
echo "📱 Target bundle: $APP_BUNDLE"
echo ""

# ─── 1. Validate source script exists ────────────────────────
echo "🔍 Step 1: Validating source script..."
if [[ ! -f "$SOURCE_SCRIPT" ]]; then
    echo "❌ Error: Source script '$SOURCE_SCRIPT' not found!"
    exit 1
fi

if [[ ! -r "$SOURCE_SCRIPT" ]]; then
    echo "❌ Error: Source script '$SOURCE_SCRIPT' is not readable!"
    exit 1
fi

echo "✅ Source script validated"

# ─── 2. Clean up existing app bundle ─────────────────────────
echo ""
echo "🧹 Step 2: Cleaning up existing app bundle..."
if [[ -d "$APP_BUNDLE" ]]; then
    echo "⚠️  Removing existing app bundle: $APP_BUNDLE"
    rm -rf "$APP_BUNDLE"
fi
echo "✅ Cleanup completed"

# ─── 3. Create app bundle directory structure ───────────────
echo ""
echo "📁 Step 3: Creating app bundle directory structure..."

# Create the main app bundle directory
mkdir -p "$APP_BUNDLE"
echo "  📂 Created: $APP_BUNDLE"

# Create Contents directory
mkdir -p "$APP_BUNDLE/Contents"
echo "  📂 Created: $APP_BUNDLE/Contents"

# Create MacOS directory (where the executable will live)
mkdir -p "$APP_BUNDLE/Contents/MacOS"
echo "  📂 Created: $APP_BUNDLE/Contents/MacOS"

# Create Resources directory (optional, for app icons and resources)
mkdir -p "$APP_BUNDLE/Contents/Resources"
echo "  📂 Created: $APP_BUNDLE/Contents/Resources"

echo "✅ Directory structure created"

# ─── 4. Copy and prepare the executable script ──────────────
echo ""
echo "📋 Step 4: Copying and preparing executable script..."

# Copy the source script to the MacOS directory with the correct name
# Remove the .sh extension as per macOS app bundle conventions
TARGET_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SOURCE_SCRIPT" "$TARGET_EXECUTABLE"
echo "  📄 Copied script to: $TARGET_EXECUTABLE"

# Make the script executable
chmod +x "$TARGET_EXECUTABLE"
echo "  🔧 Made script executable (chmod +x)"

# Verify the script is executable
if [[ ! -x "$TARGET_EXECUTABLE" ]]; then
    echo "❌ Error: Failed to make script executable!"
    exit 1
fi

echo "✅ Executable script prepared"

# ─── 5. Generate Info.plist file ─────────────────────────────
echo ""
echo "📝 Step 5: Generating Info.plist file..."

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

# Create the Info.plist with proper macOS app metadata
cat > "$INFO_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Basic app identification -->
    <key>CFBundleIdentifier</key>
    <string>com.chicksonspeed.screw1132overkill</string>
    
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    
    <key>CFBundleDisplayName</key>
    <string>Screw 1132 Overkill</string>
    
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    
    <!-- Executable information -->
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    
    <!-- App metadata -->
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    
    <!-- App description and copyright -->
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 Chicksonspeed. All rights reserved.</string>
    
    <key>CFBundleGetInfoString</key>
    <string>Screw 1132 Overkill v$VERSION - macOS Zoom Nuke &amp; Reinstall Tool</string>
    
    <!-- App behavior -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    
    <key>LSMinimumSystemVersion</key>
    <string>10.14</string>
    
    <!-- Terminal execution -->
    <key>LSUIElement</key>
    <false/>
    
    <!-- Allow app to run in Terminal -->
    <key>NSAppleScriptEnabled</key>
    <true/>
    
    <!-- Prevent app from appearing in Dock permanently -->
    <key>LSBackgroundOnly</key>
    <false/>
    
    <!-- File handling -->
    <key>CFBundleDocumentTypes</key>
    <array/>
    
    <!-- High Resolution Capable -->
    <key>NSHighResolutionCapable</key>
    <true/>
    
    <!-- App Transport Security (for network requests) -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "  📄 Created Info.plist with app metadata"
echo "  🆔 Bundle ID: com.chicksonspeed.screw1132overkill"
echo "  📦 App Name: $APP_NAME"
echo "  🔢 Version: $VERSION"

echo "✅ Info.plist generated"

# ─── 6. Verify app bundle structure ──────────────────────────
echo ""
echo "🔍 Step 6: Verifying app bundle structure..."

# Check that all required files and directories exist
REQUIRED_PATHS=(
    "$APP_BUNDLE"
    "$APP_BUNDLE/Contents"
    "$APP_BUNDLE/Contents/MacOS"
    "$APP_BUNDLE/Contents/Resources"
    "$TARGET_EXECUTABLE"
    "$INFO_PLIST"
)

for path in "${REQUIRED_PATHS[@]}"; do
    if [[ ! -e "$path" ]]; then
        echo "❌ Error: Required path missing: $path"
        exit 1
    fi
done

echo "✅ All required paths verified"

# ─── 7. Display app bundle structure ─────────────────────────
echo ""
echo "📂 Step 7: App bundle structure created:"
echo ""
tree "$APP_BUNDLE" 2>/dev/null || {
    echo "$APP_BUNDLE/"
    echo "└── Contents/"
    echo "    ├── MacOS/"
    echo "    │   └── $APP_NAME"
    echo "    ├── Resources/"
    echo "    └── Info.plist"
}

# ─── 8. Display file sizes and permissions ──────────────────
echo ""
echo "📊 File details:"
echo "  $(ls -lh "$TARGET_EXECUTABLE" | awk '{print $1, $5, $9}')"
echo "  $(ls -lh "$INFO_PLIST" | awk '{print $1, $5, $9}')"

# ─── 9. Final validation and instructions ───────────────────
echo ""
echo "✅ App bundle created successfully!"
echo ""
echo "📋 Summary:"
echo "  🎯 App Bundle: $APP_BUNDLE"
echo "  💻 Executable: Contents/MacOS/$APP_NAME"
echo "  📝 Info.plist: Contents/Info.plist"
echo "  📁 Resources: Contents/Resources/"
echo ""
echo "🚀 Usage Instructions:"
echo "  1. Double-click '$APP_NAME.app' in Finder to launch"
echo "  2. The script will run in Terminal with full functionality"
echo "  3. All original command-line options are preserved"
echo ""
echo "🔧 Command-line usage (optional):"
echo "  # Run the app bundle directly"
echo "  open '$APP_BUNDLE'"
echo ""
echo "  # Run the executable directly"
echo "  '$TARGET_EXECUTABLE'"
echo ""
echo "⚠️  Note: The app will request Terminal access when first launched."
echo "    This is normal and required for the script to function."
echo ""
echo "🎉 Build completed successfully!"