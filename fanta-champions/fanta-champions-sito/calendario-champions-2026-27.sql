-- =====================================================================
--  FANTA CHAMPIONS - Calendario reale (fase campionato 2026/27)
--  Crea la tabella "fixtures" (partite reali abbinate alle giornate)
--  e carica le 144 partite UEFA delle giornate 1-8.
--  Si può rieseguire: aggiorna orari e partite senza duplicare.
-- =====================================================================
begin;

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
drop policy if exists "fixtures leggibili" on public.fixtures;
create policy "fixtures leggibili" on public.fixtures for select using (true);
drop policy if exists "fixtures admin" on public.fixtures;
create policy "fixtures admin" on public.fixtures for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- Partite UEFA (orari italiani)
-- tabella di appoggio normale (non temporanea): funziona anche nell'SQL Editor di Supabase
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

-- Controllo nomi squadre
do $$ declare missing text; begin
  select string_agg(distinct n, ', ') into missing
  from (select home n from _cal union select away from _cal) t
  where not exists (select 1 from public.clubs c where c.name = t.n);
  if missing is not null then raise exception 'Squadre non trovate in clubs: %', missing; end if;
end $$;

-- Crea le giornate 1-8 che mancano (scadenza = primo calcio d'inizio)
insert into public.matchdays (number, name, deadline, status)
select g.md, g.md || 'ª giornata', g.first_ko,
       case when g.first_ko < now() then 'chiusa' else 'aperta' end
from (select md, min(ko at time zone 'Europe/Rome') first_ko from _cal group by md) g
where not exists (select 1 from public.matchdays m where m.number = g.md);

-- Allinea la scadenza delle giornate non ancora calcolate al primo calcio d'inizio
update public.matchdays m set deadline = g.first_ko
from (select md, min(ko at time zone 'Europe/Rome') first_ko from _cal group by md) g
where m.number = g.md and m.status <> 'calcolata';

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

commit;

select m.number as giornata, count(f.id) as partite
from public.matchdays m left join public.fixtures f on f.matchday_id = m.id
group by m.number order by m.number;
