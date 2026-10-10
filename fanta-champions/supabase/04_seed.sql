-- =====================================================================
--  FANTA CHAMPIONS - Dati iniziali stagione 2026/27 (fase campionato)
--  36 squadre + 8 giornate. Le rose dei giocatori si caricano dal
--  pannello Admin (import CSV).
--  Scadenze = orario del primo calcio d'inizio della giornata (ora italiana).
--  Controlla gli orari esatti nel pannello Admin quando escono i calendari.
-- =====================================================================

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
