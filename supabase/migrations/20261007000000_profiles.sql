create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    avatar_url text,
    matrix_user_id text unique,
    matrix_homeserver text,
    discord_id text unique,
    discord_username text,
    discord_avatar_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
create policy "Users can view their own profile" on public.profiles for select to authenticated using (id = auth.uid());
create policy "Users can create their own profile" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "Users can update their own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create or replace function public.create_profile_for_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    insert into public.profiles (id, display_name, avatar_url, discord_id, discord_username, discord_avatar_url)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'global_name', new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
        new.raw_user_meta_data ->> 'avatar_url',
        case when new.raw_app_meta_data ->> 'provider' = 'discord' then coalesce(new.raw_user_meta_data ->> 'provider_id', new.raw_user_meta_data ->> 'sub') end,
        case when new.raw_app_meta_data ->> 'provider' = 'discord' then new.raw_user_meta_data ->> 'user_name' end,
        case when new.raw_app_meta_data ->> 'provider' = 'discord' then new.raw_user_meta_data ->> 'avatar_url' end
    ) on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users
for each row execute function public.create_profile_for_auth_user();

create table if not exists public.discord_guilds_import (
    user_id uuid not null references auth.users(id) on delete cascade,
    guild_id text not null,
    name text not null,
    icon_url text,
    imported_space_id text,
    primary key (user_id, guild_id)
);

alter table public.discord_guilds_import enable row level security;
create policy "Users can view their imported guilds" on public.discord_guilds_import for select to authenticated using (user_id = auth.uid());
create policy "Users can create their imported guilds" on public.discord_guilds_import for insert to authenticated with check (user_id = auth.uid());
create policy "Users can update their imported guilds" on public.discord_guilds_import for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Only authenticated owners can access these tables through PostgREST.
grant select, insert, update on public.profiles, public.discord_guilds_import to authenticated;
revoke all on public.profiles, public.discord_guilds_import from anon;
-- Trigger functions are internal, not public RPC endpoints.
revoke execute on function public.create_profile_for_auth_user() from public, anon, authenticated;

create or replace function public.touch_profile_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end;
$$;
revoke execute on function public.touch_profile_updated_at() from public, anon, authenticated;
create trigger on_profile_updated before update on public.profiles
for each row execute function public.touch_profile_updated_at();

-- Existing Auth users also need a profile when this migration is installed.
insert into public.profiles (id) select id from auth.users on conflict (id) do nothing;
