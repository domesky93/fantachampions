import { sb, q, state, getMatchdays } from '../api.js';
import { $, esc, fmtPts, roleBadge, openModal, avatar } from '../ui.js';

// Tabella classifica riutilizzata anche dalle leghe
export function standingsTable(rows, uid) {
  if (!rows.length) return '<div class="empty-state">Ancora nessun punteggio.<br><small>La classifica si aggiorna dopo il calcolo della prima giornata.</small></div>';
  return `<div class="rank-list">
    <div class="rank-head"><span>#</span><span>Squadra</span><span class="hide-sm">G</span><span class="hide-sm">Max</span><span>Punti</span></div>
    ${rows.map((s, i) => `
    <div class="rank-row ${s.user_id === uid ? 'me' : ''}">
      <span class="rank-pos pos-${i + 1}">${i + 1}</span>
      <span class="rank-team">${avatar(s.team_name || s.username)}<span><b>${esc(s.team_name || s.username)}</b><small>${esc(s.username)}</small></span></span>
      <span class="hide-sm muted">${s.played}</span>
      <span class="hide-sm muted">${fmtPts(s.best)}</span>
      <span class="rank-pts">${fmtPts(s.total)}</span>
    </div>`).join('')}
  </div>`;
}

export function resultDetailHtml(detail) {
  const label = { titolare: '', entrato: '<span class="sub-tag">▲ entrato</span>', sostituito: '<span class="sub-tag out">▼ sostituito</span>', senza_voto: '<span class="sub-tag out">s.v.</span>', panchina: '' };
  const rowsOf = (list) => list.map((d) => `<tr class="${d.status === 'panchina' ? 'dim' : ''}">
    <td>${roleBadge(d.role)}</td><td>${esc(d.name)} ${label[d.status] || ''}</td>
    <td class="num">${d.voto ?? '–'}</td><td class="num"><b>${d.fv != null ? fmtPts(d.fv) : '–'}</b></td></tr>`).join('');
  const field = detail.filter((d) => d.status !== 'panchina');
  const bench = detail.filter((d) => d.status === 'panchina');
  return `<table class="table compact"><thead><tr><th></th><th>Giocatore</th><th class="num">Voto</th><th class="num">FV</th></tr></thead>
    <tbody>${rowsOf(field)}${bench.length ? `<tr><td colspan="4" class="muted small">Panchina non utilizzata</td></tr>${rowsOf(bench)}` : ''}</tbody></table>`;
}

export async function renderStandings(app) {
  const uid = state.session.user.id;
  const mds = (await getMatchdays()).filter((m) => m.status === 'calcolata');
  let view = 'gen';

  async function draw() {
    app.innerHTML = `
      <h1 class="page-title">Classifica</h1>
      <p class="page-sub">Somma dei punti di tutte le giornate</p>
      <div class="tabs">
        <button class="tab ${view === 'gen' ? 'active' : ''}" data-v="gen">Generale</button>
        ${mds.map((m) => `<button class="tab ${view === String(m.id) ? 'active' : ''}" data-v="${m.id}">${m.number}ª</button>`).join('')}
      </div>
      <div class="card" id="box"><div class="loading">Caricamento…</div></div>`;
    app.querySelectorAll('[data-v]').forEach((b) => b.onclick = () => { view = b.dataset.v; draw(); });

    const box = $('#box');
    if (view === 'gen') {
      const rows = await q(sb.from('standings').select('*').order('total', { ascending: false }));
      box.innerHTML = standingsTable(rows, uid);
      return;
    }
    const md = mds.find((m) => String(m.id) === view);
    const res = await q(sb.from('results').select('lineup_id,total,user_id,detail,profiles(username,team_name),lineups(module)')
      .eq('matchday_id', md.id).order('total', { ascending: false }));
    box.innerHTML = `<div class="card-head"><h2>${esc(md.name)}</h2><span class="muted small">tocca una squadra per la formazione</span></div>` + (res.length ? `<div class="rank-list">
      <div class="rank-head"><span>#</span><span>Squadra</span><span class="hide-sm">Modulo</span><span></span><span>Punti</span></div>
      ${res.map((r, i) => `<button class="rank-row clickable ${r.user_id === uid ? 'me' : ''}" data-i="${i}">
        <span class="rank-pos pos-${i + 1}">${i + 1}</span>
        <span class="rank-team">${avatar(r.profiles?.team_name || r.profiles?.username)}<span><b>${esc(r.profiles?.team_name || r.profiles?.username)}</b><small>${esc(r.profiles?.username)}</small></span></span>
        <span class="hide-sm muted">${esc(r.lineups?.module || '')}</span><span></span>
        <span class="rank-pts">${fmtPts(r.total)}</span></button>`).join('')}</div>` : '<div class="empty-state">Nessuna formazione.</div>');
    box.querySelectorAll('[data-i]').forEach((tr) => tr.onclick = () => {
      const r = res[+tr.dataset.i];
      openModal(`${esc(r.profiles?.team_name || r.profiles?.username)} · ${fmtPts(r.total)} pt`, resultDetailHtml(r.detail));
    });
  }
  await draw();
}
