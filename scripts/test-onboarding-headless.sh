#!/bin/bash
# Run the production model/adapter tests as a CLI, without an app host or simulator.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/mood-onboarding-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/OnboardingHarness" "$test_dir/Tests/OnboardingHarnessTests"
for source in OnboardingModel OnboardingAdapter OnboardingLifecycle; do
    cp "$repo_dir/mood/Features/Onboarding/$source.swift" "$test_dir/Sources/OnboardingHarness/"
done
# Only the user value type belongs to the UI module. Tests exercise the original action boundary.
cat > "$test_dir/Sources/OnboardingHarness/MoodUser.swift" <<'SWIFT'
struct MoodUser {}
SWIFT
cp "$repo_dir/moodTests/OnboardingTests.swift" "$test_dir/Tests/OnboardingHarnessTests/"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OnboardingHarness", platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OnboardingHarness"),
        .testTarget(name: "OnboardingHarnessTests", dependencies: ["OnboardingHarness"])
    ]
)
SWIFT
xcrun swift test --package-path "$test_dir" --scratch-path "$test_dir/.build" --disable-sandbox
