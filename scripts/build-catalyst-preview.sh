#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
TMP_DIR="${TMPDIR:-/tmp}/mood-catalyst-preview"
APP_NAME="Mood"
APP_DIR="$TMP_DIR/$APP_NAME.app"
DMG_NAME="${DMG_NAME:-Mood-UI-current.dmg}"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
TARGET="${TARGET:-arm64-apple-ios26.2-macabi}"
BUNDLE_ID="${BUNDLE_ID:-com.demeauxa8.mood.preview}"

SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
IOS_SUPPORT_FRAMEWORKS="$SDK_PATH/System/iOSSupport/System/Library/Frameworks"

rm -rf "$TMP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR"

xcrun swiftc \
  -parse-as-library \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -F "$IOS_SUPPORT_FRAMEWORKS" \
  -module-name Mood \
  -emit-executable "$ROOT_DIR"/mood/*.swift \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>UIDeviceFamily</key>
  <array>
    <integer>2</integer>
  </array>
</dict>
</plist>
PLIST

ICON_SOURCE="$ROOT_DIR/mood/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
ICONSET="$TMP_DIR/AppIcon.iconset"
if [[ -f "$ICON_SOURCE" ]]; then
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

printf '%s\n' "$DMG_PATH"
