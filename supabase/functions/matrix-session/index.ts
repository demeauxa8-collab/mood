// Supabase Edge Function `matrix-session`: turns a Mood (Supabase) session into a Matrix session
// on the Mood homeserver, creating the Matrix account on first use.
// Contract: docs/BACKEND-PLAN.md §2. Logic: handler.ts (flow) and lib.ts (pure helpers).
// Deploy index.ts, handler.ts and lib.ts together, with verify_jwt = false (see README.md).

import { createHandler } from "./handler.ts";

Deno.serve(createHandler((name) => Deno.env.get(name)));
