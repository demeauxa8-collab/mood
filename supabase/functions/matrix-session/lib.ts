// Pure building blocks of the `matrix-session` Edge Function.
//
// Nothing here performs I/O: every function is deterministic and covered by lib_test.ts.
// The contract these helpers serve is docs/BACKEND-PLAN.md §2. Do not change response shapes
// without updating that contract: the app (track F) decodes them as written there.

// ---------------------------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------------------------

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * Canonical form of a Supabase user id: lowercase UUID with dashes.
 * Supabase Auth already returns lowercase ids; Swift's `UUID.uuidString` is uppercase, so any
 * other component deriving Matrix credentials must lowercase first. Returns null when invalid.
 */
export function normalizeUserId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const id = value.trim().toLowerCase();
  return UUID_PATTERN.test(id) ? id : null;
}

/** Matrix localpart: "m" + the first 12 hex digits of the canonical Supabase id. */
export function matrixLocalpart(canonicalUserId: string): string {
  return "m" + canonicalUserId.replaceAll("-", "").slice(0, 12);
}

// ---------------------------------------------------------------------------------------------
// Password derivation
// ---------------------------------------------------------------------------------------------

/** RFC 4648 §5 base64url, without padding. */
export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/**
 * Matrix password = base64url(HMAC-SHA256(key = UTF-8(pepper), message = UTF-8(userId))),
 * unpadded (43 characters). The pepper string is used as-is (already trimmed by the config
 * loader), never base64-decoded. Changing any of this changes every user's password.
 */
export async function deriveMatrixPassword(pepper: string, canonicalUserId: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(canonicalUserId));
  return base64UrlEncode(new Uint8Array(mac));
}

// ---------------------------------------------------------------------------------------------
// Incoming request
// ---------------------------------------------------------------------------------------------

export const DEFAULT_DEVICE_NAME = "Mood";
export const MAX_DEVICE_NAME_LENGTH = 100;
export const MAX_REQUEST_BYTES = 4096;
const DEVICE_ID_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;

export type SessionRequest = { deviceId: string; deviceName: string };

/** Extracts the token of an `Authorization: Bearer <token>` header. */
export function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  return match ? match[1] : null;
}

/** Validates `{ "device_id": "...", "device_name": "..." }` (device_name optional). */
export function parseSessionRequest(
  body: unknown,
): { ok: true; value: SessionRequest } | { ok: false; detail: string } {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, detail: "body must be a JSON object" };
  }
  const record = body as Record<string, unknown>;
  const deviceId = typeof record.device_id === "string" ? record.device_id.trim() : "";
  if (!DEVICE_ID_PATTERN.test(deviceId)) {
    return { ok: false, detail: "device_id must be 1-64 characters of [A-Za-z0-9._-]" };
  }
  let deviceName = typeof record.device_name === "string" ? record.device_name.trim() : "";
  if (deviceName === "") deviceName = DEFAULT_DEVICE_NAME;
  deviceName = Array.from(deviceName).slice(0, MAX_DEVICE_NAME_LENGTH).join("");
  return { ok: true, value: { deviceId, deviceName } };
}

// ---------------------------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------------------------

export const MIN_PEPPER_LENGTH = 32;

/**
 * Supabase exposes API keys two ways: the new JSON dictionaries `SUPABASE_PUBLISHABLE_KEYS` /
 * `SUPABASE_SECRET_KEYS` ({"default": "sb_..."}) and the legacy `SUPABASE_ANON_KEY` /
 * `SUPABASE_SERVICE_ROLE_KEY` JWTs (retired at the end of 2026). Prefer the new key.
 */
export function resolveApiKey(jsonKeys: string | undefined, legacyKey: string | undefined): string | null {
  if (jsonKeys && jsonKeys.trim() !== "") {
    try {
      const parsed: unknown = JSON.parse(jsonKeys);
      if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) {
        const keys = parsed as Record<string, unknown>;
        const preferred = keys["default"];
        if (typeof preferred === "string" && preferred !== "") return preferred;
        const first = Object.values(keys).find((v) => typeof v === "string" && v !== "");
        if (typeof first === "string") return first;
      }
    } catch {
      // Malformed dictionary: fall back to the legacy key below.
    }
  }
  const legacy = legacyKey?.trim();
  return legacy ? legacy : null;
}

/**
 * Headers authenticating a server-side call with a Supabase API key. New `sb_...` keys are not
 * JWTs and must travel on `apikey` only (a Bearer copy is rejected as "Invalid JWT"); legacy
 * JWT keys are sent on both headers, as the Supabase clients always did.
 */
export function apiKeyHeaders(key: string): Record<string, string> {
  return key.startsWith("sb_") ? { apikey: key } : { apikey: key, Authorization: `Bearer ${key}` };
}

/** Validates an http(s) base URL and strips trailing slashes. */
export function normalizeBaseUrl(value: string | undefined): string | null {
  const raw = value?.trim();
  if (!raw) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  if (url.search !== "" || url.hash !== "") return null;
  return url.toString().replace(/\/+$/, "");
}

// ---------------------------------------------------------------------------------------------
// Matrix request bodies (Client-Server API v3)
// ---------------------------------------------------------------------------------------------

export const REGISTRATION_TOKEN_STAGE = "m.login.registration_token";
export const DUMMY_STAGE = "m.login.dummy";
const SUPPORTED_STAGES = new Set([REGISTRATION_TOKEN_STAGE, DUMMY_STAGE]);

export type Credentials = { localpart: string; password: string; deviceId: string; deviceName: string };

/** POST /_matrix/client/v3/login. Reusing `device_id` keeps one Matrix device per app install. */
export function loginBody(c: Credentials): Record<string, unknown> {
  return {
    type: "m.login.password",
    identifier: { type: "m.id.user", user: c.localpart },
    password: c.password,
    device_id: c.deviceId,
    initial_device_display_name: c.deviceName,
  };
}

/** POST /_matrix/client/v3/register (kind=user). `auth` is omitted on the first UIAA round. */
export function registerBody(c: Credentials, auth?: Record<string, unknown>): Record<string, unknown> {
  const body: Record<string, unknown> = {
    username: c.localpart,
    password: c.password,
    device_id: c.deviceId,
    initial_device_display_name: c.deviceName,
    inhibit_login: false,
  };
  if (auth) body.auth = auth;
  return body;
}

export type UiaaStep =
  | { kind: "auth"; stage: string; auth: Record<string, unknown> }
  | { kind: "fail"; detail: string };

/**
 * Chooses the next User-Interactive Auth stage from a 401 register response.
 * Supports flows made only of `m.login.registration_token` and `m.login.dummy`.
 * `attemptedStage` is the stage sent in the previous round: if the server did not mark it as
 * completed, it was rejected (wrong registration token) and we stop instead of looping.
 */
export function nextUiaaStep(body: unknown, registrationToken: string, attemptedStage?: string): UiaaStep {
  if (typeof body !== "object" || body === null) return { kind: "fail", detail: "uiaa_invalid_response" };
  const record = body as Record<string, unknown>;
  const session = record.session;
  if (typeof session !== "string" || session === "") return { kind: "fail", detail: "uiaa_missing_session" };

  const completed = stringArray(record.completed);
  if (attemptedStage && !completed.includes(attemptedStage)) {
    const errcode = typeof record.errcode === "string" ? record.errcode : "no_errcode";
    return attemptedStage === REGISTRATION_TOKEN_STAGE
      ? { kind: "fail", detail: `registration_token_rejected: ${errcode}` }
      : { kind: "fail", detail: `uiaa_stage_rejected: ${attemptedStage} ${errcode}` };
  }

  const flows = Array.isArray(record.flows) ? record.flows : [];
  const offered: string[][] = flows.map((flow) =>
    typeof flow === "object" && flow !== null ? stringArray((flow as Record<string, unknown>).stages) : []
  );
  const usable = offered.find((stages) =>
    stages.length > 0 &&
    stages.every((stage) => SUPPORTED_STAGES.has(stage)) &&
    completed.every((stage) => stages.includes(stage))
  );
  if (!usable) {
    const list = offered.map((stages) => stages.join("+")).join(", ") || "none";
    return { kind: "fail", detail: `uiaa_unsupported_flows: ${list}` };
  }
  const stage = usable.find((s) => !completed.includes(s));
  if (!stage) return { kind: "fail", detail: "uiaa_flow_already_complete" };

  const auth: Record<string, unknown> = stage === REGISTRATION_TOKEN_STAGE
    ? { type: stage, token: registrationToken, session }
    : { type: stage, session };
  return { kind: "auth", stage, auth };
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
}

// ---------------------------------------------------------------------------------------------
// Matrix responses → outcome
// ---------------------------------------------------------------------------------------------

export type MatrixSession = { userId: string; accessToken: string; deviceId: string };

/** 502/503/504 = the reverse proxy (Tailscale Funnel) has no live homeserver behind it. */
export function isUnreachableStatus(status: number): boolean {
  return status === 502 || status === 503 || status === 504;
}

export function errcodeOf(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const errcode = (body as Record<string, unknown>).errcode;
  return typeof errcode === "string" ? errcode : null;
}

/** Contract-safe failure description: stage, Matrix errcode and HTTP status, never free text. */
export function matrixFailureDetail(stage: string, status: number, body: unknown): string {
  return `${stage}: ${errcodeOf(body) ?? "no_errcode"} (HTTP ${status})`;
}

/** Reads `user_id` / `access_token` / `device_id` from a successful login or register reply. */
export function sessionFromBody(body: unknown, requestedDeviceId: string): MatrixSession | null {
  if (typeof body !== "object" || body === null) return null;
  const record = body as Record<string, unknown>;
  const userId = record.user_id;
  const accessToken = record.access_token;
  if (typeof userId !== "string" || !userId.startsWith("@")) return null;
  if (typeof accessToken !== "string" || accessToken === "") return null;
  const deviceId = typeof record.device_id === "string" && record.device_id !== ""
    ? record.device_id
    : requestedDeviceId;
  return { userId, accessToken, deviceId };
}

export type LoginOutcome =
  | { kind: "ok"; session: MatrixSession }
  | { kind: "unknown_user" }
  | { kind: "unreachable" }
  | { kind: "fail"; detail: string };

/**
 * Login reply → outcome. Continuwuity (like Synapse) answers 403 M_FORBIDDEN both for an
 * unknown user and for a wrong password; the caller tries to register, and a following
 * M_USER_IN_USE tells the two cases apart.
 */
export function classifyLogin(status: number, body: unknown, requestedDeviceId: string): LoginOutcome {
  if (status === 200) {
    const session = sessionFromBody(body, requestedDeviceId);
    return session ? { kind: "ok", session } : { kind: "fail", detail: "matrix_login_failed: malformed_response" };
  }
  if (isUnreachableStatus(status)) return { kind: "unreachable" };
  const errcode = errcodeOf(body);
  if ((status === 403 && errcode === "M_FORBIDDEN") || errcode === "M_NOT_FOUND") return { kind: "unknown_user" };
  return { kind: "fail", detail: matrixFailureDetail("matrix_login_failed", status, body) };
}

export type RegisterOutcome =
  | { kind: "ok"; session: MatrixSession }
  | { kind: "uiaa" }
  | { kind: "user_in_use" }
  | { kind: "unreachable" }
  | { kind: "fail"; detail: string };

export function classifyRegister(status: number, body: unknown, requestedDeviceId: string): RegisterOutcome {
  if (status === 200) {
    const session = sessionFromBody(body, requestedDeviceId);
    return session ? { kind: "ok", session } : { kind: "fail", detail: "matrix_register_failed: malformed_response" };
  }
  if (isUnreachableStatus(status)) return { kind: "unreachable" };
  if (errcodeOf(body) === "M_USER_IN_USE") return { kind: "user_in_use" };
  if (status === 401 && typeof body === "object" && body !== null && "session" in body) return { kind: "uiaa" };
  return { kind: "fail", detail: matrixFailureDetail("matrix_register_failed", status, body) };
}

// ---------------------------------------------------------------------------------------------
// Display name
// ---------------------------------------------------------------------------------------------

export const MAX_DISPLAY_NAME_LENGTH = 64;

/**
 * Matrix display name for a new account: `profiles.display_name`, else the part of the e-mail
 * before "@", else the Discord names from Auth metadata. Null when nothing usable exists
 * (the homeserver default is kept).
 */
export function displayNameFor(profileDisplayName: unknown, user: { email?: unknown; user_metadata?: unknown }): string | null {
  const metadata = typeof user.user_metadata === "object" && user.user_metadata !== null
    ? user.user_metadata as Record<string, unknown>
    : {};
  const email = typeof user.email === "string" ? user.email : "";
  const candidates: unknown[] = [
    profileDisplayName,
    email.includes("@") ? email.slice(0, email.indexOf("@")) : "",
    metadata.global_name,
    metadata.full_name,
    metadata.name,
    metadata.user_name,
  ];
  for (const candidate of candidates) {
    if (typeof candidate !== "string") continue;
    const trimmed = candidate.trim();
    if (trimmed !== "") return Array.from(trimmed).slice(0, MAX_DISPLAY_NAME_LENGTH).join("");
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Contract responses (docs/BACKEND-PLAN.md §2)
// ---------------------------------------------------------------------------------------------

export type SuccessBody = {
  homeserver: string;
  user_id: string;
  access_token: string;
  device_id: string;
  created: boolean;
};

export function successBody(homeserver: string, session: MatrixSession, created: boolean): SuccessBody {
  return {
    homeserver,
    user_id: session.userId,
    access_token: session.accessToken,
    device_id: session.deviceId,
    created,
  };
}

export type ErrorKind =
  | "not_authenticated"
  | "homeserver_unreachable"
  | "provisioning_failed"
  // Outside the contract: only a buggy client can reach these two.
  | "invalid_request"
  | "method_not_allowed";

const STATUS_BY_KIND: Record<ErrorKind, number> = {
  not_authenticated: 401,
  homeserver_unreachable: 503,
  provisioning_failed: 500,
  invalid_request: 400,
  method_not_allowed: 405,
};

/**
 * `{ "error": kind }`. provisioning_failed always carries `detail` (contract); invalid_request
 * carries it when given; 401 and 503 never do, so the app can match them exactly.
 */
export function errorResponseParts(
  kind: ErrorKind,
  detail?: string,
): { status: number; body: { error: ErrorKind; detail?: string } } {
  const body: { error: ErrorKind; detail?: string } = { error: kind };
  if (kind === "provisioning_failed") body.detail = detail || "unknown";
  else if (kind === "invalid_request" && detail) body.detail = detail;
  return { status: STATUS_BY_KIND[kind], body };
}
