/*
# Fanta Champions - Dati iniziali stagione 2026/27

Carica:
- 36 squadre della Champions League con codici abbreviati e nazioni
- 8 giornate della fase campionato con scadenze (orario italiano)
- Colonne foto su players (photo_url, photo_credit, photo_page)
- Funzione set_player_photos per salvataggio foto in blocco (solo admin)
*/

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