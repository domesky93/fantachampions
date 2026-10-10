import { sb, q, state, getMatchdays, pickCurrentMatchday, getSettings, getSquad, squadSize, squadPhase } from '../api.js';
import { esc, fmtDate, fmtPts, countdownHtml } from '../ui.js';
import { standingsTable } from './standings.js';

export async function renderHome(app) {
  const uid = state.session.user.id;
  const mds = await getMatchdays();
  const cur = pickCurrentMatchday(mds);
  const lastCalc = [...mds].reverse().find((m) => m.status === 'calcolata');

  const [settings, squad, myLineup, standings, myLast, lastResults] = await Promise.all([
    getSettings(), getSquad(uid),
    cur ? q(sb.from('lineups').select('id,module,updated_at').eq('user_id', uid).eq('matchday_id', cur.id).maybeSingle()) : null,
    q(sb.from('standings').select('*').order('total', { ascending: false }).limit(100)),
    lastCalc ? q(sb.from('results').select('total').eq('user_id', uid).eq('matchday_id', lastCalc.id).maybeSingle()) : null,
    lastCalc ? q(sb.from('results').select('total').eq('matchday_id', lastCalc.id).order('total', { ascending: false })) : [],
  ]);

  const myPos = standings.findIndex((s) => s.user_id === uid) + 1;
  const me = standings.find((s) => s.user_id === uid);
  const open = cur && cur.status === 'aperta' && new Date(cur.deadline) > Date.now();
  const lastPos = myLast ? lastResults.findIndex((r) => Number(r.total) <= Number(myLast.total)) + 1 : null;

  const hasRosa = settings.squad_p !== undefined;
  const squadOk = !hasRosa || squad.players.length >= squadSize(settings);
  const phase = hasRosa ? squadPhase(settings, squad.players.length > 0) : null;
  const pending = open && (!myLineup || !squadOk);
  app.innerHTML = `
    <section class="hero ${pending ? 'hero-alert' : ''}">
      <div class="hero-top">
        <div>
          <div class="hero-eyebrow">${open ? 'Prossima giornata' : 'Giornata in corso'}</div>
          <h1 class="hero-title">${cur ? esc(cur.name) : 'Nessuna giornata'}</h1>
          ${cur ? `<div class="hero-sub">Formazioni entro ${fmtDate(cur.deadline)} · <a class="hero-link" href="#/calendario/${cur.id}">vedi le partite</a></div>` : ''}
        </div>
        <img src="assets/logo.svg" alt="" class="hero-logo">
      </div>
      ${cur && open ? `<div class="cd" id="cd">${countdownHtml(cur.deadline)}</div>` : cur ? '<div class="hero-closed">Formazioni chiuse</div>' : ''}
      ${cur ? `<div class="hero-bottom">
        ${!squadOk ? `<span class="status-chip warn">! Rosa da completare · ${squad.players.length}/${squadSize(settings)}</span>
        <a class="btn btn-gold" href="#/rosa">Crea la tua rosa</a>` : `
        <span class="status-chip ${myLineup ? 'ok' : open ? 'warn' : ''}">${myLineup ? `✓ Formazione inserita · ${esc(myLineup.module)}` : open ? '! Formazione da inserire' : 'Nessuna formazione'}</span>
        <a class="btn btn-gold" href="#/formazione/${cur.id}">${open ? (myLineup ? 'Modifica formazione' : 'Schiera la formazione') : 'Vedi formazione'}</a>`}
      </div>` : ''}
    </section>

    ${phase === 'mercato' ? `<div class="notice notice-gold"><b>Mercato aperto</b> fino a ${fmtDate(settings.market_to)}: puoi cambiare fino a ${settings.market_max} giocatori. <a class="link" href="#/rosa">Vai alla rosa →</a></div>` : ''}
    ${hasRosa && squadOk && phase === 'libera' && settings.squad_deadline ? `<div class="notice">Puoi ancora modificare la rosa fino a ${fmtDate(settings.squad_deadline)}. <a class="link" href="#/rosa">Vai alla rosa →</a></div>` : ''}

    <section class="tiles">
      <div class="tile"><span class="tile-label">Punti totali</span><b>${me ? fmtPts(me.total) : '0,0'}</b></div>
      <div class="tile"><span class="tile-label">Posizione</span><b>${myPos ? myPos + '<sup>º</sup>' : '–'}</b><small>su ${standings.length}</small></div>
      <div class="tile"><span class="tile-label">Ultima giornata</span><b>${myLast ? fmtPts(myLast.total) : '–'}</b>${lastPos ? `<small>${lastPos}º di giornata</small>` : '<small>&nbsp;</small>'}</div>
      <div class="tile"><span class="tile-label">Giornate</span><b>${me?.played ?? 0}</b><small>giocate</small></div>
    </section>

    <section class="card">
      <div class="card-head"><h2>Classifica generale</h2><a href="#/classifica" class="link">Vedi tutta</a></div>
      ${standingsTable(standings.slice(0, 10), uid)}
    </section>`;

  if (open) {
    const t = setInterval(() => {
      const el = document.getElementById('cd');
      if (el) el.innerHTML = countdownHtml(cur.deadline);
    }, 1000);
    return () => clearInterval(t);
  }
}
