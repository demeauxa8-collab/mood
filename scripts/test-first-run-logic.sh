#!/bin/bash
# Run the same first-run unit tests without launching Mood, Xcode, or any simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
package=build/first-run/logic
mkdir -p "$package/Sources/FirstRunLogic" "$package/Tests/FirstRunLogicTests"
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FirstRunLogic", platforms: [.macOS(.v14)], targets: [
    .target(name: "FirstRunLogic"),
    .testTarget(name: "FirstRunLogicTests", dependencies: ["FirstRunLogic"])
])
SWIFT
cp mood/Core/Models/FirstRunPolicy.swift "$package/Sources/FirstRunLogic/"
cp moodTests/FirstRunTests.swift "$package/Tests/FirstRunLogicTests/"
xcrun swift test --package-path "$package" --jobs 4
