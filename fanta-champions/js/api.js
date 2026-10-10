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
