# Track F — Automatic Mood sessions

Implemented on `codex/app-provisioning`, locally only. No online account was created.

## Behavior

- Email/Discord sign-in and restored Mood sessions call `matrix-session` with a valid Supabase bearer and a persistent `MOOD` + 12 hexadecimal character device ID.
- The response supplies the homeserver and credentials. A separate `whoami` check validates the user before replacing local credentials, restoring the cache and starting sync/outbox delivery.
- The normal flow shows “Connexion à Mood…” and a retry/sign-out screen on failure. HTTP 401, 503 and 500 have safe French messages; server error details are never displayed.
- Manual Matrix login is available under Settings → My account → Advanced. It changes the active local session without rewriting the provisioned profile mapping; the next Mood sign-in restores the managed account.
- Signup supplies `email_redirect_to` and the Supabase Auth `redirect_to` query parameter. `mood://auth-callback` handles implicit email confirmation tokens, verifies the user and resumes provisioning. A confirmation link without tokens tells the user to sign in with email/password. Discord retains its existing PKCE browser flow.
- Device IDs are not secrets. Credentials continue to use the existing Keychain path. Unsigned Catalyst persistence retains the existing Keychain entitlement limitation.

## Validation

Commands (run from this checkout with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`):

```sh
xcodebuild -project mood.xcodeproj -scheme mood -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
xcodebuild -project mood.xcodeproj -scheme mood -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project mood.xcodeproj -scheme mood -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:moodTests
```

Verified: Mac Catalyst and iPhone simulator builds reported `** BUILD SUCCEEDED **`; the unit-test run reported `** TEST SUCCEEDED **`, 32 passing test cases including all five provisioning tests.

Local build logs are under `build/provisioning-*.log` (ignored by git).
Swift Testing covers contract decoding, invalid responses, French error mapping, stable device generation and a synthetic URLProtocol response from the function. The simulated request uses an ephemeral URLSession and in-memory fake credentials; it creates no account and persists no test token.

## Remaining integration check

A real signup → confirmation → Friends flow depends on tracks D/E being deployed, a supplied test email and Supabase redirect allowlisting for `mood://auth-callback`. No test email was provided, so no real account or authenticated screenshot was created. Store real-flow screenshots in `docs/screenshots/provisioning/` after checking that they contain no credentials. Do not infer real service availability from the simulated tests.
