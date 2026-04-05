---
name: mood_project_architecture
description: Architecture, conventions, and patterns of the Mood iOS/macOS chat app project
type: project
---

# Mood Project — Architecture Overview

## Stack
- SwiftUI + UIKit (iOS/macOS multiplatform, uses `import UIKit` for `UIPasteboard`)
- `@Observable` macro (Swift 5.9+), not `ObservableObject`
- `MatrixStore` as the main environment object, injected via `.environment(MatrixStore.self)`
- AdaptiveLayout with `.layoutMode` environment key (`.regular` = desktop, `.compact` = mobile)

## File Structure (mood/mood/)
- `Theme.swift` — `MoodTheme` enum (all color tokens), `ThemeManager` (`@Observable`)
- `Modeles.swift` — all data models + `MockData` + `RoleBadge` + `Date` extensions
- `ListeChannels.swift` — `ChannelListColumn`, `CategorySection`, `ChannelRow`, `VoiceConnectedPanel`, `UserStatusPanel`, `MuteButton`, `StatusPanelIcon`, `AnimatedSlash`
- `ZoneChat.swift` — `ChatArea`, `MessageList`, `MessageRow`, `SystemMessageRow`, `ThreadPanel`, `MemberListPanel`, etc.
- `PopupProfil.swift` — `UserProfilePopup`, `ProfileCardSection`, `ProfileSection` (legacy)
- `BarreSaisie.swift` — message input bar
- `BarreServeurs.swift` — server icon sidebar
- `VuePrincipale.swift` — root layout

## Color Token Convention
All colors go through `MoodTheme.*`. No raw `.red`, `.white`, `.black`, etc. in views.
Exceptions allowed: `.white` on overlays with explicit opacity (banner button), destructive red hardcoded in `VoicePanelButton` (intentional: different from `mentionBadge`).

## Key Components
- `StatusIndicator` — defined in ZoneChat.swift (NOT PopupProfil)
- `RoleBadge` — defined in Modeles.swift
- `AnimatedSlash` — diagonal mute slash animation, defined in ListeChannels.swift
- `ProfileCardSection` — compact section header (no background), used in popup
- `ProfileSection` — legacy, adds glass background + padding (used elsewhere)

## Spacing Patterns
- Channel list padding: `.horizontal 8/6`, rows `.vertical 6`
- Popup: `.horizontal 14`, sections `.top 12`
- System messages: icon frame width 38, "Fais coucou" button `.leading 46`
- Voice panel: `.horizontal 10`, `.vertical 8`
