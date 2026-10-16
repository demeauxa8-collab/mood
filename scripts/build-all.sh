#!/bin/zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/mood-codex-merge
L=~/mood-logs/$1
xcodebuild -project mood.xcodeproj -scheme mood -destination "platform=macOS,variant=Mac Catalyst" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build > $L-mac.log 2>&1
xcodebuild -project mood.xcodeproj -scheme mood -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build > $L-ios.log 2>&1
xcodebuild -project mood.xcodeproj -scheme mood -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:moodTests > $L-test.log 2>&1
echo DONE > $L-done
