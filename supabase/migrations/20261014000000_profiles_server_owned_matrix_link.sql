-- The Matrix identity is provisioned by the matrix-session Edge Function (service role) only.
-- A column-only revoke has no effect while the table-level grant exists, so re-grant per column.
-- Applied to project jxpgyblzymshyzbkgmat on 2026-10-14.
revoke insert, update on public.profiles from authenticated;
grant insert (id, display_name, avatar_url, discord_id, discord_username, discord_avatar_url) on public.profiles to authenticated;
grant update (display_name, avatar_url, discord_id, discord_username, discord_avatar_url) on public.profiles to authenticated;
