/*
# Calendario partite e sistema rosa/mercato

## Cosa fa questa migrazione
1. Crea la tabella `fixtures` con le 144 partite reali delle giornate 1-8 di Champions League 2026/27
2. Crea le tabelle `squads` e `squad_players` per il sistema di rosa da 25 giocatori
3. Aggiunge le colonne necessarie a `settings` per gestire rosa e mercato
4. Crea la funzione `save_squad()` per salvare la rosa con tutti i controlli
5. Crea il trigger `check_lineup_in_squad` che impedisce di schierare giocatori non in rosa
6. Abilita RLS su tutte le nuove tabelle con policy appropriate

## Nuove tabelle
- `fixtures`: partite reali (home/away club, kickoff, punteggi)
- `squads`: rosa di ogni utente (con mercato_base per il mercato di metà girone)
- `squad_players`: giocatori nella rosa di un utente (con prezzo pagato)

## Colonne aggiunte a settings
- squad_p/d/c/a: numero di giocatori per ruolo (3P, 8D, 8C, 6A = 25 totali)
- squad_deadline: scadenza per modificare liberamente la rosa
- market_from/to: finestra del mercato di metà girone
- market_max: max cambi consentiti al mercato

## Security
- RLS su fixtures: tutti possono leggere, solo admin può scrivere
- RLS su squads/squad_players: tutti possono leggere (classifica rose), scrittura solo via save_squad()
- save_squad() è SECURITY DEFINER, eseguibile solo da authenticated
*/

-- ============================================================
-- FIXTURES (calendario partite reali)
-- ============================================================
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

-- Tabella di appoggio temporanea per caricare le partite
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

-- Carica le partite
delete from public.fixtures f using public.matchdays m
where f.matchday_id = m.id and m.number between 1 and 8;

insert into public.fixtures (matchday_id, home_club_id, away_club_id, kickoff)
select m.id, h.id, a.id, c.ko at time zone 'Europe/Rome'
from _cal c
join public.matchdays m on m.number = c.md
join public.clubs h on h.name = c.home
join public.clubs a on a.name = c.away;

drop table public._cal;

-- ============================================================
-- IMPOSTAZIONI ROSA E MERCATO
-- ============================================================
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

-- ============================================================
-- TABELLE ROSA
-- ============================================================
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

-- ============================================================
-- FUNZIONE SAVE_SQUAD
-- ============================================================
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
begin
  if uid is null then raise exception 'Devi accedere per salvare la rosa'; end if;
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

-- ============================================================
-- TRIGGER: formazione solo dalla rosa
-- ============================================================
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
