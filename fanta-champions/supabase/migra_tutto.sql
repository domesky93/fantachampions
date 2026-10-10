-- ============================================================
-- FANTA CHAMPIONS - SCRIPT COMPLETO MIGRAZIONE
-- Incolla tutto questo nel SQL Editor del tuo progetto Supabase
-- (zjogufgufuimhrvzonwi) e clicca RUN
-- ============================================================

-- === 01 SCHEMA ===
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null unique check (char_length(username) between 3 and 24),
  team_name   text check (char_length(team_name) <= 40),
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_name text := coalesce(nullif(trim(new.raw_user_meta_data->>'username'), ''),
                          split_part(new.email, '@', 1));
begin
  if exists (select 1 from public.profiles where username = v_name) then
    v_name := left(v_name, 18) || '_' || substr(md5(new.id::text), 1, 4);
  end if;
  insert into public.profiles (id, username, team_name)
  values (new.id, v_name, coalesce(new.raw_user_meta_data->>'team_name', 'FC ' || v_name));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create table if not exists public.clubs (
  id       serial primary key,
  name     text not null unique,
  short    text,
  country  text
);

create table if not exists public.players (
  id       serial primary key,
  name     text not null,
  role     char(1) not null check (role in ('P','D','C','A')),
  club_id  int not null references public.clubs(id) on delete cascade,
  price    int not null default 10 check (price >= 1),
  active   boolean not null default true,
  unique (name, club_id)
);
create index if not exists players_club_idx on public.players(club_id);

create table if not exists public.matchdays (
  id        serial primary key,
  number    int not null unique,
  name      text not null,
  deadline  timestamptz not null,
  status    text not null default 'aperta' check (status in ('aperta','chiusa','calcolata'))
);

create table if not exists public.settings (
  id             int primary key default 1 check (id = 1),
  budget         int default 300,
  max_per_club   int default 3,
  max_subs       int not null default 3,
  bonus          jsonb not null default '{
     "gol": 3, "assist": 1, "ammonizione": -0.5, "espulsione": -1,
     "rigore_parato": 3, "rigore_sbagliato": -3, "autogol": -2,
     "gol_subito": -1, "porta_inviolata": 1
  }'::jsonb
);
insert into public.settings (id) values (1) on conflict do nothing;

create table if not exists public.leagues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 3 and 40),
  code        text not null unique,
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table if not exists public.league_members (
  league_id  uuid not null references public.leagues(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (league_id, user_id)
);

create or replace function public.is_league_member(p_league uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.league_members
                 where league_id = p_league and user_id = auth.uid());
$$;

create table if not exists public.lineups (
  id           serial primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  matchday_id  int  not null references public.matchdays(id) on delete cascade,
  module       text not null,
  updated_at   timestamptz not null default now(),
  unique (user_id, matchday_id)
);

create table if not exists public.lineup_players (
  lineup_id   int not null references public.lineups(id) on delete cascade,
  player_id   int not null references public.players(id) on delete cascade,
  slot        smallint not null check (slot between 1 and 18),
  primary key (lineup_id, player_id),
  unique (lineup_id, slot)
);

create table if not exists public.votes (
  matchday_id       int not null references public.matchdays(id) on delete cascade,
  player_id         int not null references public.players(id) on delete cascade,
  voto              numeric(3,1) check (voto between 0 and 10),
  gol               smallint not null default 0,
  assist            smallint not null default 0,
  ammonizione       boolean  not null default false,
  espulsione        boolean  not null default false,
  rigori_parati     smallint not null default 0,
  rigori_sbagliati  smallint not null default 0,
  autogol           smallint not null default 0,
  gol_subiti        smallint not null default 0,
  primary key (matchday_id, player_id)
);

create table if not exists public.results (
  lineup_id    int primary key references public.lineups(id) on delete cascade,
  matchday_id  int not null references public.matchdays(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  total        numeric(6,1) not null,
  detail       jsonb not null,
  computed_at  timestamptz not null default now()
);
create index if not exists results_md_idx on public.results(matchday_id);

-- === 02 FUNCTIONS ===
create or replace function public.module_counts(p_module text)
returns table (d int, c int, a int) language sql immutable as $$
  select m.d, m.c, m.a from (values
    ('3-4-3',3,4,3), ('3-5-2',3,5,2), ('4-3-3',4,3,3), ('4-4-2',4,4,2),
    ('4-5-1',4,5,1), ('5-3-2',5,3,2), ('5-4-1',5,4,1)
  ) as m(module,d,c,a) where m.module = p_module;
$$;

create or replace function public.save_lineup(p_matchday int, p_module text, p_players jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_md  record;
  v_set record;
  v_mod record;
  v_lineup int;
  v_bad int;
  v_cost int;
  v_club_max int;
  v_paid boolean;
begin
  if v_uid is null then raise exception 'Devi accedere per salvare la formazione'; end if;

  select subscription_paid into v_paid from public.profiles where id = v_uid;
  if not coalesce(v_paid, false) then
    raise exception 'Abbonamento necessario: paga 25€ dal tuo profilo per schierare la formazione';
  end if;

  select * into v_md from matchdays where id = p_matchday;
  if not found then raise exception 'Giornata inesistente'; end if;
  if v_md.status <> 'aperta' or now() >= v_md.deadline then
    raise exception 'Formazioni chiuse per questa giornata';
  end if;

  select * into v_mod from module_counts(p_module);
  if not found then raise exception 'Modulo non valido: %', p_module; end if;

  create temp table if not exists _lp (player_id int, slot int, role char(1), club_id int, price int, active boolean) on commit drop;
  truncate _lp;
  insert into _lp (player_id, slot)
  select (e->>'player_id')::int, (e->>'slot')::int from jsonb_array_elements(p_players) e;

  update _lp set role = p.role, club_id = p.club_id, price = p.price, active = p.active
  from players p where p.id = _lp.player_id;

  if (select count(*) from _lp) <> 18 then
    raise exception 'Servono 11 titolari e 7 panchinari (18 giocatori)';
  end if;
  if (select count(distinct player_id) from _lp) <> 18 or (select count(distinct slot) from _lp) <> 18 then
    raise exception 'Giocatori o posizioni duplicati';
  end if;
  if exists (select 1 from _lp where role is null or not active) then
    raise exception 'Uno o più giocatori non sono disponibili';
  end if;
  if exists (select 1 from _lp where slot not between 1 and 18) then
    raise exception 'Posizione non valida';
  end if;

  select count(*) into v_bad from _lp where
       (slot = 1 and role <> 'P')
    or (slot between 2 and 1 + v_mod.d and role <> 'D')
    or (slot between 2 + v_mod.d and 1 + v_mod.d + v_mod.c and role <> 'C')
    or (slot between 2 + v_mod.d + v_mod.c and 11 and role <> 'A')
    or (slot = 12 and role <> 'P')
    or (slot in (13,14) and role <> 'D')
    or (slot in (15,16) and role <> 'C')
    or (slot in (17,18) and role <> 'A');
  if v_bad > 0 then raise exception 'I ruoli non corrispondono al modulo %', p_module; end if;

  select * into v_set from settings where id = 1;
  select coalesce(sum(price),0) into v_cost from _lp;
  if v_set.budget is not null and v_cost > v_set.budget then
    raise exception 'Budget superato: % crediti su %', v_cost, v_set.budget;
  end if;
  select coalesce(max(n),0) into v_club_max from (select count(*) n from _lp group by club_id) t;
  if v_set.max_per_club is not null and v_club_max > v_set.max_per_club then
    raise exception 'Massimo % giocatori della stessa squadra', v_set.max_per_club;
  end if;

  insert into lineups (user_id, matchday_id, module, updated_at)
  values (v_uid, p_matchday, p_module, now())
  on conflict (user_id, matchday_id) do update set module = excluded.module, updated_at = now()
  returning id into v_lineup;

  delete from lineup_players where lineup_id = v_lineup;
  insert into lineup_players (lineup_id, player_id, slot) select v_lineup, player_id, slot from _lp;

  return v_lineup;
end $$;

create or replace function public.fantavoto(v public.votes, p_role char, b jsonb)
returns numeric language sql immutable as $$
  select case when v.voto is null then null else
      v.voto
    + v.gol              * (b->>'gol')::numeric
    + v.assist           * (b->>'assist')::numeric
    + (case when v.ammonizione then (b->>'ammonizione')::numeric else 0 end)
    + (case when v.espulsione  then (b->>'espulsione')::numeric  else 0 end)
    + v.rigori_parati    * (b->>'rigore_parato')::numeric
    + v.rigori_sbagliati * (b->>'rigore_sbagliato')::numeric
    + v.autogol          * (b->>'autogol')::numeric
    + (case when p_role = 'P' then
          v.gol_subiti * (b->>'gol_subito')::numeric
        + (case when v.gol_subiti = 0 then (b->>'porta_inviolata')::numeric else 0 end)
       else 0 end)
  end;
$$;

create or replace function public.calc_matchday(p_matchday int)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_set record;
  v_lineup record;
  v_starter record;
  v_sub record;
  v_used int[];
  v_subs int;
  v_total numeric;
  v_detail jsonb;
  v_count int := 0;
begin
  if not is_admin() then raise exception 'Solo l''amministratore può calcolare la giornata'; end if;
  select * into v_set from settings where id = 1;

  delete from results where matchday_id = p_matchday;

  for v_lineup in select * from lineups where matchday_id = p_matchday loop
    v_used := array[]::int[]; v_subs := 0; v_total := 0; v_detail := '[]'::jsonb;

    create temp table if not exists _w (slot int, player_id int, name text, role char(1), voto numeric, fv numeric) on commit drop;
    truncate _w;
    insert into _w
    select lp.slot, p.id, p.name, p.role, v.voto, fantavoto(v, p.role, v_set.bonus)
    from lineup_players lp
    join players p on p.id = lp.player_id
    left join votes v on v.player_id = p.id and v.matchday_id = p_matchday
    where lp.lineup_id = v_lineup.id;

    for v_starter in select * from _w where slot <= 11 order by slot loop
      if v_starter.fv is not null then
        v_total := v_total + v_starter.fv;
        v_detail := v_detail || jsonb_build_object('slot', v_starter.slot, 'player_id', v_starter.player_id,
          'name', v_starter.name, 'role', v_starter.role, 'voto', v_starter.voto, 'fv', v_starter.fv, 'status', 'titolare');
      else
        v_sub := null;
        if v_subs < v_set.max_subs then
          select * into v_sub from _w
          where slot > 11 and role = v_starter.role and fv is not null and not (slot = any(v_used))
          order by slot limit 1;
        end if;
        v_detail := v_detail || jsonb_build_object('slot', v_starter.slot, 'player_id', v_starter.player_id,
          'name', v_starter.name, 'role', v_starter.role, 'voto', null, 'fv', null,
          'status', case when v_sub.slot is not null then 'sostituito' else 'senza_voto' end);
        if v_sub.slot is not null then
          v_used := v_used || v_sub.slot; v_subs := v_subs + 1;
          v_total := v_total + v_sub.fv;
          v_detail := v_detail || jsonb_build_object('slot', v_sub.slot, 'player_id', v_sub.player_id,
            'name', v_sub.name, 'role', v_sub.role, 'voto', v_sub.voto, 'fv', v_sub.fv,
            'status', 'entrato', 'for_slot', v_starter.slot);
        end if;
      end if;
    end loop;

    for v_sub in select * from _w where slot > 11 and not (slot = any(v_used)) order by slot loop
      v_detail := v_detail || jsonb_build_object('slot', v_sub.slot, 'player_id', v_sub.player_id,
        'name', v_sub.name, 'role', v_sub.role, 'voto', v_sub.voto, 'fv', v_sub.fv, 'status', 'panchina');
    end loop;

    insert into results (lineup_id, matchday_id, user_id, total, detail)
    values (v_lineup.id, p_matchday, v_lineup.user_id, v_total, v_detail);
    v_count := v_count + 1;
  end loop;

  update matchdays set status = 'calcolata' where id = p_matchday;
  return v_count;
end $$;

create or replace function public.create_league(p_name text)
returns public.leagues language plpgsql security definer set search_path = public as $$
declare v_l leagues; v_code text;
begin
  if auth.uid() is null then raise exception 'Devi accedere'; end if;
  loop
    v_code := upper(substr(translate(encode(gen_random_bytes(6), 'base64'), '+/=0O1Il', ''), 1, 6));
    exit when char_length(v_code) = 6 and not exists (select 1 from leagues where code = v_code);
  end loop;
  insert into leagues (name, code, owner_id) values (trim(p_name), v_code, auth.uid()) returning * into v_l;
  insert into league_members (league_id, user_id) values (v_l.id, auth.uid());
  return v_l;
end $$;

create or replace function public.join_league(p_code text)
returns public.leagues language plpgsql security definer set search_path = public as $$
declare v_l leagues;
begin
  if auth.uid() is null then raise exception 'Devi accedere'; end if;
  select * into v_l from leagues where code = upper(trim(p_code));
  if not found then raise exception 'Codice lega non trovato'; end if;
  insert into league_members (league_id, user_id) values (v_l.id, auth.uid()) on conflict do nothing;
  return v_l;
end $$;

create or replace function public.leave_league(p_league uuid)
returns void language sql security definer set search_path = public as $$
  delete from league_members where league_id = p_league and user_id = auth.uid();
$$;

drop view if exists public.standings;
create or replace view public.standings with (security_invoker = true) as
select p.id as user_id, p.username, p.team_name,
       coalesce(sum(r.total), 0)::numeric(7,1) as total,
       count(r.lineup_id)::int as played,
       coalesce(max(r.total), 0)::numeric(6,1) as best
from profiles p
left join results r on r.user_id = p.id
group by p.id, p.username, p.team_name;

-- === 03 SECURITY ===
alter table public.profiles        enable row level security;
alter table public.clubs           enable row level security;
alter table public.players         enable row level security;
alter table public.matchdays       enable row level security;
alter table public.settings        enable row level security;
alter table public.leagues         enable row level security;
alter table public.league_members  enable row level security;
alter table public.lineups         enable row level security;
alter table public.lineup_players  enable row level security;
alter table public.votes           enable row level security;
alter table public.results         enable row level security;

drop policy if exists "profili leggibili" on public.profiles;
create policy "profili leggibili" on public.profiles for select to authenticated using (true);
drop policy if exists "modifica proprio profilo" on public.profiles;
create policy "modifica proprio profilo" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated, anon;
grant update (username, team_name) on public.profiles to authenticated;

do $$
declare t text;
begin
  foreach t in array array['clubs','players','matchdays','settings','votes'] loop
    execute format('drop policy if exists "lettura" on public.%I', t);
    execute format('create policy "lettura" on public.%I for select to authenticated using (true)', t);
    execute format('drop policy if exists "admin scrive" on public.%I', t);
    execute format('create policy "admin scrive" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

drop policy if exists "membri vedono lega" on public.leagues;
create policy "membri vedono lega" on public.leagues for select to authenticated
  using (public.is_league_member(id));
drop policy if exists "owner modifica lega" on public.leagues;
create policy "owner modifica lega" on public.leagues for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "owner elimina lega" on public.leagues;
create policy "owner elimina lega" on public.leagues for delete to authenticated
  using (owner_id = auth.uid());

drop policy if exists "membri vedono membri" on public.league_members;
create policy "membri vedono membri" on public.league_members for select to authenticated
  using (public.is_league_member(league_id));

drop policy if exists "vedi formazioni" on public.lineups;
create policy "vedi formazioni" on public.lineups for select to authenticated
  using (user_id = auth.uid()
      or exists (select 1 from public.matchdays m where m.id = matchday_id and m.deadline <= now()));

drop policy if exists "vedi giocatori formazione" on public.lineup_players;
create policy "vedi giocatori formazione" on public.lineup_players for select to authenticated
  using (exists (select 1 from public.lineups l where l.id = lineup_id));

drop policy if exists "risultati leggibili" on public.results;
create policy "risultati leggibili" on public.results for select to authenticated using (true);

revoke execute on function public.save_lineup(int, text, jsonb) from anon, public;
revoke execute on function public.calc_matchday(int) from anon, public;
revoke execute on function public.create_league(text) from anon, public;
revoke execute on function public.join_league(text) from anon, public;
revoke execute on function public.leave_league(uuid) from anon, public;
grant execute on function public.save_lineup(int, text, jsonb) to authenticated;
grant execute on function public.calc_matchday(int) to authenticated;
grant execute on function public.create_league(text) to authenticated;
grant execute on function public.join_league(text) to authenticated;
grant execute on function public.leave_league(uuid) to authenticated;
grant select on public.standings to authenticated;

-- === 04 SEED ===
insert into public.clubs (name, short, country) values
 ('Paris Saint-Germain','PSG','FRA'), ('Bayern Monaco','BAY','GER'), ('Real Madrid','RMA','ESP'),
 ('Liverpool','LIV','ENG'), ('Inter','INT','ITA'), ('Manchester City','MCI','ENG'),
 ('Arsenal','ARS','ENG'), ('Barcellona','BAR','ESP'), ('Atlético Madrid','ATM','ESP'),
 ('Borussia Dortmund','BVB','GER'), ('Roma','ROM','ITA'), ('Sporting CP','SCP','POR'),
 ('Aston Villa','AVL','ENG'), ('Porto','POR','POR'), ('Manchester United','MUN','ENG'),
 ('Club Brugge','BRU','BEL'), ('Real Betis','BET','ESP'), ('PSV Eindhoven','PSV','NED'),
 ('Feyenoord','FEY','NED'), ('Lille','LIL','FRA'), ('Bodø/Glimt','BOD','NOR'),
 ('Napoli','NAP','ITA'), ('RB Lipsia','RBL','GER'), ('Villarreal','VIL','ESP'),
 ('Fenerbahçe','FEN','TUR'), ('Shakhtar Donetsk','SHA','UKR'), ('Galatasaray','GAL','TUR'),
 ('Slavia Praga','SLA','CZE'), ('Slovan Bratislava','SLO','SVK'), ('Stoccarda','STU','GER'),
 ('AEK Atene','AEK','GRE'), ('LASK','LAS','AUT'), ('Como','COM','ITA'),
 ('Lens','RCL','FRA'), ('Viking','VIK','NOR'), ('Sabah','SAB','AZE')
on conflict (name) do nothing;

insert into public.matchdays (number, name, deadline, status) values
 (1, '1ª giornata', '2026-09-08 18:45+02', 'chiusa'),
 (2, '2ª giornata', '2026-10-13 18:45+02', 'aperta'),
 (3, '3ª giornata', '2026-10-20 18:45+02', 'aperta'),
 (4, '4ª giornata', '2026-11-03 18:45+01', 'aperta'),
 (5, '5ª giornata', '2026-11-24 18:45+01', 'aperta'),
 (6, '6ª giornata', '2026-12-08 18:45+01', 'aperta'),
 (7, '7ª giornata', '2027-01-19 18:45+01', 'aperta'),
 (8, '8ª giornata', '2027-01-27 21:00+01', 'aperta')
on conflict (number) do nothing;

alter table public.players add column if not exists photo_url    text;
alter table public.players add column if not exists photo_credit text;
alter table public.players add column if not exists photo_page   text;

create or replace function public.set_player_photos(p_rows jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_admin() then raise exception 'Solo l''amministratore può modificare le foto'; end if;
  update players p set photo_url = r.photo_url, photo_credit = r.photo_credit, photo_page = r.photo_page
  from jsonb_to_recordset(p_rows) as r(id int, photo_url text, photo_credit text, photo_page text)
  where p.id = r.id;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.set_player_photos(jsonb) from anon, public;
grant execute on function public.set_player_photos(jsonb) to authenticated;

-- === 05 PLAYERS ===
insert into public.players (name, role, club_id, price)
select v.name, v.role, c.id, v.price from (values
  ('Thomas Strakosha', 'P', 'AEK Atene', 4),
  ('Marios Balamotis', 'P', 'AEK Atene', 2),
  ('Alberto Brignoli', 'P', 'AEK Atene', 2),
  ('Harold Moukoudi', 'D', 'AEK Atene', 5),
  ('Stavros Pilios', 'D', 'AEK Atene', 5),
  ('Lazaros Rota', 'D', 'AEK Atene', 5),
  ('Domagoj Vida', 'D', 'AEK Atene', 5),
  ('Filipe Relvas', 'D', 'AEK Atene', 5),
  ('Christos Alexiou', 'D', 'AEK Atene', 3),
  ('Martin Georgiev', 'D', 'AEK Atene', 3),
  ('Stavros Psyropoulos', 'D', 'AEK Atene', 3),
  ('Spyros Christakopoulos', 'D', 'AEK Atene', 3),
  ('Charalampos Lykogiannis', 'D', 'AEK Atene', 3),
  ('Lovro Majer', 'C', 'AEK Atene', 9),
  ('Răzvan Marin', 'C', 'AEK Atene', 9),
  ('Kaan Kairinen', 'C', 'AEK Atene', 6),
  ('Mijat Gaćinović', 'C', 'AEK Atene', 6),
  ('Kervin Arriaga', 'C', 'AEK Atene', 6),
  ('Petros Mantalos', 'C', 'AEK Atene', 6),
  ('Dimitris Kaloskamis', 'C', 'AEK Atene', 3),
  ('Hakim Sahabo', 'C', 'AEK Atene', 3),
  ('Milán Vitális', 'C', 'AEK Atene', 3),
  ('Luka Jović', 'A', 'AEK Atene', 11),
  ('Oleksandr Zubkov', 'A', 'AEK Atene', 11),
  ('Aboubakary Koïta', 'A', 'AEK Atene', 11),
  ('Dereck Kutesa', 'A', 'AEK Atene', 7),
  ('Barnabás Varga', 'A', 'AEK Atene', 7),
  ('Zois Karargyris', 'A', 'AEK Atene', 4),
  ('Zini', 'A', 'AEK Atene', 4),
  ('David Raya', 'P', 'Arsenal', 16),
  ('Kepa Arrizabalaga', 'P', 'Arsenal', 2),
  ('Illan Meslier', 'P', 'Arsenal', 2),
  ('Tommy Setford', 'P', 'Arsenal', 2),
  ('William Saliba', 'D', 'Arsenal', 18),
  ('Gabriel Magalhães', 'D', 'Arsenal', 18),
  ('Jurriën Timber', 'D', 'Arsenal', 18),
  ('Cristhian Mosquera', 'D', 'Arsenal', 12),
  ('Ben White', 'D', 'Arsenal', 12),
  ('Piero Hincapié', 'D', 'Arsenal', 12),
  ('Ezri Konsa', 'D', 'Arsenal', 12),
  ('Riccardo Calafiori', 'D', 'Arsenal', 12),
  ('Myles Lewis-Skelly', 'D', 'Arsenal', 12),
  ('Martin Ødegaard', 'C', 'Arsenal', 31),
  ('Eberechi Eze', 'C', 'Arsenal', 31),
  ('Declan Rice', 'C', 'Arsenal', 31),
  ('Martín Zubimendi', 'C', 'Arsenal', 22),
  ('Bruno Guimarães', 'C', 'Arsenal', 22),
  ('Mikel Merino', 'C', 'Arsenal', 14),
  ('Fábio Vieira', 'C', 'Arsenal', 9),
  ('Bukayo Saka', 'A', 'Arsenal', 50),
  ('Viktor Gyökeres', 'A', 'Arsenal', 36),
  ('Gabriel Martinelli', 'A', 'Arsenal', 26),
  ('Noni Madueke', 'A', 'Arsenal', 26),
  ('Kai Havertz', 'A', 'Arsenal', 26),
  ('Gabriel Jesus', 'A', 'Arsenal', 17),
  ('Christos Tzolis', 'A', 'Arsenal', 17),
  ('Max Dowman', 'A', 'Arsenal', 11),
  ('Zion Suzuki', 'P', 'Aston Villa', 10),
  ('Marco Bizot', 'P', 'Aston Villa', 2),
  ('James Wright', 'P', 'Aston Villa', 2),
  ('Matty Cash', 'D', 'Aston Villa', 8),
  ('Victor Lindelöf', 'D', 'Aston Villa', 8),
  ('Taylor Harwood-Bellis', 'D', 'Aston Villa', 8),
  ('Tyrone Mings', 'D', 'Aston Villa', 8),
  ('Matteo Ruggeri', 'D', 'Aston Villa', 8),
  ('Pau Torres', 'D', 'Aston Villa', 8),
  ('Ian Maatsen', 'D', 'Aston Villa', 8),
  ('Aaron Wan-Bissaka', 'D', 'Aston Villa', 8),
  ('Modou Kéba Cissé', 'D', 'Aston Villa', 5),
  ('Travis Patterson', 'D', 'Aston Villa', 5),
  ('John McGinn', 'C', 'Aston Villa', 14),
  ('Boubacar Kamara', 'C', 'Aston Villa', 14),
  ('Emiliano Buendía', 'C', 'Aston Villa', 14),
  ('Amadou Onana', 'C', 'Aston Villa', 14),
  ('Leon Goretzka', 'C', 'Aston Villa', 14),
  ('João Gomes', 'C', 'Aston Villa', 14),
  ('Ross Barkley', 'C', 'Aston Villa', 9),
  ('Lamare Bogarde', 'C', 'Aston Villa', 9),
  ('Johan Manzambi', 'C', 'Aston Villa', 9),
  ('Jamaldeen Jimoh-Aloba', 'C', 'Aston Villa', 6),
  ('Fletcher Boyd', 'C', 'Aston Villa', 6),
  ('Nicolas Jackson', 'A', 'Aston Villa', 17),
  ('Alejandro Garnacho', 'A', 'Aston Villa', 17),
  ('Tammy Abraham', 'A', 'Aston Villa', 17),
  ('Ibrahim Mbaye', 'A', 'Aston Villa', 7),
  ('Brian Madjo', 'A', 'Aston Villa', 7),
  ('Alysson', 'A', 'Aston Villa', 7),
  ('George Hemmings', 'A', 'Aston Villa', 7),
  ('Rory Wilson', 'A', 'Aston Villa', 7),
  ('Mason Cotcher', 'A', 'Aston Villa', 7),
  ('Jan Oblak', 'P', 'Atlético Madrid', 16),
  ('Juan Musso', 'P', 'Atlético Madrid', 2),
  ('Salvi Esquivel', 'P', 'Atlético Madrid', 2),
  ('Cristian Romero', 'D', 'Atlético Madrid', 18),
  ('Álex Grimaldo', 'D', 'Atlético Madrid', 18),
  ('Dávid Hancko', 'D', 'Atlético Madrid', 12),
  ('Marc Pubill', 'D', 'Atlético Madrid', 12),
  ('Robin Le Normand', 'D', 'Atlético Madrid', 12),
  ('Jorge Domínguez', 'D', 'Atlético Madrid', 3),
  ('Dani Martínez', 'D', 'Atlético Madrid', 3),
  ('Pablo Barrios', 'C', 'Atlético Madrid', 22),
  ('Álex Baena', 'C', 'Atlético Madrid', 22),
  ('Johnny Cardoso', 'C', 'Atlético Madrid', 14),
  ('Koke', 'C', 'Atlético Madrid', 14),
  ('Lee Kang-in', 'C', 'Atlético Madrid', 14),
  ('Marcos Llorente', 'C', 'Atlético Madrid', 14),
  ('Morten Hjulmand', 'C', 'Atlético Madrid', 14),
  ('Obed Vargas', 'C', 'Atlético Madrid', 9),
  ('Rodri Mendoza', 'C', 'Atlético Madrid', 9),
  ('Arnau Ortiz', 'C', 'Atlético Madrid', 3),
  ('Julián Álvarez', 'A', 'Atlético Madrid', 50),
  ('Ademola Lookman', 'A', 'Atlético Madrid', 36),
  ('Alexander Sørloth', 'A', 'Atlético Madrid', 26),
  ('Jonathan David', 'A', 'Atlético Madrid', 26),
  ('Giuliano Simeone', 'A', 'Atlético Madrid', 17),
  ('Joan Garcia', 'P', 'Barcellona', 16),
  ('Wojciech Szczęsny', 'P', 'Barcellona', 2),
  ('Dominik Livaković', 'P', 'Barcellona', 2),
  ('Alejandro Balde', 'D', 'Barcellona', 18),
  ('Pau Cubarsí', 'D', 'Barcellona', 18),
  ('Jules Koundé', 'D', 'Barcellona', 18),
  ('João Cancelo', 'D', 'Barcellona', 12),
  ('Gerard Martín', 'D', 'Barcellona', 12),
  ('Eric García', 'D', 'Barcellona', 12),
  ('Andreas Christensen', 'D', 'Barcellona', 8),
  ('Xavi Espart', 'D', 'Barcellona', 3),
  ('Pedri', 'C', 'Barcellona', 31),
  ('Fermín López', 'C', 'Barcellona', 22),
  ('Dani Olmo', 'C', 'Barcellona', 22),
  ('Frenkie de Jong', 'C', 'Barcellona', 22),
  ('Gavi', 'C', 'Barcellona', 14),
  ('Marc Bernal', 'C', 'Barcellona', 14),
  ('Marc Casadó', 'C', 'Barcellona', 9),
  ('Lamine Yamal', 'A', 'Barcellona', 50),
  ('Raphinha', 'A', 'Barcellona', 50),
  ('Anthony Gordon', 'A', 'Barcellona', 36),
  ('Karim Adeyemi', 'A', 'Barcellona', 26),
  ('Roony Bardghji', 'A', 'Barcellona', 11),
  ('Manuel Neuer', 'P', 'Bayern Monaco', 16),
  ('Sven Ulreich', 'P', 'Bayern Monaco', 2),
  ('Jannis Bärtl', 'P', 'Bayern Monaco', 2),
  ('Leonard Prescott', 'P', 'Bayern Monaco', 2),
  ('Jonas Urbig', 'P', 'Bayern Monaco', 2),
  ('Leon Klanac', 'P', 'Bayern Monaco', 2),
  ('Dayot Upamecano', 'D', 'Bayern Monaco', 18),
  ('Jonathan Tah', 'D', 'Bayern Monaco', 18),
  ('Kim Min-jae', 'D', 'Bayern Monaco', 12),
  ('Alphonso Davies', 'D', 'Bayern Monaco', 12),
  ('Josip Stanišić', 'D', 'Bayern Monaco', 12),
  ('Hiroki Ito', 'D', 'Bayern Monaco', 8),
  ('Cassiano Kiala', 'D', 'Bayern Monaco', 3),
  ('Deniz Ofli', 'D', 'Bayern Monaco', 3),
  ('Vincent Manuba', 'D', 'Bayern Monaco', 3),
  ('Filip Pavić', 'D', 'Bayern Monaco', 3),
  ('Joshua Kimmich', 'C', 'Bayern Monaco', 31),
  ('Jamal Musiala', 'C', 'Bayern Monaco', 31),
  ('Aleksandar Pavlović', 'C', 'Bayern Monaco', 22),
  ('Tom Bischof', 'C', 'Bayern Monaco', 14),
  ('Konrad Laimer', 'C', 'Bayern Monaco', 14),
  ('Lennart Karl', 'C', 'Bayern Monaco', 14),
  ('Guido Della Rovere', 'C', 'Bayern Monaco', 3),
  ('Erblin Osmani', 'C', 'Bayern Monaco', 3),
  ('Bara Ndiaye', 'C', 'Bayern Monaco', 3),
  ('David Santos Daiber', 'C', 'Bayern Monaco', 3),
  ('Harry Kane', 'A', 'Bayern Monaco', 50),
  ('Michael Olise', 'A', 'Bayern Monaco', 50),
  ('Luis Díaz', 'A', 'Bayern Monaco', 36),
  ('Serge Gnabry', 'A', 'Bayern Monaco', 17),
  ('Bastian Assomo', 'A', 'Bayern Monaco', 4),
  ('Maycon Cardozo', 'A', 'Bayern Monaco', 4),
  ('Nikita Haikin', 'P', 'Bodø/Glimt', 4),
  ('Julian Faye Lund', 'P', 'Bodø/Glimt', 2),
  ('Isak Sjong', 'P', 'Bodø/Glimt', 2),
  ('Odin Bjørtuft', 'D', 'Bodø/Glimt', 5),
  ('Haitam Aleesami', 'D', 'Bodø/Glimt', 5),
  ('Jostein Gundersen', 'D', 'Bodø/Glimt', 5),
  ('Fredrik André Bjørkan', 'D', 'Bodø/Glimt', 5),
  ('Fredrik Sjøvold', 'D', 'Bodø/Glimt', 5),
  ('Isak Dybvik Määttä', 'D', 'Bodø/Glimt', 5),
  ('Villads Nielsen', 'D', 'Bodø/Glimt', 3),
  ('Kasper Solhaug', 'D', 'Bodø/Glimt', 3),
  ('Patrick Berg', 'C', 'Bodø/Glimt', 6),
  ('Sondre Auklend', 'C', 'Bodø/Glimt', 6),
  ('Ulrik Saltnes', 'C', 'Bodø/Glimt', 6),
  ('Sondre Brunstad Fet', 'C', 'Bodø/Glimt', 6),
  ('Håkon Evjen', 'C', 'Bodø/Glimt', 6),
  ('Joshua Kitolano', 'C', 'Bodø/Glimt', 3),
  ('Magnus Riisnæs', 'C', 'Bodø/Glimt', 3),
  ('Jens Petter Hauge', 'A', 'Bodø/Glimt', 11),
  ('Andreas Helmersen', 'A', 'Bodø/Glimt', 7),
  ('Ole Didrik Blomberg', 'A', 'Bodø/Glimt', 7),
  ('Ola Brynhildsen', 'A', 'Bodø/Glimt', 7),
  ('Joel Mvuka', 'A', 'Bodø/Glimt', 4),
  ('Mikkel Bro Hansen', 'A', 'Bodø/Glimt', 4),
  ('August Mikkelsen', 'A', 'Bodø/Glimt', 4),
  ('Gregor Kobel', 'P', 'Borussia Dortmund', 10),
  ('Patrick Drewes', 'P', 'Borussia Dortmund', 2),
  ('Silas Ostrzinski', 'P', 'Borussia Dortmund', 2),
  ('Alexander Meyer', 'P', 'Borussia Dortmund', 2),
  ('Nico Schlotterbeck', 'D', 'Borussia Dortmund', 12),
  ('Waldemar Anton', 'D', 'Borussia Dortmund', 8),
  ('Ramy Bensebaini', 'D', 'Borussia Dortmund', 8),
  ('Emre Can', 'D', 'Borussia Dortmund', 8),
  ('Daniel Svensson', 'D', 'Borussia Dortmund', 8),
  ('Julian Ryerson', 'D', 'Borussia Dortmund', 8),
  ('Joane Gadou', 'D', 'Borussia Dortmund', 5),
  ('Kauã Prates', 'D', 'Borussia Dortmund', 5),
  ('Filippo Mané', 'D', 'Borussia Dortmund', 5),
  ('Luca Reggiani', 'D', 'Borussia Dortmund', 5),
  ('Jobe Bellingham', 'C', 'Borussia Dortmund', 14),
  ('Felix Nmecha', 'C', 'Borussia Dortmund', 14),
  ('Ethan Nwaneri', 'C', 'Borussia Dortmund', 14),
  ('Carney Chukwuemeka', 'C', 'Borussia Dortmund', 9),
  ('Konstantinos Karetsas', 'C', 'Borussia Dortmund', 9),
  ('Marcel Sabitzer', 'C', 'Borussia Dortmund', 9),
  ('Joey Veerman', 'C', 'Borussia Dortmund', 9),
  ('Giannis Konstantelias', 'C', 'Borussia Dortmund', 9),
  ('Justin Lerma', 'C', 'Borussia Dortmund', 6),
  ('Enzo dos Santos', 'C', 'Borussia Dortmund', 6),
  ('Mussa Kaba', 'C', 'Borussia Dortmund', 6),
  ('Serhou Guirassy', 'A', 'Borussia Dortmund', 36),
  ('Maximilian Beier', 'A', 'Borussia Dortmund', 17),
  ('Fábio Silva', 'A', 'Borussia Dortmund', 17),
  ('Samuele Inácio', 'A', 'Borussia Dortmund', 7),
  ('Mathis Albert', 'A', 'Borussia Dortmund', 7),
  ('Yann Sommer', 'P', 'Club Brugge', 10),
  ('Nordin Jackers', 'P', 'Club Brugge', 2),
  ('Argus Vanden Driessche', 'P', 'Club Brugge', 2),
  ('Lee Han-beom', 'D', 'Club Brugge', 8),
  ('Joel Ordóñez', 'D', 'Club Brugge', 8),
  ('Hugo Siquet', 'D', 'Club Brugge', 8),
  ('Brandon Mechele', 'D', 'Club Brugge', 8),
  ('Jorne Spileers', 'D', 'Club Brugge', 8),
  ('Kyriani Sabbe', 'D', 'Club Brugge', 8),
  ('Joaquin Seys', 'D', 'Club Brugge', 8),
  ('Matteo Dams', 'D', 'Club Brugge', 5),
  ('Hans Vanaken', 'C', 'Club Brugge', 14),
  ('Freddie Potts', 'C', 'Club Brugge', 9),
  ('Hugo Vetlesen', 'C', 'Club Brugge', 9),
  ('Cheveyo Tsawa', 'C', 'Club Brugge', 9),
  ('Lynnt Audoor', 'C', 'Club Brugge', 6),
  ('Alejandro Granados', 'C', 'Club Brugge', 6),
  ('Félix Lemaréchal', 'C', 'Club Brugge', 6),
  ('Tian Nai Koren', 'C', 'Club Brugge', 6),
  ('Gianluca Okon', 'C', 'Club Brugge', 6),
  ('Nicolò Tresoldi', 'A', 'Club Brugge', 17),
  ('Carlos Forbs', 'A', 'Club Brugge', 17),
  ('Romeo Vermant', 'A', 'Club Brugge', 17),
  ('Mamadou Diakhon', 'A', 'Club Brugge', 11),
  ('Jan Virgili', 'A', 'Club Brugge', 7),
  ('Wisdom Mike', 'A', 'Club Brugge', 7),
  ('Andrej Vasovic', 'A', 'Club Brugge', 7),
  ('Jean Butez', 'P', 'Como', 10),
  ('Mauro Vigorito', 'P', 'Como', 2),
  ('Robert Sánchez', 'P', 'Como', 2),
  ('Marc-Oliver Kempf', 'D', 'Como', 8),
  ('Álex Valle', 'D', 'Como', 8),
  ('Jacobo Ramón', 'D', 'Como', 8),
  ('Alberto Dossena', 'D', 'Como', 8),
  ('Yan Couto', 'D', 'Como', 8),
  ('Ivan Smolčić', 'D', 'Como', 8),
  ('Willy Kambwala', 'D', 'Como', 8),
  ('Trevoh Chalobah', 'D', 'Como', 8),
  ('Kaiki Bruno', 'D', 'Como', 5),
  ('Edoardo Goldaniga', 'D', 'Como', 5),
  ('Nico Paz', 'C', 'Como', 22),
  ('Máximo Perrone', 'C', 'Como', 14),
  ('Martin Baturina', 'C', 'Como', 14),
  ('Lucas Da Cunha', 'C', 'Como', 9),
  ('Maxence Caqueret', 'C', 'Como', 9),
  ('Samuele Ricci', 'C', 'Como', 9),
  ('Luis Milla', 'C', 'Como', 6),
  ('Adrian Lahdo', 'C', 'Como', 6),
  ('Mattia Liberali', 'C', 'Como', 6),
  ('Moise Kean', 'A', 'Como', 26),
  ('Anastasios Douvikas', 'A', 'Como', 17),
  ('Assane Diao', 'A', 'Como', 17),
  ('Jesús Rodríguez', 'A', 'Como', 17),
  ('Jayden Addai', 'A', 'Como', 11),
  ('Ederson', 'P', 'Fenerbahçe', 10),
  ('Tarık Çetin', 'P', 'Fenerbahçe', 2),
  ('Mert Günok', 'P', 'Fenerbahçe', 2),
  ('Archie Brown', 'D', 'Fenerbahçe', 8),
  ('Çağlar Söyüncü', 'D', 'Fenerbahçe', 8),
  ('Nathan Aké', 'D', 'Fenerbahçe', 8),
  ('Levent Mercan', 'D', 'Fenerbahçe', 8),
  ('Jayden Oosterwolde', 'D', 'Fenerbahçe', 8),
  ('Nélson Semedo', 'D', 'Fenerbahçe', 8),
  ('Milan Škriniar', 'D', 'Fenerbahçe', 8),
  ('Yiğit Efe Demir', 'D', 'Fenerbahçe', 5),
  ('Mert Müldür', 'D', 'Fenerbahçe', 5),
  ('Ognjen Mimović', 'D', 'Fenerbahçe', 5),
  ('Rodrigo Becão', 'D', 'Fenerbahçe', 5),
  ('Diego Carlos', 'D', 'Fenerbahçe', 5),
  ('Mattéo Guendouzi', 'C', 'Fenerbahçe', 14),
  ('Marco Asensio', 'C', 'Fenerbahçe', 14),
  ('N''Golo Kanté', 'C', 'Fenerbahçe', 14),
  ('İsmail Yüksek', 'C', 'Fenerbahçe', 9),
  ('İrfan Can Kahveci', 'C', 'Fenerbahçe', 9),
  ('Oğuz Aydın', 'C', 'Fenerbahçe', 9),
  ('Sofyan Amrabat', 'C', 'Fenerbahçe', 9),
  ('Mert Hakan Yandaş', 'C', 'Fenerbahçe', 6),
  ('Bartuğ Elmaz', 'C', 'Fenerbahçe', 6),
  ('Mason Greenwood', 'A', 'Fenerbahçe', 26),
  ('Kerem Aktürkoğlu', 'A', 'Fenerbahçe', 17),
  ('Romelu Lukaku', 'A', 'Fenerbahçe', 17),
  ('Talisca', 'A', 'Fenerbahçe', 17),
  ('Vedat Muriqi', 'A', 'Fenerbahçe', 11),
  ('Dorgeles Nene', 'A', 'Fenerbahçe', 11),
  ('Cengiz Ünder', 'A', 'Fenerbahçe', 7),
  ('Tjark Ernst', 'P', 'Feyenoord', 10),
  ('Florian Kastenmeier', 'P', 'Feyenoord', 2),
  ('Manou Berger', 'P', 'Feyenoord', 2),
  ('Liam Bossin', 'P', 'Feyenoord', 2),
  ('Thomas Beelen', 'D', 'Feyenoord', 8),
  ('Tsuyoshi Watanabe', 'D', 'Feyenoord', 8),
  ('Gijs Smal', 'D', 'Feyenoord', 8),
  ('Jeremiah St. Juste', 'D', 'Feyenoord', 8),
  ('Jordan Bos', 'D', 'Feyenoord', 8),
  ('Givairo Read', 'D', 'Feyenoord', 8),
  ('Bart Nieuwkoop', 'D', 'Feyenoord', 5),
  ('Javi López', 'D', 'Feyenoord', 5),
  ('Mats Deijl', 'D', 'Feyenoord', 5),
  ('Tijme Wessels', 'D', 'Feyenoord', 5),
  ('Mika Mármol', 'D', 'Feyenoord', 5),
  ('Sem Steijn', 'C', 'Feyenoord', 14),
  ('Jakub Moder', 'C', 'Feyenoord', 9),
  ('Luciano Valente', 'C', 'Feyenoord', 9),
  ('Oussama Targhalline', 'C', 'Feyenoord', 9),
  ('Gjivai Zechiël', 'C', 'Feyenoord', 6),
  ('Tobias van den Elshout', 'C', 'Feyenoord', 6),
  ('Thijs Kraaijeveld', 'C', 'Feyenoord', 6),
  ('Charles Vanhoutte', 'C', 'Feyenoord', 6),
  ('Anis Hadj Moussa', 'A', 'Feyenoord', 17),
  ('Gonçalo Borges', 'A', 'Feyenoord', 11),
  ('Reiss Nelson', 'A', 'Feyenoord', 11),
  ('Nacho Ferri', 'A', 'Feyenoord', 11),
  ('Gaoussou Diarra', 'A', 'Feyenoord', 11),
  ('Jivayno Zinhagel', 'A', 'Feyenoord', 7),
  ('Shaqueel van Persie', 'A', 'Feyenoord', 7),
  ('Uğurcan Çakır', 'P', 'Galatasaray', 10),
  ('Günay Güvenç', 'P', 'Galatasaray', 2),
  ('Jankat Yılmaz', 'P', 'Galatasaray', 2),
  ('Enes Emre Büyük', 'P', 'Galatasaray', 2),
  ('Ismail Jakobs', 'D', 'Galatasaray', 8),
  ('Davinson Sánchez', 'D', 'Galatasaray', 8),
  ('Eren Elmalı', 'D', 'Galatasaray', 8),
  ('Abdülkerim Bardakcı', 'D', 'Galatasaray', 8),
  ('Wilfried Singo', 'D', 'Galatasaray', 8),
  ('El Chadaille Bitshiabu', 'D', 'Galatasaray', 5),
  ('Kaan Ayhan', 'D', 'Galatasaray', 5),
  ('Kazımcan Karataş', 'D', 'Galatasaray', 5),
  ('Arda Ünyay', 'D', 'Galatasaray', 5),
  ('Gabriel Sara', 'C', 'Galatasaray', 14),
  ('İlkay Gündoğan', 'C', 'Galatasaray', 14),
  ('Aleksey Batrakov', 'C', 'Galatasaray', 14),
  ('Roland Sallai', 'C', 'Galatasaray', 9),
  ('Lesley Ugochukwu', 'C', 'Galatasaray', 9),
  ('Lucas Torreira', 'C', 'Galatasaray', 9),
  ('Mario Lemina', 'C', 'Galatasaray', 9),
  ('Eyüp Aydın', 'C', 'Galatasaray', 6),
  ('Armando Güner', 'C', 'Galatasaray', 6),
  ('Renato Nhaga', 'C', 'Galatasaray', 6),
  ('Berat Luş', 'C', 'Galatasaray', 6),
  ('Victor Osimhen', 'A', 'Galatasaray', 36),
  ('Rafael Leão', 'A', 'Galatasaray', 26),
  ('Leroy Sané', 'A', 'Galatasaray', 17),
  ('Barış Alper Yılmaz', 'A', 'Galatasaray', 17),
  ('Yunus Akgün', 'A', 'Galatasaray', 11),
  ('Deniz Gül', 'A', 'Galatasaray', 7),
  ('Ada Yüzgeç', 'A', 'Galatasaray', 7),
  ('Josep Martínez', 'P', 'Inter', 16),
  ('Raffaele Di Gennaro', 'P', 'Inter', 2),
  ('Ivan Provedel', 'P', 'Inter', 2),
  ('Federico Dimarco', 'D', 'Inter', 25),
  ('Alessandro Bastoni', 'D', 'Inter', 25),
  ('Manuel Akanji', 'D', 'Inter', 18),
  ('John Stones', 'D', 'Inter', 12),
  ('Benjamin Pavard', 'D', 'Inter', 12),
  ('Carlos Augusto', 'D', 'Inter', 12),
  ('Yann Aurel Bisseck', 'D', 'Inter', 12),
  ('Djed Spence', 'D', 'Inter', 12),
  ('Hakan Çalhanoğlu', 'C', 'Inter', 31),
  ('Nicolò Barella', 'C', 'Inter', 31),
  ('Piotr Zieliński', 'C', 'Inter', 14),
  ('Petar Sučić', 'C', 'Inter', 14),
  ('Luis Henrique', 'C', 'Inter', 14),
  ('Curtis Jones', 'C', 'Inter', 14),
  ('Henrikh Mkhitaryan', 'C', 'Inter', 14),
  ('Aleksandar Stanković', 'C', 'Inter', 9),
  ('Andy Diouf', 'C', 'Inter', 9),
  ('Lautaro Martínez', 'A', 'Inter', 50),
  ('Marcus Thuram', 'A', 'Inter', 36),
  ('Ange-Yoan Bonny', 'A', 'Inter', 17),
  ('Pio Esposito', 'A', 'Inter', 17),
  ('Lukas Jungwirth', 'P', 'LASK', 4),
  ('Tobias Schützenauer', 'P', 'LASK', 2),
  ('Fabian Schillinger', 'P', 'LASK', 2),
  ('George Bello', 'D', 'LASK', 5),
  ('Andrés Andrade', 'D', 'LASK', 5),
  ('Kasper Jørgensen', 'D', 'LASK', 5),
  ('Florian Flecker', 'D', 'LASK', 5),
  ('Miguel Freckleton', 'D', 'LASK', 3),
  ('Xavier Mbuyamba', 'D', 'LASK', 3),
  ('Manoël Verhaeghe', 'D', 'LASK', 3),
  ('Yvan Dibango', 'D', 'LASK', 3),
  ('Alemão', 'D', 'LASK', 3),
  ('Cheikne Kébé', 'D', 'LASK', 3),
  ('Art Smakaj', 'C', 'LASK', 6),
  ('Robert Ljubičić', 'C', 'LASK', 6),
  ('Alessandro Schöpf', 'C', 'LASK', 6),
  ('Sascha Horvath', 'C', 'LASK', 6),
  ('Melayro Bogarde', 'C', 'LASK', 3),
  ('Kryštof Daněk', 'C', 'LASK', 3),
  ('Mohamed Sanogo', 'C', 'LASK', 3),
  ('Saša Kalajdžić', 'A', 'LASK', 11),
  ('Samuel Adeniran', 'A', 'LASK', 7),
  ('Moses Usor', 'A', 'LASK', 7),
  ('Christoph Lang', 'A', 'LASK', 7),
  ('Ramiz Harakaté', 'A', 'LASK', 4),
  ('Filip Perović', 'A', 'LASK', 4),
  ('Robin Risser', 'P', 'Lens', 10),
  ('Régis Gurtner', 'P', 'Lens', 2),
  ('Mathieu Gorgelin', 'P', 'Lens', 2),
  ('Ilan Jourdren', 'P', 'Lens', 2),
  ('Ruben Aguilar', 'D', 'Lens', 8),
  ('Samson Baidoo', 'D', 'Lens', 8),
  ('Matthieu Udol', 'D', 'Lens', 8),
  ('Saud Abdulhamid', 'D', 'Lens', 8),
  ('Jonathan Gradit', 'D', 'Lens', 8),
  ('Ismaëlo Ganiou', 'D', 'Lens', 8),
  ('Nidal Čelik', 'D', 'Lens', 5),
  ('Kyllian Antonio', 'D', 'Lens', 5),
  ('Andrija Bulatović', 'C', 'Lens', 9),
  ('Mamadou Sangaré', 'C', 'Lens', 9),
  ('Amadou Haidara', 'C', 'Lens', 9),
  ('Michaël Cuisance', 'C', 'Lens', 9),
  ('Fodé Sylla', 'C', 'Lens', 6),
  ('Anthony Bermont', 'C', 'Lens', 6),
  ('Alpha Diallo', 'C', 'Lens', 6),
  ('Florian Thauvin', 'A', 'Lens', 17),
  ('Odsonne Édouard', 'A', 'Lens', 17),
  ('Abdallah Sima', 'A', 'Lens', 17),
  ('Florian Sotoca', 'A', 'Lens', 11),
  ('Erawan Garnier', 'A', 'Lens', 7),
  ('Rayan Fofana', 'A', 'Lens', 7),
  ('Berke Özer', 'P', 'Lille', 10),
  ('Arnaud Bodart', 'P', 'Lille', 2),
  ('Alexsandro', 'D', 'Lille', 8),
  ('Romain Perraud', 'D', 'Lille', 8),
  ('Tanguy Nianzou', 'D', 'Lille', 8),
  ('Calvin Verdonk', 'D', 'Lille', 8),
  ('Loun Srdanovic', 'D', 'Lille', 5),
  ('Nathan Ngoy', 'D', 'Lille', 5),
  ('Tiago Santos', 'D', 'Lille', 5),
  ('Isaac Cossier', 'D', 'Lille', 5),
  ('Ousmane Touré', 'D', 'Lille', 5),
  ('Hákon Haraldsson', 'C', 'Lille', 14),
  ('Ngal''ayel Mukau', 'C', 'Lille', 9),
  ('Benjamin André', 'C', 'Lille', 9),
  ('Ayyoub Bouaddi', 'C', 'Lille', 9),
  ('Matias Fernandez-Pardo', 'A', 'Lille', 17),
  ('Olivier Giroud', 'A', 'Lille', 17),
  ('Hamza Igamane', 'A', 'Lille', 17),
  ('Ethan Mbappé', 'A', 'Lille', 11),
  ('Osame Sahraoui', 'A', 'Lille', 11),
  ('Félix Correia', 'A', 'Lille', 11),
  ('Mohamed Bayo', 'A', 'Lille', 11),
  ('Marius Broholm', 'A', 'Lille', 7),
  ('Başar Önal', 'A', 'Lille', 7),
  ('Noah Edjouma', 'A', 'Lille', 7),
  ('Gaëtan Perrin', 'A', 'Lille', 7),
  ('Soriba Diaoune', 'A', 'Lille', 7),
  ('Tiago Morais', 'A', 'Lille', 7),
  ('Alisson Becker', 'P', 'Liverpool', 16),
  ('Giorgi Mamardashvili', 'P', 'Liverpool', 2),
  ('Freddie Woodman', 'P', 'Liverpool', 2),
  ('Vítězslav Jaroš', 'P', 'Liverpool', 2),
  ('Harvey Davies', 'P', 'Liverpool', 2),
  ('Virgil van Dijk', 'D', 'Liverpool', 18),
  ('Milos Kerkez', 'D', 'Liverpool', 18),
  ('Jeremie Frimpong', 'D', 'Liverpool', 18),
  ('Jérémy Jacquet', 'D', 'Liverpool', 12),
  ('Conor Bradley', 'D', 'Liverpool', 12),
  ('Giovanni Leoni', 'D', 'Liverpool', 12),
  ('Ronald Araújo', 'D', 'Liverpool', 12),
  ('Joe Gomez', 'D', 'Liverpool', 8),
  ('Kostas Tsimikas', 'D', 'Liverpool', 8),
  ('Florian Wirtz', 'C', 'Liverpool', 31),
  ('Dominik Szoboszlai', 'C', 'Liverpool', 31),
  ('Alexis Mac Allister', 'C', 'Liverpool', 31),
  ('Ryan Gravenberch', 'C', 'Liverpool', 22),
  ('Wataru Endo', 'C', 'Liverpool', 9),
  ('Harvey Elliott', 'C', 'Liverpool', 9),
  ('Trey Nyoni', 'C', 'Liverpool', 3),
  ('Stefan Bajcetic', 'C', 'Liverpool', 3),
  ('James McConnell', 'C', 'Liverpool', 3),
  ('Alexander Isak', 'A', 'Liverpool', 50),
  ('Cody Gakpo', 'A', 'Liverpool', 36),
  ('Hugo Ekitike', 'A', 'Liverpool', 36),
  ('Bradley Barcola', 'A', 'Liverpool', 36),
  ('Federico Chiesa', 'A', 'Liverpool', 17),
  ('Víctor Muñoz', 'A', 'Liverpool', 17),
  ('Rio Ngumoha', 'A', 'Liverpool', 11),
  ('Gianluigi Donnarumma', 'P', 'Manchester City', 16),
  ('James Trafford', 'P', 'Manchester City', 2),
  ('Marcus Bettinelli', 'P', 'Manchester City', 2),
  ('Rúben Dias', 'D', 'Manchester City', 18),
  ('Marc Guéhi', 'D', 'Manchester City', 18),
  ('Joško Gvardiol', 'D', 'Manchester City', 18),
  ('Rayan Aït-Nouri', 'D', 'Manchester City', 12),
  ('Abdukodir Khusanov', 'D', 'Manchester City', 12),
  ('Rico Lewis', 'D', 'Manchester City', 12),
  ('Vitor Reis', 'D', 'Manchester City', 8),
  ('Joshua Wilson-Esbrand', 'D', 'Manchester City', 3),
  ('Tijjani Reijnders', 'C', 'Manchester City', 31),
  ('Rayan Cherki', 'C', 'Manchester City', 31),
  ('Rodri', 'C', 'Manchester City', 31),
  ('Phil Foden', 'C', 'Manchester City', 31),
  ('Mateo Kovačić', 'C', 'Manchester City', 14),
  ('Nico González', 'C', 'Manchester City', 14),
  ('Matheus Nunes', 'C', 'Manchester City', 14),
  ('Nico O''Reilly', 'C', 'Manchester City', 14),
  ('Jack Grealish', 'C', 'Manchester City', 14),
  ('Claudio Echeverri', 'C', 'Manchester City', 9),
  ('Sverre Nypan', 'C', 'Manchester City', 9),
  ('Kalvin Phillips', 'C', 'Manchester City', 3),
  ('Erling Haaland', 'A', 'Manchester City', 50),
  ('Antoine Semenyo', 'A', 'Manchester City', 36),
  ('Jérémy Doku', 'A', 'Manchester City', 26),
  ('Savinho', 'A', 'Manchester City', 26),
  ('Omar Marmoush', 'A', 'Manchester City', 26),
  ('Senne Lammens', 'P', 'Manchester United', 10),
  ('Karl Darlow', 'P', 'Manchester United', 2),
  ('Tom Heaton', 'P', 'Manchester United', 2),
  ('Dermot Mee', 'P', 'Manchester United', 2),
  ('Diogo Dalot', 'D', 'Manchester United', 8),
  ('Noussair Mazraoui', 'D', 'Manchester United', 8),
  ('Matthijs de Ligt', 'D', 'Manchester United', 8),
  ('Harry Maguire', 'D', 'Manchester United', 8),
  ('Lisandro Martínez', 'D', 'Manchester United', 8),
  ('Patrick Dorgu', 'D', 'Manchester United', 8),
  ('Leny Yoro', 'D', 'Manchester United', 8),
  ('Luke Shaw', 'D', 'Manchester United', 8),
  ('Ayden Heaven', 'D', 'Manchester United', 5),
  ('Harry Amass', 'D', 'Manchester United', 5),
  ('Bruno Fernandes', 'C', 'Manchester United', 22),
  ('Amad Diallo', 'C', 'Manchester United', 14),
  ('Youri Tielemans', 'C', 'Manchester United', 14),
  ('Carlos Baleba', 'C', 'Manchester United', 14),
  ('Kobbie Mainoo', 'C', 'Manchester United', 14),
  ('Mason Mount', 'C', 'Manchester United', 9),
  ('Manuel Ugarte', 'C', 'Manchester United', 9),
  ('Andrey Santos', 'C', 'Manchester United', 6),
  ('Jack Fletcher', 'C', 'Manchester United', 6),
  ('Tyler Fletcher', 'C', 'Manchester United', 6),
  ('Matheus Cunha', 'A', 'Manchester United', 26),
  ('Bryan Mbeumo', 'A', 'Manchester United', 26),
  ('Benjamin Šeško', 'A', 'Manchester United', 26),
  ('Marcus Rashford', 'A', 'Manchester United', 17),
  ('Joshua Zirkzee', 'A', 'Manchester United', 11),
  ('Shea Lacey', 'A', 'Manchester United', 7),
  ('Vanja Milinković-Savić', 'P', 'Napoli', 10),
  ('Alex Meret', 'P', 'Napoli', 2),
  ('Nikita Contini', 'P', 'Napoli', 2),
  ('Alessandro Buongiorno', 'D', 'Napoli', 12),
  ('Amir Rrahmani', 'D', 'Napoli', 12),
  ('Giovanni Di Lorenzo', 'D', 'Napoli', 12),
  ('Rafa Marín', 'D', 'Napoli', 8),
  ('Mathías Olivera', 'D', 'Napoli', 8),
  ('Pasquale Mazzocchi', 'D', 'Napoli', 8),
  ('Sam Beukema', 'D', 'Napoli', 8),
  ('Leonardo Spinazzola', 'D', 'Napoli', 8),
  ('Luca Marianucci', 'D', 'Napoli', 5),
  ('Benoît Badiashile', 'D', 'Napoli', 5),
  ('Scott McTominay', 'C', 'Napoli', 31),
  ('Kevin De Bruyne', 'C', 'Napoli', 22),
  ('Stanislav Lobotka', 'C', 'Napoli', 14),
  ('André-Frank Zambo Anguissa', 'C', 'Napoli', 14),
  ('Billy Gilmour', 'C', 'Napoli', 9),
  ('Antonio Vergara', 'C', 'Napoli', 9),
  ('Rasmus Højlund', 'A', 'Napoli', 26),
  ('David Neres', 'A', 'Napoli', 17),
  ('Lorenzo Lucca', 'A', 'Napoli', 17),
  ('Matteo Politano', 'A', 'Napoli', 17),
  ('Noa Lang', 'A', 'Napoli', 17),
  ('Giovane', 'A', 'Napoli', 11),
  ('Alisson Santos', 'A', 'Napoli', 11),
  ('Nick Olij', 'P', 'PSV Eindhoven', 10),
  ('Matěj Kovář', 'P', 'PSV Eindhoven', 2),
  ('Tijn Smolenaars', 'P', 'PSV Eindhoven', 2),
  ('Ivan Perišić', 'D', 'PSV Eindhoven', 12),
  ('Lutsharel Geertruida', 'D', 'PSV Eindhoven', 8),
  ('Yarek Gasiorowski', 'D', 'PSV Eindhoven', 8),
  ('Armando Obispo', 'D', 'PSV Eindhoven', 8),
  ('Ryan Flamingo', 'D', 'PSV Eindhoven', 8),
  ('Sergiño Dest', 'D', 'PSV Eindhoven', 8),
  ('Mauro Júnior', 'D', 'PSV Eindhoven', 8),
  ('Filip Kostić', 'D', 'PSV Eindhoven', 8),
  ('Kiliann Sildillia', 'D', 'PSV Eindhoven', 8),
  ('Fabian Merién', 'D', 'PSV Eindhoven', 5),
  ('Adamo Nagalo', 'D', 'PSV Eindhoven', 5),
  ('Guus Til', 'C', 'PSV Eindhoven', 14),
  ('Paul Wanner', 'C', 'PSV Eindhoven', 9),
  ('Sven Mijnans', 'C', 'PSV Eindhoven', 9),
  ('Jerdy Schouten', 'C', 'PSV Eindhoven', 9),
  ('Kodai Sano', 'C', 'PSV Eindhoven', 6),
  ('Isaac Babadi', 'C', 'PSV Eindhoven', 6),
  ('Noah Fernandez', 'C', 'PSV Eindhoven', 6),
  ('Joël van den Berg', 'C', 'PSV Eindhoven', 6),
  ('Ricardo Pepi', 'A', 'PSV Eindhoven', 17),
  ('Couhaib Driouech', 'A', 'PSV Eindhoven', 17),
  ('Dennis Man', 'A', 'PSV Eindhoven', 17),
  ('Ruben van Bommel', 'A', 'PSV Eindhoven', 11),
  ('Alassane Pléa', 'A', 'PSV Eindhoven', 11),
  ('Esmir Bajraktarević', 'A', 'PSV Eindhoven', 11),
  ('Lucas Chevalier', 'P', 'Paris Saint-Germain', 16),
  ('Alessandro Longoni', 'P', 'Paris Saint-Germain', 2),
  ('Matvey Safonov', 'P', 'Paris Saint-Germain', 2),
  ('Achraf Hakimi', 'D', 'Paris Saint-Germain', 25),
  ('Nuno Mendes', 'D', 'Paris Saint-Germain', 25),
  ('Marquinhos', 'D', 'Paris Saint-Germain', 18),
  ('Willian Pacho', 'D', 'Paris Saint-Germain', 18),
  ('Illia Zabarnyi', 'D', 'Paris Saint-Germain', 12),
  ('Lucas Hernandez', 'D', 'Paris Saint-Germain', 12),
  ('Lucas Beraldo', 'D', 'Paris Saint-Germain', 8),
  ('Lucas Digne', 'D', 'Paris Saint-Germain', 8),
  ('Vitinha', 'C', 'Paris Saint-Germain', 31),
  ('João Neves', 'C', 'Paris Saint-Germain', 31),
  ('Fabián Ruiz', 'C', 'Paris Saint-Germain', 22),
  ('Maghnes Akliouche', 'C', 'Paris Saint-Germain', 22),
  ('Warren Zaïre-Emery', 'C', 'Paris Saint-Germain', 14),
  ('Senny Mayulu', 'C', 'Paris Saint-Germain', 3),
  ('Dro Fernández', 'C', 'Paris Saint-Germain', 3),
  ('Khvicha Kvaratskhelia', 'A', 'Paris Saint-Germain', 50),
  ('Ousmane Dembélé', 'A', 'Paris Saint-Germain', 50),
  ('Désiré Doué', 'A', 'Paris Saint-Germain', 36),
  ('Ferran Torres', 'A', 'Paris Saint-Germain', 26),
  ('Mika Godts', 'A', 'Paris Saint-Germain', 17),
  ('Quentin Ndjantou', 'A', 'Paris Saint-Germain', 4),
  ('Diogo Costa', 'P', 'Porto', 10),
  ('Cláudio Ramos', 'P', 'Porto', 2),
  ('João Costa', 'P', 'Porto', 2),
  ('João Afonso', 'P', 'Porto', 2),
  ('Jakub Kiwior', 'D', 'Porto', 8),
  ('Jan Bednarek', 'D', 'Porto', 8),
  ('Alberto Costa', 'D', 'Porto', 8),
  ('Dominik Prpić', 'D', 'Porto', 8),
  ('Martim Fernandes', 'D', 'Porto', 8),
  ('Francisco Moura', 'D', 'Porto', 8),
  ('Zaidu Sanusi', 'D', 'Porto', 5),
  ('Nehuén Pérez', 'D', 'Porto', 5),
  ('Souza', 'D', 'Porto', 5),
  ('William Gomes', 'C', 'Porto', 14),
  ('Victor Froholdt', 'C', 'Porto', 14),
  ('Gabri Veiga', 'C', 'Porto', 14),
  ('Hwang In-beom', 'C', 'Porto', 9),
  ('Alan Varela', 'C', 'Porto', 9),
  ('Seko Fofana', 'C', 'Porto', 9),
  ('Pablo Rosario', 'C', 'Porto', 6),
  ('Vasco Sousa', 'C', 'Porto', 6),
  ('Samu Aghehowa', 'A', 'Porto', 26),
  ('Pepê', 'A', 'Porto', 17),
  ('Borja Sainz', 'A', 'Porto', 17),
  ('Santiago Giménez', 'A', 'Porto', 17),
  ('André Silva', 'A', 'Porto', 11),
  ('Gabriel Mec', 'A', 'Porto', 11),
  ('Oskar Pietuszewski', 'A', 'Porto', 11),
  ('Maarten Vandevoordt', 'P', 'RB Lipsia', 10),
  ('Ørjan Nyland', 'P', 'RB Lipsia', 2),
  ('Leopold Zingerle', 'P', 'RB Lipsia', 2),
  ('David Raum', 'D', 'RB Lipsia', 12),
  ('Maxime Estève', 'D', 'RB Lipsia', 8),
  ('Willi Orbán', 'D', 'RB Lipsia', 8),
  ('Ridle Baku', 'D', 'RB Lipsia', 8),
  ('Castello Lukeba', 'D', 'RB Lipsia', 8),
  ('Benjamin Henrichs', 'D', 'RB Lipsia', 8),
  ('Abdoul Koné', 'D', 'RB Lipsia', 5),
  ('Lukas Klostermann', 'D', 'RB Lipsia', 5),
  ('Max Finkgräfe', 'D', 'RB Lipsia', 5),
  ('Assan Ouédraogo', 'C', 'RB Lipsia', 14),
  ('Christoph Baumgartner', 'C', 'RB Lipsia', 14),
  ('Ezechiel Banzuzi', 'C', 'RB Lipsia', 9),
  ('Nicolas Seiwald', 'C', 'RB Lipsia', 9),
  ('Rocco Reitz', 'C', 'RB Lipsia', 9),
  ('Andrija Maksimović', 'C', 'RB Lipsia', 6),
  ('Benno Kaltefleiter', 'C', 'RB Lipsia', 6),
  ('Viggo Gebel', 'C', 'RB Lipsia', 6),
  ('Antonio Nusa', 'A', 'RB Lipsia', 17),
  ('Brajan Gruda', 'A', 'RB Lipsia', 17),
  ('Johan Bakayoko', 'A', 'RB Lipsia', 17),
  ('Christopher Nkunku', 'A', 'RB Lipsia', 17),
  ('Marc Guiu', 'A', 'RB Lipsia', 11),
  ('Tidiam Gomis', 'A', 'RB Lipsia', 11),
  ('Suleman Sani', 'A', 'RB Lipsia', 7),
  ('Rômulo', 'A', 'RB Lipsia', 7),
  ('Samba Konaté', 'A', 'RB Lipsia', 7),
  ('Álvaro Valles', 'P', 'Real Betis', 10),
  ('Diego Conde', 'P', 'Real Betis', 2),
  ('Héctor Bellerín', 'D', 'Real Betis', 8),
  ('Diego Llorente', 'D', 'Real Betis', 8),
  ('Natan', 'D', 'Real Betis', 8),
  ('Fran García', 'D', 'Real Betis', 8),
  ('Valentín Gómez', 'D', 'Real Betis', 8),
  ('Junior Firpo', 'D', 'Real Betis', 8),
  ('Marc Bartra', 'D', 'Real Betis', 5),
  ('Ángel Ortiz', 'D', 'Real Betis', 5),
  ('Giovani Lo Celso', 'C', 'Real Betis', 14),
  ('Isco', 'C', 'Real Betis', 14),
  ('Pablo Fornals', 'C', 'Real Betis', 9),
  ('Álvaro Fidalgo', 'C', 'Real Betis', 9),
  ('Nelson Deossa', 'C', 'Real Betis', 9),
  ('Marc Roca', 'C', 'Real Betis', 9),
  ('Facundo Bernal', 'C', 'Real Betis', 6),
  ('Antony', 'A', 'Real Betis', 26),
  ('Abde Ezzalzouli', 'A', 'Real Betis', 17),
  ('Cucho Hernández', 'A', 'Real Betis', 17),
  ('Rodrigo Riquelme', 'A', 'Real Betis', 11),
  ('Aitor Ruibal', 'A', 'Real Betis', 11),
  ('Pablo García', 'A', 'Real Betis', 7),
  ('Thibaut Courtois', 'P', 'Real Madrid', 16),
  ('Andriy Lunin', 'P', 'Real Madrid', 2),
  ('Dean Huijsen', 'D', 'Real Madrid', 18),
  ('Trent Alexander-Arnold', 'D', 'Real Madrid', 18),
  ('Ibrahima Konaté', 'D', 'Real Madrid', 18),
  ('Marc Cucurella', 'D', 'Real Madrid', 18),
  ('Álvaro Carreras', 'D', 'Real Madrid', 18),
  ('Denzel Dumfries', 'D', 'Real Madrid', 18),
  ('Éder Militão', 'D', 'Real Madrid', 12),
  ('Antonio Rüdiger', 'D', 'Real Madrid', 12),
  ('Raúl Asencio', 'D', 'Real Madrid', 8),
  ('Ferland Mendy', 'D', 'Real Madrid', 8),
  ('Jude Bellingham', 'C', 'Real Madrid', 31),
  ('Federico Valverde', 'C', 'Real Madrid', 31),
  ('Arda Güler', 'C', 'Real Madrid', 31),
  ('Aurélien Tchouaméni', 'C', 'Real Madrid', 22),
  ('Bernardo Silva', 'C', 'Real Madrid', 22),
  ('Eduardo Camavinga', 'C', 'Real Madrid', 14),
  ('Thiago Pitarch', 'C', 'Real Madrid', 3),
  ('Vinícius Júnior', 'A', 'Real Madrid', 50),
  ('Kylian Mbappé', 'A', 'Real Madrid', 50),
  ('Rodrygo', 'A', 'Real Madrid', 26),
  ('Endrick', 'A', 'Real Madrid', 17),
  ('Brahim Díaz', 'A', 'Real Madrid', 17),
  ('Yan Diomande', 'A', 'Real Madrid', 17),
  ('Carlos Espí', 'A', 'Real Madrid', 4),
  ('Mile Svilar', 'P', 'Roma', 10),
  ('Giorgio De Marzi', 'P', 'Roma', 2),
  ('Radosław Żelezny', 'P', 'Roma', 2),
  ('Pierluigi Gollini', 'P', 'Roma', 2),
  ('Devyne Rensch', 'D', 'Roma', 8),
  ('Angeliño', 'D', 'Roma', 8),
  ('Evan Ndicka', 'D', 'Roma', 8),
  ('Zeki Çelik', 'D', 'Roma', 8),
  ('Mario Hermoso', 'D', 'Roma', 8),
  ('Gianluca Mancini', 'D', 'Roma', 8),
  ('Wesley', 'D', 'Roma', 8),
  ('Daniele Ghilardi', 'D', 'Roma', 8),
  ('Jan Ziółkowski', 'D', 'Roma', 5),
  ('Manu Koné', 'C', 'Roma', 14),
  ('Bryan Cristante', 'C', 'Roma', 9),
  ('Lorenzo Pellegrini', 'C', 'Roma', 9),
  ('Neil El Aynaoui', 'C', 'Roma', 9),
  ('Niccolò Pisilli', 'C', 'Roma', 9),
  ('Artem Dovbyk', 'A', 'Roma', 17),
  ('Donyell Malen', 'A', 'Roma', 17),
  ('Matías Soulé', 'A', 'Roma', 17),
  ('Paulo Dybala', 'A', 'Roma', 17),
  ('Robinio Vaz', 'A', 'Roma', 11),
  ('Amin Ramazanov', 'P', 'Sabah', 4),
  ('Stas Pokatilov', 'P', 'Sabah', 2),
  ('Ravan Mirzammadov', 'P', 'Sabah', 2),
  ('Steve Solvet', 'D', 'Sabah', 5),
  ('Tymoteusz Puchacz', 'D', 'Sabah', 5),
  ('Akim Zedadka', 'D', 'Sabah', 5),
  ('Aden McCarthy', 'D', 'Sabah', 3),
  ('Rahman Dashdamirov', 'D', 'Sabah', 3),
  ('Tellur Mutallimov', 'D', 'Sabah', 3),
  ('Erivaldo Almeida', 'D', 'Sabah', 3),
  ('Japhet Dungus', 'D', 'Sabah', 3),
  ('Godfred Boakye', 'D', 'Sabah', 3),
  ('Kaheem Parris', 'C', 'Sabah', 6),
  ('Ivan Lepinjica', 'C', 'Sabah', 6),
  ('Joy-Lance Mickels', 'C', 'Sabah', 6),
  ('Veljko Simić', 'C', 'Sabah', 6),
  ('Zinédine Ould Khaled', 'C', 'Sabah', 6),
  ('Younes Lachaab', 'C', 'Sabah', 6),
  ('Xander Severina', 'C', 'Sabah', 6),
  ('Abdulakh Khaybulayev', 'C', 'Sabah', 3),
  ('Umarali Rakhmonaliev', 'C', 'Sabah', 3),
  ('Khayal Aliyev', 'C', 'Sabah', 3),
  ('Aleksey Isayev', 'C', 'Sabah', 3),
  ('Rauf Rustamli', 'C', 'Sabah', 3),
  ('Du Queiroz', 'C', 'Sabah', 3),
  ('Rodrigo Fernandes', 'C', 'Sabah', 3),
  ('Cafar Mukhtarov', 'C', 'Sabah', 3),
  ('Christian Nwachukwu', 'A', 'Sabah', 7),
  ('Carlos Eduardo', 'A', 'Sabah', 7),
  ('Timilehin Oluwaseun', 'A', 'Sabah', 4),
  ('Orphé Mbina', 'A', 'Sabah', 4),
  ('Dmytro Riznyk', 'P', 'Shakhtar Donetsk', 4),
  ('Kiril Fesyun', 'P', 'Shakhtar Donetsk', 2),
  ('Rostyslav Bahlay', 'P', 'Shakhtar Donetsk', 2),
  ('Denys Tvardovskyi', 'P', 'Shakhtar Donetsk', 2),
  ('Tymur Puzankov', 'P', 'Shakhtar Donetsk', 2),
  ('Marlon Santos', 'D', 'Shakhtar Donetsk', 5),
  ('Valeriy Bondar', 'D', 'Shakhtar Donetsk', 5),
  ('Pedro Henrique', 'D', 'Shakhtar Donetsk', 5),
  ('Irakli Azarovi', 'D', 'Shakhtar Donetsk', 5),
  ('Vinicius Tobias', 'D', 'Shakhtar Donetsk', 5),
  ('Alaa Ghram', 'D', 'Shakhtar Donetsk', 5),
  ('Mykola Matviyenko', 'D', 'Shakhtar Donetsk', 5),
  ('Alan Matturro', 'D', 'Shakhtar Donetsk', 3),
  ('Maryan Faryna', 'D', 'Shakhtar Donetsk', 3),
  ('Viktor Korniyenko', 'D', 'Shakhtar Donetsk', 3),
  ('Roman Savchenko', 'D', 'Shakhtar Donetsk', 3),
  ('Marlon Gomes', 'C', 'Shakhtar Donetsk', 9),
  ('Pedrinho', 'C', 'Shakhtar Donetsk', 9),
  ('Dmytro Kryskiv', 'C', 'Shakhtar Donetsk', 6),
  ('Newerton', 'C', 'Shakhtar Donetsk', 6),
  ('Isaque', 'C', 'Shakhtar Donetsk', 6),
  ('Oleksandr Karavayev', 'C', 'Shakhtar Donetsk', 6),
  ('Oleh Ocheretko', 'C', 'Shakhtar Donetsk', 6),
  ('Viktor Tsukanov', 'C', 'Shakhtar Donetsk', 3),
  ('Yehor Nazaryna', 'C', 'Shakhtar Donetsk', 3),
  ('Lucas Ferreira', 'C', 'Shakhtar Donetsk', 3),
  ('Prosper Obah', 'C', 'Shakhtar Donetsk', 3),
  ('Gleiker Mendoza', 'C', 'Shakhtar Donetsk', 3),
  ('Anton Hlushchenko', 'C', 'Shakhtar Donetsk', 3),
  ('Maryan Shved', 'C', 'Shakhtar Donetsk', 3),
  ('Eguinaldo', 'A', 'Shakhtar Donetsk', 11),
  ('Lassina Traoré', 'A', 'Shakhtar Donetsk', 11),
  ('Kauã Elias', 'A', 'Shakhtar Donetsk', 11),
  ('Gabriel Carvalho', 'A', 'Shakhtar Donetsk', 7),
  ('Alisson Santana', 'A', 'Shakhtar Donetsk', 7),
  ('Muhamadou Kanteh', 'A', 'Shakhtar Donetsk', 4),
  ('Luca Meirelles', 'A', 'Shakhtar Donetsk', 4),
  ('Ryan Roberto', 'A', 'Shakhtar Donetsk', 4),
  ('Bruninho', 'A', 'Shakhtar Donetsk', 4),
  ('Jindřich Staněk', 'P', 'Slavia Praga', 4),
  ('Ondřej Kolář', 'P', 'Slavia Praga', 2),
  ('Nazar Domchak', 'P', 'Slavia Praga', 2),
  ('Jakub Markovič', 'P', 'Slavia Praga', 2),
  ('Štěpán Chaloupek', 'D', 'Slavia Praga', 5),
  ('Tomáš Holeš', 'D', 'Slavia Praga', 5),
  ('David Zima', 'D', 'Slavia Praga', 5),
  ('Igoh Ogbu', 'D', 'Slavia Praga', 5),
  ('David Jurásek', 'D', 'Slavia Praga', 5),
  ('Ange N''Guessan', 'D', 'Slavia Praga', 3),
  ('Samuel Isife', 'D', 'Slavia Praga', 3),
  ('Tomáš Vlček', 'D', 'Slavia Praga', 3),
  ('Mikuláš Konečný', 'D', 'Slavia Praga', 3),
  ('Eliáš Piták', 'D', 'Slavia Praga', 3),
  ('Lukáš Provod', 'C', 'Slavia Praga', 9),
  ('Oskar Kubiak', 'C', 'Slavia Praga', 6),
  ('Youssoupha Sanyang', 'C', 'Slavia Praga', 6),
  ('David Moses', 'C', 'Slavia Praga', 6),
  ('Toumani Diakité', 'C', 'Slavia Praga', 6),
  ('Michal Sadílek', 'C', 'Slavia Praga', 6),
  ('Danijel Šturm', 'C', 'Slavia Praga', 3),
  ('Mubarak Suleiman', 'C', 'Slavia Praga', 3),
  ('Wiktor Nowak', 'C', 'Slavia Praga', 3),
  ('Pavel Kačor', 'C', 'Slavia Praga', 3),
  ('Mojmír Chytil', 'A', 'Slavia Praga', 11),
  ('Tomáš Chorý', 'A', 'Slavia Praga', 11),
  ('Ivan Schranz', 'A', 'Slavia Praga', 11),
  ('Adonija Ouanda', 'A', 'Slavia Praga', 7),
  ('Emmanuel Ayaosi', 'A', 'Slavia Praga', 4),
  ('Dominik Takáč', 'P', 'Slovan Bratislava', 4),
  ('Aleksandar Popović', 'P', 'Slovan Bratislava', 2),
  ('Matúš Macík', 'P', 'Slovan Bratislava', 2),
  ('Kevin Wimmer', 'D', 'Slovan Bratislava', 5),
  ('Kenan Bajrić', 'D', 'Slovan Bratislava', 5),
  ('Jurij Medveděv', 'D', 'Slovan Bratislava', 5),
  ('César Blackman', 'D', 'Slovan Bratislava', 5),
  ('Samuel Kozlovský', 'D', 'Slovan Bratislava', 3),
  ('Svetozar Marković', 'D', 'Slovan Bratislava', 3),
  ('Sandro Cruz', 'D', 'Slovan Bratislava', 3),
  ('Sahmkou Camara', 'D', 'Slovan Bratislava', 3),
  ('Tigran Barseghyan', 'C', 'Slovan Bratislava', 9),
  ('Peter Pokorný', 'C', 'Slovan Bratislava', 6),
  ('Rahim Ibrahim', 'C', 'Slovan Bratislava', 6),
  ('Artur Gajdoš', 'C', 'Slovan Bratislava', 6),
  ('Danylo Ihnatenko', 'C', 'Slovan Bratislava', 6),
  ('Leo Hofstädter', 'C', 'Slovan Bratislava', 3),
  ('Alen Mustafić', 'C', 'Slovan Bratislava', 3),
  ('Cristian Martínez', 'C', 'Slovan Bratislava', 3),
  ('Daiki Matsuoka', 'C', 'Slovan Bratislava', 3),
  ('Andraž Šporar', 'A', 'Slovan Bratislava', 11),
  ('Mykola Kukharevych', 'A', 'Slovan Bratislava', 7),
  ('Nino Marcelli', 'A', 'Slovan Bratislava', 7),
  ('Kelvin Ofori', 'A', 'Slovan Bratislava', 7),
  ('Roman Čerepkai', 'A', 'Slovan Bratislava', 4),
  ('Alasana Yirajang', 'A', 'Slovan Bratislava', 4),
  ('Manasse Kianga', 'A', 'Slovan Bratislava', 4),
  ('Suleiman Camara', 'A', 'Slovan Bratislava', 4),
  ('Matúš Tomáško', 'A', 'Slovan Bratislava', 4),
  ('Alexej Maroš', 'A', 'Slovan Bratislava', 4),
  ('Adam Griger', 'A', 'Slovan Bratislava', 4),
  ('Rui Silva', 'P', 'Sporting CP', 10),
  ('João Virgínia', 'P', 'Sporting CP', 2),
  ('Diego Callai', 'P', 'Sporting CP', 2),
  ('Francisco Silva', 'P', 'Sporting CP', 2),
  ('Maximiliano Araújo', 'D', 'Sporting CP', 12),
  ('Gonçalo Inácio', 'D', 'Sporting CP', 12),
  ('Zeno Debast', 'D', 'Sporting CP', 8),
  ('Georgios Vagiannidis', 'D', 'Sporting CP', 8),
  ('Iván Fresneda', 'D', 'Sporting CP', 8),
  ('Ousmane Diomande', 'D', 'Sporting CP', 8),
  ('Eduardo Quaresma', 'D', 'Sporting CP', 8),
  ('Nuno Santos', 'D', 'Sporting CP', 5),
  ('Ibrahima Ba', 'D', 'Sporting CP', 5),
  ('Geny Catamo', 'C', 'Sporting CP', 14),
  ('Rodrigo Zalazar', 'C', 'Sporting CP', 14),
  ('Silas Andersen', 'C', 'Sporting CP', 9),
  ('João Simões', 'C', 'Sporting CP', 9),
  ('Giorgi Kochorashvili', 'C', 'Sporting CP', 9),
  ('Sergi Altimira', 'C', 'Sporting CP', 6),
  ('Pedro Lima', 'C', 'Sporting CP', 6),
  ('Flávio Gonçalves', 'C', 'Sporting CP', 6),
  ('Issa Doumbia', 'C', 'Sporting CP', 6),
  ('Koba Koindredi', 'C', 'Sporting CP', 6),
  ('Mateo Tanlongo', 'C', 'Sporting CP', 6),
  ('Luis Suárez', 'A', 'Sporting CP', 26),
  ('Fotis Ioannidis', 'A', 'Sporting CP', 17),
  ('Luis Guilherme', 'A', 'Sporting CP', 11),
  ('Rafael Nel', 'A', 'Sporting CP', 7),
  ('Jesse Derry', 'A', 'Sporting CP', 7),
  ('Fabian Bredlow', 'P', 'Stoccarda', 7),
  ('Marius Funk', 'P', 'Stoccarda', 2),
  ('Dennis Seimen', 'P', 'Stoccarda', 2),
  ('Stefan Drljača', 'P', 'Stoccarda', 2),
  ('Ameen Al-Dakhil', 'D', 'Stoccarda', 8),
  ('Ramon Hendriks', 'D', 'Stoccarda', 8),
  ('Josha Vagnoman', 'D', 'Stoccarda', 8),
  ('Maximilian Mittelstädt', 'D', 'Stoccarda', 8),
  ('Leonidas Stergiou', 'D', 'Stoccarda', 8),
  ('Lorenz Assignon', 'D', 'Stoccarda', 8),
  ('Jeff Chabot', 'D', 'Stoccarda', 8),
  ('Finn Jeltsch', 'D', 'Stoccarda', 8),
  ('Luca Jaquez', 'D', 'Stoccarda', 5),
  ('Dan-Axel Zagadou', 'D', 'Stoccarda', 5),
  ('Angelo Stiller', 'C', 'Stoccarda', 14),
  ('Bilal El Khannouss', 'C', 'Stoccarda', 14),
  ('Atakan Karazor', 'C', 'Stoccarda', 9),
  ('Nikolas Nartey', 'C', 'Stoccarda', 9),
  ('Grischa Prömel', 'C', 'Stoccarda', 6),
  ('Ertuğrul Yiğit', 'C', 'Stoccarda', 6),
  ('Ermedin Demirović', 'A', 'Stoccarda', 17),
  ('Jamie Leweling', 'A', 'Stoccarda', 17),
  ('Deniz Undav', 'A', 'Stoccarda', 17),
  ('Tiago Tomás', 'A', 'Stoccarda', 11),
  ('Chris Führich', 'A', 'Stoccarda', 11),
  ('Dženan Pejčinović', 'A', 'Stoccarda', 7),
  ('Justin Diehl', 'A', 'Stoccarda', 7),
  ('Jarzinho Malanga', 'A', 'Stoccarda', 7),
  ('Leo Sauer', 'A', 'Stoccarda', 7),
  ('Arild Østbø', 'P', 'Viking', 4),
  ('Erlend Jacobsen', 'P', 'Viking', 2),
  ('Ľubomír Belko', 'P', 'Viking', 2),
  ('Viljar Vevatne', 'D', 'Viking', 5),
  ('Henrik Heggheim', 'D', 'Viking', 5),
  ('Essiën Bassey', 'D', 'Viking', 5),
  ('Kristoffer Haugen', 'D', 'Viking', 5),
  ('Herman Haugen', 'D', 'Viking', 3),
  ('Martin Ove Roseth', 'D', 'Viking', 3),
  ('Gianni Stensness', 'D', 'Viking', 3),
  ('Sondre Bjørshol', 'D', 'Viking', 3),
  ('Anders Bærtelsen', 'D', 'Viking', 3),
  ('Vetle Auklend', 'D', 'Viking', 3),
  ('Henrik Falchener', 'D', 'Viking', 3),
  ('Jesper Daland', 'D', 'Viking', 3),
  ('Franco Lino', 'D', 'Viking', 3),
  ('Fillip Voster Botnen', 'D', 'Viking', 3),
  ('Kristoffer Askildsen', 'C', 'Viking', 6),
  ('Joe Bell', 'C', 'Viking', 6),
  ('Henrik Bjørdal', 'C', 'Viking', 6),
  ('Simen Kvia-Egeskog', 'C', 'Viking', 3),
  ('Tobias Moi', 'C', 'Viking', 3),
  ('Jakob Segadal Hansen', 'C', 'Viking', 3),
  ('Ola Visted', 'C', 'Viking', 3),
  ('Ruben Alte', 'C', 'Viking', 3),
  ('Nicholas D''Agostino', 'A', 'Viking', 7),
  ('Zlatko Tripić', 'A', 'Viking', 7),
  ('Romano Postema', 'A', 'Viking', 7),
  ('Veton Berisha', 'A', 'Viking', 7),
  ('Peter Christiansen', 'A', 'Viking', 7),
  ('Erik Botheim', 'A', 'Viking', 7),
  ('Amin Ćosić', 'A', 'Viking', 4),
  ('Niklas Fuglestad', 'A', 'Viking', 4),
  ('Kelvin Frimpong', 'A', 'Viking', 4),
  ('Luiz Júnior', 'P', 'Villarreal', 10),
  ('Rubén Gómez', 'P', 'Villarreal', 2),
  ('Logan Costa', 'D', 'Villarreal', 8),
  ('Alex Freeman', 'D', 'Villarreal', 8),
  ('Pau Navarro', 'D', 'Villarreal', 8),
  ('Juan Foyth', 'D', 'Villarreal', 8),
  ('Renato Veiga', 'D', 'Villarreal', 8),
  ('Santiago Mouriño', 'D', 'Villarreal', 8),
  ('Sergi Cardona', 'D', 'Villarreal', 8),
  ('Carlos Romero', 'D', 'Villarreal', 5),
  ('Daniel Budesca', 'D', 'Villarreal', 5),
  ('Lautaro Spatz', 'D', 'Villarreal', 5),
  ('César Bonafé', 'D', 'Villarreal', 5),
  ('Moussa Diallo', 'D', 'Villarreal', 5),
  ('Alberto Moleiro', 'C', 'Villarreal', 14),
  ('Santi Comesaña', 'C', 'Villarreal', 9),
  ('Pape Gueye', 'C', 'Villarreal', 9),
  ('Thiago Fernández', 'C', 'Villarreal', 6),
  ('Carlos Maciá', 'C', 'Villarreal', 6),
  ('Alassane Diatta', 'C', 'Villarreal', 6),
  ('Cheikh Thiam', 'C', 'Villarreal', 6),
  ('Gerard Moreno', 'A', 'Villarreal', 17),
  ('Georges Mikautadze', 'A', 'Villarreal', 17),
  ('Nicolas Pépé', 'A', 'Villarreal', 17),
  ('Ayoze Pérez', 'A', 'Villarreal', 17),
  ('Tajon Buchanan', 'A', 'Villarreal', 11),
  ('Tani Oluwaseyi', 'A', 'Villarreal', 11),
  ('Ilias Akhomach', 'A', 'Villarreal', 11),
  ('Pau Cabanes', 'A', 'Villarreal', 7),
  ('Nizar El Jmili', 'A', 'Villarreal', 7),
  ('Álex Forés', 'A', 'Villarreal', 7)
) as v(name, role, club, price)
join public.clubs c on c.name = v.club
on conflict (name, club_id) do update set role = excluded.role, price = excluded.price, active = true;

-- === 06 FIXTURES AND SQUADS ===
create table if not exists public.fixtures (
  id            bigint generated always as identity primary key,
  matchday_id   bigint not null references public.matchdays(id) on delete cascade,
  home_club_id  bigint not null references public.clubs(id) on delete cascade,
  away_club_id  bigint not null references public.clubs(id) on delete cascade,
  kickoff       timestamptz not null,
  home_score    int,
  away_score    int,
  unique (matchday_id, home_club_id),
  unique (matchday_id, away_club_id),
  check (home_club_id <> away_club_id)
);
create index if not exists fixtures_matchday_idx on public.fixtures(matchday_id);

alter table public.fixtures enable row level security;
drop policy if exists "fixtures_select" on public.fixtures;
create policy "fixtures_select" on public.fixtures for select to anon, authenticated using (true);
drop policy if exists "fixtures_admin" on public.fixtures;
create policy "fixtures_admin" on public.fixtures for all
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

drop table if exists public._cal;
create table public._cal (md int, ko timestamp, home text, away text);
insert into _cal values
  (1, '2026-09-08 18:45', 'AEK Atene', 'LASK'),
  (1, '2026-09-08 18:45', 'Club Brugge', 'Aston Villa'),
  (1, '2026-09-08 21:00', 'Borussia Dortmund', 'Villarreal'),
  (1, '2026-09-08 21:00', 'Porto', 'Manchester City'),
  (1, '2026-09-08 21:00', 'Lille', 'Real Betis'),
  (1, '2026-09-08 21:00', 'Real Madrid', 'Inter'),
  (1, '2026-09-09 18:45', 'Barcellona', 'Feyenoord'),
  (1, '2026-09-09 18:45', 'Stoccarda', 'Viking'),
  (1, '2026-09-09 21:00', 'Liverpool', 'Atlético Madrid'),
  (1, '2026-09-09 21:00', 'Paris Saint-Germain', 'Slovan Bratislava'),
  (1, '2026-09-09 21:00', 'Sporting CP', 'Galatasaray'),
  (1, '2026-09-09 21:00', 'Napoli', 'Arsenal'),
  (1, '2026-09-10 18:45', 'Fenerbahçe', 'Roma'),
  (1, '2026-09-10 18:45', 'PSV Eindhoven', 'Shakhtar Donetsk'),
  (1, '2026-09-10 21:00', 'Como', 'RB Lipsia'),
  (1, '2026-09-10 21:00', 'Bayern Monaco', 'Bodø/Glimt'),
  (1, '2026-09-10 21:00', 'Manchester United', 'Sabah'),
  (1, '2026-09-10 21:00', 'Slavia Praga', 'Lens'),
  (2, '2026-10-13 18:45', 'Lens', 'Sporting CP'),
  (2, '2026-10-13 18:45', 'Sabah', 'Slavia Praga'),
  (2, '2026-10-13 21:00', 'Arsenal', 'Lille'),
  (2, '2026-10-13 21:00', 'Atlético Madrid', 'Manchester United'),
  (2, '2026-10-13 21:00', 'Inter', 'Club Brugge'),
  (2, '2026-10-13 21:00', 'Galatasaray', 'Barcellona'),
  (2, '2026-10-13 21:00', 'RB Lipsia', 'PSV Eindhoven'),
  (2, '2026-10-13 21:00', 'Viking', 'Bayern Monaco'),
  (2, '2026-10-13 21:00', 'Villarreal', 'Napoli'),
  (2, '2026-10-14 18:45', 'Feyenoord', 'Como'),
  (2, '2026-10-14 18:45', 'LASK', 'Liverpool'),
  (2, '2026-10-14 21:00', 'Roma', 'Real Madrid'),
  (2, '2026-10-14 21:00', 'Aston Villa', 'Fenerbahçe'),
  (2, '2026-10-14 21:00', 'Shakhtar Donetsk', 'AEK Atene'),
  (2, '2026-10-14 21:00', 'Bodø/Glimt', 'Borussia Dortmund'),
  (2, '2026-10-14 21:00', 'Manchester City', 'Paris Saint-Germain'),
  (2, '2026-10-14 21:00', 'Real Betis', 'Porto'),
  (2, '2026-10-14 21:00', 'Slovan Bratislava', 'Stoccarda'),
  (3, '2026-10-20 18:45', 'Fenerbahçe', 'Slavia Praga'),
  (3, '2026-10-20 18:45', 'Sabah', 'Borussia Dortmund'),
  (3, '2026-10-20 21:00', 'Roma', 'Slovan Bratislava'),
  (3, '2026-10-20 21:00', 'Porto', 'PSV Eindhoven'),
  (3, '2026-10-20 21:00', 'Liverpool', 'Villarreal'),
  (3, '2026-10-20 21:00', 'Manchester City', 'AEK Atene'),
  (3, '2026-10-20 21:00', 'Paris Saint-Germain', 'Barcellona'),
  (3, '2026-10-20 21:00', 'Napoli', 'Bodø/Glimt'),
  (3, '2026-10-20 21:00', 'Stoccarda', 'Atlético Madrid'),
  (3, '2026-10-21 18:45', 'Como', 'Manchester United'),
  (3, '2026-10-21 18:45', 'Lille', 'Galatasaray'),
  (3, '2026-10-21 21:00', 'Aston Villa', 'Viking'),
  (3, '2026-10-21 21:00', 'Club Brugge', 'Lens'),
  (3, '2026-10-21 21:00', 'Bayern Monaco', 'Arsenal'),
  (3, '2026-10-21 21:00', 'Inter', 'Shakhtar Donetsk'),
  (3, '2026-10-21 21:00', 'Real Madrid', 'RB Lipsia'),
  (3, '2026-10-21 21:00', 'Real Betis', 'Feyenoord'),
  (3, '2026-10-21 21:00', 'Sporting CP', 'LASK'),
  (4, '2026-11-03 18:45', 'Shakhtar Donetsk', 'Sporting CP'),
  (4, '2026-11-03 18:45', 'Galatasaray', 'Stoccarda'),
  (4, '2026-11-03 21:00', 'Atlético Madrid', 'Bayern Monaco'),
  (4, '2026-11-03 21:00', 'Barcellona', 'Aston Villa'),
  (4, '2026-11-03 21:00', 'Feyenoord', 'Inter'),
  (4, '2026-11-03 21:00', 'Bodø/Glimt', 'Lille'),
  (4, '2026-11-03 21:00', 'LASK', 'Slovan Bratislava'),
  (4, '2026-11-03 21:00', 'Manchester United', 'Roma'),
  (4, '2026-11-03 21:00', 'Villarreal', 'Paris Saint-Germain'),
  (4, '2026-11-04 18:45', 'AEK Atene', 'Real Madrid'),
  (4, '2026-11-04 18:45', 'Fenerbahçe', 'Liverpool'),
  (4, '2026-11-04 21:00', 'Borussia Dortmund', 'Real Betis'),
  (4, '2026-11-04 21:00', 'Porto', 'Napoli'),
  (4, '2026-11-04 21:00', 'PSV Eindhoven', 'Club Brugge'),
  (4, '2026-11-04 21:00', 'RB Lipsia', 'Manchester City'),
  (4, '2026-11-04 21:00', 'Lens', 'Como'),
  (4, '2026-11-04 21:00', 'Slavia Praga', 'Arsenal'),
  (4, '2026-11-04 21:00', 'Viking', 'Sabah'),
  (5, '2026-11-24 18:45', 'Bodø/Glimt', 'LASK'),
  (5, '2026-11-24 18:45', 'Galatasaray', 'Aston Villa'),
  (5, '2026-11-24 21:00', 'Arsenal', 'Borussia Dortmund'),
  (5, '2026-11-24 21:00', 'Como', 'AEK Atene'),
  (5, '2026-11-24 21:00', 'Feyenoord', 'Porto'),
  (5, '2026-11-24 21:00', 'Manchester City', 'Napoli'),
  (5, '2026-11-24 21:00', 'RB Lipsia', 'Lens'),
  (5, '2026-11-24 21:00', 'Real Madrid', 'PSV Eindhoven'),
  (5, '2026-11-24 21:00', 'Slovan Bratislava', 'Real Betis'),
  (5, '2026-11-25 18:45', 'Sabah', 'Barcellona'),
  (5, '2026-11-25 18:45', 'Slavia Praga', 'Villarreal'),
  (5, '2026-11-25 21:00', 'Atlético Madrid', 'Viking'),
  (5, '2026-11-25 21:00', 'Club Brugge', 'Liverpool'),
  (5, '2026-11-25 21:00', 'Inter', 'Stoccarda'),
  (5, '2026-11-25 21:00', 'Shakhtar Donetsk', 'Fenerbahçe'),
  (5, '2026-11-25 21:00', 'Lille', 'Bayern Monaco'),
  (5, '2026-11-25 21:00', 'Paris Saint-Germain', 'Roma'),
  (5, '2026-11-25 21:00', 'Sporting CP', 'Manchester United'),
  (6, '2026-12-08 18:45', 'Viking', 'Feyenoord'),
  (6, '2026-12-08 18:45', 'Villarreal', 'Sabah'),
  (6, '2026-12-08 21:00', 'AEK Atene', 'Galatasaray'),
  (6, '2026-12-08 21:00', 'Roma', 'Sporting CP'),
  (6, '2026-12-08 21:00', 'Aston Villa', 'Paris Saint-Germain'),
  (6, '2026-12-08 21:00', 'Barcellona', 'Manchester City'),
  (6, '2026-12-08 21:00', 'Bayern Monaco', 'Slavia Praga'),
  (6, '2026-12-08 21:00', 'Manchester United', 'RB Lipsia'),
  (6, '2026-12-08 21:00', 'Napoli', 'Club Brugge'),
  (6, '2026-12-09 18:45', 'Real Betis', 'Como'),
  (6, '2026-12-09 18:45', 'Slovan Bratislava', 'Shakhtar Donetsk'),
  (6, '2026-12-09 21:00', 'Arsenal', 'Real Madrid'),
  (6, '2026-12-09 21:00', 'Borussia Dortmund', 'Inter'),
  (6, '2026-12-09 21:00', 'LASK', 'Fenerbahçe'),
  (6, '2026-12-09 21:00', 'Liverpool', 'Porto'),
  (6, '2026-12-09 21:00', 'Lens', 'Bodø/Glimt'),
  (6, '2026-12-09 21:00', 'PSV Eindhoven', 'Atlético Madrid'),
  (6, '2026-12-09 21:00', 'Stoccarda', 'Lille'),
  (7, '2027-01-19 18:45', 'Bodø/Glimt', 'Atlético Madrid'),
  (7, '2027-01-19 18:45', 'Galatasaray', 'Feyenoord'),
  (7, '2027-01-19 21:00', 'AEK Atene', 'Roma'),
  (7, '2027-01-19 21:00', 'Aston Villa', 'Borussia Dortmund'),
  (7, '2027-01-19 21:00', 'Inter', 'Liverpool'),
  (7, '2027-01-19 21:00', 'Porto', 'Slavia Praga'),
  (7, '2027-01-19 21:00', 'Lille', 'Slovan Bratislava'),
  (7, '2027-01-19 21:00', 'Real Madrid', 'LASK'),
  (7, '2027-01-19 21:00', 'Stoccarda', 'Club Brugge'),
  (7, '2027-01-20 18:45', 'Fenerbahçe', 'Villarreal'),
  (7, '2027-01-20 18:45', 'Sabah', 'Napoli'),
  (7, '2027-01-20 21:00', 'Como', 'Paris Saint-Germain'),
  (7, '2027-01-20 21:00', 'Manchester United', 'Bayern Monaco'),
  (7, '2027-01-20 21:00', 'RB Lipsia', 'Shakhtar Donetsk'),
  (7, '2027-01-20 21:00', 'Lens', 'Manchester City'),
  (7, '2027-01-20 21:00', 'Real Betis', 'Arsenal'),
  (7, '2027-01-20 21:00', 'Sporting CP', 'Barcellona'),
  (7, '2027-01-20 21:00', 'Viking', 'PSV Eindhoven'),
  (8, '2027-01-27 21:00', 'Arsenal', 'Sabah'),
  (8, '2027-01-27 21:00', 'Roma', 'Lille'),
  (8, '2027-01-27 21:00', 'Atlético Madrid', 'Fenerbahçe'),
  (8, '2027-01-27 21:00', 'Borussia Dortmund', 'AEK Atene'),
  (8, '2027-01-27 21:00', 'Club Brugge', 'Bodø/Glimt'),
  (8, '2027-01-27 21:00', 'Bayern Monaco', 'Real Betis'),
  (8, '2027-01-27 21:00', 'Barcellona', 'Como'),
  (8, '2027-01-27 21:00', 'Shakhtar Donetsk', 'Real Madrid'),
  (8, '2027-01-27 21:00', 'Feyenoord', 'RB Lipsia'),
  (8, '2027-01-27 21:00', 'LASK', 'Porto'),
  (8, '2027-01-27 21:00', 'Liverpool', 'Lens'),
  (8, '2027-01-27 21:00', 'Manchester City', 'Sporting CP'),
  (8, '2027-01-27 21:00', 'Paris Saint-Germain', 'Galatasaray'),
  (8, '2027-01-27 21:00', 'PSV Eindhoven', 'Stoccarda'),
  (8, '2027-01-27 21:00', 'Slavia Praga', 'Aston Villa'),
  (8, '2027-01-27 21:00', 'Napoli', 'Viking'),
  (8, '2027-01-27 21:00', 'Villarreal', 'Manchester United'),
  (8, '2027-01-27 21:00', 'Slovan Bratislava', 'Inter');

delete from public.fixtures f using public.matchdays m
where f.matchday_id = m.id and m.number between 1 and 8;

insert into public.fixtures (matchday_id, home_club_id, away_club_id, kickoff)
select m.id, h.id, a.id, c.ko at time zone 'Europe/Rome'
from _cal c
join public.matchdays m on m.number = c.md
join public.clubs h on h.name = c.home
join public.clubs a on a.name = c.away;

drop table public._cal;

alter table public.settings
  add column if not exists squad_p        int not null default 3,
  add column if not exists squad_d        int not null default 8,
  add column if not exists squad_c        int not null default 8,
  add column if not exists squad_a        int not null default 6,
  add column if not exists squad_deadline timestamptz,
  add column if not exists market_from    timestamptz,
  add column if not exists market_to      timestamptz,
  add column if not exists market_max     int not null default 3;

update public.settings set
  budget         = 400,
  squad_deadline = coalesce((select deadline from public.matchdays where number = 2), '2026-10-13 18:45+02'),
  market_from    = '2026-11-05 10:00+01',
  market_to      = coalesce((select deadline from public.matchdays where number = 5), '2026-11-24 18:45+01'),
  market_max     = 3
where id = 1;

create table if not exists public.squads (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  market_base    bigint[],
  market_base_at timestamptz
);

create table if not exists public.squad_players (
  user_id   uuid   not null references public.squads(user_id) on delete cascade,
  player_id bigint not null references public.players(id) on delete cascade,
  price     int    not null,
  primary key (user_id, player_id)
);
create index if not exists squad_players_player_idx on public.squad_players(player_id);

alter table public.squads enable row level security;
alter table public.squad_players enable row level security;

drop policy if exists "squads_select" on public.squads;
create policy "squads_select" on public.squads for select to anon, authenticated using (true);
drop policy if exists "squad_players_select" on public.squad_players;
create policy "squad_players_select" on public.squad_players for select to anon, authenticated using (true);

create or replace function public.save_squad(p_players bigint[])
returns json language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  s public.settings;
  v_ids bigint[];
  v_old bigint[];
  v_has boolean;
  v_base bigint[];
  v_base_at timestamptz;
  v_phase text;
  n_p int; n_d int; n_c int; n_a int;
  v_cost int;
  v_changes int := 0;
  v_txt text;
  v_paid boolean;
begin
  if uid is null then raise exception 'Devi accedere per salvare la rosa'; end if;

  select subscription_paid into v_paid from public.profiles where id = uid;
  if not coalesce(v_paid, false) then
    raise exception 'Abbonamento necessario: paga 25€ dal tuo profilo per creare la rosa';
  end if;

  select * into s from public.settings where id = 1;

  v_ids := array(select distinct x from unnest(coalesce(p_players, '{}')) x where x is not null);
  if cardinality(v_ids) <> cardinality(coalesce(p_players, '{}')) then
    raise exception 'Hai inserito lo stesso giocatore due volte';
  end if;
  if exists (select 1 from unnest(v_ids) x where not exists (select 1 from public.players p where p.id = x)) then
    raise exception 'Giocatore non trovato';
  end if;

  select count(*) filter (where role = 'P'), count(*) filter (where role = 'D'),
         count(*) filter (where role = 'C'), count(*) filter (where role = 'A')
    into n_p, n_d, n_c, n_a
  from public.players where id = any(v_ids);
  if n_p <> s.squad_p or n_d <> s.squad_d or n_c <> s.squad_c or n_a <> s.squad_a then
    raise exception 'La rosa deve avere % portieri, % difensori, % centrocampisti e % attaccanti (ora: %, %, %, %)',
      s.squad_p, s.squad_d, s.squad_c, s.squad_a, n_p, n_d, n_c, n_a;
  end if;

  if s.max_per_club is not null then
    select c.name into v_txt from public.players p join public.clubs c on c.id = p.club_id
    where p.id = any(v_ids) group by c.name having count(*) > s.max_per_club limit 1;
    if v_txt is not null then
      raise exception 'Massimo % giocatori della stessa squadra (troppi del %)', s.max_per_club, v_txt;
    end if;
  end if;

  select true, market_base, market_base_at into v_has, v_base, v_base_at from public.squads where user_id = uid;
  v_has := coalesce(v_has, false);
  v_old := array(select player_id from public.squad_players where user_id = uid);

  if not v_has or cardinality(v_old) = 0 or s.squad_deadline is null or now() < s.squad_deadline then
    v_phase := 'libera';
  elsif s.market_from is not null and s.market_to is not null and now() >= s.market_from and now() < s.market_to then
    v_phase := 'mercato';
  else
    raise exception 'La rosa è bloccata: potrai cambiarla solo durante il mercato di metà girone';
  end if;

  select string_agg(p.name, ', ') into v_txt from public.players p
  where p.id = any(v_ids) and not (p.id = any(v_old)) and not coalesce(p.active, true);
  if v_txt is not null then raise exception 'Non più in lista UEFA: %', v_txt; end if;

  if v_phase = 'mercato' then
    select coalesce(sum(coalesce(sp.price, p.price)), 0) into v_cost
    from public.players p left join public.squad_players sp on sp.user_id = uid and sp.player_id = p.id
    where p.id = any(v_ids);
  else
    select coalesce(sum(p.price), 0) into v_cost from public.players p where p.id = any(v_ids);
  end if;
  if s.budget is not null and v_cost > s.budget then
    raise exception 'Budget superato: % crediti su %', v_cost, s.budget;
  end if;

  if v_phase = 'mercato' then
    if v_base is null or v_base_at is null or v_base_at < s.market_from then
      v_base := v_old;
      update public.squads set market_base = v_old, market_base_at = now() where user_id = uid;
    end if;
    select count(*) into v_changes from unnest(v_ids) x where not (x = any(v_base));
    if v_changes > s.market_max then
      raise exception 'Al mercato puoi cambiare al massimo % giocatori (ne stai cambiando %)', s.market_max, v_changes;
    end if;
  end if;

  insert into public.squads (user_id) values (uid)
    on conflict (user_id) do update set updated_at = now();
  delete from public.squad_players where user_id = uid and not (player_id = any(v_ids));
  if v_phase = 'libera' then
    update public.squad_players sp set price = p.price from public.players p
    where sp.user_id = uid and p.id = sp.player_id;
  end if;
  insert into public.squad_players (user_id, player_id, price)
    select uid, p.id, p.price from public.players p where p.id = any(v_ids)
    on conflict (user_id, player_id) do nothing;

  return json_build_object('phase', v_phase, 'cost', v_cost, 'changes', v_changes);
end $$;

revoke all on function public.save_squad(bigint[]) from public, anon;
grant execute on function public.save_squad(bigint[]) to authenticated;

create or replace function public.check_lineup_in_squad()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_name text;
begin
  select user_id into v_user from public.lineups where id = new.lineup_id;
  if not exists (select 1 from public.squad_players where user_id = v_user and player_id = new.player_id) then
    select name into v_name from public.players where id = new.player_id;
    raise exception 'Puoi schierare solo giocatori della tua rosa (% non c''è)', coalesce(v_name, '?');
  end if;
  return new;
end $$;

drop trigger if exists lineup_players_in_squad on public.lineup_players;
create trigger lineup_players_in_squad
  before insert or update of player_id on public.lineup_players
  for each row execute function public.check_lineup_in_squad();

-- === 07 SUBSCRIPTION ===
alter table public.profiles
  add column if not exists subscription_paid     boolean     not null default false,
  add column if not exists subscription_paid_at  timestamptz,
  add column if not exists paypal_order_id       text;

alter table public.settings
  add column if not exists subscription_price  numeric(10,2) not null default 25.00,
  add column if not exists subscription_label  text          not null default 'Abbonamento Champions 2026/27';

update public.settings set subscription_price = 25.00, subscription_label = 'Abbonamento Champions 2026/27' where id = 1;

create or replace function public.is_subscribed()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select subscription_paid from public.profiles where id = auth.uid()), false);
$$;

revoke all on function public.is_subscribed() from public, anon;
grant execute on function public.is_subscribed() to authenticated;

create or replace function public.mark_subscription_paid(p_uid uuid, p_order_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
    set subscription_paid = true,
        subscription_paid_at = now(),
        paypal_order_id = p_order_id
    where id = p_uid;
end;
$$;

revoke all on function public.mark_subscription_paid(uuid, text) from public, anon, authenticated;

-- === 08 PAYPAL SETTINGS ===
alter table public.settings
  add column if not exists paypal_client_id     text,
  add column if not exists paypal_client_secret  text,
  add column if not exists paypal_mode           text not null default 'sandbox';

update public.settings set
  paypal_client_id = 'AdfkKzl7a8AwCSrmsJ9SPZKvueAySSn9GVY1LPwVi7tDVaaD0GiVuDMnwKDLMVQb5C6D9pt5fYLwuX_K',
  paypal_client_secret = 'EMbRU0jVmn_HwVBasZAkEwL74X64v2-lgrbZir_9a3gdFnNIP5SAvZ7NI06JdJ2ssITDRxShV-CJ2LUS',
  paypal_mode = 'live'
where id = 1;

-- === 09 SETTINGS VIEW ===
drop view if exists public.settings_public;
create or replace view public.settings_public with (security_invoker = true) as
  select id, budget, max_per_club, max_subs, bonus,
         squad_p, squad_d, squad_c, squad_a, squad_deadline,
         market_from, market_to, market_max,
         subscription_price, subscription_label
  from public.settings;

grant select on public.settings_public to authenticated;
revoke select on public.settings from authenticated, anon;

-- === 10 SETTINGS RLS FIX ===
drop policy if exists "lettura" on public.settings;
create policy "settings admin only" on public.settings for select to authenticated
  using (public.is_admin());

-- === 11 SETTINGS GRANTS FIX ===
revoke all on public.settings from anon;
revoke all on public.settings from authenticated;
grant all on public.settings to authenticated;
revoke update (paypal_client_id, paypal_client_secret, paypal_mode) on public.settings from authenticated;
grant update (budget, max_per_club, max_subs, bonus, squad_p, squad_d, squad_c, squad_a, squad_deadline, market_from, market_to, market_max, subscription_price, subscription_label) on public.settings to authenticated;
grant select on public.settings to authenticated;
grant insert on public.settings to authenticated;
grant delete on public.settings to authenticated;

-- === 13 PROFILE CRESTS ===
alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists crest text default 'auto',
  add column if not exists crest_url text;

-- === 14 SECURITY FIXES ===
revoke execute on function public.check_lineup_in_squad() from anon;
revoke execute on function public.save_squad(bigint[]) from anon;
revoke execute on function public.save_lineup(int, text, jsonb) from anon;

alter function public.module_counts(text) set search_path = public;
alter function public.fantavoto(votes, character, jsonb) set search_path = public;
