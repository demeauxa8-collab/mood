# Brief B — Mood accounts with Supabase + "Se connecter avec Discord" (Codex)

Branch: `codex/accounts-supabase` (from `refactor/structure`). Read `AGENTS.md` first.

## Decision (from Augustin)

Mood gets a real account system on **Supabase Auth**, with **Discord as a login provider** to sync
the user's Discord identity. **Matrix stays the messaging layer** — do not replace or wrap Matrix.
A Mood account (Supabase) owns a profile that is linked to the user's Matrix account.

Supabase project: `mood` (ref `jxpgyblzymshyzbkgmat`, region eu-west-3).
Zero external dependency rule still holds: **no supabase-swift SDK** — call the Auth REST API (GoTrue)
with `URLSession`, like `MatrixClient` does.

## Scope

### 1. Config
- `Config.xcconfig` (gitignored) + `Config.example.xcconfig` (committed) with `SUPABASE_URL` and
  `SUPABASE_ANON_KEY`; expose them through Info.plist keys (`MoodSupabaseURL`, `MoodSupabaseAnonKey`).
  Never hard-code them. Add `Config.xcconfig` to `.gitignore`.

### 2. `mood/Core/Account/`
- `SupabaseAuthClient` (URLSession, async/await):
  - `signUp(email:password:)` → `POST /auth/v1/signup`
  - `signIn(email:password:)` → `POST /auth/v1/token?grant_type=password`
  - `refresh(refreshToken:)` → `POST /auth/v1/token?grant_type=refresh_token`
  - `signOut()` → `POST /auth/v1/logout`
  - **Discord OAuth with PKCE**: build `GET /auth/v1/authorize?provider=discord&redirect_to=mood://auth-callback`
    `&code_challenge=…&code_challenge_method=s256&scopes=identify%20email%20guilds`, open it with
    `ASWebAuthenticationSession` (callback scheme `mood`), then exchange the `code` with
    `POST /auth/v1/token?grant_type=pkce` (`auth_code`, `code_verifier`).
  - Keep `access_token`, `refresh_token`, `expires_at` in the Keychain (`KeychainHelper`), refresh before expiry.
- `AccountStore` (`@Observable @MainActor`): current Supabase user, profile, `isSignedIn`, sign-in/out flows,
  restore on launch. Injected in the environment next to `MatrixStore` (see `App/MoodApp.swift`).
- `DiscordSync`: with the `provider_token` returned after Discord login, call Discord's API
  `GET https://discord.com/api/users/@me` (username, global_name, avatar, banner, accent_color) and
  `GET https://discord.com/api/users/@me/guilds` (id, name, icon). Discord does **not** give the friends list
  or messages to normal OAuth apps — do not try.

### 3. Database (SQL migration file only — do not run it)
`supabase/migrations/20261007000000_profiles.sql`:
- `public.profiles` (`id uuid primary key references auth.users on delete cascade`, `display_name text`,
  `avatar_url text`, `matrix_user_id text unique`, `matrix_homeserver text`, `discord_id text unique`,
  `discord_username text`, `discord_avatar_url text`, `created_at`, `updated_at`).
- RLS on; policies: a user can select/insert/update only `id = auth.uid()`.
- Trigger creating the profile row on `auth.users` insert, filling Discord fields from `raw_user_meta_data`.
- `public.discord_guilds_import` (`user_id`, `guild_id`, `name`, `icon_url`, `imported_space_id`), same RLS.

### 4. UI (Discord's own login screen is the reference)
- Login screen (`mood/Features/Auth/AuthViews.swift`): primary **"Se connecter avec Discord"** button
  (Discord blurple `#5865F2`, Discord logo), email + password for a Mood account, "Créer un compte".
  The existing Matrix login moves behind "Se connecter avec un compte Matrix" (keep it working).
  Remove the fake "Apple"/"Google" buttons unless they really work.
- After the Mood account login, if no Matrix account is linked: a screen "Relie ton compte Matrix"
  (homeserver + username/password, reusing `matrixStore.login`), then store `matrix_user_id` /
  `matrix_homeserver` in `profiles` via PostgREST (`PATCH /rest/v1/profiles?id=eq.<uid>`, bearer = access token).
- Settings › Mon compte: shows the Mood email, linked Discord (avatar + name, "Synchroniser" button,
  "Délier"), linked Matrix id.
- "Importer mes serveurs Discord" (from Settings and once after the first Discord login): list the guilds with
  icons and checkboxes; importing creates a Mood server per guild with `matrixStore.createServer(name:isPublic:)`
  (+ icon via `updateServerIcon`) and records it in `discord_guilds_import`. It copies name + icon only.
- Discord avatar/name can be applied to the Matrix profile ("Utiliser mon profil Discord"):
  `matrixStore.updateDisplayName` + `updateAvatar`.

## Out of scope (do not do)
- Running migrations or changing the live Supabase project. Configuring the Discord provider in the dashboard
  (Augustin does it: Discord Developer Portal app + client id/secret in Supabase › Auth › Providers).
- Our own Synapse / OIDC bridge (later).

## Done when
- Mac Catalyst and iPhone simulator builds `** BUILD SUCCEEDED **`; `moodTests` pass, with new tests for
  PKCE generation (verifier/challenge per RFC 7636 test vector), URL building, token-expiry logic.
- The app still logs into Matrix exactly as before when Supabase is not configured (no crash, Discord button hidden).
- Short `docs/ACCOUNTS.md`: setup steps for Augustin (Discord app, redirect URL
  `https://jxpgyblzymshyzbkgmat.supabase.co/auth/v1/callback`, Supabase provider settings, `mood://auth-callback`
  in Supabase › Auth › URL configuration, filling `Config.xcconfig`).
- Commits on `codex/accounts-supabase`. Do not push to `main`.
