-- Chess Battle server setup for Supabase.
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run.
-- It is safe to run again: everything is created only if missing or replaced in place.


-- ---------------------------------------------------------------- tables
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  name         text not null default '' check (char_length(name) <= 16),
  av           text not null default 'Q' check (av in ('K','Q','R','B','N','P')),
  avc          text not null default 'gold' check (char_length(avc) <= 10),
  nation       text check (nation in ('ember','tide','grove','dusk')),
  nation_at    timestamptz,
  legacy       int not null default 0 check (legacy >= 0),
  legacy_peak  int not null default 0,
  nat_given    int not null default 0,
  rating       int not null default 700 check (rating between 100 and 4000),
  wins         int not null default 0,
  losses       int not null default 0,
  draws        int not null default 0,
  bot_day      date,
  bot_today    int not null default 0,
  last_bot_at  timestamptz,
  imported     boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists profiles_legacy_idx on public.profiles (legacy desc);
create index if not exists profiles_nation_idx on public.profiles (nation, legacy desc);

-- every star that moves, so monthly standings can be summed
create table if not exists public.star_events (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  nation     text,
  month      text not null,
  delta      int not null,
  kind       text not null check (kind in ('online','bot','import')),
  match_key  text,
  created_at timestamptz not null default now()
);
create index if not exists star_events_month_idx on public.star_events (month, kind, nation);
create index if not exists star_events_user_idx on public.star_events (user_id, month);

-- both players report each online result; stars move only when the two reports agree
create table if not exists public.match_reports (
  match_key  text not null,
  game_no    int  not null,
  reporter   uuid not null references public.profiles(id) on delete cascade,
  white      uuid not null,
  black      uuid not null,
  outcome    text not null check (outcome in ('white','black','draw')),
  created_at timestamptz not null default now(),
  primary key (match_key, game_no, reporter)
);
create table if not exists public.settled_matches (
  match_key  text not null,
  game_no    int  not null,
  white      uuid not null,
  black      uuid not null,
  outcome    text not null,
  scored     boolean not null,
  settled_at timestamptz not null default now(),
  primary key (match_key, game_no)
);
create index if not exists settled_pair_idx on public.settled_matches (white, black, settled_at);

-- quick-match lobby
create table if not exists public.mm_queue (
  user_id      uuid primary key references public.profiles(id) on delete cascade,
  code         text not null check (code ~ '^[A-Z0-9]{6}$'),
  nation       text,
  rating       int,
  created_at   timestamptz not null default now(),
  seen_at      timestamptz not null default now(),
  matched_with uuid
);

-- ---------------------------------------------------------------- security
-- Everyone can read public profile fields (for leaderboards). All writes go through the functions below.
alter table public.profiles        enable row level security;
alter table public.star_events     enable row level security;
alter table public.match_reports   enable row level security;
alter table public.settled_matches enable row level security;
alter table public.mm_queue        enable row level security;
drop policy if exists "profiles are public" on public.profiles;
create policy "profiles are public" on public.profiles for select using (true);

-- ---------------------------------------------------------------- helpers
create or replace function public.cb_month() returns text
language sql stable as $$ select to_char(now() at time zone 'utc', 'YYYY-MM') $$;

create or replace function public.cb_me() returns uuid
language plpgsql stable as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'not signed in'; end if;
  return u;
end $$;

-- make sure the caller has a profile row
create or replace function public.cb_ensure() returns public.profiles
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles;
begin
  insert into profiles (id) values (me) on conflict (id) do nothing;
  select * into p from profiles where id = me;
  return p;
end $$;

-- ---------------------------------------------------------------- profile
create or replace function public.sync_profile(p_name text, p_av text, p_avc text, p_rating int)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles;
begin
  perform cb_ensure();
  update profiles set
    name   = left(coalesce(p_name, ''), 16),
    av     = case when p_av in ('K','Q','R','B','N','P') then p_av else av end,
    avc    = left(coalesce(p_avc, avc), 10),
    rating = greatest(100, least(4000, coalesce(p_rating, rating))),
    updated_at = now()
  where id = me returning * into p;
  return get_me();
end $$;

-- one-time import of progress earned before accounts existed (capped)
create or replace function public.import_local(p_legacy int, p_nation text, p_nat_given int)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; add int;
begin
  p := cb_ensure();
  if not p.imported then
    add := greatest(0, least(coalesce(p_legacy, 0), 300));
    update profiles set
      legacy = legacy + add,
      legacy_peak = greatest(legacy_peak, legacy + add),
      nat_given = nat_given + greatest(-100, least(coalesce(p_nat_given, 0), 100)),
      nation = coalesce(nation, case when p_nation in ('ember','tide','grove','dusk') then p_nation end),
      nation_at = case when nation is null and p_nation in ('ember','tide','grove','dusk') then now() else nation_at end,
      imported = true, updated_at = now()
    where id = me;
    if add > 0 then
      insert into star_events (user_id, nation, month, delta, kind) values (me, null, cb_month(), add, 'import');
    end if;
  end if;
  return get_me();
end $$;

-- the caller's profile plus rank info
create or replace function public.get_me() returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; g_rank bigint; n_rank bigint; m_stars bigint;
begin
  p := cb_ensure();
  select count(*) + 1 into g_rank from profiles where legacy > p.legacy;
  select count(*) + 1 into n_rank from profiles where nation = p.nation and legacy > p.legacy;
  select coalesce(sum(delta), 0) into m_stars from star_events where user_id = me and month = cb_month() and kind = 'online';
  return json_build_object('id', p.id, 'name', p.name, 'nation', p.nation, 'legacy', p.legacy, 'legacy_peak', p.legacy_peak,
    'nat_given', p.nat_given, 'rating', p.rating, 'wins', p.wins, 'losses', p.losses, 'draws', p.draws,
    'imported', p.imported, 'global_rank', g_rank, 'nation_rank', case when p.nation is null then null else n_rank end,
    'month_stars', m_stars);
end $$;

-- ---------------------------------------------------------------- nations
-- assigns the nation with the fewest members (ties broken at random); permanent once set
create or replace function public.join_nation() returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; pick text;
begin
  perform pg_advisory_xact_lock(4201);
  p := cb_ensure();
  if p.nation is null then
    select n into pick from (values ('ember'),('tide'),('grove'),('dusk')) v(n)
      left join profiles pr on pr.nation = v.n
      group by n order by count(pr.id), random() limit 1;
    update profiles set nation = pick, nation_at = now(), updated_at = now() where id = me;
  end if;
  return get_me();
end $$;

create or replace function public.get_standings(p_month text default null)
returns table (nation text, stars bigint, members bigint, active bigint)
language sql security definer set search_path = public stable as $$
  with m as (select coalesce(p_month, cb_month()) as month)
  select v.n,
    coalesce((select sum(e.delta) from star_events e, m where e.month = m.month and e.kind = 'online' and e.nation = v.n), 0),
    (select count(*) from profiles pr where pr.nation = v.n),
    (select count(distinct e.user_id) from star_events e, m where e.month = m.month and e.kind = 'online' and e.nation = v.n)
  from (values ('ember'),('tide'),('grove'),('dusk')) v(n)
  order by 2 desc, 3 desc;
$$;

-- top players overall or within a nation, by legacy
create or replace function public.top_players(p_nation text default null, p_limit int default 20)
returns table (id uuid, name text, nation text, legacy int, av text, avc text, wins int)
language sql security definer set search_path = public stable as $$
  select id, name, nation, legacy, av, avc, wins from profiles
  where (p_nation is null or nation = p_nation) and (legacy > 0 or wins > 0)
  order by legacy desc, wins desc, created_at
  limit greatest(1, least(coalesce(p_limit, 20), 100));
$$;

-- this month's top contributors to a nation
create or replace function public.nation_heroes(p_nation text, p_limit int default 10)
returns table (id uuid, name text, stars bigint, av text, avc text, legacy int)
language sql security definer set search_path = public stable as $$
  select p.id, p.name, sum(e.delta) as stars, p.av, p.avc, p.legacy
  from star_events e join profiles p on p.id = e.user_id
  where e.month = cb_month() and e.kind = 'online' and e.nation = p_nation
  group by p.id having sum(e.delta) > 0
  order by stars desc, p.legacy desc
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

-- ---------------------------------------------------------------- results
-- bot and daily games: win +2, draw +1, loss -1, at most 10 stars a day, never counted for a nation
create or replace function public.add_bot_result(p_res text)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; d int; today date := (now() at time zone 'utc')::date;
begin
  p := cb_ensure();
  d := case p_res when 'w' then 2 when 'd' then 1 when 'l' then -1 else 0 end;
  if p.bot_day is distinct from today then p.bot_today := 0; end if;
  if d > 0 then
    if p.last_bot_at is not null and now() - p.last_bot_at < interval '15 seconds' then d := 0; end if;
    d := greatest(0, least(d, 10 - p.bot_today));
  end if;
  d := greatest(d, -p.legacy);
  update profiles set legacy = legacy + d, legacy_peak = greatest(legacy_peak, legacy + d),
    bot_day = today, bot_today = p.bot_today + greatest(d, 0), last_bot_at = now(), updated_at = now()
  where id = me;
  if d <> 0 then insert into star_events (user_id, nation, month, delta, kind) values (me, null, cb_month(), d, 'bot'); end if;
  return json_build_object('delta', d, 'me', get_me());
end $$;

-- online games: both players report; when the two reports agree the stars move once
-- win +5 for the player and their nation, loss -3, draw +1 each
create or replace function public.report_result(p_key text, p_game int, p_white uuid, p_black uuid, p_outcome text)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); other uuid; o match_reports; s settled_matches; pw profiles; pb profiles;
  dw int; db int; pair_today int; v_scored boolean := true; mo text := cb_month();
begin
  if p_key !~ '^[A-Z0-9]{6}$' or p_game < 1 or p_game > 10000 then raise exception 'bad match'; end if;
  if p_outcome not in ('white','black','draw') then raise exception 'bad outcome'; end if;
  if p_white = p_black or me not in (p_white, p_black) then raise exception 'not a player in this match'; end if;
  perform cb_ensure();
  perform pg_advisory_xact_lock(hashtext(p_key || ':' || p_game));
  select * into s from settled_matches where match_key = p_key and game_no = p_game;
  if found then return json_build_object('status', 'settled', 'scored', s.scored, 'outcome', s.outcome, 'me', get_me()); end if;
  insert into match_reports (match_key, game_no, reporter, white, black, outcome)
    values (p_key, p_game, me, p_white, p_black, p_outcome) on conflict do nothing;
  other := case when me = p_white then p_black else p_white end;
  select * into o from match_reports where match_key = p_key and game_no = p_game and reporter = other;
  if not found then return json_build_object('status', 'pending', 'me', get_me()); end if;
  if o.white <> p_white or o.black <> p_black or o.outcome <> p_outcome then
    return json_build_object('status', 'disputed', 'me', get_me());
  end if;
  -- the same two accounts can only score 10 games a day against each other
  select count(*) into pair_today from settled_matches
    where settled_matches.scored and ((white = p_white and black = p_black) or (white = p_black and black = p_white))
      and settled_at > now() - interval '1 day';
  if pair_today >= 10 then v_scored := false; end if;
  insert into settled_matches (match_key, game_no, white, black, outcome, scored) values (p_key, p_game, p_white, p_black, p_outcome, v_scored);
  if v_scored then
    insert into profiles (id) values (p_white), (p_black) on conflict (id) do nothing;
    select * into pw from profiles where id = p_white;
    select * into pb from profiles where id = p_black;
    dw := case p_outcome when 'white' then 5 when 'black' then -3 else 1 end;
    db := case p_outcome when 'black' then 5 when 'white' then -3 else 1 end;
    update profiles set legacy = greatest(0, legacy + dw), legacy_peak = greatest(legacy_peak, legacy + dw), nat_given = nat_given + dw,
      wins = wins + (dw = 5)::int, losses = losses + (dw = -3)::int, draws = draws + (dw = 1)::int, updated_at = now() where id = p_white;
    update profiles set legacy = greatest(0, legacy + db), legacy_peak = greatest(legacy_peak, legacy + db), nat_given = nat_given + db,
      wins = wins + (db = 5)::int, losses = losses + (db = -3)::int, draws = draws + (db = 1)::int, updated_at = now() where id = p_black;
    insert into star_events (user_id, nation, month, delta, kind, match_key) values
      (p_white, pw.nation, mo, dw, 'online', p_key), (p_black, pb.nation, mo, db, 'online', p_key);
  end if;
  return json_build_object('status', 'settled', 'scored', v_scored, 'outcome', p_outcome, 'me', get_me());
end $$;

-- ---------------------------------------------------------------- quick match
-- call every few seconds while searching. Returns {role:'host'} while waiting, or {role:'join', code} when paired.
create or replace function public.find_match(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; mine mm_queue; them mm_queue;
begin
  if p_code !~ '^[A-Z0-9]{6}$' then raise exception 'bad code'; end if;
  perform pg_advisory_xact_lock(4202);
  p := cb_ensure();
  delete from mm_queue where seen_at < now() - interval '20 seconds';
  select * into mine from mm_queue where user_id = me;
  if found and mine.matched_with is not null then
    update mm_queue set seen_at = now() where user_id = me;
    return json_build_object('role', 'host', 'code', mine.code, 'matched', true);
  end if;
  select * into them from mm_queue where user_id <> me and matched_with is null order by created_at limit 1;
  if found then
    update mm_queue set matched_with = me, seen_at = now() where user_id = them.user_id;
    delete from mm_queue where user_id = me;
    return json_build_object('role', 'join', 'code', them.code, 'nation', them.nation, 'rating', them.rating);
  end if;
  insert into mm_queue (user_id, code, nation, rating) values (me, p_code, p.nation, p.rating)
    on conflict (user_id) do update set code = excluded.code, seen_at = now(), matched_with = null;
  return json_build_object('role', 'host', 'code', p_code, 'matched', false,
    'waiting', (select count(*) from mm_queue where matched_with is null));
end $$;

create or replace function public.leave_match_queue() returns void
language sql security definer set search_path = public as $$ delete from mm_queue where user_id = auth.uid(); $$;

-- ---------------------------------------------------------------- permissions
revoke all on function public.cb_ensure() from public, anon;
grant execute on function public.sync_profile(text, text, text, int) to authenticated;
grant execute on function public.import_local(int, text, int) to authenticated;
grant execute on function public.get_me() to authenticated;
grant execute on function public.join_nation() to authenticated;
grant execute on function public.add_bot_result(text) to authenticated;
grant execute on function public.report_result(text, int, uuid, uuid, text) to authenticated;
grant execute on function public.find_match(text) to authenticated;
grant execute on function public.leave_match_queue() to authenticated;
grant execute on function public.get_standings(text) to anon, authenticated;
grant execute on function public.top_players(text, int) to anon, authenticated;
grant execute on function public.nation_heroes(text, int) to anon, authenticated;
