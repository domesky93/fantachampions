/*
# Fanta Champions - Logica di gioco

## Funzioni create
- module_counts(module): restituisce il numero di difensori/centrocampisti/attaccanti per un modulo valido
- save_lineup(matchday, module, players): salva e valida una formazione (18 giocatori, budget, ruoli, limiti)
- fantavoto(votes, role, bonus): calcola il fantavoto di un giocatore (voto + bonus/malus)
- calc_matchday(matchday): calcola i risultati di una giornata con sostituzioni automatiche (solo admin)
- create_league(name): crea una lega privata con codice univoco
- join_league(code): unisciti a una lega con un codice
- leave_league(league_id): esci da una lega
- standings (view): classifica generale aggregata per utente
*/

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
begin
  if v_uid is null then raise exception 'Devi accedere per salvare la formazione'; end if;

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

create or replace view public.standings with (security_invoker = true) as
select p.id as user_id, p.username, p.team_name,
       coalesce(sum(r.total), 0)::numeric(7,1) as total,
       count(r.lineup_id)::int as played,
       coalesce(max(r.total), 0)::numeric(6,1) as best
from profiles p
left join results r on r.user_id = p.id
group by p.id, p.username, p.team_name;