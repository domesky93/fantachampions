// Accesso ai dati Supabase
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export const state = { session: null, profile: null };

// Lancia l'errore se la chiamata Supabase fallisce
export async function q(promise) {
  const { data, error } = await promise;
  if (error) throw error;
  return data;
}

// Scarica tutte le righe superando il limite di 1000 per richiesta
export async function fetchAll(build) {
  const out = []; const size = 1000;
  for (let from = 0; ; from += size) {
    const rows = await q(build().range(from, from + size - 1));
    out.push(...rows);
    if (rows.length < size) break;
  }
  return out;
}

// --- cache di squadre e giocatori ---
let _clubs = null; let _players = null;

export async function getClubs(force = false) {
  if (!_clubs || force) _clubs = await q(sb.from('clubs').select('*').order('name'));
  return _clubs;
}

export async function getPlayers(force = false) {
  if (!_players || force) {
    _players = await fetchAll(() => sb.from('players').select('*').order('id'));
  }
  return _players;
}

export function invalidatePlayers() { _players = null; _clubs = null; }

export async function getSettings() {
  return q(sb.from('settings').select('*').eq('id', 1).single());
}

export async function getMatchdays() {
  return q(sb.from('matchdays').select('*').order('number'));
}

// Partite reali (tutte o di una giornata). Se la tabella non esiste ancora restituisce [].
export async function getFixtures(matchdayId = null) {
  let qb = sb.from('fixtures').select('*').order('kickoff');
  if (matchdayId) qb = qb.eq('matchday_id', matchdayId);
  try { return await q(qb); } catch (e) { console.warn('Calendario non disponibile:', e.message); return []; }
}

// club_id -> prossima partita (la prima non ancora iniziata)
export function nextFixtureByClub(fixtures) {
  const now = Date.now(); const m = new Map();
  [...fixtures].sort((a, b) => new Date(a.kickoff) - new Date(b.kickoff)).forEach((f) => {
    if (new Date(f.kickoff) <= now) return;
    if (!m.has(f.home_club_id)) m.set(f.home_club_id, { opp: f.away_club_id, home: true, kickoff: f.kickoff, fixture: f });
    if (!m.has(f.away_club_id)) m.set(f.away_club_id, { opp: f.home_club_id, home: false, kickoff: f.kickoff, fixture: f });
  });
  return m;
}

// Rosa di un utente: [{ player_id, price }] + riga squads
export async function getSquad(uid) {
  const [players, row] = await Promise.all([
    q(sb.from('squad_players').select('player_id,price').eq('user_id', uid)).catch(() => []),
    q(sb.from('squads').select('*').eq('user_id', uid).maybeSingle()).catch(() => null),
  ]);
  return { players, row };
}

export const squadSize = (s) => (s.squad_p ?? 3) + (s.squad_d ?? 8) + (s.squad_c ?? 8) + (s.squad_a ?? 6);
export const squadNeed = (s) => ({ P: s.squad_p ?? 3, D: s.squad_d ?? 8, C: s.squad_c ?? 8, A: s.squad_a ?? 6 });

// Fase della rosa: 'libera' | 'mercato' | 'bloccata'
export function squadPhase(s, hasSquad) {
  const now = Date.now();
  if (!hasSquad || !s.squad_deadline || now < new Date(s.squad_deadline)) return 'libera';
  if (s.market_from && s.market_to && now >= new Date(s.market_from) && now < new Date(s.market_to)) return 'mercato';
  return 'bloccata';
}

// Prossima giornata aperta (deadline futura), altrimenti l'ultima
export function pickCurrentMatchday(mds) {
  const now = Date.now();
  return mds.find((m) => m.status === 'aperta' && new Date(m.deadline) > now) || mds[mds.length - 1];
}

export async function loadProfile() {
  if (!state.session) { state.profile = null; return null; }
  state.profile = await q(sb.from('profiles').select('*').eq('id', state.session.user.id).single());
  return state.profile;
}
