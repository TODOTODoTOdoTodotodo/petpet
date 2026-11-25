#!/bin/bash
# 배포용 앱·DMG 생성. 기본은 공개용(scripts/private-skins.txt의 캐릭터 제외)
# 개인용으로 모든 캐릭터를 넣으려면: ./scripts/package_app.sh --with-private
set -e
cd "$(dirname "$0")/.."

WITH_PRIVATE=false
[ "$1" = "--with-private" ] && WITH_PRIVATE=true

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

# 출처 미확인 캐릭터는 공개용에서 뺌
if [ "$WITH_PRIVATE" = false ]; then
    grep -v '^#' scripts/private-skins.txt | while read -r name; do
        [ -n "$name" ] || continue
        rm -rf "$RESOURCES_DIR/Assets/Skins/$name" "$RESOURCES_DIR/Assets/Rigs/$name.hang.json"
        echo "    - excluded $name (public build)"
    done
fi

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
    <string>1.2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>펫이 다가오는 일정을 말풍선으로 알려 주기 위해 캘린더를 읽습니다.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>펫이 다가오는 일정을 말풍선으로 알려 주기 위해 캘린더를 읽습니다.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>펫이 마감 시각이 된 미리 알림을 말풍선으로 알려 주기 위해 미리 알림을 읽습니다.</string>
    <key>NSRemindersUsageDescription</key>
    <string>펫이 마감 시각이 된 미리 알림을 말풍선으로 알려 주기 위해 미리 알림을 읽습니다.</string>
</dict>
</plist>
EOF

echo "==> App bundle built successfully at $BUNDLE_DIR"

# 앱 묶음 전체에 임시 서명(ad-hoc). 실행 파일만 서명된 상태면 내려받은 뒤 "손상된 앱"으로 막힐 수 있음
codesign --force --deep --sign - "$BUNDLE_DIR"
codesign --verify --deep --strict "$BUNDLE_DIR"
echo "==> Signed (ad-hoc, not notarized)"

echo "==> Creating Installable DMG (DeskPet.dmg)..."
STAGING_DIR="dmg_stage"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$BUNDLE_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "DeskPet" -srcfolder "$STAGING_DIR" -ov -format UDZO "DeskPet.dmg" > /dev/null

rm -rf "$STAGING_DIR"
echo "==> DMG successfully created: DeskPet.dmg! Share this file with others."

# 터미널 한 줄 설치(install.sh)가 내려받는 압축본. GitHub Releases에 DMG와 함께 올림
echo "==> Creating DeskPet.zip for install.sh..."
rm -f "DeskPet.zip"
ditto -c -k --keepParent "$BUNDLE_DIR" "DeskPet.zip"
echo "==> Zip created: DeskPet.zip (upload to GitHub Releases with DeskPet.dmg)"
