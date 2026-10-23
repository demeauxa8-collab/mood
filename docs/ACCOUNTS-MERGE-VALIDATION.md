# Account integration validation — 9 October 2026

Branch: `codex/accounts-supabase`. Merge commit: `d9162be`.
Integrated `origin/refactor/structure` at `c04806b`; no push or PR.

## Merge

The only conflict was in `moodTests/moodTests.swift`. Both account test suites and the incoming search suite were retained as separate structures.
Supabase/Discord files remain intact. The incoming quick switcher, public directory, message search, inbox and existing disk cache are retained. `MatrixStore` merged automatically; its account-facing methods and new search/directory/inbox sections compile together.

## Checks

Commands use the AGENTS.md destinations and `build/DerivedData`, with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

- Mac Catalyst: `** BUILD SUCCEEDED **` (`build/validation/mac.log`).
- iPhone 18 Pro simulator: `** BUILD SUCCEEDED **` (`build/validation/iphone.log`).
- `moodTests`: `** TEST SUCCEEDED **`, 27 passed, no failures (`build/validation/tests.log`). Includes all account, PKCE, configuration, cache and search tests.
- `git diff --check`: clean; the incoming branch tip is an ancestor of the merge commit.

## Login verification

Reviewed the unchanged login actions, session restoration and RootView routing: without Supabase configuration, the Matrix password/SSO actions remain available and the Discord button is hidden. With configuration, Discord/email actions use AccountStore and authenticated Mood users are routed to Matrix linking when required. Matrix direct login remains accessible.

The dedicated `Mood B accounts verification` simulator was used for the following screenshots. Each image was opened and visually inspected:

- [Matrix login without Supabase](../screenshots/merge-accounts/iphone-matrix.png).
- [Discord/email login with fixture configuration](../screenshots/merge-accounts/iphone-discord.png).
- [Merged demo home](../screenshots/merge-accounts/iphone-preview.png).

The configured screenshot uses a copy under `build/validation/ConfiguredMood.app` with a fictitious HTTPS URL and public key in its Info.plist. No credentials were submitted and this does not validate live authentication. The normal compiled application was reinstalled afterward and launched with `-uiPreview`. No source configuration or installed Mac application was modified.

## Still requires live verification

Real Matrix password/SSO login was not attempted without a test account. Real Supabase email confirmation, Discord OAuth callback/token exchange, profile persistence, Matrix linking and guild import require a configured Supabase project, the supplied SQL migration applied by its administrator, the Discord provider and test credentials. No migration or provider configuration was performed here.

The pre-existing untracked `docs/HANDOFF-latest.md` was read and left unchanged.
