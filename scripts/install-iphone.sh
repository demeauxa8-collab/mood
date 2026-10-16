#!/bin/zsh
# Reinstalls Mood on Augustin's real iPhone (free personal team: the profile lasts 7 days).
# Signing has to run in the logged-in GUI session (codesign over SSH fails with errSecInternalComponent),
# so Xcode on the Studio builds and signs (project open, run destination "iPhone de ADM"), then devicectl
# installs the signed app. No "Run": a debugger-attached app dies when Xcode stops, and Run waits forever
# on a locked phone.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
DEVICE=00008150-00160388118A401C
open -a /Applications/Xcode.app mood.xcodeproj
result=$(osascript scripts/xcode-action.applescript build)
echo "Xcode build: $result"
[[ "$result" == succeeded* ]]
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/mood-*/Build/Products/Debug-iphoneos/mood.app | head -1)
xcrun devicectl device install app --device $DEVICE "$APP" | grep -E "bundleID|installationURL|rror"
