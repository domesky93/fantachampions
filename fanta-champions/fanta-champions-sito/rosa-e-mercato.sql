-- =====================================================================
--  FANTA CHAMPIONS - Rosa da 25 giocatori e mercato di metà girone
--  * Ogni utente compra una rosa di 25 (3 P, 8 D, 8 C, 6 A) con 400 crediti
--  * La rosa si può cambiare liberamente fino alla scadenza rosa,
--    poi resta bloccata fino alla fine della fase campionato
--  * Un solo mercato a metà fase: max 3 cambi
--  * Ogni giornata la formazione (11 + 7) si sceglie SOLO dalla propria rosa
--  Si può rieseguire senza problemi.
-- =====================================================================
begin;

-- ---------------------------------------------------------- impostazioni
alter table public.settings
  add column if not exists squad_p        int not null default 3,
  add column if not exists squad_d        int not null default 8,
  add column if not exists squad_c        int not null default 8,
  add column if not exists squad_a        int not null default 6,
  add column if not exists squad_deadline timestamptz,
  add column if not exists market_from    timestamptz,
  add column if not exists market_to      timestamptz,
  add column if not exists market_max     int not null default 3;

-- Budget 400 · rose libere fino al via della 2ª giornata (13/10 18:45)
-- Mercato: dal giorno dopo la 4ª giornata fino al via della 5ª (24/11 18:45)
update public.settings set
  budget         = 400,
  squad_deadline = coalesce((select deadline from public.matchdays where number = 2), '2026-10-13 18:45+02'),
  market_from    = '2026-11-05 10:00+01',
  market_to      = coalesce((select deadline from public.matchdays where number = 5), '2026-11-24 18:45+01'),
  market_max     = 3
where id = 1;

-- ---------------------------------------------------------- tabelle rosa
create table if not exists public.squads (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  market_base    bigint[],      -- rosa com'era all'apertura del mercato
  market_base_at timestamptz
);

create table if not exists public.squad_players (
  user_id   uuid   not null references public.squads(user_id) on delete cascade,
  player_id bigint not null references public.players(id) on delete cascade,
  price     int    not null,     -- prezzo pagato
  primary key (user_id, player_id)
);
create index if not exists squad_players_player_idx on public.squad_players(player_id);

alter table public.squads enable row level security;
alter table public.squad_players enable row level security;
drop policy if exists "rose leggibili" on public.squads;
create policy "rose leggibili" on public.squads for select using (true);
drop policy if exists "giocatori rosa leggibili" on public.squad_players;
create policy "giocatori rosa leggibili" on public.squad_players for select using (true);
-- nessuna policy di scrittura: si salva solo con save_squad()

-- ---------------------------------------------------------- salvataggio rosa
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

  -- composizione
  select count(*) filter (where role = 'P'), count(*) filter (where role = 'D'),
         count(*) filter (where role = 'C'), count(*) filter (where role = 'A')
    into n_p, n_d, n_c, n_a
  from public.players where id = any(v_ids);
  if n_p <> s.squad_p or n_d <> s.squad_d or n_c <> s.squad_c or n_a <> s.squad_a then
    raise exception 'La rosa deve avere % portieri, % difensori, % centrocampisti e % attaccanti (ora: %, %, %, %)',
      s.squad_p, s.squad_d, s.squad_c, s.squad_a, n_p, n_d, n_c, n_a;
  end if;

  -- max giocatori della stessa squadra
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

  -- fase: libera (prima della scadenza o prima rosa di chi arriva tardi), mercato, bloccata
  if not v_has or cardinality(v_old) = 0 or s.squad_deadline is null or now() < s.squad_deadline then
    v_phase := 'libera';
  elsif s.market_from is not null and s.market_to is not null and now() >= s.market_from and now() < s.market_to then
    v_phase := 'mercato';
  else
    raise exception 'La rosa è bloccata: potrai cambiarla solo durante il mercato di metà girone';
  end if;

  -- i giocatori nuovi devono essere nella lista UEFA attuale
  select string_agg(p.name, ', ') into v_txt from public.players p
  where p.id = any(v_ids) and not (p.id = any(v_old)) and not coalesce(p.active, true);
  if v_txt is not null then raise exception 'Non più in lista UEFA: %', v_txt; end if;

  -- costo: al mercato chi resta mantiene il prezzo pagato
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

  -- limite cambi al mercato (rispetto alla rosa di inizio mercato)
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

-- ---------------------------------------------------------- formazione solo dalla rosa
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

commit;

select budget, squad_p, squad_d, squad_c, squad_a,
       squad_deadline at time zone 'Europe/Rome' as rose_libere_fino_a,
       market_from at time zone 'Europe/Rome' as mercato_dal,
       market_to at time zone 'Europe/Rome' as mercato_fino_al,
       market_max as cambi_mercato
from public.settings where id = 1;
