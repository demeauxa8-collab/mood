// Local end-to-end bench for the `matrix-session` Edge Function against the REAL Mood homeserver.
//
// One Deno process serves the real handler at /functions/v1/matrix-session plus a stub of the
// two Supabase endpoints it calls (/auth/v1/user, /rest/v1/profiles). Only Supabase is faked:
// the Matrix calls go to MATRIX_HOMESERVER_URL with the real registration token and pepper,
// read by Deno from ~/mood-server/.env (never printed). Run on the Mac Studio:
//
//   deno run --allow-net --allow-env --env-file=$HOME/mood-server/.env scripts/matrix-session-local-e2e.ts
//   echo local-e2e-supabase-token | SUPABASE_URL=http://127.0.0.1:54329 SUPABASE_ANON_KEY=stub \
//     REPEAT=1 scripts/test-matrix-session.sh -
//
// The stub user is a fixed test identity; it creates @m0e2e00001014:mood.local on first run.

import { createHandler } from "../supabase/functions/matrix-session/handler.ts";

const PORT = Number(Deno.env.get("E2E_PORT") ?? "54329");
const BASE = `http://127.0.0.1:${PORT}`;
const STUB_TOKEN = "local-e2e-supabase-token"; // accepted by the stub only, not a real credential
const STUB_USER = { id: "0e2e0000-1014-4000-8000-000000000001", email: "e2e-probe@mood.local", user_metadata: {} };

const env = (name: string): string | undefined => {
  if (name === "SUPABASE_URL") return BASE;
  if (name === "SUPABASE_ANON_KEY" || name === "SUPABASE_SERVICE_ROLE_KEY") return "stub";
  if (name === "SUPABASE_PUBLISHABLE_KEYS" || name === "SUPABASE_SECRET_KEYS") return undefined;
  return Deno.env.get(name);
};
const handler = createHandler(env);

Deno.serve({ hostname: "127.0.0.1", port: PORT }, async (req) => {
  const { pathname } = new URL(req.url);
  if (pathname === "/functions/v1/matrix-session") return await handler(req);
  if (pathname === "/auth/v1/user") {
    return req.headers.get("authorization") === `Bearer ${STUB_TOKEN}`
      ? Response.json(STUB_USER)
      : Response.json({ code: 401, msg: "invalid JWT" }, { status: 401 });
  }
  if (pathname === "/rest/v1/profiles") {
    if (req.method === "GET") return Response.json([]);
    const row = await req.json();
    console.log(JSON.stringify({ stub: "profiles_upsert", matrix_user_id: row.matrix_user_id, matrix_homeserver: row.matrix_homeserver }));
    return new Response(null, { status: 201 });
  }
  return new Response("not found", { status: 404 });
});
