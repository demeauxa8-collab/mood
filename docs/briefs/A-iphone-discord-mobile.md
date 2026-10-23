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

## Update (Augustin, 07/10) — Liquid Glass + closer to Discord iOS

**References:** 6 official Discord iPhone screenshots (App Store, v348, Oct 2026) are attached to your
prompt and stored outside git in `~/discord-ios-ref/` on the Studio. Match them closely:
- `discord-ios-3`: **Messages** = server rail on the left, then "Messages" title, search field +
  "Ajouter des amis" pill + "+" button, rows (avatar with status, name, last message preview, relative time "15m/1h"),
  and at the bottom a floating **user pill** (avatar, name, "En ligne") + bell button.
- `discord-ios-4`: **Server** = rail + channel list with a server banner/header card (name, verified badge,
  "1 062 membres · Communauté"), "Rechercher" pill + invite + events buttons, categories "Discussion ⌄",
  channels, voice channel with its members, and a floating bottom bar "Rejoindre le salon vocal".
- `discord-ios-1`: **Chat** = back chevron, "# général ›" with "En ligne - 125" under it, messages
  (avatar, name colored by role, "Aujourd'hui à 14:11"), floating composer "Envoyer un message dans #…"
  with gift / emoji / mic, emoji picker sheet (Émoji / GIF / Autocollants tabs, search).
These replace the 3-tab design in the section above where they differ: follow the screenshots.

**Liquid Glass (iPhone only — desktop must not change):** use iOS 26 Liquid Glass for every floating
control: bottom user pill / navigation, composer, header icon buttons, "Rejoindre le salon vocal" bar,
menus and sheets. SwiftUI: `.glassEffect(.regular, in: .capsule)` (or `.rect(cornerRadius:)`),
`GlassEffectContainer` to group neighbors, `.buttonStyle(.glass)` / `.glassProminent` for primary actions,
`.tabBarMinimizeBehavior` if you use a TabView. Deployment target is iOS 17: wrap in
`if #available(iOS 26.0, *)` and fall back to `.ultraThinMaterial` + hairline border below 26.
Content (lists, messages) stays on Discord's dark opaque backgrounds; glass is only for controls that float
above content. No glows, no gradients behind glass.
