/*
# Fanta Champions - Schema database

Crea tutte le tabelle del gioco e il trigger automatico per i profili utente.

## Tabelle create
- profiles: profili utente (username, team_name, is_admin)
- clubs: squadre reali della Champions League
- players: giocatori con ruolo, prezzo, squadra
- matchdays: giornate di gioco con scadenza e stato
- settings: impostazioni di gioco (budget, limiti, bonus/malus)
- leagues: leghe private tra amici
- league_members: membri delle leghe
- lineups: formazioni degli utenti
- lineup_players: giocatori nelle formazioni (slot 1-18)
- votes: voti e statistiche per giocatore per giornata
- results: risultati calcolati per ogni formazione

## Funzioni create
- handle_new_user(): trigger che crea automaticamente il profilo alla registrazione
- is_admin(): helper per verificare se l'utente è amministratore
- is_league_member(): helper per verificare l'appartenenza a una lega
*/

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