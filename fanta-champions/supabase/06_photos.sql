-- =====================================================================
--  FANTA CHAMPIONS - Foto dei giocatori (esegui dopo 05_players.sql)
--  Le foto si cercano dal pannello Admin → Giocatori → "Cerca foto".
-- =====================================================================
alter table public.players add column if not exists photo_url    text;
alter table public.players add column if not exists photo_credit text;   -- autore e licenza (obbligatori per le foto Creative Commons)
alter table public.players add column if not exists photo_page   text;   -- pagina della foto su Wikimedia

-- Salvataggio in blocco delle foto trovate (solo admin)
-- p_rows = [{"id": 1, "photo_url": "...", "photo_credit": "...", "photo_page": "..."}, ...]
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
