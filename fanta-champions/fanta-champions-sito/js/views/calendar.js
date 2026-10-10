import { getMatchdays, getClubs, getFixtures, pickCurrentMatchday } from '../api.js';
import { esc, fmtDate, fmtTime } from '../ui.js';
import { clubDot, clubShort } from '../clubs.js';

// Calendario: partite reali di Champions abbinate alle giornate del fanta
export async function renderCalendar(app, params) {
  const [mds, clubs, fixtures] = await Promise.all([getMatchdays(), getClubs(), getFixtures()]);
  if (!mds.length) { app.innerHTML = '<div class="card">Nessuna giornata disponibile.</div>'; return; }
  const cById = new Map(clubs.map((c) => [c.id, c]));
  let md = mds.find((m) => String(m.id) === params[0]) || pickCurrentMatchday(mds);

  const team = (cid, right) => {
    const c = cById.get(cid);
    return `<span class="fx-team ${right ? 'right' : ''}">${clubDot(c?.name)}<span class="fx-name">${esc(c?.name || '?')}</span><span class="fx-short">${esc(clubShort(c))}</span></span>`;
  };

  function draw() {
    const list = fixtures.filter((f) => f.matchday_id === md.id);
    const open = md.status === 'aperta' && new Date(md.deadline) > Date.now();
    let lastDay = '';
    const rows = list.map((f) => {
      const day = new Date(f.kickoff).toLocaleDateString('it-IT', { weekday: 'long', day: 'numeric', month: 'long' });
      const head = day !== lastDay ? `<div class="fx-day">${esc(day)}</div>` : '';
      lastDay = day;
      const played = f.home_score != null && f.away_score != null;
      return `${head}<div class="fx-row">${team(f.home_club_id, false)}<span class="fx-mid ${played ? 'played' : ''}">${played ? `${f.home_score} - ${f.away_score}` : fmtTime(f.kickoff)}</span>${team(f.away_club_id, true)}</div>`;
    }).join('');

    app.innerHTML = `
      <h1 class="page-title">Calendario</h1>
      <p class="page-sub">Le partite reali di Champions League di ogni giornata</p>
      <div class="tabs">${mds.map((m) => `<button class="tab ${m.id === md.id ? 'active' : ''}" data-md="${m.id}">${m.number}ª</button>`).join('')}</div>
      <div class="card fx-card">
        <div class="card-head"><h2>${esc(md.name)}</h2>
          <span class="muted small">${open ? `Formazioni entro ${fmtDate(md.deadline)}` : md.status === 'calcolata' ? 'Giornata calcolata' : 'Formazioni chiuse'}</span></div>
        ${rows || '<div class="empty-state">Partite non ancora inserite per questa giornata.</div>'}
        <div class="fx-foot"><a class="btn ${open ? 'btn-primary' : 'btn-ghost'}" href="#/formazione/${md.id}">${open ? 'Schiera la formazione' : 'Vedi formazione'}</a></div>
      </div>`;

    app.querySelectorAll('[data-md]').forEach((b) => b.onclick = () => {
      md = mds.find((m) => m.id === +b.dataset.md);
      history.replaceState(null, '', `#/calendario/${md.id}`);
      draw();
    });
    app.querySelector('.tab.active')?.scrollIntoView({ block: 'nearest', inline: 'center' });
  }
  draw();
}
