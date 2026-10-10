/*
# Fanta Champions - Sicurezza (Row Level Security)

Abilita RLS su tutte le tabelle e definisce le policy di accesso.

## Policy principali
- profiles: tutti gli utenti autenticati possono leggere; ognuno modifica solo il proprio profilo (solo username/team_name, non is_admin)
- clubs/players/matchdays/settings/votes: lettura per tutti, scrittura solo admin
- leagues: visibili solo ai membri; modifica/eliminazione solo dal proprietario
- league_members: visibili solo ai membri della stessa lega
- lineups: le proprie sempre; quelle altrui solo dopo la scadenza
- lineup_players: eredita la visibilità dalla formazione
- results: pubblici a tutti gli autenticati
- Funzioni di gioco: revocate da anon/public, concesse agli autenticati
*/

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