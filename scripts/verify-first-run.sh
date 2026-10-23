#!/bin/bash
# Compile and run Foundation-only tests. Never boot, install, launch, or contact a backend.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
logs=build/first-run
mkdir -p "$logs"
common=(-project mood.xcodeproj -scheme mood -derivedDataPath build/FirstRunDerivedData
    -jobs 4 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO)
xcodebuild "${common[@]}" -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build > "$logs/mac-build.log" 2>&1
rg -q '^\*\* BUILD SUCCEEDED \*\*' "$logs/mac-build.log"
xcodebuild "${common[@]}" -destination 'generic/platform=iOS' build > "$logs/iphone-build.log" 2>&1
rg -q '^\*\* BUILD SUCCEEDED \*\*' "$logs/iphone-build.log"
xcodebuild "${common[@]}" -destination 'generic/platform=iOS Simulator' build-for-testing > "$logs/test-build.log" 2>&1
rg -q '^\*\* TEST BUILD SUCCEEDED \*\*' "$logs/test-build.log"
bash scripts/test-first-run-logic.sh > "$logs/logic-tests.log" 2>&1
echo 'Mac Catalyst + iPhone compiled; iOS test bundle compiled; first-run logic tests passed.'
