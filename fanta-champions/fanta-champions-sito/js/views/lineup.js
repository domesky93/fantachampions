import { sb, q, state, getMatchdays, getPlayers, getClubs, getSettings, getFixtures, fixturesByClub, pickCurrentMatchday, getSquad, squadSize } from '../api.js';
import { $, $$, esc, roleBadge, shirt, face, fmtDate, fmtKick, fmtTime, fmtPts, countdown, toast, errMsg, openModal, norm, ROLE_NAME } from '../ui.js';
import { clubColors, clubShort, clubDot } from '../clubs.js';

// "Lautaro Martínez" -> "L. Martínez" (nomi lunghi sul campo)
const shortName = (n) => { const w = n.split(' '); return n.length > 11 && w.length > 1 ? `${w[0][0]}. ${w.slice(1).join(' ')}` : n; };

export const MODULES = {
  '3-4-3': [3, 4, 3], '3-5-2': [3, 5, 2], '4-3-3': [4, 3, 3], '4-4-2': [4, 4, 2],
  '4-5-1': [4, 5, 1], '5-3-2': [5, 3, 2], '5-4-1': [5, 4, 1],
};
const BENCH = { 12: 'P', 13: 'D', 14: 'D', 15: 'C', 16: 'C', 17: 'A', 18: 'A' };

export function slotRole(slot, module) {
  if (slot > 11) return BENCH[slot];
  const [d, c] = MODULES[module];
  if (slot === 1) return 'P';
  if (slot <= 1 + d) return 'D';
  if (slot <= 1 + d + c) return 'C';
  return 'A';
}
const startersOf = (module, role) => Array.from({ length: 11 }, (_, i) => i + 1).filter((s) => slotRole(s, module) === role);

export async function renderLineup(app, params) {
  const uid = state.session.user.id;
  const [mds, players, clubs, settings, squad] = await Promise.all([getMatchdays(), getPlayers(), getClubs(), getSettings(), getSquad(uid)]);
  if (!mds.length) { app.innerHTML = '<div class="card">Nessuna giornata disponibile.</div>'; return; }

  const md = mds.find((m) => String(m.id) === params[0]) || pickCurrentMatchday(mds);
  const pById = new Map(players.map((p) => [p.id, p]));
  const cById = new Map(clubs.map((c) => [c.id, c]));
  const open = md.status === 'aperta' && new Date(md.deadline) > Date.now();
  // la formazione si sceglie solo tra i giocatori della propria rosa
  const squadIds = new Set(squad.players.map((r) => r.player_id));
  const squadReady = settings.squad_p === undefined || squadIds.size >= squadSize(settings);

  // formazione salvata + eventuale risultato + partite reali della giornata
  const [saved, fixtures] = await Promise.all([
    q(sb.from('lineups').select('id,module,lineup_players(player_id,slot)').eq('user_id', uid).eq('matchday_id', md.id).maybeSingle()),
    getFixtures(md.id),
  ]);
  const fxByClub = fixturesByClub(fixtures);

  // Avversario del giocatore: "vs BRU" in casa, "@ BRU" in trasferta
  const oppOf = (p) => fxByClub.get(p?.club_id);
  const oppTag = (p) => {
    if (!fixtures.length || !p) return '';
    const o = oppOf(p);
    if (!o) return '<span class="opp opp-none" title="La sua squadra non gioca in questa giornata">non gioca</span>';
    return `<span class="opp ${o.home ? 'opp-home' : 'opp-away'}" title="${o.home ? 'In casa' : 'In trasferta'} contro ${esc(cById.get(o.opp)?.name || '')} · ${fmtKick(o.kickoff)}">${o.home ? 'vs' : '@'} ${esc(clubShort(cById.get(o.opp)))}</span>`;
  };
  const oppLong = (p) => {
    const o = oppOf(p);
    if (!fixtures.length || !p) return '';
    if (!o) return '<span class="warn">non gioca questa giornata</span>';
    return `${o.home ? 'vs' : '@'} ${esc(cById.get(o.opp)?.name || '')} · ${fmtKick(o.kickoff)}`;
  };
  const result = saved ? await q(sb.from('results').select('total,detail').eq('lineup_id', saved.id).maybeSingle()) : null;

  let module = saved?.module || '4-3-3';
  let sel = {}; // slot -> player_id
  saved?.lineup_players.forEach((lp) => { sel[lp.slot] = lp.player_id; });
  let dirty = false;
  // giocatori non più in rosa (es. dopo il mercato) tolti dalla formazione aperta
  if (open && settings.squad_p !== undefined && squadIds.size) {
    const out = Object.entries(sel).filter(([, id]) => !squadIds.has(id));
    out.forEach(([s]) => delete sel[s]);
    if (out.length) { dirty = true; setTimeout(() => toast(`${out.length} giocator${out.length > 1 ? 'i tolti' : 'e tolto'}: non ${out.length > 1 ? 'sono' : 'è'} più nella tua rosa`, 'warn'), 300); }
  }

  const fvBySlot = {};
  result?.detail.forEach((d) => { fvBySlot[d.slot] = d; });

  const cost = () => Object.values(sel).reduce((t, id) => t + (pById.get(id)?.price || 0), 0);
  const clubCount = (excludeSlot) => {
    const m = new Map();
    Object.entries(sel).forEach(([s, id]) => { if (+s !== excludeSlot) { const c = pById.get(id)?.club_id; m.set(c, (m.get(c) || 0) + 1); } });
    return m;
  };

  const BENCH_LABEL = { 12: 'P', 13: 'D1', 14: 'D2', 15: 'C1', 16: 'C2', 17: 'A1', 18: 'A2' };

  function resultTag(slot) {
    const r = fvBySlot[slot];
    if (!r) return '';
    const cls = r.status === 'entrato' ? 'in' : r.status === 'sostituito' || r.status === 'senza_voto' ? 'out' : '';
    let t = `<span class="fv ${cls}">${r.fv != null ? fmtPts(r.fv) : 's.v.'}</span>`;
    if (r.status === 'entrato') t += '<span class="sub-ico in" title="Entrato dalla panchina">▲</span>';
    if (r.status === 'sostituito') t += '<span class="sub-ico out" title="Sostituito">▼</span>';
    return t;
  }

  // Giocatore sul campo: maglia della squadra + nome
  function card(slot) {
    const p = pById.get(sel[slot]);
    const role = slotRole(slot, module);
    if (!p) {
      return `<button class="token empty" data-slot="${slot}" ${open ? '' : 'disabled'}>
        <span class="token-shirt">${shirt('', '', { empty: true })}${roleBadge(role)}</span>
        <span class="token-name">${open ? 'Scegli' : '—'}</span></button>`;
    }
    const club = cById.get(p.club_id);
    const [c1, c2] = clubColors(club?.name);
    return `<button class="token" data-slot="${slot}" ${open ? '' : 'data-ro'}>
      <span class="token-shirt ${p.photo_url ? 'has-photo' : ''}">${p.photo_url ? face(p, c1, c2, 'face-lg') : shirt(c1, c2)}${roleBadge(p.role)}${resultTag(slot)}</span>
      <span class="token-name">${esc(shortName(p.name))}</span>
      <span class="token-meta">${esc(clubShort(club))}${open ? ` · ${p.price}` : ''}</span>${oppTag(p)}</button>`;
  }

  // Riga della panchina
  function benchRow(slot) {
    const p = pById.get(sel[slot]);
    const role = slotRole(slot, module);
    if (!p) {
      return `<button class="brow empty" data-slot="${slot}" ${open ? '' : 'disabled'}>
        <span class="brow-n">${BENCH_LABEL[slot]}</span>${roleBadge(role)}
        <span class="brow-name muted">${open ? `Aggiungi ${ROLE_NAME[role].toLowerCase()}` : '—'}</span><span class="brow-plus">${open ? '+' : ''}</span></button>`;
    }
    const club = cById.get(p.club_id);
    const [c1, c2] = clubColors(club?.name);
    const r = fvBySlot[slot];
    return `<button class="brow ${r?.status === 'entrato' ? 'brow-in' : ''}" data-slot="${slot}" ${open ? '' : 'data-ro'}>
      <span class="brow-n">${BENCH_LABEL[slot]}</span>${roleBadge(p.role)}
      ${face(p, c1, c2, 'face-sm')}
      <span class="brow-name"><b>${esc(p.name)}</b><small>${esc(club?.name || '')}${fixtures.length ? ` · ${oppLong(p)}` : ''}</small></span>
      ${r ? `<span class="brow-fv ${r.fv == null ? 'out' : ''}">${r.fv != null ? fmtPts(r.fv) : 's.v.'}${r.status === 'entrato' ? ' ▲' : ''}</span>` : `<span class="price-tag">${p.price}</span>`}
    </button>`;
  }

  // Partite reali della giornata, con quanti giocatori miei ci sono per squadra
  function fixturesCard() {
    const mine = new Map();
    Object.values(sel).forEach((id) => { const c = pById.get(id)?.club_id; if (c) mine.set(c, (mine.get(c) || 0) + 1); });
    const side = (cid, right) => {
      const c = cById.get(cid); const n = mine.get(cid);
      const cnt = n ? `<span class="fx-mine" title="${n} tuoi giocatori">${n}</span>` : '';
      return `<span class="fx-team ${right ? 'right' : ''}">${right ? cnt : ''}${clubDot(c?.name)}<span class="fx-name">${esc(c?.name || '?')}</span><span class="fx-short">${esc(clubShort(c))}</span>${right ? '' : cnt}</span>`;
    };
    let lastDay = '';
    const rows = fixtures.map((f) => {
      const day = new Date(f.kickoff).toLocaleDateString('it-IT', { weekday: 'long', day: 'numeric', month: 'long' });
      const head = day !== lastDay ? `<div class="fx-day">${esc(day)}</div>` : '';
      lastDay = day;
      const score = f.home_score != null && f.away_score != null ? `<b>${f.home_score} - ${f.away_score}</b>` : fmtTime(f.kickoff);
      return `${head}<div class="fx-row ${mine.has(f.home_club_id) || mine.has(f.away_club_id) ? 'has-mine' : ''}">${side(f.home_club_id, false)}<span class="fx-mid">${score}</span>${side(f.away_club_id, true)}</div>`;
    }).join('');
    return `<div class="card fx-card"><div class="card-head"><h3>Partite della giornata</h3><a class="link" href="#/calendario/${md.id}">Calendario</a></div>
      <p class="muted small">Il numero indica quanti tuoi giocatori ci sono in quella squadra.</p>${rows}</div>`;
  }

  function draw() {
    const budget = settings.budget;
    const filled = Object.keys(sel).length;
    const [d, c, a] = MODULES[module];
    const row = (role) => `<div class="pitch-row">${startersOf(module, role).map(card).join('')}</div>`;

    if (open && !squadReady) {
      app.innerHTML = `
        <div class="lineup-head"><div class="md-pick">
          <select id="md-select" class="md-select">${mds.map((m) => `<option value="${m.id}" ${m.id === md.id ? 'selected' : ''}>${esc(m.name)}</option>`).join('')}</select>
          <div class="md-info"><span class="live-dot"></span>Chiude tra <b id="cd">${countdown(md.deadline)}</b></div></div></div>
        <div class="card squad-cta"><div><h2>Prima crea la tua rosa</h2>
          <p class="muted">Compra ${squadSize(settings)} giocatori${budget ? ` con ${budget} crediti` : ''}: ogni giornata schiererai la formazione scegliendo tra loro.${squadIds.size ? ` Ora ne hai ${squadIds.size}.` : ''}</p></div>
          <a class="btn btn-primary" href="#/rosa">Crea la rosa</a></div>
        ${fixtures.length ? fixturesCard() : ''}`;
      $('#md-select').onchange = (e) => { location.hash = `#/formazione/${e.target.value}`; };
      return;
    }

    app.innerHTML = `
      <div class="lineup-head">
        <div class="md-pick">
          <select id="md-select" class="md-select">${mds.map((m) => `<option value="${m.id}" ${m.id === md.id ? 'selected' : ''}>${esc(m.name)}</option>`).join('')}</select>
          <div class="md-info">${open ? `<span class="live-dot"></span>Chiude tra <b id="cd">${countdown(md.deadline)}</b>` : `Chiusa · ${fmtDate(md.deadline)}`}</div>
        </div>
        ${result ? `<div class="total-badge"><span>${fmtPts(result.total)}</span><small>punti</small></div>` : ''}
      </div>

      ${open ? `
      <div class="lineup-tools card">
        <div class="modules" role="radiogroup" aria-label="Modulo">${Object.keys(MODULES).map((m) => `<button class="mod ${m === module ? 'active' : ''}" data-mod="${m}" role="radio" aria-checked="${m === module}">${m}</button>`).join('')}</div>
        <div class="lineup-squad"><span class="muted small">Scegli dalla tua rosa di ${squadIds.size} giocatori</span><a class="link" href="#/rosa">Vedi rosa →</a></div>
        <div class="toolbar-actions">
          <button class="btn btn-ghost btn-sm" id="copy-prev">↺ Copia precedente</button>
          <button class="btn btn-ghost btn-sm" id="clear">Svuota</button>
        </div>
      </div>` : `<div class="notice">${saved ? (result ? 'Giornata calcolata. ▲ entrato dalla panchina · ▼ sostituito.' : 'Formazione bloccata: in attesa dei voti.') : 'Non hai schierato la formazione per questa giornata.'}</div>`}

      ${open || saved ? `
      <div class="lineup-grid">
        <div class="pitch">
          <div class="pitch-lines"><i class="pl-mid"></i><i class="pl-circle"></i><i class="pl-box top"></i><i class="pl-box bottom"></i></div>
          ${row('A')}${row('C')}${row('D')}${row('P')}
          <div class="pitch-module">${module}</div>
        </div>
        <div class="bench card">
          <div class="card-head"><h3>Panchina</h3><span class="muted small">max ${settings.max_subs} cambi</span></div>
          <p class="muted small bench-hint">Se un titolare non prende voto entra il primo panchinaro dello stesso ruolo.</p>
          ${[12, 13, 14, 15, 16, 17, 18].map(benchRow).join('')}
        </div>
      </div>` : ''}

      ${fixtures.length ? fixturesCard() : ''}

      ${open ? `
      <div class="save-bar">
        <div class="save-progress"><b>${filled}</b>/18 <span class="muted">${dirty ? '· <span class="warn">non salvata</span>' : saved ? '· <span class="ok">salvata ✓</span>' : ''}</span></div>
        <button class="btn btn-primary" id="save" ${filled < 18 ? 'disabled' : ''}>Salva formazione</button>
      </div>` : ''}
      <p class="muted small rules">${d} difensori · ${c} centrocampisti · ${a} attaccanti + portiere
        ${settings.max_per_club ? ` · max ${settings.max_per_club} per squadra` : ''}
        ${fixtures.length ? '<br><b>vs</b> = gioca in casa · <b>@</b> = gioca in trasferta' : ''}
        ${players.some((x) => x.photo_url) ? '<br><a href="#/crediti">Foto: Wikimedia Commons · crediti</a>' : ''}</p>`;

    $('#md-select').onchange = (e) => { location.hash = `#/formazione/${e.target.value}`; };
    if (!open) {
      $$('[data-ro]').forEach((b) => b.onclick = () => showPlayer(pById.get(sel[+b.dataset.slot]), fvBySlot[+b.dataset.slot]));
      return;
    }
    $$('[data-mod]').forEach((b) => b.onclick = () => { if (b.dataset.mod !== module) changeModule(b.dataset.mod); });
    $$('[data-slot]').forEach((b) => b.onclick = () => pick(+b.dataset.slot));
    $('#clear').onclick = () => { if (confirmLeave('Svuotare la formazione?')) { sel = {}; dirty = true; draw(); } };
    $('#copy-prev').onclick = copyPrevious;
    $('#save').onclick = save;
  }

  function confirmLeave(msg) { return window.confirm(msg); }

  function changeModule(newMod) {
    const keep = {}; let dropped = 0;
    for (const s of [12, 13, 14, 15, 16, 17, 18]) if (sel[s]) keep[s] = sel[s];
    for (const role of ['P', 'D', 'C', 'A']) {
      const ids = startersOf(module, role).map((s) => sel[s]).filter(Boolean);
      const slots = startersOf(newMod, role);
      ids.forEach((id, i) => { if (slots[i]) keep[slots[i]] = id; else dropped++; });
    }
    module = newMod; sel = keep; dirty = true;
    if (dropped) toast(`${dropped} giocator${dropped > 1 ? 'i rimossi' : 'e rimosso'} per il cambio modulo`, 'warn');
    draw();
  }

  async function copyPrevious() {
    const prev = await q(sb.from('lineups').select('module,matchday_id,lineup_players(player_id,slot),matchdays(number)')
      .eq('user_id', uid).neq('matchday_id', md.id));
    if (!prev.length) return toast('Nessuna formazione precedente', 'warn');
    prev.sort((x, y) => y.matchdays.number - x.matchdays.number);
    const p = prev[0];
    module = p.module; sel = {};
    let skipped = 0;
    p.lineup_players.forEach((lp) => { if (pById.get(lp.player_id)?.active !== false && (settings.squad_p === undefined || squadIds.has(lp.player_id))) sel[lp.slot] = lp.player_id; else skipped++; });
    dirty = true; draw();
    toast(skipped ? `Copiata (${skipped} giocatori non più disponibili)` : 'Formazione copiata');
  }

  function pick(slot) {
    const role = slotRole(slot, module);
    const current = pById.get(sel[slot]);
    const chosen = new Set(Object.values(sel));
    const inSquad = (p) => settings.squad_p === undefined || squadIds.has(p.id);
    const clubOpts = clubs.filter((c) => players.some((p) => p.club_id === c.id && p.role === role && inSquad(p))).map((c) => {
      const o = fxByClub.get(c.id);
      const vs = !fixtures.length ? '' : o ? ` (${o.home ? 'vs' : '@'} ${clubShort(cById.get(o.opp))})` : ' (non gioca)';
      return `<option value="${c.id}">${esc(c.name + vs)}</option>`;
    }).join('');

    const { el, close } = openModal(`${slot > 11 ? 'Panchina' : 'Titolare'} · ${ROLE_NAME[role]}`, `
      ${current ? `<div class="current">Attuale: ${roleBadge(current.role)} <b>${esc(current.name)}</b> <button class="btn btn-ghost btn-sm" id="remove">Rimuovi</button></div>` : ''}
      <div class="filters">
        <input id="f-q" type="search" placeholder="Cerca giocatore…" autofocus>
        <select id="f-club"><option value="">Tutte le squadre</option>${clubOpts}</select>
        <select id="f-sort"><option value="pd">Prezzo ↓</option><option value="pa">Prezzo ↑</option><option value="n">Nome</option></select>
      </div>
      <p class="muted small">Scegli tra i giocatori della tua rosa · <a class="link" href="#/rosa">vedi rosa</a></p>
      <div class="plist" id="plist"></div>`);

    const list = () => {
      const qs = norm($('#f-q', el).value);
      const club = +$('#f-club', el).value;
      const sort = $('#f-sort', el).value;
      let rows = players.filter((p) => p.role === role && inSquad(p) && (!club || p.club_id === club) && (!qs || norm(p.name).includes(qs)));
      rows.sort(sort === 'n' ? (a, b) => a.name.localeCompare(b.name) : sort === 'pa' ? (a, b) => a.price - b.price : (a, b) => b.price - a.price);
      if (fixtures.length) rows.sort((a, b) => (oppOf(a) ? 0 : 1) - (oppOf(b) ? 0 : 1)); // chi non gioca in fondo
      const total = rows.length; rows = rows.slice(0, 150);
      $('#plist', el).innerHTML = rows.map((p) => {
        const taken = chosen.has(p.id) && p.id !== current?.id;
        const why = taken ? 'già schierato' : '';
        return `<button class="prow" data-id="${p.id}" ${taken ? 'disabled' : ''}>
          ${face(p, ...clubColors(cById.get(p.club_id)?.name), 'face-sm')}${roleBadge(p.role)}<span class="prow-name"><b>${esc(p.name)}</b><small>${esc(cById.get(p.club_id)?.name || '')}${fixtures.length ? ` · ${oppLong(p)}` : ''}</small></span>
          ${why ? `<span class="why">${why}</span>` : oppTag(p)}<span class="price">${p.price}</span></button>`;
      }).join('') + (total > 150 ? `<p class="muted small center">Mostrati 150 su ${total}: usa la ricerca o il filtro squadra.</p>` : '')
        + (!total ? '<p class="muted center">Nessun giocatore della tua rosa per questo ruolo.</p>' : '');
      $$('.prow', el).forEach((b) => b.onclick = () => { sel[slot] = +b.dataset.id; dirty = true; close(); draw(); });
    };
    ['#f-q', '#f-club', '#f-sort'].forEach((s) => $(s, el).addEventListener('input', list));
    $('#remove', el)?.addEventListener('click', () => { delete sel[slot]; dirty = true; close(); draw(); });
    list();
  }

  function showPlayer(p, r) {
    if (!p) return;
    const club = cById.get(p.club_id);
    const [c1, c2] = clubColors(club?.name);
    openModal(esc(p.name), `<div class="player-sheet">
      ${face(p, c1, c2, 'face-xl')}
      <div><p>${roleBadge(p.role)} <b>${esc(ROLE_NAME[p.role])}</b> · ${esc(club?.name || '')}</p>
      <p class="muted">${p.price} crediti</p>
      ${fixtures.length ? `<p>Partita: <b>${oppLong(p)}</b></p>` : ''}
      ${r ? `<p>Voto <b>${r.voto ?? 's.v.'}</b> · Fantavoto <b>${r.fv != null ? fmtPts(r.fv) : '–'}</b></p>` : ''}
      ${p.photo_credit ? `<p class="photo-credit">Foto: <a href="${esc(p.photo_page || '#')}" target="_blank" rel="noopener">${esc(p.photo_credit)}</a></p>` : ''}</div></div>`);
  }

  async function save() {
    const btn = $('#save'); btn.disabled = true;
    try {
      const payload = Object.entries(sel).map(([slot, id]) => ({ slot: +slot, player_id: id }));
      await q(sb.rpc('save_lineup', { p_matchday: md.id, p_module: module, p_players: payload }));
      dirty = false; toast('Formazione salvata ✅'); draw();
    } catch (e) { toast(errMsg(e), 'err'); btn.disabled = false; }
  }

  const onBeforeUnload = (e) => { if (dirty) { e.preventDefault(); e.returnValue = ''; } };
  window.addEventListener('beforeunload', onBeforeUnload);
  draw();

  const t = open ? setInterval(() => { const c = document.getElementById('cd'); if (c) c.textContent = countdown(md.deadline); }, 1000) : null;
  return () => { clearInterval(t); window.removeEventListener('beforeunload', onBeforeUnload); };
}
