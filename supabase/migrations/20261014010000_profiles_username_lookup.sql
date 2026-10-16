-- Discord-style unique usernames: how people find and add each other. The Matrix user directory
-- hides local users who share no room with the searcher, so a new Mood user is unfindable there.
-- Applied to project jxpgyblzymshyzbkgmat on 2026-10-14.
alter table public.profiles add column if not exists username text;
alter table public.profiles add constraint profiles_username_format
    check (username is null or (username ~ '^[a-z0-9_.]{2,32}$' and username !~ '\.\.'));
create unique index if not exists profiles_username_key on public.profiles (username);

-- "Jean.Dupont+x@…" → "jean.dupont" (or with 4 digits when taken). Internal, not an RPC.
create or replace function public.mood_default_username(p_seed text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
    base text := left(regexp_replace(regexp_replace(lower(coalesce(p_seed, '')), '[^a-z0-9_.]', '', 'g'), '\.{2,}', '.', 'g'), 28);
    candidate text;
begin
    if length(base) < 2 then base := 'user'; end if;
    candidate := base;
    for i in 1..50 loop
        exit when not exists (select 1 from public.profiles p where p.username = candidate);
        candidate := base || (floor(random() * 9000) + 1000)::int::text;
    end loop;
    return candidate;
end;
$$;
revoke execute on function public.mood_default_username(text) from public, anon, authenticated;

create or replace function public.create_profile_for_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    is_discord boolean := new.raw_app_meta_data ->> 'provider' = 'discord';
    seed text := coalesce(case when is_discord then new.raw_user_meta_data ->> 'user_name' end, split_part(new.email, '@', 1));
begin
    for attempt in 1..3 loop
        begin
            insert into public.profiles (id, display_name, avatar_url, discord_id, discord_username, discord_avatar_url, username)
            values (
                new.id,
                coalesce(new.raw_user_meta_data ->> 'global_name', new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
                new.raw_user_meta_data ->> 'avatar_url',
                case when is_discord then coalesce(new.raw_user_meta_data ->> 'provider_id', new.raw_user_meta_data ->> 'sub') end,
                case when is_discord then new.raw_user_meta_data ->> 'user_name' end,
                case when is_discord then new.raw_user_meta_data ->> 'avatar_url' end,
                public.mood_default_username(seed)
            ) on conflict (id) do nothing;
            return new;
        exception when unique_violation then
            if attempt = 3 then raise; end if; -- a username taken in between: draw another one
        end;
    end loop;
    return new;
end;
$$;

update public.profiles p
set username = public.mood_default_username(coalesce(p.discord_username, split_part(u.email, '@', 1)))
from auth.users u
where u.id = p.id and p.username is null;

-- Exact-match lookup only (no listing): what "Ajouter un ami" needs.
create or replace function public.find_user_by_username(p_username text)
returns table (username text, display_name text, avatar_url text, matrix_user_id text)
language sql stable security definer set search_path = '' as $$
    select p.username, p.display_name, p.avatar_url, p.matrix_user_id
    from public.profiles p
    where p.username = lower(trim(p_username)) and p.matrix_user_id is not null
    limit 1
$$;
revoke execute on function public.find_user_by_username(text) from public, anon;
grant execute on function public.find_user_by_username(text) to authenticated;

grant update (username) on public.profiles to authenticated;
