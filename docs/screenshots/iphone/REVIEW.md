# iPhone visual review — 2026-10-09

Reference build: `2e6c795`, compiled in `/tmp/mood-avant`, launched with `-uiPreview -uiPreviewScreen server`. `accueil-avant.png` is an unedited simulator capture of that build. The old preview can change its selected server when its data loads; compare geometry and surfaces rather than the server name.

The home files were restored from that commit before applying the requested softer shapes. The restored opaque search field replaces the subsequent glass search field. The server banner has continuous upper corners; channel rows use 14 pt continuous corners; search fields and floating user controls use capsules. The 72 pt rail and list density are retained. DM and profile avatars use rounded squares. Notification cards and profile settings use 16 pt continuous corners. The chat composer and back control use capsule glass. Shared message rendering and its Matrix actions remain reused without changing desktop files.

All six PNG files were opened and inspected. Compared with the supplied Discord references: the server rail, banner/header, channel hierarchy, DM rows and bottom user pill retain their placement; chat is full width with a floating composer. Lists and cards remain opaque. No new gradients, glows or heavy shadows were introduced. Unsupported voice, gift and microphone controls were not added. The demo content and avatars differ from the Discord promotional illustrations.

Validation:
- Reference iPhone build: `** BUILD SUCCEEDED **`.
- Final iPhone simulator build: `** BUILD SUCCEEDED **` (`build/review/iphone.log`).
- Final Mac Catalyst build: `** BUILD SUCCEEDED **` (`build/review/catalyst.log`).
- `moodTests`: `** TEST SUCCEEDED **` (`build/review/tests.log`).
- Runtime screenshots use the dedicated Mood Mobile Review simulator, iOS 27.
- This pass validates demo rendering and unit tests; it does not establish a live Matrix end-to-end result.

Desktop source files are unchanged by this pass. No push or installation into `~/Applications` was performed. The temporary reference worktree was removed after capture.
