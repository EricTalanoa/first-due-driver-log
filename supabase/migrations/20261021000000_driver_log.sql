-- Driver log schema for Supabase. Applied to project jtofziwssarbifugqjnn.
create extension if not exists btree_gist with schema extensions;

create table public.profiles (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  name text not null default '' check (length(name) <= 500),
  carrier text not null default 'First Due Movers' check (length(carrier) <= 500),
  terminal text not null default '' check (length(terminal) <= 500),
  office text not null default '' check (length(office) <= 500),
  vehicle text not null default '' check (length(vehicle) <= 500),
  co_driver text not null default '' check (length(co_driver) <= 500),
  zone text not null default 'America/Los_Angeles' check (length(zone) <= 100),
  updated_at timestamptz not null default now()
);

-- One row per duty period. The row with no end_at is the period being recorded now.
create table public.entries (
  id text primary key check (length(id) between 1 and 100),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null check (status in ('Off duty', 'Sleeper berth', 'Driving', 'On duty')),
  start_at timestamptz not null,
  end_at timestamptz check (end_at is null or end_at > start_at),
  from_place text not null default '' check (length(from_place) <= 2000),
  to_place text not null default '' check (length(to_place) <= 2000),
  miles double precision check (miles is null or (miles >= 0 and miles <= 100000)),
  note text not null default '' check (length(note) <= 2000),
  partial boolean not null default false,
  source text not null default 'manual' check (source in ('manual', 'gps')),
  last_point jsonb,
  document text check (length(document) <= 1000),
  shipper text check (length(shipper) <= 1000),
  commodity text check (length(commodity) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Duty periods never overlap; checked at commit so a status change can end one and start the next.
  constraint entries_no_overlap exclude using gist (user_id with =, tstzrange(start_at, end_at) with &&) deferrable initially deferred
);
create index entries_user_start on public.entries (user_id, start_at);

alter table public.profiles enable row level security;
alter table public.entries enable row level security;

create policy "Own profile: read" on public.profiles for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own profile: add" on public.profiles for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own profile: change" on public.profiles for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own entries: read" on public.entries for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own entries: add" on public.entries for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own entries: change" on public.entries for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own entries: remove" on public.entries for delete to authenticated using ((select auth.uid()) = user_id);

-- Applies one change to the log (added/changed entries, removed entries, profile) in a single transaction.
create function public.save_log(upserts jsonb default '[]', deletes text[] default '{}', profile jsonb default null)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to save your log.' using errcode = '42501'; end if;
  delete from public.entries where user_id = auth.uid() and id = any(deletes);
  insert into public.entries as t (id, user_id, status, start_at, end_at, from_place, to_place, miles, note, partial, source, last_point, document, shipper, commodity, updated_at)
  select e.id, auth.uid(), e.status, e.start_at, e.end_at, coalesce(e.from_place, ''), coalesce(e.to_place, ''), e.miles, coalesce(e.note, ''), coalesce(e.partial, false), coalesce(e.source, 'manual'), e.last_point, e.document, e.shipper, e.commodity, now()
  from jsonb_to_recordset(upserts) as e(id text, status text, start_at timestamptz, end_at timestamptz, from_place text, to_place text, miles double precision, note text, partial boolean, source text, last_point jsonb, document text, shipper text, commodity text)
  on conflict (id) do update set status = excluded.status, start_at = excluded.start_at, end_at = excluded.end_at, from_place = excluded.from_place, to_place = excluded.to_place,
    miles = excluded.miles, note = excluded.note, partial = excluded.partial, source = excluded.source, last_point = excluded.last_point,
    document = excluded.document, shipper = excluded.shipper, commodity = excluded.commodity, updated_at = now()
  where t.user_id = auth.uid();
  if profile is not null then
    insert into public.profiles as p (user_id, name, carrier, terminal, office, vehicle, co_driver, zone, updated_at)
    values (auth.uid(), profile->>'name', profile->>'carrier', profile->>'terminal', profile->>'office', profile->>'vehicle', profile->>'coDriver', profile->>'zone', now())
    on conflict (user_id) do update set name = excluded.name, carrier = excluded.carrier, terminal = excluded.terminal, office = excluded.office,
      vehicle = excluded.vehicle, co_driver = excluded.co_driver, zone = excluded.zone, updated_at = now();
  end if;
end $$;
revoke execute on function public.save_log(jsonb, text[], jsonb) from public, anon;
grant execute on function public.save_log(jsonb, text[], jsonb) to authenticated;
