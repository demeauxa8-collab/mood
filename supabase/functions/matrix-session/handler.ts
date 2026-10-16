// Request handler of the `matrix-session` Edge Function (contract: docs/BACKEND-PLAN.md §2).
//
// Flow: verify the Supabase access token → derive Matrix credentials → login, or register via
// UIAA with the registration token on first use → set the display name of a new account →
// record matrix_user_id / matrix_homeserver in public.profiles → return the Matrix session.
//
// Every outgoing call goes through an injected `fetch`, so handler_test.ts can run the whole
// flow against a fake homeserver. Logs carry outcomes, stages, errcodes and the localpart only:
// never a token, a password, the pepper or a request body.

import {
  apiKeyHeaders,
  bearerToken,
  classifyLogin,
  classifyRegister,
  type Credentials,
  deriveMatrixPassword,
  displayNameFor,
  type ErrorKind,
  errorResponseParts,
  loginBody,
  MAX_REQUEST_BYTES,
  type MatrixSession,
  matrixLocalpart,
  MIN_PEPPER_LENGTH,
  nextUiaaStep,
  normalizeBaseUrl,
  normalizeUserId,
  parseSessionRequest,
  registerBody,
  resolveApiKey,
  successBody,
} from "./lib.ts";

export type Env = (name: string) => string | undefined;
export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export type Deps = {
  fetch: FetchLike;
  now: () => number;
  log: (entry: Record<string, unknown>) => void;
  /** Per outgoing request (brief: 8 s, then 503). */
  requestTimeoutMs: number;
  /** Whole request, so a slow-but-alive chain of calls still ends before the app gives up. */
  totalBudgetMs: number;
};

export const DEFAULT_DEPS: Deps = {
  fetch: (url, init) => fetch(url, init),
  now: () => Date.now(),
  log: (entry) => console.log(JSON.stringify(entry)),
  requestTimeoutMs: 8_000,
  totalBudgetMs: 25_000,
};

const MAX_UIAA_ROUNDS = 4;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------------------------

export type Config = {
  supabaseUrl: string;
  publishableKey: string;
  secretKey: string;
  homeserverUrl: string;
  registrationToken: string;
  pepper: string;
};

/** Reads the environment. Problems name the variables only, never their values. */
export function loadConfig(env: Env): { ok: true; config: Config } | { ok: false; problems: string[] } {
  const problems: string[] = [];
  const supabaseUrl = normalizeBaseUrl(env("SUPABASE_URL"));
  if (!supabaseUrl) problems.push("SUPABASE_URL");
  const publishableKey = resolveApiKey(env("SUPABASE_PUBLISHABLE_KEYS"), env("SUPABASE_ANON_KEY"));
  if (!publishableKey) problems.push("SUPABASE_ANON_KEY");
  const secretKey = resolveApiKey(env("SUPABASE_SECRET_KEYS"), env("SUPABASE_SERVICE_ROLE_KEY"));
  if (!secretKey) problems.push("SUPABASE_SERVICE_ROLE_KEY");
  const homeserverUrl = normalizeBaseUrl(env("MATRIX_HOMESERVER_URL"));
  if (!homeserverUrl) problems.push("MATRIX_HOMESERVER_URL");
  const registrationToken = env("MATRIX_REGISTRATION_TOKEN")?.trim() ?? "";
  if (registrationToken === "") problems.push("MATRIX_REGISTRATION_TOKEN");
  const pepper = env("MATRIX_PASSWORD_PEPPER")?.trim() ?? "";
  if (pepper.length < MIN_PEPPER_LENGTH) problems.push(`MATRIX_PASSWORD_PEPPER (min ${MIN_PEPPER_LENGTH} chars)`);

  if (problems.length > 0 || !supabaseUrl || !publishableKey || !secretKey || !homeserverUrl) {
    return { ok: false, problems };
  }
  return { ok: true, config: { supabaseUrl, publishableKey, secretKey, homeserverUrl, registrationToken, pepper } };
}

// ---------------------------------------------------------------------------------------------
// Failures
// ---------------------------------------------------------------------------------------------

class NotAuthenticated extends Error {}

class HomeserverUnreachable extends Error {
  constructor(readonly stage: string, readonly reason: string) {
    super(stage);
  }
}

class ProvisioningFailed extends Error {
  constructor(readonly detail: string) {
    super(detail);
  }
}

// ---------------------------------------------------------------------------------------------
// HTTP with timeouts
// ---------------------------------------------------------------------------------------------

type HttpResult =
  | { kind: "response"; status: number; body: unknown }
  | { kind: "unreachable"; reason: "timeout" | "network" };

class Http {
  constructor(private readonly deps: Deps, private readonly deadline: number) {}

  async call(url: string, method: string, headers: Record<string, string>, body?: unknown): Promise<HttpResult> {
    const remaining = this.deadline - this.deps.now();
    if (remaining <= 0) return { kind: "unreachable", reason: "timeout" };
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.min(this.deps.requestTimeoutMs, remaining));
    try {
      const init: RequestInit = { method, headers: { Accept: "application/json", ...headers }, signal: controller.signal };
      if (body !== undefined) {
        init.headers = { ...init.headers as Record<string, string>, "Content-Type": "application/json" };
        init.body = JSON.stringify(body);
      }
      const response = await this.deps.fetch(url, init);
      const text = await response.text(); // still covered by the abort signal
      let parsed: unknown = null;
      if (text !== "") {
        try {
          parsed = JSON.parse(text);
        } catch {
          parsed = null; // e.g. an HTML error page from the reverse proxy
        }
      }
      return { kind: "response", status: response.status, body: parsed };
    } catch {
      return { kind: "unreachable", reason: controller.signal.aborted ? "timeout" : "network" };
    } finally {
      clearTimeout(timer);
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Supabase
// ---------------------------------------------------------------------------------------------

type SupabaseUser = { id: string; email?: unknown; user_metadata?: unknown };

/** Validates the caller's access token with Supabase Auth; never trusts an id from the body. */
async function verifyUser(http: Http, config: Config, token: string): Promise<SupabaseUser> {
  const result = await http.call(`${config.supabaseUrl}/auth/v1/user`, "GET", {
    apikey: config.publishableKey,
    Authorization: `Bearer ${token}`,
  });
  if (result.kind === "unreachable") throw new ProvisioningFailed(`supabase_auth_unreachable (${result.reason})`);
  if ([400, 401, 403, 404].includes(result.status)) throw new NotAuthenticated();
  if (result.status !== 200 || typeof result.body !== "object" || result.body === null) {
    throw new ProvisioningFailed(`supabase_auth_failed (HTTP ${result.status})`);
  }
  const user = result.body as Record<string, unknown>;
  if (typeof user.id !== "string") throw new ProvisioningFailed("supabase_auth_failed: no user id");
  return { id: user.id, email: user.email, user_metadata: user.user_metadata };
}

type ProfileState =
  | { status: "found"; displayName: unknown; matrixUserId: unknown; matrixHomeserver: unknown }
  | { status: "missing" }
  | { status: "error" };

/** Never throws: the profile only refines the display name and avoids a redundant write. */
async function fetchProfile(http: Http, config: Config, userId: string): Promise<ProfileState> {
  try {
    const url = `${config.supabaseUrl}/rest/v1/profiles?id=eq.${userId}` +
      "&select=display_name,matrix_user_id,matrix_homeserver";
    const result = await http.call(url, "GET", apiKeyHeaders(config.secretKey));
    if (result.kind !== "response" || result.status !== 200 || !Array.isArray(result.body)) return { status: "error" };
    const row = result.body[0];
    if (typeof row !== "object" || row === null) return { status: "missing" };
    const record = row as Record<string, unknown>;
    return {
      status: "found",
      displayName: record.display_name,
      matrixUserId: record.matrix_user_id,
      matrixHomeserver: record.matrix_homeserver,
    };
  } catch {
    return { status: "error" };
  }
}

/** Upsert (not PATCH) so a profile row missing its auth trigger is created rather than skipped. */
async function linkProfile(http: Http, config: Config, userId: string, session: MatrixSession): Promise<HttpResult> {
  return await http.call(
    `${config.supabaseUrl}/rest/v1/profiles?on_conflict=id`,
    "POST",
    { ...apiKeyHeaders(config.secretKey), Prefer: "resolution=merge-duplicates,return=minimal" },
    { id: userId, matrix_user_id: session.userId, matrix_homeserver: config.homeserverUrl },
  );
}

// ---------------------------------------------------------------------------------------------
// Matrix
// ---------------------------------------------------------------------------------------------

async function matrixPost(http: Http, config: Config, stage: string, path: string, body: unknown) {
  const result = await http.call(`${config.homeserverUrl}${path}`, "POST", {}, body);
  if (result.kind === "unreachable") throw new HomeserverUnreachable(stage, result.reason);
  return result;
}

async function login(http: Http, config: Config, creds: Credentials): Promise<MatrixSession | null> {
  const result = await matrixPost(http, config, "login", "/_matrix/client/v3/login", loginBody(creds));
  const outcome = classifyLogin(result.status, result.body, creds.deviceId);
  switch (outcome.kind) {
    case "ok":
      return outcome.session;
    case "unknown_user":
      return null;
    case "unreachable":
      throw new HomeserverUnreachable("login", `HTTP ${result.status}`);
    case "fail":
      throw new ProvisioningFailed(outcome.detail);
  }
}

/** Returns the new session, or null when the account already exists (M_USER_IN_USE). */
async function register(http: Http, config: Config, creds: Credentials): Promise<MatrixSession | null> {
  let auth: Record<string, unknown> | undefined;
  let attemptedStage: string | undefined;
  for (let round = 0; round < MAX_UIAA_ROUNDS; round++) {
    const result = await matrixPost(http, config, "register", "/_matrix/client/v3/register", registerBody(creds, auth));
    const outcome = classifyRegister(result.status, result.body, creds.deviceId);
    switch (outcome.kind) {
      case "ok":
        return outcome.session;
      case "user_in_use":
        return null;
      case "unreachable":
        throw new HomeserverUnreachable("register", `HTTP ${result.status}`);
      case "fail":
        throw new ProvisioningFailed(outcome.detail);
      case "uiaa": {
        const step = nextUiaaStep(result.body, config.registrationToken, attemptedStage);
        if (step.kind === "fail") throw new ProvisioningFailed(`matrix_register_failed: ${step.detail}`);
        auth = step.auth;
        attemptedStage = step.stage;
      }
    }
  }
  throw new ProvisioningFailed("matrix_register_failed: uiaa_too_many_rounds");
}

/**
 * login → (unknown) register → (taken meanwhile by a concurrent first call) login again.
 * Both concurrent callers derive the same password, so whichever registers, the other logs in.
 */
async function provision(
  http: Http,
  config: Config,
  creds: Credentials,
): Promise<{ session: MatrixSession; created: boolean; path: string }> {
  const existing = await login(http, config, creds);
  if (existing) return { session: existing, created: false, path: "login" };
  const registered = await register(http, config, creds);
  if (registered) return { session: registered, created: true, path: "register" };
  const raced = await login(http, config, creds);
  if (raced) return { session: raced, created: false, path: "login_after_user_in_use" };
  throw new ProvisioningFailed("matrix_credentials_rejected");
}

async function setDisplayName(http: Http, config: Config, session: MatrixSession, name: string): Promise<HttpResult> {
  return await http.call(
    `${config.homeserverUrl}/_matrix/client/v3/profile/${encodeURIComponent(session.userId)}/displayname`,
    "PUT",
    { Authorization: `Bearer ${session.accessToken}` },
    { displayname: name },
  );
}

// ---------------------------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------------------------

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function errorResponse(kind: ErrorKind, detail?: string): Response {
  const { status, body } = errorResponseParts(kind, detail);
  return json(status, body);
}

export function createHandler(env: Env, overrides: Partial<Deps> = {}): (req: Request) => Promise<Response> {
  const deps: Deps = { ...DEFAULT_DEPS, ...overrides };

  return async (req: Request): Promise<Response> => {
    const started = deps.now();
    const elapsed = () => deps.now() - started;
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    if (req.method !== "POST") return errorResponse("method_not_allowed");

    let localpart: string | undefined;
    try {
      const token = bearerToken(req.headers.get("authorization"));
      if (!token) throw new NotAuthenticated();

      const loaded = loadConfig(env);
      if (!loaded.ok) throw new ProvisioningFailed(`missing_config: ${loaded.problems.join(", ")}`);
      const config = loaded.config;

      const raw = await req.text();
      if (raw.length > MAX_REQUEST_BYTES) return errorResponse("invalid_request", "body too large");
      let payload: unknown;
      try {
        payload = raw.trim() === "" ? {} : JSON.parse(raw);
      } catch {
        return errorResponse("invalid_request", "body must be JSON");
      }
      const request = parseSessionRequest(payload);
      if (!request.ok) return errorResponse("invalid_request", request.detail);

      const http = new Http(deps, started + deps.totalBudgetMs);
      const user = await verifyUser(http, config, token);
      const userId = normalizeUserId(user.id);
      if (!userId) throw new ProvisioningFailed("supabase_user_id_invalid");
      localpart = matrixLocalpart(userId);
      const creds: Credentials = {
        localpart,
        password: await deriveMatrixPassword(config.pepper, userId),
        deviceId: request.value.deviceId,
        deviceName: request.value.deviceName,
      };

      // The profile read runs while the homeserver works; it never throws.
      const profilePromise = fetchProfile(http, config, userId);
      const { session, created, path } = await provision(http, config, creds);
      if (!session.userId.startsWith(`@${localpart}:`)) throw new ProvisioningFailed("matrix_user_id_mismatch");
      const profile = await profilePromise;

      const linked = profile.status === "found" &&
        profile.matrixUserId === session.userId &&
        profile.matrixHomeserver === config.homeserverUrl;
      // First provisioning only: never overwrite a name the user may have changed since.
      const firstLink = created || (profile.status === "found" && profile.matrixUserId !== session.userId);
      if (firstLink) {
        const name = displayNameFor(profile.status === "found" ? profile.displayName : null, user);
        if (name) {
          const result = await setDisplayName(http, config, session, name);
          if (result.kind !== "response" || result.status !== 200) {
            deps.log({ event: "matrix_session_step", step: "displayname", ok: false, user: localpart, ...stepFailure(result) });
          }
        }
      }
      if (!linked) {
        const result = await linkProfile(http, config, userId, session);
        if (result.kind !== "response" || result.status >= 300) {
          // Not fatal: the Matrix session works, and the next call retries the write.
          deps.log({ event: "matrix_session_step", step: "profile_link", ok: false, user: localpart, ...stepFailure(result) });
        } else if (profile.status === "found" && typeof profile.matrixUserId === "string" && profile.matrixUserId !== session.userId) {
          deps.log({ event: "matrix_session_step", step: "profile_link", ok: true, user: localpart, replaced_other_link: true });
        }
      }

      deps.log({ event: "matrix_session", outcome: "ok", path, created, user: localpart, ms: elapsed() });
      return json(200, successBody(config.homeserverUrl, session, created));
    } catch (error) {
      if (error instanceof NotAuthenticated) {
        deps.log({ event: "matrix_session", outcome: "not_authenticated", ms: elapsed() });
        return errorResponse("not_authenticated");
      }
      if (error instanceof HomeserverUnreachable) {
        deps.log({
          event: "matrix_session",
          outcome: "homeserver_unreachable",
          stage: error.stage,
          reason: error.reason,
          user: localpart,
          ms: elapsed(),
        });
        return errorResponse("homeserver_unreachable");
      }
      if (error instanceof ProvisioningFailed) {
        deps.log({ event: "matrix_session", outcome: "provisioning_failed", detail: error.detail, user: localpart, ms: elapsed() });
        return errorResponse("provisioning_failed", error.detail);
      }
      // Unexpected bug: log the error class only, a message could quote request data.
      const name = error instanceof Error ? error.name : typeof error;
      deps.log({ event: "matrix_session", outcome: "internal_error", error: name, user: localpart, ms: elapsed() });
      return errorResponse("provisioning_failed", "internal_error");
    }
  };
}

function stepFailure(result: HttpResult): Record<string, unknown> {
  if (result.kind === "unreachable") return { reason: result.reason };
  const body = result.body;
  const code = typeof body === "object" && body !== null
    ? (body as Record<string, unknown>).errcode ?? (body as Record<string, unknown>).code
    : undefined;
  return { status: result.status, code: typeof code === "string" ? code : undefined };
}
