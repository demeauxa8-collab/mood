# AGENTS.md — Mood

Instructions for any coding agent (Codex, Claude) working in this repo.
Product owner: Augustin. Talk to him in French; code, comments and commits in English.

## What Mood is

A native SwiftUI Matrix client that copies **Discord's UI/UX** (desktop first, then iPhone).
Matrix spaces = Discord servers, rooms = channels, `m.direct` rooms = DMs.
No external dependency (no SPM, no CocoaPods): the Matrix HTTP client is hand-written.
There is **no end-to-end encryption** yet: never show a lock or "E2E" badge.

## Layout

```
mood/
  App/            MoodApp (entry, RootView, Mac window config)
  Core/Matrix/    MatrixClient (HTTP), MatrixStore (@Observable state + actions), MessageOutbox
  Core/Models/    UI models (MoodUser, MoodServer, Channel, ChatMessage…)
  Core/Storage/   KeychainHelper, SyncCache (disk snapshot)
  DesignSystem/   Theme (MoodTheme colors, MoodMotion, AvatarGlyph), LayoutMetrics, MoodLogo, DesktopChrome
  Features/       Auth, Home (ContentView), Servers, Chat, DirectMessages, Profile, Settings, Calls
  Resources/      Assets.xcassets
moodTests/        Swift Testing, pure logic only
docs/briefs/      one file per parallel work track — read yours before starting
```

The Xcode project uses a synchronized root group: adding/moving files needs no `.pbxproj` edit.

## Rules

- Colors only via `MoodTheme.*`, sizes via `LayoutMetrics.*` and `Font.mood(...)` (Mac Catalyst scales ×1.3).
- Motion: Discord barely animates. Navigation is instant. Hover = `MoodMotion.hover`, popouts = `MoodMotion.popover`.
  No springs, glows, pulses, scale-on-press, `repeatForever`.
- Every button must do something real. No "Bientôt disponible" alerts, no fake success flashes.
  If Matrix cannot do it, hide the control.
- State: `@Observable` + `@MainActor` (project default isolation is MainActor). Views call `MatrixStore` methods;
  networking stays in `MatrixClient`.
- No secrets in code: Supabase URL/anon key come from `Config.xcconfig` (gitignored) via Info.plist keys.
- Small commits, one concern each, imperative English subject. Never commit to `main`.

## Build & verify (Mac Studio, Xcode 27)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Mac
xcodebuild -project mood.xcodeproj -scheme mood -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
# iPhone simulator (iPhone 18 Pro)
xcodebuild -project mood.xcodeproj -scheme mood -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
# Unit tests
xcodebuild -project mood.xcodeproj -scheme mood -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:moodTests
```

Judge a build by `** BUILD SUCCEEDED **` in the log, never by `$?` behind a pipe.
Launch with `-uiPreview` to open directly on demo data (no Matrix account needed).
Screenshot the simulator: `xcrun simctl io booted screenshot out.png`. Look at it before saying a screen is done.
