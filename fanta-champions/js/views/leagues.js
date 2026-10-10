import { sb, q, state } from '../api.js';
import { $, esc, toast, errMsg } from '../ui.js';
import { standingsTable } from './standings.js';

export async function renderLeagues(app, params) {
  const uid = state.session.user.id;
  if (params[0]) return renderLeague(app, params[0], uid);

  const mine = await q(sb.from('league_members').select('leagues(id,name,code,owner_id)').eq('user_id', uid));
  const leagues = mine.map((m) => m.leagues).filter(Boolean);

  app.innerHTML = `
    <h1 class="page-title">Leghe private</h1>
    <p class="muted">Crea una lega e invita gli amici con il codice: avrete una classifica solo vostra. La formazione è unica e vale in tutte le leghe.</p>
    <div class="grid-2">
      <form class="card" id="create"><h2>Crea una lega</h2>
        <label>Nome della lega<input name="name" required minlength="3" maxlength="40" placeholder="es. Lega del Bar"></label>
        <button class="btn btn-primary">Crea</button></form>
      <form class="card" id="join"><h2>Entra con un codice</h2>
        <label>Codice invito<input name="code" required maxlength="6" placeholder="ABC123" style="text-transform:uppercase"></label>
        <button class="btn btn-primary">Entra</button></form>
    </div>
    <div class="card"><h2>Le tue leghe</h2>
      ${leagues.length ? `<div class="list">${leagues.map((l) => `
        <a class="list-item" href="#/leghe/${l.id}"><b>${esc(l.name)}</b><span class="muted small">codice ${esc(l.code)}</span><span>→</span></a>`).join('')}</div>`
        : '<p class="muted">Non sei ancora in nessuna lega.</p>'}
    </div>`;

  $('#create').onsubmit = async (e) => {
    e.preventDefault();
    try { const l = await q(sb.rpc('create_league', { p_name: e.target.name.value })); location.hash = `#/leghe/${l.id}`; }
    catch (err) { toast(errMsg(err), 'err'); }
  };
  $('#join').onsubmit = async (e) => {
    e.preventDefault();
    try { const l = await q(sb.rpc('join_league', { p_code: e.target.code.value })); toast(`Sei entrato in ${l.name}`); location.hash = `#/leghe/${l.id}`; }
    catch (err) { toast(errMsg(err), 'err'); }
  };
}

async function renderLeague(app, id, uid) {
  const league = await q(sb.from('leagues').select('*').eq('id', id).maybeSingle());
  if (!league) { app.innerHTML = '<div class="card">Lega non trovata.</div>'; return; }
  const members = await q(sb.from('league_members').select('user_id').eq('league_id', id));
  const rows = await q(sb.from('standings').select('*').in('user_id', members.map((m) => m.user_id)).order('total', { ascending: false }));
  const invite = `Unisciti alla mia lega "${league.name}" su Fanta Champions! ${location.origin}  Codice: ${league.code}`;

  app.innerHTML = `
    <a href="#/leghe" class="link">← Leghe</a>
    <h1 class="page-title">${esc(league.name)}</h1>
    <div class="card invite">
      <div><div class="eyebrow">Codice invito</div><div class="code">${esc(league.code)}</div></div>
      <div class="invite-actions">
        <button class="btn btn-ghost" id="copy">Copia invito</button>
        <a class="btn btn-whatsapp" target="_blank" rel="noopener" href="https://wa.me/?text=${encodeURIComponent(invite)}">WhatsApp</a>
      </div>
    </div>
    <div class="card"><h2>Classifica (${members.length} partecipanti)</h2>${standingsTable(rows, uid)}</div>
    <button class="btn btn-danger-ghost" id="leave">${league.owner_id === uid ? 'Elimina lega' : 'Esci dalla lega'}</button>`;

  $('#copy').onclick = async () => { await navigator.clipboard.writeText(invite); toast('Invito copiato'); };
  $('#leave').onclick = async () => {
    const owner = league.owner_id === uid;
    if (!confirm(owner ? 'Eliminare la lega per tutti?' : 'Uscire dalla lega?')) return;
    try {
      if (owner) await q(sb.from('leagues').delete().eq('id', id));
      else await q(sb.rpc('leave_league', { p_league: id }));
      location.hash = '#/leghe';
    } catch (err) { toast(errMsg(err), 'err'); }
  };
}
