# Brief A — iPhone: copy Discord mobile (Codex)

Branch: `codex/iphone-discord` (from `refactor/structure`). Read `AGENTS.md` first.

## Goal

On iPhone (`layoutMode == .compact`), Mood must look and behave like the **Discord iOS app (2025)**.
Today it is a generic list of servers with a 4-tab bar (Serveurs / Messages / Mentions / Toi) that
does not resemble Discord. Desktop (`layoutMode == .regular`) must not change at all.

## What you own

- `compactLayout`, `CompactTab` and every `Compact*` type in `mood/Features/Home/ContentView.swift`
  (lines ~391–1256: `CompactServerListView`, `CompactChannelListView`, `CompactChatWrapper`,
  `CompactDMListView`, `CompactDMRow`, `CompactDMChatWrapper`, `CompactNotificationsView`, `CompactProfileView`).
- Move them out to new files in `mood/Features/Mobile/` (one main type per file), then rebuild them.
  In `ContentView.swift` leave only the call site `compactLayout` → your new root view.
- Do not edit desktop views (`desktopLayout`, Friends*, Chat/Servers desktop files) — another agent is on them.
  Reuse them read-only (e.g. `ChatArea`, `MessageRow`, `MessageInputBar`) when they fit.

## Target (Discord iOS 2025)

1. **Tab bar**: 3 tabs — `Accueil` (house), `Notifications` (bell), `Toi` (avatar with status dot).
   Unread badge on Notifications from real data (sum of mentions), never a hard-coded number.
2. **Accueil** = two columns side by side:
   - left: the server rail (72 pt): Messages privés button on top (Mood logo), separator, server icons
     (rounded squares, real `iconURL` or emoji), unread dot / mention badge, white pill for selected, `+` and Explore at the bottom.
   - right: the selected server's channel list (server name header with chevron, categories in sentence case
     "Salons textuels ⌄", channels with `#`, bold + badge when unread), or the DM list when Messages privés is selected
     (search field "Rechercher", rows: avatar + status dot, name, last message, time).
3. Tapping a channel or DM **slides the chat in from the right, full screen** (Discord's swipe panels):
   back with the top-left arrow or an edge swipe. Chat header: back, `#name`, members button.
   Composer at the bottom (reuse `MessageInputBar`).
4. **Notifications** tab: real mentions/unreads per room (from `MatrixStore`), empty state "Rien de nouveau".
5. **Toi** tab: banner + avatar, display name, `@username`, status picker (reuse `StatusPickerMenu` logic /
   `matrixStore.setMyStatus`), buttons to Settings (`AccountSettingsView`) and Logout.
6. Server unread indicator bug to fix: today servers with mentions show the tall white "selected" pill.
   Discord: small white dot = unread, tall pill = selected only, red badge = mentions.

Motion: instant tab switches; chat push/pop is a plain horizontal slide (system navigation or a 0.25 s
`.easeOut`), no springs or bounces.

## Done when

- iPhone simulator build `** BUILD SUCCEEDED **` and Mac Catalyst build still succeeds.
- Screenshots in `docs/screenshots/iphone/` (with `-uiPreview`): accueil-serveur.png, accueil-mps.png,
  chat.png, notifications.png, toi.png. Look at each one; compare to Discord iOS.
- No `MockData` reached when a real Matrix session exists (demo data only with `-uiPreview`).
- Commits on `codex/iphone-discord`, small and descriptive. Do not push to `main`.
