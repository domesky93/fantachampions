// Avvio app e navigazione
import { sb, state, loadProfile } from './api.js';
import { $, esc, errMsg, teamBadge, userPhoto } from './ui.js';
import { SUPABASE_URL } from './config.js';
import { renderLogin } from './views/login.js';
import { renderHome } from './views/home.js';
import { renderLineup } from './views/lineup.js';
import { renderStandings } from './views/standings.js';
import { renderLeagues } from './views/leagues.js';
import { renderAdmin } from './views/admin.js';
import { renderProfile } from './views/profile.js';
import { renderCredits } from './views/credits.js';
import { renderCalendar } from './views/calendar.js';
import { renderSquad } from './views/squad.js';

const routes = {
  '': renderHome,
  rosa: renderSquad,
  formazione: renderLineup,
  calendario: renderCalendar,
  classifica: renderStandings,
  leghe: renderLeagues,
  admin: renderAdmin,
  profilo: renderProfile,
  crediti: renderCredits,
};

const I = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const ICONS = {
  home: I('<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>'),
  pitch: I('<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 12h18"/><circle cx="12" cy="12" r="3"/><path d="M8 3v3h8V3M8 21v-3h8v3"/>'),
  trophy: I('<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>'),
  users: I('<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6 6 0 0 1 3.5 6"/>'),
  gear: I('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  calendar: I('<rect x="3" y="4.5" width="18" height="16.5" rx="2"/><path d="M3 9.5h18M8 2.5v4M16 2.5v4"/><path d="M7.5 13.5h2M11 13.5h2M14.5 13.5h2M7.5 17h2M11 17h2"/>'),
  shirt: I('<path d="M8 3 4 5.5 2 10l3.5 2L7 11v10h10V11l1.5 1 3.5-2-2-4.5L16 3c-1 1.5-2.4 2.2-4 2.2S9 4.5 8 3z"/>'),
  user: I('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
};

const NAV = [
  ['', 'home', 'Home'],
  ['rosa', 'shirt', 'Rosa'],
  ['formazione', 'pitch', 'Formazione'],
  ['calendario', 'calendar', 'Calendario'],
  ['classifica', 'trophy', 'Classifica'],
  ['leghe', 'users', 'Leghe'],
  ['profilo', 'user', 'Profilo'],
];

let cleanup = null;

function renderNav(current) {
  const items = [...NAV];
  if (state.profile?.is_admin) items.splice(items.length - 1, 0, ['admin', 'gear', 'Admin']);
  const link = ([r, icon, label]) =>
    `<a href="#/${r}" class="${current === r ? 'active' : ''}"><span class="ni">${ICONS[icon]}</span><span>${label}</span></a>`;
  const html = state.session ? items.map(link).join('') : '';
  $('#nav').innerHTML = html;
  // sul telefono "Leghe" si apre dalla Classifica, così la barra in basso non è troppo piena
  $('#bottom-nav').innerHTML = state.session ? items.filter(([r]) => r !== 'leghe').map(link).join('') : '';
  const p = state.profile;
  $('#top-user').innerHTML = state.session && p
    ? `<a href="#/profilo" class="top-user-link">${teamBadge(p, 'badge-sm')}<span><b>${esc(p.team_name || p.username)}</b><small>${esc(p.username)}</small></span>${userPhoto(p, 'avatar-sm')}</a>` : '';
  document.body.classList.toggle('logged', !!state.session);
}

async function router() {
  const app = $('#app');
  if (cleanup) { try { cleanup(); } catch {} cleanup = null; }

  if (SUPABASE_URL.includes('TUO-PROGETTO')) {
    app.innerHTML = `<div class="card"><h2>Configurazione mancante</h2>
      <p>Apri <code>js/config.js</code> e inserisci URL e chiave anon del tuo progetto Supabase.</p></div>`;
    return;
  }

  const [path, ...params] = location.hash.replace(/^#\/?/, '').split('/');
  renderNav(path);

  if (!state.session) { await renderLogin(app); return; }

  const view = routes[path] || renderHome;
  app.innerHTML = '<div class="loading"><span class="spinner"></span></div>';
  try {
    cleanup = await view(app, params.map(decodeURIComponent));
  } catch (e) {
    console.error(e);
    app.innerHTML = `<div class="card error-card"><h2>Ops, qualcosa è andato storto</h2><p>${esc(errMsg(e))}</p></div>`;
  }
  window.scrollTo(0, 0);
}

async function init() {
  const { data } = await sb.auth.getSession();
  state.session = data.session;
  if (state.session) await loadProfile().catch(() => null);

  // ATTENZIONE: qui dentro non si possono fare richieste a Supabase in modo diretto
  // (la libreria si blocca): il lavoro viene rimandato con setTimeout.
  sb.auth.onAuthStateChange((event, session) => {
    const was = !!state.session;
    state.session = session;
    if (was === !!session) return;            // es. rinnovo del token: nulla da fare
    setTimeout(async () => {
      if (session) await loadProfile().catch(() => null);
      router();
    }, 0);
  });

  window.addEventListener('hashchange', router);
  document.addEventListener('profile-changed', () => renderNav(location.hash.replace(/^#\/?/, '').split('/')[0]));
  router();
}

init();
