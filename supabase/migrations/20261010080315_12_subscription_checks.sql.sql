-- Add subscription check to save_squad function
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

-- Add subscription check to save_lineup function
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

revoke all on function public.save_lineup(int, text, jsonb) from anon, public;
grant execute on function public.save_lineup(int, text, jsonb) to authenticated;
