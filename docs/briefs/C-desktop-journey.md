# Brief C — Desktop Discord journey, remaining gaps (Claude)

Branch: `refactor/structure`. Owner: Claude. Integrates A and B when they land.

Done so far (see git log): real create/join server, add friend, attachments, reactions, edit, delete,
replies, pins, avatars, unread divider, jump to present, members + roles, Friends tabs, status,
profile card, server settings, channel create/edit/delete, invites, welcome screens, disk cache.

Remaining, in order:
1. Quick switcher (Cmd+K) on real servers/channels/DMs, arrow keys + Enter + Esc.
2. Header search → `POST /search` with a results panel (jump to message).
3. Inbox (title-bar tray): mentions via `GET /notifications`.
4. Threads: real `m.thread` relations (panel + reply), header threads list.
5. Explore servers: `fetchPublicRooms` + join.
6. System messages (joins, renames) and markdown links/code blocks.
7. Hide what Matrix cannot do yet (calls/voice are simulated: hide them in real sessions).
8. Recover the two unpushed Codex commits on the Studio (`f9314c1`, `0527e06`: unread indicators,
   reduce-motion, SVG icons) and merge what still applies.
