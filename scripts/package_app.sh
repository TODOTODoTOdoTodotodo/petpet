#!/bin/bash
set -e

echo "==> Building DeskPet (Release)..."
swift build -c release

APP_NAME="DeskPet"
BUNDLE_DIR="$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating macOS App Bundle ($BUNDLE_DIR)..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp ".build/release/DeskPet" "$MACOS_DIR/$APP_NAME"

# Copy Assets/Skins into App Bundle Resources
cp -R "Assets" "$RESOURCES_DIR/"

# Create Info.plist (LSUIElement = true ensures it runs as a pure Menu Bar / Overlay app)
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DeskPet</string>
    <key>CFBundleIdentifier</key>
    <string>com.deskpet.companion</string>
    <key>CFBundleName</key>
    <string>DeskPet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "==> App bundle built successfully at $BUNDLE_DIR"

echo "==> Creating Installable DMG (DeskPet.dmg)..."
STAGING_DIR="dmg_stage"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$BUNDLE_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "DeskPet" -srcfolder "$STAGING_DIR" -ov -format UDZO "DeskPet.dmg" > /dev/null

rm -rf "$STAGING_DIR"
echo "==> DMG successfully created: DeskPet.dmg! Share this file with others."
