import { sb, q, state, getPlayers, getClubs, getSettings, getFixtures, getSquad, squadSize, squadNeed, squadPhase, nextFixtureByClub } from '../api.js';
import { $, $$, esc, roleBadge, face, fmtDate, fmtKick, toast, errMsg, openModal, norm, ROLE_NAME } from '../ui.js';
import { clubColors, clubShort } from '../clubs.js';

const ROLE_PLURAL = { P: 'Portieri', D: 'Difensori', C: 'Centrocampisti', A: 'Attaccanti' };

// La rosa da 25: si compra all'inizio e resta fino alla fine dei gironi (+1 mercato)
export async function renderSquad(app) {
  const uid = state.session.user.id;
  const [players, clubs, settings, fixtures, squad] = await Promise.all([
    getPlayers(), getClubs(), getSettings(), getFixtures(), getSquad(uid),
  ]);

  if (settings.squad_p === undefined) {
    app.innerHTML = `<div class="card"><h2>Rosa non ancora attiva</h2>
      <p>L'amministratore deve eseguire lo script <code>rosa-e-mercato.sql</code> in Supabase.</p></div>`;
    return;
  }

  const pById = new Map(players.map((p) => [p.id, p]));
  const cById = new Map(clubs.map((c) => [c.id, c]));
  const nextBy = nextFixtureByClub(fixtures);
  const need = squadNeed(settings);
  const total = squadSize(settings);
  const budget = settings.budget;

  const savedIds = squad.players.map((r) => r.player_id);
  const paid = new Map(squad.players.map((r) => [r.player_id, r.price]));
  const phase = squadPhase(settings, savedIds.length > 0);
  const editable = phase !== 'bloccata';

  // rosa di partenza del mercato (per contare i cambi)
  const row = squad.row;
  const base = phase === 'mercato' && row?.market_base && row.market_base_at && new Date(row.market_base_at) >= new Date(settings.market_from)
    ? new Set(row.market_base) : new Set(savedIds);

  let sel = [...savedIds];
  let dirty = false;

  const priceOf = (id) => (phase === 'mercato' && paid.has(id) ? paid.get(id) : pById.get(id)?.price || 0);
  const cost = () => sel.reduce((t, id) => t + priceOf(id), 0);
  const byRole = (r) => sel.filter((id) => pById.get(id)?.role === r)
    .sort((a, b) => (pById.get(b)?.price || 0) - (pById.get(a)?.price || 0));
  const changes = () => sel.filter((id) => !base.has(id)).length;

  // "vs INT · mar 13/10 21:00" della prossima partita
  const nextTag = (p) => {
    const o = nextBy.get(p.club_id);
    if (!fixtures.length) return '';
    if (!o) return '<span class="opp opp-none">nessuna partita</span>';
    return `<span class="opp ${o.home ? 'opp-home' : 'opp-away'}" title="${o.home ? 'In casa' : 'In trasferta'} · ${fmtKick(o.kickoff)}">${o.home ? 'vs' : '@'} ${esc(clubShort(cById.get(o.opp)))}</span>`;
  };
  const nextLong = (p) => {
    const o = nextBy.get(p.club_id);
    if (!fixtures.length || !o) return '';
    return `${o.home ? 'vs' : '@'} ${esc(cById.get(o.opp)?.name || '')} · ${fmtKick(o.kickoff)}`;
  };

  function phaseText() {
    if (phase === 'libera') {
      if (!savedIds.length && settings.squad_deadline && Date.now() >= new Date(settings.squad_deadline)) {
        return 'Crea la tua rosa: dopo il salvataggio resterà bloccata fino al mercato di metà girone.';
      }
      return settings.squad_deadline
        ? `Puoi cambiarla liberamente fino a <b>${fmtDate(settings.squad_deadline)}</b>, poi resta bloccata fino al mercato.`
        : 'Puoi cambiarla liberamente.';
    }
    if (phase === 'mercato') return `<b>Mercato aperto</b> fino a ${fmtDate(settings.market_to)}: puoi cambiare al massimo <b>${settings.market_max}</b> giocatori.`;
    const now = Date.now();
    if (settings.market_from && now < new Date(settings.market_from)) {
      return `Rosa bloccata. Mercato di metà girone dal <b>${fmtDate(settings.market_from)}</b> (max ${settings.market_max} cambi).`;
    }
    return 'Rosa bloccata fino alla fine della fase a gironi.';
  }

  function prow(id) {
    const p = pById.get(id); if (!p) return '';
    const club = cById.get(p.club_id);
    const [c1, c2] = clubColors(club?.name);
    const isNew = phase === 'mercato' && !base.has(id);
    return `<div class="sq-row ${isNew ? 'sq-new' : ''}">
      ${roleBadge(p.role)}${face(p, c1, c2, 'face-sm')}
      <span class="brow-name"><b>${esc(p.name)}</b><small>${esc(club?.name || '')}${nextLong(p) ? ` · ${nextLong(p)}` : ''}${p.active === false ? ' · <span class="warn">fuori lista UEFA</span>' : ''}</small></span>
      ${nextTag(p)}
      <span class="price-tag">${priceOf(id)}</span>
      ${editable ? `<button class="icon-btn sq-del" data-del="${id}" aria-label="Togli ${esc(p.name)}">✕</button>` : ''}
    </div>`;
  }

  function roleCard(r) {
    const ids = byRole(r);
    const empty = Math.max(0, need[r] - ids.length);
    return `<div class="card sq-card">
      <div class="card-head"><h3>${roleBadge(r)} ${ROLE_PLURAL[r]}</h3><span class="sq-count ${ids.length === need[r] ? 'ok' : ''}">${ids.length}/${need[r]}</span></div>
      ${ids.map(prow).join('')}
      ${editable ? Array.from({ length: empty }, () => `<button class="brow empty" data-add="${r}">${roleBadge(r)}<span class="brow-name muted">Aggiungi ${ROLE_NAME[r].toLowerCase()}</span><span class="brow-plus">+</span></button>`).join('')
        : Array.from({ length: empty }, () => '<div class="brow empty"><span class="brow-name muted">—</span></div>').join('')}
    </div>`;
  }

  function draw() {
    const spent = cost();
    const left = budget ? budget - spent : null;
    const full = sel.length === total;
    app.innerHTML = `
      <h1 class="page-title">La mia rosa</h1>
      <p class="page-sub">${total} giocatori (${need.P} P · ${need.D} D · ${need.C} C · ${need.A} A): ogni giornata schieri la formazione scegliendo da qui.</p>
      <div class="notice ${phase === 'mercato' ? 'notice-gold' : ''}">${phaseText()}</div>

      <div class="card sq-summary">
        <div class="budget ${budget && spent > budget ? 'over' : ''}">
          <div class="budget-row"><span>Crediti spesi</span><span><b>${spent}</b>${budget ? ` / ${budget}` : ''}</span></div>
          ${budget ? `<div class="bar"><i style="width:${Math.min(100, spent / budget * 100)}%"></i></div>
          <div class="budget-left">${left >= 0 ? `Ti restano <b>${left}</b> crediti` : `<b>Sforato di ${-left}</b> crediti`}</div>` : ''}
        </div>
        <div class="sq-roles">${['P', 'D', 'C', 'A'].map((r) => `<span class="sq-chip ${byRole(r).length === need[r] ? 'ok' : ''}">${roleBadge(r)} ${byRole(r).length}/${need[r]}</span>`).join('')}
          ${phase === 'mercato' ? `<span class="sq-chip ${changes() > settings.market_max ? 'bad' : ''}">Cambi ${changes()}/${settings.market_max}</span>` : ''}</div>
      </div>

      <div class="grid-2 sq-grid">${['P', 'D', 'C', 'A'].map(roleCard).join('')}</div>

      ${editable ? `
      <div class="save-bar">
        <div class="save-progress"><b>${sel.length}</b>/${total} <span class="muted">${dirty ? '· <span class="warn">non salvata</span>' : savedIds.length ? '· <span class="ok">salvata ✓</span>' : ''}</span></div>
        <button class="btn btn-primary" id="save" ${!full || !dirty || (budget && spent > budget) ? 'disabled' : ''}>Salva rosa</button>
      </div>` : ''}
      <p class="muted small rules">${budget ? `Budget ${budget} crediti · ` : ''}${settings.max_per_club ? `max ${settings.max_per_club} per squadra · ` : ''}un mercato a metà girone con max ${settings.market_max} cambi
        ${fixtures.length ? '<br>Accanto a ogni giocatore la prossima partita: <b>vs</b> in casa · <b>@</b> in trasferta' : ''}</p>`;

    if (!editable) return;
    $$('[data-add]').forEach((b) => b.onclick = () => pick(b.dataset.add));
    $$('[data-del]').forEach((b) => b.onclick = () => { sel = sel.filter((id) => id !== +b.dataset.del); dirty = true; draw(); });
    $('#save').onclick = save;
  }

  function pick(role) {
    const chosen = new Set(sel);
    const counts = new Map();
    sel.forEach((id) => { const c = pById.get(id)?.club_id; counts.set(c, (counts.get(c) || 0) + 1); });
    // lascia almeno 1 credito per ogni posto ancora vuoto
    const emptyAfter = total - sel.length - 1;
    const maxSpend = budget ? budget - cost() - Math.max(0, emptyAfter) : Infinity;
    const changesLeft = phase === 'mercato' ? settings.market_max - changes() : Infinity;
    const clubOpts = clubs.map((c) => {
      const o = nextBy.get(c.id);
      const vs = o ? ` (${o.home ? 'vs' : '@'} ${clubShort(cById.get(o.opp))})` : '';
      return `<option value="${c.id}">${esc(c.name + vs)}</option>`;
    }).join('');

    const { el, close } = openModal(`Aggiungi · ${ROLE_NAME[role]}`, `
      <div class="filters">
        <input id="f-q" type="search" placeholder="Cerca giocatore…" autofocus>
        <select id="f-club"><option value="">Tutte le squadre</option>${clubOpts}</select>
        <select id="f-sort"><option value="pd">Prezzo ↓</option><option value="pa">Prezzo ↑</option><option value="n">Nome</option></select>
      </div>
      ${budget ? `<p class="muted small">Puoi spendere fino a <b>${maxSpend}</b> crediti${emptyAfter > 0 ? ` (resta 1 credito per ognuno degli altri ${emptyAfter} posti)` : ''}.</p>` : ''}
      ${phase === 'mercato' ? `<p class="muted small">Cambi rimasti: <b>${Math.max(0, changesLeft)}</b></p>` : ''}
      <div class="plist" id="plist"></div>`);

    const list = () => {
      const qs = norm($('#f-q', el).value);
      const club = +$('#f-club', el).value;
      const sort = $('#f-sort', el).value;
      let rows = players.filter((p) => p.role === role && p.active !== false && (!club || p.club_id === club) && (!qs || norm(p.name).includes(qs)));
      rows.sort(sort === 'n' ? (a, b) => a.name.localeCompare(b.name) : sort === 'pa' ? (a, b) => a.price - b.price : (a, b) => b.price - a.price);
      const n = rows.length; rows = rows.slice(0, 150);
      $('#plist', el).innerHTML = rows.map((p) => {
        let why = '';
        const price = phase === 'mercato' && paid.has(p.id) ? paid.get(p.id) : p.price;
        if (chosen.has(p.id)) why = 'già in rosa';
        else if (price > maxSpend) why = 'budget';
        else if (settings.max_per_club && (counts.get(p.club_id) || 0) >= settings.max_per_club) why = `max ${settings.max_per_club} per squadra`;
        else if (!base.has(p.id) && changesLeft <= 0) why = 'cambi finiti';
        return `<button class="prow" data-id="${p.id}" ${why ? 'disabled' : ''}>
          ${face(p, ...clubColors(cById.get(p.club_id)?.name), 'face-sm')}${roleBadge(p.role)}<span class="prow-name"><b>${esc(p.name)}</b><small>${esc(cById.get(p.club_id)?.name || '')}${nextLong(p) ? ` · ${nextLong(p)}` : ''}</small></span>
          ${why ? `<span class="why">${why}</span>` : nextTag(p)}<span class="price">${price}</span></button>`;
      }).join('') + (n > 150 ? `<p class="muted small center">Mostrati 150 su ${n}: usa la ricerca o il filtro squadra.</p>` : '')
        + (!n ? '<p class="muted center">Nessun giocatore trovato.</p>' : '');
      $$('.prow', el).forEach((b) => b.onclick = () => { sel.push(+b.dataset.id); dirty = true; close(); draw(); });
    };
    ['#f-q', '#f-club', '#f-sort'].forEach((s) => $(s, el).addEventListener('input', list));
    list();
  }

  async function save() {
    const btn = $('#save'); btn.disabled = true;
    try {
      await q(sb.rpc('save_squad', { p_players: sel }));
      toast('Rosa salvata ✅');
      dirty = false;
      window.dispatchEvent(new HashChangeEvent('hashchange')); // ricarica la pagina della rosa
    } catch (e) { toast(errMsg(e), 'err'); btn.disabled = false; }
  }

  const onBeforeUnload = (e) => { if (dirty) { e.preventDefault(); e.returnValue = ''; } };
  window.addEventListener('beforeunload', onBeforeUnload);
  draw();
  return () => window.removeEventListener('beforeunload', onBeforeUnload);
}
