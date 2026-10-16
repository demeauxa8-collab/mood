// End-to-end flow of the handler against an in-memory Supabase + Continuwuity double.
// deno test supabase/functions/matrix-session/
import { createHandler, type Deps } from "./handler.ts";
import { deriveMatrixPassword } from "./lib.ts";
import { assert, assertEquals, assertExcludes, assertIncludes } from "./testing.ts";

const SUPABASE = "https://proj.supabase.co";
const HS = "https://hs.test:8443";
const PEPPER = "mood-test-pepper-0123456789abcdef";
const REG_TOKEN = "registration-token-for-tests";
const USER_TOKEN = "user-session-jwt-for-tests";
const USER = {
  id: "1a2b3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d",
  email: "augustin@example.com",
  user_metadata: { full_name: "Augustin D" },
};
const LOCALPART = "m1a2b3c4d5e6f";
const MXID = `@${LOCALPART}:mood.local`;

const LEGACY_ENV: Record<string, string | undefined> = {
  SUPABASE_URL: SUPABASE,
  SUPABASE_ANON_KEY: "eyJ.anon.legacy",
  SUPABASE_SERVICE_ROLE_KEY: "eyJ.service.legacy",
  MATRIX_HOMESERVER_URL: HS + "/",
  MATRIX_REGISTRATION_TOKEN: REG_TOKEN,
  MATRIX_PASSWORD_PEPPER: PEPPER,
};

type Call = { method: string; url: string; headers: Record<string, string>; body: unknown };

/** Just enough of Supabase Auth, PostgREST and Continuwuity's client API for this function. */
class FakeBackend {
  calls: Call[] = [];
  users = new Map<string, string>(); // localpart → password
  devices = new Map<string, Map<string, string>>(); // localpart → device_id → access token
  displayNames = new Map<string, string>();
  uiaaSessions = new Set<string>();
  profile: Record<string, unknown> | null = { display_name: "Augustin", matrix_user_id: null, matrix_homeserver: null };
  profileWrites: Record<string, unknown>[] = [];
  homeserver: "up" | "down" | "proxy_502" | "hang" = "up";
  auth: "up" | "down" = "up";
  registrationToken = REG_TOKEN;
  displayNameStatus = 200;
  profileWriteStatus = 201;
  issuedTokens: string[] = [];
  afterFirstLogin?: () => void;
  private loginCount = 0;
  private counter = 0;

  constructor(readonly publishableKey = "eyJ.anon.legacy", readonly secretKey = "eyJ.service.legacy") {}

  fetch = async (url: string, init: RequestInit): Promise<Response> => {
    const method = init.method ?? "GET";
    const headers = Object.fromEntries(new Headers(init.headers).entries());
    const body = typeof init.body === "string" ? JSON.parse(init.body) : undefined;
    this.calls.push({ method, url, headers, body });
    if (url.startsWith(SUPABASE)) {
      if (this.auth === "down") throw new TypeError("error sending request");
      return this.supabase(method, new URL(url), headers, body);
    }
    if (url.startsWith(HS)) {
      if (this.homeserver === "down") throw new TypeError("error sending request: Connection refused");
      if (this.homeserver === "proxy_502") return new Response("<html>502 Bad Gateway</html>", { status: 502 });
      if (this.homeserver === "hang") {
        return await new Promise<Response>((_resolve, reject) =>
          init.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")))
        );
      }
      return this.matrix(method, new URL(url).pathname, headers, body);
    }
    throw new Error(`unexpected URL ${url}`);
  };

  callsTo(path: string): Call[] {
    return this.calls.filter((c) => new URL(c.url).pathname === path);
  }

  private supabase(method: string, url: URL, headers: Record<string, string>, body: unknown): Response {
    if (method === "GET" && url.pathname === "/auth/v1/user") {
      if (headers.apikey !== this.publishableKey) return reply(401, { message: "Invalid API key" });
      if (headers.authorization !== `Bearer ${USER_TOKEN}`) return reply(403, { code: 403, error_code: "bad_jwt" });
      return reply(200, USER);
    }
    if (url.pathname === "/rest/v1/profiles") {
      if (headers.apikey !== this.secretKey) return reply(401, { message: "Invalid API key" });
      if (method === "GET") {
        assertEquals(url.searchParams.get("id"), `eq.${USER.id}`);
        return reply(200, this.profile ? [this.profile] : []);
      }
      if (method === "POST") {
        assertEquals(url.searchParams.get("on_conflict"), "id");
        assertIncludes(headers.prefer ?? "", "resolution=merge-duplicates");
        const row = body as Record<string, unknown>;
        this.profileWrites.push(row);
        if (this.profileWriteStatus >= 300) return reply(this.profileWriteStatus, { code: "23505" });
        const { id: _id, ...fields } = row;
        this.profile = { ...(this.profile ?? { display_name: null }), ...fields };
        return new Response(null, { status: this.profileWriteStatus });
      }
    }
    return reply(404, { message: "not found" });
  }

  private matrix(method: string, path: string, headers: Record<string, string>, body: unknown): Response {
    const b = (body ?? {}) as Record<string, unknown>;
    if (method === "POST" && path === "/_matrix/client/v3/login") {
      const localpart = String((b.identifier as Record<string, unknown>).user);
      const ok = this.users.has(localpart) && this.users.get(localpart) === b.password;
      const response = ok
        ? reply(200, this.openDevice(localpart, String(b.device_id)))
        : reply(403, { errcode: "M_FORBIDDEN", error: "Wrong username or password." });
      if (++this.loginCount === 1) this.afterFirstLogin?.();
      return response;
    }
    if (method === "POST" && path === "/_matrix/client/v3/register") {
      const localpart = String(b.username);
      if (this.users.has(localpart)) {
        return reply(400, { errcode: "M_USER_IN_USE", error: "Desired user ID is already taken." });
      }
      const flows = [{ stages: ["m.login.registration_token"] }];
      const auth = b.auth as Record<string, unknown> | undefined;
      if (!auth) {
        const session = `uiaa${++this.counter}`;
        this.uiaaSessions.add(session);
        return reply(401, { session, flows, params: {} });
      }
      if (!this.uiaaSessions.has(String(auth.session))) {
        return reply(403, { errcode: "M_FORBIDDEN", error: "UIAA session does not exist." });
      }
      if (auth.type !== "m.login.registration_token" || auth.token !== this.registrationToken) {
        return reply(401, {
          session: auth.session,
          flows,
          params: {},
          completed: [],
          errcode: "M_FORBIDDEN",
          error: "Invalid registration token.",
        });
      }
      this.users.set(localpart, String(b.password));
      this.displayNames.set(localpart, `${localpart} 🏳️‍⚧️`); // Continuwuity's default suffix
      return reply(200, this.openDevice(localpart, String(b.device_id)));
    }
    const displayName = /^\/_matrix\/client\/v3\/profile\/([^/]+)\/displayname$/.exec(path);
    if (method === "PUT" && displayName) {
      const userId = decodeURIComponent(displayName[1]);
      const localpart = userId.slice(1, userId.indexOf(":"));
      const token = headers.authorization?.replace("Bearer ", "");
      const valid = [...(this.devices.get(localpart)?.values() ?? [])].includes(token ?? "");
      if (!valid) return reply(401, { errcode: "M_UNKNOWN_TOKEN" });
      if (this.displayNameStatus !== 200) return reply(this.displayNameStatus, { errcode: "M_UNKNOWN" });
      this.displayNames.set(localpart, String(b.displayname));
      return reply(200, {});
    }
    return reply(404, { errcode: "M_UNRECOGNIZED" });
  }

  /** Same device_id → same Matrix device with a fresh token, as Continuwuity does. */
  private openDevice(localpart: string, deviceId: string) {
    const token = `syt_${localpart}_${++this.counter}`;
    this.issuedTokens.push(token);
    const devices = this.devices.get(localpart) ?? new Map<string, string>();
    devices.set(deviceId, token);
    this.devices.set(localpart, devices);
    return { user_id: `@${localpart}:mood.local`, access_token: token, device_id: deviceId, home_server: "mood.local" };
  }
}

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function setup(options: { env?: Record<string, string | undefined>; backend?: FakeBackend; deps?: Partial<Deps> } = {}) {
  const backend = options.backend ?? new FakeBackend();
  const logs: Record<string, unknown>[] = [];
  const env = { ...LEGACY_ENV, ...options.env };
  const handler = createHandler((name) => env[name], {
    fetch: backend.fetch,
    log: (entry) => logs.push(entry),
    ...options.deps,
  });
  return { backend, logs, handler };
}

function sessionRequest(
  options: { body?: unknown; token?: string | null; deviceId?: string; method?: string } = {},
): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json", apikey: "eyJ.anon.legacy" };
  const token = options.token === undefined ? USER_TOKEN : options.token;
  if (token) headers.Authorization = `Bearer ${token}`;
  const body = options.body ?? { device_id: options.deviceId ?? "MOODMAC1A2B3C4D", device_name: "Mood · Mac" };
  return new Request("http://localhost/functions/v1/matrix-session", {
    method: options.method ?? "POST",
    headers,
    body: options.method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function invoke(handler: (req: Request) => Promise<Response>, req: Request) {
  const response = await handler(req);
  const text = await response.text();
  return { status: response.status, headers: response.headers, text, body: text ? JSON.parse(text) : null };
}

/** Logs and error bodies must never contain a credential. */
async function assertNoSecrets(logs: unknown[], extra: string[] = [], backend?: FakeBackend) {
  const output = JSON.stringify(logs);
  const password = await deriveMatrixPassword(PEPPER, USER.id);
  for (const secret of [PEPPER, REG_TOKEN, USER_TOKEN, password, ...(backend?.issuedTokens ?? []), ...extra]) {
    assertExcludes(output, secret, "a secret leaked into the logs");
  }
}

// --- happy paths --------------------------------------------------------------------------------

Deno.test("first call registers through UIAA, names the account and links the profile", async () => {
  const { backend, logs, handler } = setup();
  const res = await invoke(handler, sessionRequest());

  assertEquals(res.status, 200);
  assertEquals(res.body, {
    homeserver: HS,
    user_id: MXID,
    access_token: backend.issuedTokens[0],
    device_id: "MOODMAC1A2B3C4D",
    created: true,
  });
  assertEquals(res.headers.get("cache-control"), "no-store");

  assertEquals(backend.users.get(LOCALPART), await deriveMatrixPassword(PEPPER, USER.id));
  const registers = backend.callsTo("/_matrix/client/v3/register");
  assertEquals(registers.length, 2);
  assert(!("auth" in (registers[0].body as object)), "first UIAA round must not carry auth");
  assertEquals((registers[1].body as Record<string, unknown>).auth, {
    type: "m.login.registration_token",
    token: REG_TOKEN,
    session: "uiaa1",
  });
  assertEquals(backend.displayNames.get(LOCALPART), "Augustin"); // profiles.display_name wins
  assertEquals(backend.profileWrites, [{ id: USER.id, matrix_user_id: MXID, matrix_homeserver: HS }]);
  const write = backend.calls.find((c) => c.method === "POST" && c.url.includes("/rest/v1/profiles"));
  assertEquals(write?.headers.authorization, "Bearer eyJ.service.legacy"); // legacy JWT on both headers
  assertEquals(logs.at(-1)?.outcome, "ok");
  assertEquals(logs.at(-1)?.path, "register");
  await assertNoSecrets(logs, [], backend);
});

Deno.test("later calls log in on the same Matrix device without registering again", async () => {
  const { backend, logs, handler } = setup();
  const first = await invoke(handler, sessionRequest());
  const callsAfterFirst = backend.calls.length;
  const second = await invoke(handler, sessionRequest());

  assertEquals(second.status, 200);
  assertEquals(second.body.created, false);
  assertEquals(second.body.user_id, first.body.user_id);
  assertEquals(second.body.device_id, "MOODMAC1A2B3C4D");
  assert(second.body.access_token !== first.body.access_token, "a fresh token is issued for the device");
  assertEquals(backend.devices.get(LOCALPART)?.size, 1);

  const secondCalls = backend.calls.slice(callsAfterFirst).map((c) => `${c.method} ${new URL(c.url).pathname}`);
  assertEquals(secondCalls.sort(), [
    "GET /auth/v1/user",
    "GET /rest/v1/profiles",
    "POST /_matrix/client/v3/login",
  ]); // no register, no display name, no profile write: already linked
  await assertNoSecrets(logs, [], backend);
});

Deno.test("an existing account whose profile was never linked gets linked and named", async () => {
  const backend = new FakeBackend();
  backend.users.set(LOCALPART, await deriveMatrixPassword(PEPPER, USER.id));
  backend.profile = { display_name: null, matrix_user_id: null, matrix_homeserver: null };
  const { handler } = setup({ backend });
  const res = await invoke(handler, sessionRequest());

  assertEquals(res.status, 200);
  assertEquals(res.body.created, false);
  assertEquals(backend.displayNames.get(LOCALPART), "augustin"); // e-mail local part
  assertEquals(backend.profileWrites.length, 1);
});

Deno.test("concurrent first calls from two devices: one registers, the other logs in", async () => {
  const { backend, logs, handler } = setup();
  const [mac, phone] = await Promise.all([
    invoke(handler, sessionRequest({ deviceId: "MOODMACAAAAAAAA" })),
    invoke(handler, sessionRequest({ deviceId: "MOODIPHONEBBBBB" })),
  ]);

  assertEquals([mac.status, phone.status], [200, 200]);
  assertEquals([mac.body.created, phone.body.created].sort(), [false, true]);
  assertEquals(mac.body.user_id, phone.body.user_id);
  assertEquals(backend.users.size, 1);
  assertEquals([...(backend.devices.get(LOCALPART)?.keys() ?? [])].sort(), ["MOODIPHONEBBBBB", "MOODMACAAAAAAAA"]);
  await assertNoSecrets(logs, [], backend);
});

Deno.test("register answering M_USER_IN_USE falls back to login", async () => {
  const backend = new FakeBackend();
  const password = await deriveMatrixPassword(PEPPER, USER.id);
  // Another call registers the account right after our first login was refused.
  backend.afterFirstLogin = () => backend.users.set(LOCALPART, password);
  const { logs, handler } = setup({ backend });
  const res = await invoke(handler, sessionRequest());

  assertEquals(res.status, 200);
  assertEquals(res.body.created, false);
  assertEquals(backend.callsTo("/_matrix/client/v3/login").length, 2);
  assertEquals(backend.callsTo("/_matrix/client/v3/register").length, 1);
  assertEquals(logs.at(-1)?.path, "login_after_user_in_use");
});

Deno.test("new sb_ API keys are read from the JSON env and sent on apikey only", async () => {
  const backend = new FakeBackend("sb_publishable_test", "sb_secret_test");
  const { handler } = setup({
    backend,
    env: {
      SUPABASE_PUBLISHABLE_KEYS: '{"default":"sb_publishable_test"}',
      SUPABASE_SECRET_KEYS: '{"default":"sb_secret_test"}',
    },
  });
  const res = await invoke(handler, sessionRequest());

  assertEquals(res.status, 200);
  const rest = backend.calls.filter((c) => c.url.includes("/rest/v1/"));
  assertEquals(rest.length, 2);
  for (const call of rest) {
    assertEquals(call.headers.apikey, "sb_secret_test");
    assertEquals(call.headers.authorization, undefined);
  }
});

Deno.test("display-name and profile-write failures do not fail the session", async () => {
  const backend = new FakeBackend();
  backend.displayNameStatus = 500;
  backend.profileWriteStatus = 409;
  const { logs, handler } = setup({ backend });
  const res = await invoke(handler, sessionRequest());

  assertEquals(res.status, 200);
  assertEquals(res.body.created, true);
  const steps = logs.filter((l) => l.event === "matrix_session_step").map((l) => [l.step, l.ok]);
  assertEquals(steps, [["displayname", false], ["profile_link", false]]);
  await assertNoSecrets(logs, [], backend);
});

// --- 401 ----------------------------------------------------------------------------------------

Deno.test("no bearer token → 401 not_authenticated, nothing called", async () => {
  const { backend, handler } = setup();
  const res = await invoke(handler, sessionRequest({ token: null }));
  assertEquals(res.status, 401);
  assertEquals(res.body, { error: "not_authenticated" });
  assertEquals(backend.calls.length, 0);
});

Deno.test("invalid or expired Supabase token → 401, homeserver never contacted", async () => {
  const { backend, logs, handler } = setup();
  const res = await invoke(handler, sessionRequest({ token: "expired-or-forged" }));
  assertEquals(res.status, 401);
  assertEquals(res.body, { error: "not_authenticated" });
  assertEquals(backend.calls.map((c) => new URL(c.url).pathname), ["/auth/v1/user"]);
  await assertNoSecrets(logs, ["expired-or-forged"]);
});

Deno.test("Supabase Auth unreachable → 500, not 401 (the app must not sign the user out)", async () => {
  const backend = new FakeBackend();
  backend.auth = "down";
  const { handler } = setup({ backend });
  const res = await invoke(handler, sessionRequest());
  assertEquals(res.status, 500);
  assertEquals(res.body, { error: "provisioning_failed", detail: "supabase_auth_unreachable (network)" });
});

// --- 503 ----------------------------------------------------------------------------------------

for (
  const [label, mode] of [
    ["connection refused", "down"],
    ["Tailscale Funnel 502", "proxy_502"],
    ["8 s timeout", "hang"],
  ] as const
) {
  Deno.test(`homeserver ${label} → 503 homeserver_unreachable`, async () => {
    const backend = new FakeBackend();
    backend.homeserver = mode;
    const { logs, handler } = setup({ backend, deps: { requestTimeoutMs: 20 } });
    const res = await invoke(handler, sessionRequest());
    assertEquals(res.status, 503);
    assertEquals(res.body, { error: "homeserver_unreachable" });
    assertEquals(logs.at(-1)?.outcome, "homeserver_unreachable");
    assertEquals(logs.at(-1)?.stage, "login");
    if (mode === "hang") assertEquals(logs.at(-1)?.reason, "timeout");
  });
}

// --- 500 ----------------------------------------------------------------------------------------

Deno.test("a rejected registration token → 500 with a detail that does not quote the token", async () => {
  const backend = new FakeBackend();
  backend.registrationToken = "the-server-has-another-token";
  const { logs, handler } = setup({ backend });
  const res = await invoke(handler, sessionRequest());

  assertEquals(res.status, 500);
  assertEquals(res.body, {
    error: "provisioning_failed",
    detail: "matrix_register_failed: registration_token_rejected: M_FORBIDDEN",
  });
  assertEquals(backend.callsTo("/_matrix/client/v3/register").length, 2); // no retry loop
  assertExcludes(res.text, REG_TOKEN);
  await assertNoSecrets(logs, [], backend);
});

Deno.test("an existing Matrix account refusing the derived password → matrix_credentials_rejected", async () => {
  const backend = new FakeBackend();
  backend.users.set(LOCALPART, "password-from-an-older-pepper");
  const { logs, handler } = setup({ backend });
  const res = await invoke(handler, sessionRequest());

  assertEquals(res.status, 500);
  assertEquals(res.body, { error: "provisioning_failed", detail: "matrix_credentials_rejected" });
  const sequence = backend.calls
    .filter((c) => c.url.startsWith(HS))
    .map((c) => new URL(c.url).pathname.replace("/_matrix/client/v3/", ""));
  assertEquals(sequence, ["login", "register", "login"]);
  await assertNoSecrets(logs, [], backend);
});

Deno.test("missing secrets → 500 naming the variables only, nothing called", async () => {
  const { backend, handler } = setup({
    env: { MATRIX_REGISTRATION_TOKEN: undefined, MATRIX_PASSWORD_PEPPER: "too-short" },
  });
  const res = await invoke(handler, sessionRequest());
  assertEquals(res.status, 500);
  assertEquals(res.body, {
    error: "provisioning_failed",
    detail: "missing_config: MATRIX_REGISTRATION_TOKEN, MATRIX_PASSWORD_PEPPER (min 32 chars)",
  });
  assertExcludes(res.text, "too-short");
  assertEquals(backend.calls.length, 0);
});

// --- outside the contract -----------------------------------------------------------------------

Deno.test("malformed body → 400 invalid_request before any network call", async () => {
  const { backend, handler } = setup();
  for (const body of ["not json", { device_name: "Mood · Mac" }, { device_id: "bad id" }, "[]"]) {
    const res = await invoke(handler, sessionRequest({ body }));
    assertEquals(res.status, 400);
    assertEquals(res.body.error, "invalid_request");
  }
  assertEquals(backend.calls.length, 0);
});

Deno.test("OPTIONS → 204 with CORS headers, GET → 405", async () => {
  const { handler } = setup();
  const preflight = await handler(new Request("http://localhost/functions/v1/matrix-session", { method: "OPTIONS" }));
  assertEquals(preflight.status, 204);
  assertIncludes(preflight.headers.get("access-control-allow-headers") ?? "", "authorization");
  const get = await invoke(handler, sessionRequest({ method: "GET" }));
  assertEquals(get.status, 405);
  assertEquals(get.body, { error: "method_not_allowed" });
});
