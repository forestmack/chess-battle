-- Chess Battle server setup for Supabase (version 2).
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run.
-- Safe to run again at any time: it only adds what is missing and replaces functions in place.

-- ================================================================ tables
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
alter table public.profiles add column if not exists fcode text;
alter table public.profiles add column if not exists last_seen timestamptz;
alter table public.profiles add column if not exists front text;
alter table public.profiles add column if not exists referred_by uuid;
alter table public.profiles add column if not exists kid boolean not null default false;
create unique index if not exists profiles_fcode_idx on public.profiles (fcode);
create index if not exists profiles_legacy_idx on public.profiles (legacy desc);
create index if not exists profiles_nation_idx on public.profiles (nation, legacy desc);
create index if not exists profiles_ref_idx on public.profiles (referred_by);

-- every star that moves; delta here is what counts for the nation (doubled on war weekends)
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
alter table public.star_events add column if not exists region text;
create index if not exists star_events_month_idx on public.star_events (month, kind, nation);
create index if not exists star_events_user_idx on public.star_events (user_id, month);
create index if not exists star_events_region_idx on public.star_events (month, region);

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

create table if not exists public.mm_queue (
  user_id      uuid primary key references public.profiles(id) on delete cascade,
  code         text not null check (code ~ '^[A-Z0-9]{6}$'),
  nation       text,
  rating       int,
  created_at   timestamptz not null default now(),
  seen_at      timestamptz not null default now(),
  matched_with uuid
);

-- every online game: live games and one-move-a-day games
create table if not exists public.games (
  code         text primary key check (code ~ '^[A-Z0-9]{6}$'),
  kind         text not null default 'live' check (kind in ('live','daily')),
  host         uuid not null references public.profiles(id) on delete cascade,
  guest        uuid references public.profiles(id) on delete set null,
  invitee      uuid references public.profiles(id) on delete set null,
  host_color   int not null default 1 check (host_color in (0,1)),
  status       text not null default 'open' check (status in ('open','active','over','declined')),
  game_no      int not null default 1,
  rev          int not null default 0,
  state        jsonb,
  turn         int,
  tctl         text,
  last_move_at timestamptz not null default now(),
  deadline     timestamptz,
  outcome      text,
  why          text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists games_host_idx on public.games (host, status);
create index if not exists games_guest_idx on public.games (guest, status);
create index if not exists games_invitee_idx on public.games (invitee, status);
create index if not exists games_live_idx on public.games (kind, status, updated_at desc);

create table if not exists public.friends (
  a uuid not null references public.profiles(id) on delete cascade,
  b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a, b)
);

create table if not exists public.rush_scores (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day     date not null,
  score   int not null check (score between 0 and 100),
  primary key (user_id, day)
);
create index if not exists rush_day_idx on public.rush_scores (day, score desc);

create table if not exists public.activity (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day     date not null,
  primary key (user_id, day)
);

-- ================================================================ security
-- public profile fields are readable for leaderboards; every write goes through the functions below
alter table public.profiles        enable row level security;
alter table public.star_events     enable row level security;
alter table public.match_reports   enable row level security;
alter table public.settled_matches enable row level security;
alter table public.mm_queue        enable row level security;
alter table public.games           enable row level security;
alter table public.friends         enable row level security;
alter table public.rush_scores     enable row level security;
alter table public.activity        enable row level security;
drop policy if exists "profiles are public" on public.profiles;
create policy "profiles are public" on public.profiles for select using (true);

-- ================================================================ helpers
create or replace function public.cb_month() returns text
language sql stable as $$ select to_char(now() at time zone 'utc', 'YYYY-MM') $$;

create or replace function public.cb_me() returns uuid
language plpgsql stable as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'not signed in'; end if;
  return u;
end $$;

create or replace function public.cb_weekend() returns boolean
language sql stable as $$ select extract(isodow from now() at time zone 'utc') in (6, 7) $$;

create or replace function public.cb_ensure() returns public.profiles
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; c text;
begin
  insert into profiles (id) values (me) on conflict (id) do nothing;
  select * into p from profiles where id = me;
  if p.fcode is null then
    loop
      c := upper(substr(translate(encode(sha256((me::text || random()::text)::bytea), 'base64'), '+/=0O1Il', ''), 1, 8));
      begin
        update profiles set fcode = c where id = me;
        exit;
      exception when unique_violation then null;
      end;
    end loop;
    select * into p from profiles where id = me;
  end if;
  return p;
end $$;

create or replace function public.cb_name(p profiles) returns text
language sql immutable as $$ select case when p.kid then '' else p.name end $$;

-- ================================================================ profile
create or replace function public.sync_profile(p_name text, p_av text, p_avc text, p_rating int)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me();
begin
  perform cb_ensure();
  update profiles set
    name   = left(coalesce(p_name, ''), 16),
    av     = case when p_av in ('K','Q','R','B','N','P') then p_av else av end,
    avc    = left(coalesce(p_avc, avc), 10),
    rating = greatest(100, least(4000, coalesce(p_rating, rating))),
    updated_at = now()
  where id = me;
  return get_me();
end $$;

create or replace function public.set_kid(p_kid boolean) returns json
language plpgsql security definer set search_path = public as $$
begin perform cb_ensure(); update profiles set kid = coalesce(p_kid, false) where id = cb_me(); return get_me(); end $$;

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

create or replace function public.get_me() returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; g_rank bigint; n_rank bigint; m_stars bigint; recruits bigint;
begin
  p := cb_ensure();
  update profiles set last_seen = now() where id = me;
  insert into activity (user_id, day) values (me, (now() at time zone 'utc')::date) on conflict do nothing;
  select count(*) + 1 into g_rank from profiles where legacy > p.legacy;
  select count(*) + 1 into n_rank from profiles where nation = p.nation and legacy > p.legacy;
  select coalesce(sum(delta), 0) into m_stars from star_events where user_id = me and month = cb_month() and kind = 'online';
  select count(*) into recruits from profiles where referred_by = me;
  return json_build_object('id', p.id, 'name', p.name, 'nation', p.nation, 'legacy', p.legacy, 'legacy_peak', p.legacy_peak,
    'nat_given', p.nat_given, 'rating', p.rating, 'wins', p.wins, 'losses', p.losses, 'draws', p.draws,
    'imported', p.imported, 'global_rank', g_rank, 'nation_rank', case when p.nation is null then null else n_rank end,
    'month_stars', m_stars, 'fcode', p.fcode, 'front', p.front, 'recruits', recruits, 'kid', p.kid, 'weekend', cb_weekend());
end $$;

-- deletes the account and everything tied to it
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare me uuid := cb_me();
begin
  delete from games where host = me;
  delete from profiles where id = me;
  delete from auth.users where id = me;
end $$;

-- ================================================================ nations
-- assigns the nation with the fewest members, or the recruiter's nation when joining through a recruit link
drop function if exists public.join_nation();
create or replace function public.join_nation(p_ref uuid default null) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); p profiles; pick text; r profiles;
begin
  perform pg_advisory_xact_lock(4201);
  p := cb_ensure();
  if p.nation is null then
    if p_ref is not null and p_ref <> me then select * into r from profiles where id = p_ref; end if;
    if r.id is not null and r.nation is not null then
      pick := r.nation;
      update profiles set referred_by = r.id where id = me and referred_by is null;
    else
      select n into pick from (values ('ember'),('tide'),('grove'),('dusk')) v(n)
        left join profiles pr on pr.nation = v.n
        group by n order by count(pr.id), random() limit 1;
    end if;
    update profiles set nation = pick, nation_at = now(), updated_at = now() where id = me;
  end if;
  return get_me();
end $$;

create or replace function public.set_front(p_region text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if p_region !~ '^r[0-9]{2}$' then raise exception 'bad region'; end if;
  perform cb_ensure();
  update profiles set front = p_region where id = cb_me();
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

-- stars per region per nation, for the territory map
create or replace function public.get_map(p_month text default null)
returns table (region text, nation text, stars bigint)
language sql security definer set search_path = public stable as $$
  select region, nation, sum(delta) from star_events
  where month = coalesce(p_month, cb_month()) and kind = 'online' and region is not null and nation is not null
  group by region, nation;
$$;

create or replace function public.top_players(p_nation text default null, p_limit int default 20)
returns table (id uuid, name text, nation text, legacy int, av text, avc text, wins int)
language sql security definer set search_path = public stable as $$
  select p.id, cb_name(p), p.nation, p.legacy, p.av, p.avc, p.wins from profiles p
  where (p_nation is null or p.nation = p_nation) and (p.legacy > 0 or p.wins > 0)
  order by p.legacy desc, p.wins desc, p.created_at
  limit greatest(1, least(coalesce(p_limit, 20), 100));
$$;

drop function if exists public.nation_heroes(text, int);
create or replace function public.nation_heroes(p_nation text, p_limit int default 10, p_month text default null)
returns table (id uuid, name text, stars bigint, av text, avc text, legacy int)
language sql security definer set search_path = public stable as $$
  select p.id, cb_name(p), sum(e.delta) as stars, p.av, p.avc, p.legacy
  from star_events e join profiles p on p.id = e.user_id
  where e.month = coalesce(p_month, cb_month()) and e.kind = 'online' and e.nation = p_nation
  group by p.id having sum(e.delta) > 0
  order by stars desc, p.legacy desc
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

-- ================================================================ results
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

-- moves the stars for a finished online game exactly once.
-- win +5, loss -3, draw +1 for each player's legacy; their nation gets the same, doubled on war weekends.
create or replace function public.cb_settle(p_key text, p_game int, p_white uuid, p_black uuid, p_outcome text)
returns boolean language plpgsql security definer set search_path = public as $$
declare pw profiles; pb profiles; dw int; db int; pair_today int; v_scored boolean := true; mo text := cb_month(); mult int;
begin
  if exists (select 1 from settled_matches where match_key = p_key and game_no = p_game) then return false; end if;
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
    mult := case when cb_weekend() then 2 else 1 end;
    update profiles set legacy = greatest(0, legacy + dw), legacy_peak = greatest(legacy_peak, legacy + dw), nat_given = nat_given + dw * mult,
      wins = wins + (dw = 5)::int, losses = losses + (dw = -3)::int, draws = draws + (dw = 1)::int, updated_at = now() where id = p_white;
    update profiles set legacy = greatest(0, legacy + db), legacy_peak = greatest(legacy_peak, legacy + db), nat_given = nat_given + db * mult,
      wins = wins + (db = 5)::int, losses = losses + (db = -3)::int, draws = draws + (db = 1)::int, updated_at = now() where id = p_black;
    insert into star_events (user_id, nation, month, delta, kind, match_key, region) values
      (p_white, pw.nation, mo, dw * mult, 'online', p_key, pw.front), (p_black, pb.nation, mo, db * mult, 'online', p_key, pb.front);
  end if;
  update games set status = 'over', outcome = p_outcome, updated_at = now() where code = p_key and game_no = p_game and status <> 'over';
  return v_scored;
end $$;
revoke all on function public.cb_settle(text, int, uuid, uuid, text) from public, anon, authenticated;

-- both players report each result; stars move when the two reports agree.
-- for a one-move-a-day game, a lone report settles once the other player has been silent for 3 days.
create or replace function public.report_result(p_key text, p_game int, p_white uuid, p_black uuid, p_outcome text)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); other uuid; o match_reports; s settled_matches; g games; sc boolean;
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
  if not found then
    select * into g from games where code = p_key;
    if g.code is not null and g.kind = 'daily' and g.game_no = p_game and g.last_move_at < now() - interval '3 days' then
      sc := cb_settle(p_key, p_game, p_white, p_black, p_outcome);
      return json_build_object('status', 'settled', 'scored', sc, 'outcome', p_outcome, 'me', get_me());
    end if;
    return json_build_object('status', 'pending', 'me', get_me());
  end if;
  if o.white <> p_white or o.black <> p_black or o.outcome <> p_outcome then
    return json_build_object('status', 'disputed', 'me', get_me());
  end if;
  sc := cb_settle(p_key, p_game, p_white, p_black, p_outcome);
  return json_build_object('status', 'settled', 'scored', sc, 'outcome', p_outcome, 'me', get_me());
end $$;

-- ================================================================ games on the server
create or replace function public.cb_game_json(g games, me uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare h profiles; gu profiles; wid uuid; bid uuid;
begin
  select * into h from profiles where id = g.host;
  if g.guest is not null then select * into gu from profiles where id = g.guest; end if;
  wid := case when g.host_color = 1 then g.host else g.guest end;
  bid := case when g.host_color = 1 then g.guest else g.host end;
  return json_build_object('code', g.code, 'kind', g.kind, 'status', g.status, 'game_no', g.game_no, 'rev', g.rev, 'state', g.state,
    'turn', g.turn, 'tctl', g.tctl, 'host', g.host, 'guest', g.guest, 'invitee', g.invitee, 'host_color', g.host_color,
    'white', wid, 'black', bid, 'outcome', g.outcome, 'why', g.why, 'last_move_at', g.last_move_at, 'deadline', g.deadline,
    'host_name', cb_name(h), 'host_nation', h.nation, 'host_legacy', h.legacy, 'host_rating', h.rating, 'host_av', h.av, 'host_avc', h.avc,
    'guest_name', cb_name(gu), 'guest_nation', gu.nation, 'guest_legacy', gu.legacy, 'guest_rating', gu.rating, 'guest_av', gu.av, 'guest_avc', gu.avc,
    'my_color', case when me = g.host then g.host_color when me = g.guest then 1 - g.host_color else null end,
    'my_turn', case when g.status = 'active' and g.turn is not null and me in (g.host, g.guest)
      then (case when me = g.host then g.host_color else 1 - g.host_color end) = g.turn else false end,
    'updated_at', g.updated_at);
end $$;

create or replace function public.host_game(p_code text, p_kind text, p_tctl text, p_invitee uuid default null, p_state jsonb default null)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); g games;
begin
  if p_code !~ '^[A-Z0-9]{6}$' then raise exception 'bad code'; end if;
  if p_kind not in ('live','daily') then raise exception 'bad kind'; end if;
  perform cb_ensure();
  insert into games (code, kind, host, invitee, tctl, state, turn, deadline)
    values (p_code, p_kind, me, case when p_invitee = me then null else p_invitee end, left(p_tctl, 8), p_state, 1,
      case when p_kind = 'daily' then now() + interval '3 days' end)
  on conflict (code) do update set updated_at = now() where games.host = me
  returning * into g;
  if g.code is null then raise exception 'code taken'; end if;
  return cb_game_json(g, me);
end $$;

create or replace function public.join_game(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); g games;
begin
  perform cb_ensure();
  select * into g from games where code = upper(p_code) for update;
  if not found then raise exception 'game not found'; end if;
  if me in (g.host, g.guest) then return cb_game_json(g, me); end if;
  if g.guest is not null or g.status not in ('open') then raise exception 'game full'; end if;
  if g.invitee is not null and g.invitee <> me then raise exception 'not invited'; end if;
  update games set guest = me, status = 'active', last_move_at = now(), updated_at = now(),
    deadline = case when kind = 'daily' then now() + interval '3 days' else deadline end
  where code = g.code returning * into g;
  return cb_game_json(g, me);
end $$;

create or replace function public.decline_game(p_code text) returns void
language sql security definer set search_path = public as $$
  update games set status = 'declined', updated_at = now() where code = upper(p_code) and invitee = auth.uid() and status = 'open';
$$;

-- saves the latest position; newer game numbers and revisions win
create or replace function public.push_state(p_code text, p_game_no int, p_rev int, p_state jsonb, p_turn int, p_host_color int, p_over boolean default false)
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); g games;
begin
  select * into g from games where code = p_code for update;
  if not found or me not in (g.host, coalesce(g.guest, g.host)) then return false; end if;
  if p_game_no < g.game_no or (p_game_no = g.game_no and p_rev <= g.rev) then return false; end if;
  if octet_length(p_state::text) > 200000 then return false; end if;
  update games set state = p_state, rev = p_rev, game_no = p_game_no, turn = p_turn, host_color = coalesce(p_host_color, host_color),
    status = case when p_over then 'over' when guest is not null then 'active' else status end,
    outcome = case when p_game_no > g.game_no then null else outcome end,
    last_move_at = now(), updated_at = now(),
    deadline = case when kind = 'daily' then now() + interval '3 days' else deadline end
  where code = p_code;
  update profiles set last_seen = now() where id = me;
  return true;
end $$;

create or replace function public.get_game(p_code text) returns json
language plpgsql security definer set search_path = public stable as $$
declare g games;
begin
  select * into g from games where code = upper(p_code);
  if not found then return null; end if;
  return cb_game_json(g, auth.uid());
end $$;

-- the caller's one-move-a-day games and pending invitations
create or replace function public.my_games() returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me();
begin
  return coalesce((select json_agg(cb_game_json(g, me) order by g.updated_at desc) from games g
    where (g.host = me or g.guest = me or (g.invitee = me and g.status = 'open'))
      and ((g.kind = 'daily' and (g.status in ('open','active') or (g.status = 'over' and g.updated_at > now() - interval '7 days')))
        or (g.kind = 'live' and g.status = 'open' and g.invitee = me and g.updated_at > now() - interval '10 minutes'))), '[]'::json);
end $$;

-- games being played right now, best players first, for spectators
create or replace function public.live_games(p_limit int default 12) returns json
language sql security definer set search_path = public stable as $$
  select coalesce(json_agg(x), '[]'::json) from (
    select cb_game_json(g, null) as x from games g
      join profiles h on h.id = g.host left join profiles gu on gu.id = g.guest
    where g.kind = 'live' and g.status = 'active' and g.updated_at > now() - interval '3 minutes'
    order by greatest(h.legacy, coalesce(gu.legacy, 0)) desc
    limit greatest(1, least(coalesce(p_limit, 12), 50))) t;
$$;

-- the opponent stopped moving: claim the win
-- live games: 2 minutes without a move on their turn. one-move-a-day games: their 3-day deadline has passed.
create or replace function public.claim_timeout(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); g games; mycol int; wid uuid; bid uuid; oc text; sc boolean;
begin
  select * into g from games where code = p_code for update;
  if not found or g.status <> 'active' or g.guest is null or me not in (g.host, g.guest) then raise exception 'cannot claim'; end if;
  mycol := case when me = g.host then g.host_color else 1 - g.host_color end;
  if g.turn is null or g.turn = mycol then raise exception 'it is your turn'; end if;
  if (g.kind = 'live' and g.last_move_at > now() - interval '2 minutes') or (g.kind = 'daily' and coalesce(g.deadline, now()) > now()) then
    raise exception 'too early';
  end if;
  wid := case when g.host_color = 1 then g.host else g.guest end;
  bid := case when g.host_color = 1 then g.guest else g.host end;
  oc := case when mycol = 1 then 'white' else 'black' end;
  update games set status = 'over', outcome = oc, why = 'Abandoned', updated_at = now() where code = p_code;
  sc := cb_settle(p_code, g.game_no, wid, bid, oc);
  return json_build_object('outcome', oc, 'scored', sc, 'me', get_me());
end $$;

-- ================================================================ friends
create or replace function public.add_friend(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); f profiles;
begin
  perform cb_ensure();
  select * into f from profiles where fcode = upper(trim(p_code));
  if not found then raise exception 'no player with that code'; end if;
  if f.id = me then raise exception 'that is your own code'; end if;
  insert into friends (a, b) values (me, f.id), (f.id, me) on conflict do nothing;
  return json_build_object('id', f.id, 'name', cb_name(f));
end $$;

create or replace function public.remove_friend(p_id uuid) returns void
language sql security definer set search_path = public as $$
  delete from friends where (a = auth.uid() and b = p_id) or (b = auth.uid() and a = p_id);
$$;

create or replace function public.list_friends() returns json
language sql security definer set search_path = public stable as $$
  select coalesce(json_agg(json_build_object('id', p.id, 'name', cb_name(p), 'nation', p.nation, 'legacy', p.legacy, 'av', p.av, 'avc', p.avc,
    'rating', p.rating, 'online', coalesce(p.last_seen > now() - interval '3 minutes', false), 'last_seen', p.last_seen)
    order by p.last_seen desc nulls last), '[]'::json)
  from friends f join profiles p on p.id = f.b where f.a = auth.uid();
$$;

-- ================================================================ puzzle rush
create or replace function public.submit_rush(p_score int) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := cb_me(); d date := (now() at time zone 'utc')::date; best int;
begin
  perform cb_ensure();
  insert into rush_scores (user_id, day, score) values (me, d, greatest(0, least(coalesce(p_score, 0), 100)))
    on conflict (user_id, day) do update set score = greatest(rush_scores.score, excluded.score);
  select max(score) into best from rush_scores where user_id = me;
  return json_build_object('today', (select score from rush_scores where user_id = me and day = d), 'best', best);
end $$;

create or replace function public.rush_board(p_today boolean default true, p_limit int default 20) returns json
language sql security definer set search_path = public stable as $$
  select coalesce(json_agg(x order by (x->>'score')::int desc), '[]'::json) from (
    select json_build_object('id', p.id, 'name', cb_name(p), 'nation', p.nation, 'av', p.av, 'avc', p.avc, 'score', max(r.score)) as x
    from rush_scores r join profiles p on p.id = r.user_id
    where (not p_today) or r.day = (now() at time zone 'utc')::date
    group by p.id order by max(r.score) desc limit greatest(1, least(coalesce(p_limit, 20), 50))) t;
$$;

-- ================================================================ quick match
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

-- ================================================================ retention report (run in the SQL editor, not public)
create or replace view public.retention_report as
  with first as (select user_id, min(day) as d0 from activity group by user_id)
  select f.d0 as first_day, count(*) as new_players,
    round(100.0 * count(*) filter (where exists (select 1 from activity a where a.user_id = f.user_id and a.day = f.d0 + 1)) / count(*), 1) as day1_pct,
    round(100.0 * count(*) filter (where exists (select 1 from activity a where a.user_id = f.user_id and a.day = f.d0 + 7)) / count(*), 1) as day7_pct,
    round(100.0 * count(*) filter (where exists (select 1 from activity a where a.user_id = f.user_id and a.day = f.d0 + 30)) / count(*), 1) as day30_pct
  from first f group by f.d0 order by f.d0 desc;
revoke all on public.retention_report from anon, authenticated;

-- ================================================================ permissions
revoke all on function public.cb_ensure() from public, anon;
grant execute on function public.sync_profile(text, text, text, int) to authenticated;
grant execute on function public.set_kid(boolean) to authenticated;
grant execute on function public.import_local(int, text, int) to authenticated;
grant execute on function public.get_me() to authenticated;
grant execute on function public.delete_account() to authenticated;
grant execute on function public.join_nation(uuid) to authenticated;
grant execute on function public.set_front(text) to authenticated;
grant execute on function public.add_bot_result(text) to authenticated;
grant execute on function public.report_result(text, int, uuid, uuid, text) to authenticated;
grant execute on function public.host_game(text, text, text, uuid, jsonb) to authenticated;
grant execute on function public.join_game(text) to authenticated;
grant execute on function public.decline_game(text) to authenticated;
grant execute on function public.push_state(text, int, int, jsonb, int, int, boolean) to authenticated;
grant execute on function public.my_games() to authenticated;
grant execute on function public.claim_timeout(text) to authenticated;
grant execute on function public.add_friend(text) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.list_friends() to authenticated;
grant execute on function public.submit_rush(int) to authenticated;
grant execute on function public.find_match(text) to authenticated;
grant execute on function public.leave_match_queue() to authenticated;
grant execute on function public.get_game(text) to anon, authenticated;
grant execute on function public.live_games(int) to anon, authenticated;
grant execute on function public.get_standings(text) to anon, authenticated;
grant execute on function public.get_map(text) to anon, authenticated;
grant execute on function public.top_players(text, int) to anon, authenticated;
grant execute on function public.nation_heroes(text, int, text) to anon, authenticated;
grant execute on function public.rush_board(boolean, int) to anon, authenticated;
