// deno test supabase/functions/matrix-session/
import {
  apiKeyHeaders,
  base64UrlEncode,
  bearerToken,
  classifyLogin,
  classifyRegister,
  type Credentials,
  DEFAULT_DEVICE_NAME,
  deriveMatrixPassword,
  displayNameFor,
  errorResponseParts,
  isUnreachableStatus,
  loginBody,
  matrixFailureDetail,
  matrixLocalpart,
  nextUiaaStep,
  normalizeBaseUrl,
  normalizeUserId,
  parseSessionRequest,
  registerBody,
  resolveApiKey,
  successBody,
} from "./lib.ts";
import { assert, assertEquals } from "./testing.ts";

// Same id as the contract example (@m1a2b3c4d5e6f:mood.local).
const USER_ID = "1a2b3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d";

const CREDS: Credentials = {
  localpart: "m1a2b3c4d5e6f",
  password: "derived-password",
  deviceId: "MOODMAC1A2B3C4D",
  deviceName: "Mood · Mac",
};

// --- identity ---------------------------------------------------------------------------------

Deno.test("localpart is m + first 12 hex digits of the Supabase id", () => {
  assertEquals(matrixLocalpart(USER_ID), "m1a2b3c4d5e6f");
});

Deno.test("user id is canonicalised to lowercase and validated", () => {
  assertEquals(normalizeUserId("1A2B3C4D-5E6F-4A1B-8C2D-3E4F5A6B7C8D"), USER_ID);
  assertEquals(normalizeUserId(` ${USER_ID} `), USER_ID);
  assertEquals(normalizeUserId("not-a-uuid"), null);
  assertEquals(normalizeUserId("1a2b3c4d5e6f4a1b8c2d3e4f5a6b7c8d"), null);
  assertEquals(normalizeUserId(42), null);
  assertEquals(normalizeUserId(undefined), null);
});

// --- password derivation ------------------------------------------------------------------------

Deno.test("base64url uses the URL-safe alphabet without padding", () => {
  assertEquals(base64UrlEncode(new Uint8Array([0xfb, 0xff, 0xfe])), "-__-");
  assertEquals(base64UrlEncode(new Uint8Array([0x66])), "Zg");
  assertEquals(base64UrlEncode(new Uint8Array([0x66, 0x6f])), "Zm8");
  assertEquals(base64UrlEncode(new Uint8Array([])), "");
});

Deno.test("HMAC-SHA256 matches RFC 4231 test case 2", async () => {
  // HMAC-SHA256(key "Jefe", "what do ya want for nothing?") =
  // 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
  assertEquals(
    await deriveMatrixPassword("Jefe", "what do ya want for nothing?"),
    "W9zBRr9gdU5qBCQmCJV1x1oAPwidJzmDnexYuWTsOEM",
  );
});

Deno.test("derived Matrix password matches the fixed vector", async () => {
  // Computed independently with:
  // printf '%s' 1a2b3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d \
  //   | openssl dgst -sha256 -hmac mood-test-pepper-0123456789abcdef -binary | base64 | tr '+/' '-_' | tr -d '='
  const password = await deriveMatrixPassword("mood-test-pepper-0123456789abcdef", USER_ID);
  assertEquals(password, "AJAZWBFeoE3C0d2encAuMcPuwOei5Eh3l3g7nMo3rSk");
  assertEquals(password.length, 43);
  assert(/^[A-Za-z0-9_-]+$/.test(password), "password must be base64url");
});

Deno.test("derived password depends on both the pepper and the user id", async () => {
  const base = await deriveMatrixPassword("mood-test-pepper-0123456789abcdef", USER_ID);
  assert(base !== await deriveMatrixPassword("mood-test-pepper-0123456789abcdeF", USER_ID));
  assert(base !== await deriveMatrixPassword("mood-test-pepper-0123456789abcdef", USER_ID.replace("8d", "8e")));
});

// --- incoming request ---------------------------------------------------------------------------

Deno.test("bearer token is read from the Authorization header", () => {
  assertEquals(bearerToken("Bearer abc.def.ghi"), "abc.def.ghi");
  assertEquals(bearerToken("bearer abc"), "abc");
  assertEquals(bearerToken("Bearer "), null);
  assertEquals(bearerToken("Basic abc"), null);
  assertEquals(bearerToken(null), null);
});

Deno.test("session request requires a device_id and defaults the device name", () => {
  assertEquals(parseSessionRequest({ device_id: "MOODMAC1A2B3C4D", device_name: "Mood · Mac" }), {
    ok: true,
    value: { deviceId: "MOODMAC1A2B3C4D", deviceName: "Mood · Mac" },
  });
  assertEquals(parseSessionRequest({ device_id: "MOODIPHONE12345" }), {
    ok: true,
    value: { deviceId: "MOODIPHONE12345", deviceName: DEFAULT_DEVICE_NAME },
  });
  assertEquals(parseSessionRequest({ device_id: "MOOD1", device_name: "   " }).ok, true);
  assertEquals(parseSessionRequest({}).ok, false);
  assertEquals(parseSessionRequest({ device_id: "" }).ok, false);
  assertEquals(parseSessionRequest({ device_id: "has space" }).ok, false);
  assertEquals(parseSessionRequest({ device_id: "X".repeat(65) }).ok, false);
  assertEquals(parseSessionRequest({ device_id: 12 }).ok, false);
  assertEquals(parseSessionRequest([]).ok, false);
  assertEquals(parseSessionRequest(null).ok, false);
});

Deno.test("long device names are truncated, not rejected", () => {
  const parsed = parseSessionRequest({ device_id: "MOOD1", device_name: "é".repeat(300) });
  assert(parsed.ok);
  assertEquals(Array.from(parsed.value.deviceName).length, 100);
});

// --- configuration ------------------------------------------------------------------------------

Deno.test("API keys prefer the new JSON dictionaries, then the legacy variables", () => {
  assertEquals(resolveApiKey('{"default":"sb_secret_new"}', "legacy.jwt"), "sb_secret_new");
  assertEquals(resolveApiKey('{"backend":"sb_secret_other"}', undefined), "sb_secret_other");
  assertEquals(resolveApiKey("{}", "legacy.jwt"), "legacy.jwt");
  assertEquals(resolveApiKey("not json", "legacy.jwt"), "legacy.jwt");
  assertEquals(resolveApiKey(undefined, " legacy.jwt "), "legacy.jwt");
  assertEquals(resolveApiKey(undefined, undefined), null);
});

Deno.test("new sb_ keys travel on apikey only, legacy JWT keys on both headers", () => {
  assertEquals(apiKeyHeaders("sb_secret_abc"), { apikey: "sb_secret_abc" });
  assertEquals(apiKeyHeaders("eyJ.legacy"), { apikey: "eyJ.legacy", Authorization: "Bearer eyJ.legacy" });
});

Deno.test("base URLs are validated and lose their trailing slash", () => {
  assertEquals(
    normalizeBaseUrl("https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443/"),
    "https://mac-studio-de-charlesmacstudio.tail80a3cb.ts.net:8443",
  );
  assertEquals(normalizeBaseUrl("http://127.0.0.1:6167"), "http://127.0.0.1:6167");
  assertEquals(normalizeBaseUrl("  https://x.supabase.co  "), "https://x.supabase.co");
  assertEquals(normalizeBaseUrl("ftp://example.com"), null);
  assertEquals(normalizeBaseUrl("https://example.com/?a=1"), null);
  assertEquals(normalizeBaseUrl("mood.local"), null);
  assertEquals(normalizeBaseUrl(""), null);
  assertEquals(normalizeBaseUrl(undefined), null);
});

// --- Matrix request bodies ----------------------------------------------------------------------

Deno.test("login body uses m.login.password with an m.id.user identifier and the device id", () => {
  assertEquals(loginBody(CREDS), {
    type: "m.login.password",
    identifier: { type: "m.id.user", user: "m1a2b3c4d5e6f" },
    password: "derived-password",
    device_id: "MOODMAC1A2B3C4D",
    initial_device_display_name: "Mood · Mac",
  });
});

Deno.test("register body omits auth on the first UIAA round and carries it afterwards", () => {
  const first = registerBody(CREDS);
  assertEquals(first, {
    username: "m1a2b3c4d5e6f",
    password: "derived-password",
    device_id: "MOODMAC1A2B3C4D",
    initial_device_display_name: "Mood · Mac",
    inhibit_login: false,
  });
  assert(!("auth" in first));
  const auth = { type: "m.login.registration_token", token: "T", session: "S" };
  assertEquals(registerBody(CREDS, auth).auth, auth);
});

// --- UIAA ---------------------------------------------------------------------------------------

const TOKEN_CHALLENGE = { session: "sess1", flows: [{ stages: ["m.login.registration_token"] }], params: {} };

Deno.test("UIAA: registration-token flow sends the token with the session", () => {
  assertEquals(nextUiaaStep(TOKEN_CHALLENGE, "reg-token"), {
    kind: "auth",
    stage: "m.login.registration_token",
    auth: { type: "m.login.registration_token", token: "reg-token", session: "sess1" },
  });
});

Deno.test("UIAA: a rejected token stops instead of looping", () => {
  const rejected = { ...TOKEN_CHALLENGE, completed: [], errcode: "M_FORBIDDEN", error: "Invalid registration token." };
  assertEquals(nextUiaaStep(rejected, "reg-token", "m.login.registration_token"), {
    kind: "fail",
    detail: "registration_token_rejected: M_FORBIDDEN",
  });
});

Deno.test("UIAA: multi-stage flows continue with the next stage", () => {
  const challenge = {
    session: "s",
    flows: [{ stages: ["m.login.email.identity"] }, { stages: ["m.login.registration_token", "m.login.dummy"] }],
    completed: ["m.login.registration_token"],
  };
  assertEquals(nextUiaaStep(challenge, "reg-token", "m.login.registration_token"), {
    kind: "auth",
    stage: "m.login.dummy",
    auth: { type: "m.login.dummy", session: "s" },
  });
});

Deno.test("UIAA: open registration with a dummy stage is supported", () => {
  const step = nextUiaaStep({ session: "s", flows: [{ stages: ["m.login.dummy"] }] }, "reg-token");
  assertEquals(step, { kind: "auth", stage: "m.login.dummy", auth: { type: "m.login.dummy", session: "s" } });
});

Deno.test("UIAA: unsupported flows and malformed challenges fail with a detail", () => {
  assertEquals(nextUiaaStep({ session: "s", flows: [{ stages: ["m.login.recaptcha"] }] }, "t"), {
    kind: "fail",
    detail: "uiaa_unsupported_flows: m.login.recaptcha",
  });
  assertEquals(nextUiaaStep({ flows: TOKEN_CHALLENGE.flows }, "t"), { kind: "fail", detail: "uiaa_missing_session" });
  assertEquals(nextUiaaStep(null, "t"), { kind: "fail", detail: "uiaa_invalid_response" });
  assertEquals(nextUiaaStep({ session: "s" }, "t"), { kind: "fail", detail: "uiaa_unsupported_flows: none" });
});

// --- Matrix error mapping -----------------------------------------------------------------------

const SESSION_REPLY = { user_id: "@m1a2b3c4d5e6f:mood.local", access_token: "syt_x", device_id: "MOODMAC1A2B3C4D" };

Deno.test("login: 200 yields a session, falling back to the requested device id", () => {
  assertEquals(classifyLogin(200, SESSION_REPLY, "MOODMAC1A2B3C4D"), {
    kind: "ok",
    session: { userId: "@m1a2b3c4d5e6f:mood.local", accessToken: "syt_x", deviceId: "MOODMAC1A2B3C4D" },
  });
  const { device_id: _ignored, ...withoutDevice } = SESSION_REPLY;
  const outcome = classifyLogin(200, withoutDevice, "REQUESTED");
  assert(outcome.kind === "ok");
  assertEquals(outcome.session.deviceId, "REQUESTED");
  assertEquals(classifyLogin(200, { user_id: "@a:b" }, "D").kind, "fail");
});

Deno.test("login: M_FORBIDDEN / M_NOT_FOUND mean 'try to register'", () => {
  assertEquals(classifyLogin(403, { errcode: "M_FORBIDDEN", error: "Wrong username or password." }, "D").kind, "unknown_user");
  assertEquals(classifyLogin(404, { errcode: "M_NOT_FOUND" }, "D").kind, "unknown_user");
});

Deno.test("login: other errors become provisioning failures with errcode and status", () => {
  assertEquals(classifyLogin(403, { errcode: "M_USER_DEACTIVATED" }, "D"), {
    kind: "fail",
    detail: "matrix_login_failed: M_USER_DEACTIVATED (HTTP 403)",
  });
  assertEquals(classifyLogin(404, null, "D"), { kind: "fail", detail: "matrix_login_failed: no_errcode (HTTP 404)" });
  assertEquals(classifyLogin(429, { errcode: "M_LIMIT_EXCEEDED" }, "D").kind, "fail");
});

Deno.test("proxy errors 502/503/504 mean the homeserver is unreachable", () => {
  for (const status of [502, 503, 504]) {
    assert(isUnreachableStatus(status));
    assertEquals(classifyLogin(status, null, "D").kind, "unreachable");
    assertEquals(classifyRegister(status, null, "D").kind, "unreachable");
  }
  assert(!isUnreachableStatus(500));
  assertEquals(classifyLogin(500, { errcode: "M_UNKNOWN" }, "D").kind, "fail");
});

Deno.test("register: UIAA challenge, user in use, success, refusal", () => {
  assertEquals(classifyRegister(401, TOKEN_CHALLENGE, "D").kind, "uiaa");
  assertEquals(classifyRegister(400, { errcode: "M_USER_IN_USE", error: "Desired user ID is already taken." }, "D").kind, "user_in_use");
  assertEquals(classifyRegister(200, SESSION_REPLY, "D").kind, "ok");
  assertEquals(classifyRegister(403, { errcode: "M_FORBIDDEN", error: "Registration has been disabled." }, "D"), {
    kind: "fail",
    detail: "matrix_register_failed: M_FORBIDDEN (HTTP 403)",
  });
  assertEquals(classifyRegister(401, { errcode: "M_UNKNOWN_TOKEN" }, "D").kind, "fail");
});

Deno.test("failure details never quote the homeserver's free-text message", () => {
  const detail = matrixFailureDetail("matrix_login_failed", 400, { errcode: "M_BAD_JSON", error: "secret-ish text" });
  assertEquals(detail, "matrix_login_failed: M_BAD_JSON (HTTP 400)");
});

// --- display name -------------------------------------------------------------------------------

Deno.test("display name: profile, then e-mail local part, then Discord metadata", () => {
  assertEquals(displayNameFor("Augustin", { email: "a@b.c" }), "Augustin");
  assertEquals(displayNameFor(null, { email: "augustin.d@example.com" }), "augustin.d");
  assertEquals(displayNameFor("  ", { email: "x@y.z" }), "x");
  assertEquals(displayNameFor(null, { user_metadata: { global_name: "Gus", user_name: "gus42" } }), "Gus");
  assertEquals(displayNameFor(null, { user_metadata: { user_name: "gus42" } }), "gus42");
  assertEquals(displayNameFor(null, { email: "no-at-sign", user_metadata: null }), null);
  assertEquals(displayNameFor(null, {}), null);
  assertEquals(Array.from(displayNameFor("é".repeat(200), {}) ?? "").length, 64);
});

// --- contract responses -------------------------------------------------------------------------

Deno.test("success body has exactly the contract keys", () => {
  const body = successBody(
    "https://hs.example:8443",
    { userId: "@m1a2b3c4d5e6f:mood.local", accessToken: "syt_x", deviceId: "MOODMAC1A2B3C4D" },
    true,
  );
  assertEquals(Object.keys(body).sort(), ["access_token", "created", "device_id", "homeserver", "user_id"]);
  assertEquals(body, {
    homeserver: "https://hs.example:8443",
    user_id: "@m1a2b3c4d5e6f:mood.local",
    access_token: "syt_x",
    device_id: "MOODMAC1A2B3C4D",
    created: true,
  });
});

Deno.test("error bodies match the contract exactly", () => {
  assertEquals(errorResponseParts("not_authenticated", "ignored"), { status: 401, body: { error: "not_authenticated" } });
  assertEquals(errorResponseParts("homeserver_unreachable", "ignored"), {
    status: 503,
    body: { error: "homeserver_unreachable" },
  });
  assertEquals(errorResponseParts("provisioning_failed", "matrix_credentials_rejected"), {
    status: 500,
    body: { error: "provisioning_failed", detail: "matrix_credentials_rejected" },
  });
  assertEquals(errorResponseParts("provisioning_failed"), {
    status: 500,
    body: { error: "provisioning_failed", detail: "unknown" },
  });
  assertEquals(errorResponseParts("invalid_request", "device_id").status, 400);
  assertEquals(errorResponseParts("method_not_allowed"), { status: 405, body: { error: "method_not_allowed" } });
});
