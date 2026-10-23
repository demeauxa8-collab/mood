#!/bin/zsh
# Builds a Release Mood.app for the Mac (Mac Catalyst, ad-hoc signed) and packs it into build/Release-dmg/Mood.dmg.
# Not notarized (no Developer ID): on another Mac, open it with right-click > Ouvrir the first time (docs/RELEASE.md).
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
[ -d mood/Vendor/MatrixSDKCrypto ] || { echo "mood/Vendor/MatrixSDKCrypto missing: run scripts/build-crypto.sh or copy it"; exit 1; }
OUT=build/Release-dmg
rm -rf "$OUT"; mkdir -p "$OUT/dmg"
xcodebuild -project mood.xcodeproj -scheme mood -configuration Release \
  -destination "platform=macOS,variant=Mac Catalyst" -derivedDataPath build/ReleaseData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build > build/release-mac.log 2>&1 || true
grep -q "\*\* BUILD SUCCEEDED \*\*" build/release-mac.log || { grep -E "error:" build/release-mac.log | sort -u | head -10; echo "RELEASE BUILD FAILED (build/release-mac.log)"; exit 1; }
ditto build/ReleaseData/Build/Products/Release-maccatalyst/mood.app "$OUT/dmg/Mood.app"
codesign --force --deep --sign - "$OUT/dmg/Mood.app"   # ad-hoc: required to run on Apple Silicon
codesign --verify --deep "$OUT/dmg/Mood.app"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Mood" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/Mood.dmg" >/dev/null
echo "DMG: $PWD/$OUT/Mood.dmg ($(du -h "$OUT/Mood.dmg" | cut -f1))"
