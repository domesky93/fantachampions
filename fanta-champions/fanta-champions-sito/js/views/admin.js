import { sb, q, state, fetchAll, getMatchdays, getClubs, getPlayers, getSettings, getFixtures, invalidatePlayers } from '../api.js';
import { $, $$, esc, roleBadge, toast, errMsg, toLocalInput, fmtDate, parseCSV, norm, face } from '../ui.js';
import { findPhotos } from '../photos.js';
import { clubColors } from '../clubs.js';

const TABS = [['giornate', 'Giornate'], ['partite', 'Partite'], ['voti', 'Voti e calcolo'], ['giocatori', 'Giocatori'], ['impostazioni', 'Impostazioni']];

export async function renderAdmin(app, params) {
  if (!state.profile?.is_admin) { app.innerHTML = '<div class="card">Area riservata all\'amministratore.</div>'; return; }
  const tab = params[0] || 'giornate';
  app.innerHTML = `
    <h1 class="page-title">Pannello Admin</h1>
    <div class="tabs">${TABS.map(([k, l]) => `<a class="tab ${k === tab ? 'active' : ''}" href="#/admin/${k}">${l}</a>`).join('')}</div>
    <div id="admin-body"><div class="loading">Caricamento…</div></div>`;
  const body = $('#admin-body');
  if (tab === 'giornate') return matchdaysTab(body);
  if (tab === 'partite') return fixturesTab(body, params[1]);
  if (tab === 'voti') return votesTab(body, params[1]);
  if (tab === 'giocatori') return playersTab(body);
  if (tab === 'impostazioni') return settingsTab(body);
}

// ---------------------------------------------------------------- GIORNATE
async function matchdaysTab(body) {
  const mds = await getMatchdays();
  body.innerHTML = `
    <div class="card"><h2>Giornate</h2>
      <p class="muted small">La scadenza è l'ora in cui si bloccano le formazioni (di solito il primo calcio d'inizio).</p>
      <div class="table-wrap"><table class="table">
        <thead><tr><th>N.</th><th>Nome</th><th>Scadenza</th><th>Stato</th><th></th></tr></thead>
        <tbody>${mds.map((m) => `<tr data-id="${m.id}">
          <td>${m.number}</td>
          <td><input name="name" value="${esc(m.name)}"></td>
          <td><input name="deadline" type="datetime-local" value="${toLocalInput(m.deadline)}"></td>
          <td><select name="status">${['aperta', 'chiusa', 'calcolata'].map((s) => `<option ${s === m.status ? 'selected' : ''}>${s}</option>`).join('')}</select></td>
          <td class="nowrap"><button class="btn btn-sm btn-primary" data-save>Salva</button> <button class="btn btn-sm btn-danger-ghost" data-del>✕</button></td>
        </tr>`).join('')}</tbody></table></div>
    </div>
    <form class="card" id="new-md"><h2>Aggiungi giornata</h2>
      <div class="form-row">
        <label>Numero<input name="number" type="number" required value="${(mds.at(-1)?.number || 0) + 1}"></label>
        <label>Nome<input name="name" required placeholder="es. Playoff andata"></label>
        <label>Scadenza<input name="deadline" type="datetime-local" required></label>
      </div>
      <button class="btn btn-primary">Aggiungi</button>
    </form>`;

  $$('tr[data-id]', body).forEach((tr) => {
    const id = +tr.dataset.id;
    $('[data-save]', tr).onclick = async () => {
      try {
        await q(sb.from('matchdays').update({
          name: $('[name=name]', tr).value, deadline: new Date($('[name=deadline]', tr).value).toISOString(), status: $('[name=status]', tr).value,
        }).eq('id', id));
        toast('Giornata salvata');
      } catch (e) { toast(errMsg(e), 'err'); }
    };
    $('[data-del]', tr).onclick = async () => {
      if (!confirm('Eliminare la giornata con tutte le formazioni e i voti?')) return;
      try { await q(sb.from('matchdays').delete().eq('id', id)); matchdaysTab(body); } catch (e) { toast(errMsg(e), 'err'); }
    };
  });
  $('#new-md').onsubmit = async (e) => {
    e.preventDefault(); const f = e.target;
    try {
      await q(sb.from('matchdays').insert({ number: +f.number.value, name: f.name.value, deadline: new Date(f.deadline.value).toISOString() }));
      toast('Giornata aggiunta'); matchdaysTab(body);
    } catch (err) { toast(errMsg(err), 'err'); }
  };
}

// ---------------------------------------------------------------- PARTITE REALI
async function fixturesTab(body, mdParam) {
  const [mds, clubs] = await Promise.all([getMatchdays(), getClubs()]);
  const md = mds.find((m) => String(m.id) === mdParam) || mds.find((m) => m.status === 'aperta' && new Date(m.deadline) > Date.now()) || mds[0];
  if (!md) { body.innerHTML = '<div class="card">Crea prima una giornata.</div>'; return; }
  const fixtures = await getFixtures(md.id);
  const clubSel = (name, val) => `<select name="${name}">${clubs.map((c) => `<option value="${c.id}" ${c.id === val ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select>`;
  const used = new Set(fixtures.flatMap((f) => [f.home_club_id, f.away_club_id]));
  const resting = clubs.filter((c) => !used.has(c.id));

  body.innerHTML = `
    <div class="card">
      <div class="form-row"><label>Giornata<select id="fx-md">${mds.map((m) => `<option value="${m.id}" ${m.id === md.id ? 'selected' : ''}>${esc(m.name)}</option>`).join('')}</select></label></div>
      <p class="muted small">${fixtures.length} partite · scadenza formazioni ${fmtDate(md.deadline)}. Il risultato è facoltativo (serve per il calendario).
        ${fixtures.length && resting.length ? `<br>Squadre senza partita: ${resting.map((c) => esc(c.name)).join(', ')}` : ''}</p>
      <div class="table-wrap"><table class="table">
        <thead><tr><th>Casa</th><th>Trasferta</th><th>Calcio d'inizio</th><th>Ris.</th><th></th></tr></thead>
        <tbody>${fixtures.map((f) => `<tr data-id="${f.id}">
          <td>${clubSel('home', f.home_club_id)}</td><td>${clubSel('away', f.away_club_id)}</td>
          <td><input name="kickoff" type="datetime-local" value="${toLocalInput(f.kickoff)}"></td>
          <td class="nowrap"><input class="nin" name="hs" type="number" min="0" value="${f.home_score ?? ''}"> - <input class="nin" name="as" type="number" min="0" value="${f.away_score ?? ''}"></td>
          <td class="nowrap"><button class="btn btn-sm btn-primary" data-save>Salva</button> <button class="btn btn-sm btn-danger-ghost" data-del>✕</button></td>
        </tr>`).join('') || '<tr><td colspan="5" class="muted">Nessuna partita: aggiungile qui sotto oppure carica il calendario con l\'SQL.</td></tr>'}</tbody>
      </table></div>
    </div>
    <form class="card" id="fx-new"><h2>Aggiungi partita</h2>
      <div class="form-row">
        <label>Casa${clubSel('home', resting[0]?.id)}</label>
        <label>Trasferta${clubSel('away', resting[1]?.id)}</label>
        <label>Calcio d'inizio<input name="kickoff" type="datetime-local" required value="${toLocalInput(md.deadline)}"></label>
      </div>
      <button class="btn btn-primary">Aggiungi a ${esc(md.name)}</button>
    </form>`;

  const num = (v) => (v === '' ? null : +v);
  $('#fx-md').onchange = (e) => { location.hash = `#/admin/partite/${e.target.value}`; };
  $$('tr[data-id]', body).forEach((tr) => {
    const id = +tr.dataset.id;
    $('[data-save]', tr).onclick = async () => {
      try {
        await q(sb.from('fixtures').update({
          home_club_id: +$('[name=home]', tr).value, away_club_id: +$('[name=away]', tr).value,
          kickoff: new Date($('[name=kickoff]', tr).value).toISOString(),
          home_score: num($('[name=hs]', tr).value), away_score: num($('[name=as]', tr).value),
        }).eq('id', id));
        toast('Partita salvata');
      } catch (e) { toast(errMsg(e), 'err'); }
    };
    $('[data-del]', tr).onclick = async () => {
      if (!confirm('Eliminare la partita?')) return;
      try { await q(sb.from('fixtures').delete().eq('id', id)); fixturesTab(body, String(md.id)); } catch (e) { toast(errMsg(e), 'err'); }
    };
  });
  $('#fx-new').onsubmit = async (e) => {
    e.preventDefault(); const f = e.target;
    if (f.home.value === f.away.value) return toast('Scegli due squadre diverse', 'err');
    try {
      await q(sb.from('fixtures').insert({ matchday_id: md.id, home_club_id: +f.home.value, away_club_id: +f.away.value, kickoff: new Date(f.kickoff.value).toISOString() }));
      toast('Partita aggiunta'); fixturesTab(body, String(md.id));
    } catch (err) { toast(/duplicate|unique/i.test(errMsg(err)) ? 'Una delle due squadre ha già una partita in questa giornata' : errMsg(err), 'err'); }
  };
}

// ---------------------------------------------------------------- VOTI
const VFIELDS = [
  ['gol', 'Gol'], ['assist', 'Ass'], ['ammonizione', 'Amm', 'bool'], ['espulsione', 'Esp', 'bool'],
  ['rigori_parati', 'RP'], ['rigori_sbagliati', 'RS'], ['autogol', 'AG'], ['gol_subiti', 'GS'],
];

async function votesTab(body, mdParam) {
  const [mds, clubs, players] = await Promise.all([getMatchdays(), getClubs(), getPlayers()]);
  const md = mds.find((m) => String(m.id) === mdParam) || [...mds].reverse().find((m) => new Date(m.deadline) <= Date.now()) || mds[0];
  if (!md) { body.innerHTML = '<div class="card">Crea prima una giornata.</div>'; return; }

  const [votes, lineups] = await Promise.all([
    fetchAll(() => sb.from('votes').select('*').eq('matchday_id', md.id)),
    fetchAll(() => sb.from('lineups').select('id,lineup_players(player_id)').eq('matchday_id', md.id)),
  ]);
  const vMap = new Map(votes.map((v) => [v.player_id, v]));
  const used = new Set(lineups.flatMap((l) => l.lineup_players.map((lp) => lp.player_id)));
  const usedClubs = new Set(players.filter((p) => used.has(p.id)).map((p) => p.club_id));
  let clubId = clubs.find((c) => usedClubs.has(c.id))?.id || clubs[0]?.id;
  let onlyUsed = used.size > 0;

  function draw() {
    const list = players.filter((p) => p.club_id === clubId && (!onlyUsed || used.has(p.id)))
      .sort((a, b) => 'PDCA'.indexOf(a.role) - 'PDCA'.indexOf(b.role) || a.name.localeCompare(b.name));
    body.innerHTML = `
      <div class="card">
        <div class="form-row">
          <label>Giornata<select id="v-md">${mds.map((m) => `<option value="${m.id}" ${m.id === md.id ? 'selected' : ''}>${esc(m.name)} (${m.status})</option>`).join('')}</select></label>
          <label>Squadra<select id="v-club">${clubs.map((c) => `<option value="${c.id}" ${c.id === clubId ? 'selected' : ''}>${usedClubs.has(c.id) ? '● ' : ''}${esc(c.name)}</option>`).join('')}</select></label>
          <label class="check"><input type="checkbox" id="v-only" ${onlyUsed ? 'checked' : ''}> Solo giocatori schierati (${used.size})</label>
        </div>
        <p class="muted small">● = squadra con giocatori schierati. Lascia il voto vuoto se il giocatore non ha giocato (s.v.): scatterà la sostituzione. ${lineups.length} formazioni inserite. Scadenza ${fmtDate(md.deadline)}.</p>
      </div>
      <div class="card">
        <div class="table-wrap"><table class="table votes-table">
          <thead><tr><th></th><th>Giocatore</th><th>Voto</th>${VFIELDS.map(([, l]) => `<th>${l}</th>`).join('')}</tr></thead>
          <tbody>${list.map((p) => { const v = vMap.get(p.id) || {}; return `<tr data-pid="${p.id}" class="${used.has(p.id) ? '' : 'dim'}">
            <td>${roleBadge(p.role)}</td><td class="nowrap">${esc(p.name)}</td>
            <td><input class="vin" name="voto" type="number" step="0.5" min="0" max="10" value="${v.voto ?? ''}"></td>
            ${VFIELDS.map(([k, , t]) => t === 'bool'
              ? `<td><input type="checkbox" name="${k}" ${v[k] ? 'checked' : ''}></td>`
              : `<td><input class="nin" name="${k}" type="number" min="0" max="9" value="${v[k] || ''}" ${k === 'gol_subiti' && p.role !== 'P' ? 'disabled' : ''}></td>`).join('')}
          </tr>`; }).join('') || '<tr><td colspan="11" class="muted">Nessun giocatore.</td></tr>'}</tbody>
        </table></div>
        <button class="btn btn-primary" id="v-save">Salva voti di questa squadra</button>
      </div>
      <div class="grid-2">
        <div class="card"><h2>Importa voti da CSV</h2>
          <p class="muted small">Colonne: <code>nome;squadra;voto;gol;assist;amm;esp;rp;rs;ag;gs</code>. amm/esp = 1 o 0. Voto vuoto = s.v.</p>
          <input type="file" id="v-csv" accept=".csv,text/csv">
        </div>
        <div class="card highlight"><h2>Calcola giornata</h2>
          <p class="muted small">Calcola i punteggi di tutte le formazioni con i voti inseriti. Puoi ricalcolare quante volte vuoi.</p>
          <button class="btn btn-primary" id="v-calc">⚡ Calcola ${esc(md.name)}</button>
        </div>
      </div>`;

    $('#v-md').onchange = (e) => { location.hash = `#/admin/voti/${e.target.value}`; };
    $('#v-club').onchange = (e) => { clubId = +e.target.value; draw(); };
    $('#v-only').onchange = (e) => { onlyUsed = e.target.checked; draw(); };
    $('#v-save').onclick = saveVotes;
    $('#v-csv').onchange = importCsv;
    $('#v-calc').onclick = async () => {
      if (new Date(md.deadline) > Date.now() && !confirm('La scadenza non è ancora passata. Calcolare comunque?')) return;
      try { const n = await q(sb.rpc('calc_matchday', { p_matchday: md.id })); toast(`Calcolate ${n} formazioni ✅`); }
      catch (e) { toast(errMsg(e), 'err'); }
    };
  }

  async function saveVotes() {
    const upserts = []; const deletes = [];
    $$('tr[data-pid]', body).forEach((tr) => {
      const pid = +tr.dataset.pid;
      const voto = $('[name=voto]', tr).value;
      const row = { matchday_id: md.id, player_id: pid, voto: voto === '' ? null : +voto };
      VFIELDS.forEach(([k, , t]) => { const i = $(`[name=${k}]`, tr); row[k] = t === 'bool' ? i.checked : +(i.value || 0); });
      const empty = row.voto === null && VFIELDS.every(([k]) => !row[k]);
      if (empty) { if (vMap.has(pid)) deletes.push(pid); } else upserts.push(row);
    });
    try {
      if (upserts.length) await q(sb.from('votes').upsert(upserts));
      if (deletes.length) await q(sb.from('votes').delete().eq('matchday_id', md.id).in('player_id', deletes));
      upserts.forEach((r) => vMap.set(r.player_id, r)); deletes.forEach((id) => vMap.delete(id));
      toast(`Salvati ${upserts.length} voti`);
    } catch (e) { toast(errMsg(e), 'err'); }
  }

  async function importCsv(e) {
    const file = e.target.files[0]; if (!file) return;
    const rows = parseCSV(await file.text());
    const clubByName = new Map(); clubs.forEach((c) => { clubByName.set(norm(c.name), c.id); if (c.short) clubByName.set(norm(c.short), c.id); });
    const missing = []; const up = [];
    for (const r of rows) {
      const cid = clubByName.get(norm(r.squadra));
      const p = players.find((x) => x.club_id === cid && norm(x.name) === norm(r.nome));
      if (!p) { missing.push(`${r.nome} (${r.squadra})`); continue; }
      const n = (v) => +(String(v || '0').replace(',', '.')) || 0;
      up.push({ matchday_id: md.id, player_id: p.id, voto: r.voto === '' || r.voto == null ? null : n(r.voto),
        gol: n(r.gol), assist: n(r.assist), ammonizione: n(r.amm) > 0, espulsione: n(r.esp) > 0,
        rigori_parati: n(r.rp), rigori_sbagliati: n(r.rs), autogol: n(r.ag), gol_subiti: n(r.gs) });
    }
    try {
      for (let i = 0; i < up.length; i += 500) await q(sb.from('votes').upsert(up.slice(i, i + 500)));
      up.forEach((r) => vMap.set(r.player_id, r));
      toast(`Importati ${up.length} voti${missing.length ? `, ${missing.length} non trovati` : ''}`, missing.length ? 'warn' : 'ok');
      if (missing.length) console.warn('Giocatori non trovati:', missing);
      draw();
      if (missing.length) alert('Giocatori non trovati:\n' + missing.slice(0, 40).join('\n'));
    } catch (err) { toast(errMsg(err), 'err'); }
  }

  draw();
}

// ---------------------------------------------------------------- GIOCATORI
async function playersTab(body) {
  const [clubs, players] = await Promise.all([getClubs(true), getPlayers(true)]);
  let clubId = clubs[0]?.id;
  const counts = new Map(); players.forEach((p) => counts.set(p.club_id, (counts.get(p.club_id) || 0) + 1));

  function draw() {
    const list = players.filter((p) => p.club_id === clubId).sort((a, b) => 'PDCA'.indexOf(a.role) - 'PDCA'.indexOf(b.role) || b.price - a.price);
    const withPhoto = players.filter((p) => p.photo_url).length;
    body.innerHTML = `
      <div class="card photo-card">
        <div class="photo-card-head">
          <div><h2>Foto dei giocatori</h2>
            <p class="muted small">Cerca automaticamente le foto su Wikipedia (solo immagini con licenza libera, con autore e licenza salvati). Ci vogliono 1-3 minuti: lascia la pagina aperta.</p></div>
          <div class="photo-count"><b>${withPhoto}</b><small>su ${players.length} con foto</small></div>
        </div>
        <div class="photo-actions">
          <button class="btn btn-primary" id="ph-missing">📷 Cerca foto mancanti</button>
          <button class="btn btn-ghost" id="ph-all">Ricerca tutte da capo</button>
        </div>
        <div class="ph-progress" id="ph-progress" hidden><div class="bar"><i></i></div><span></span></div>
      </div>
      <div class="grid-2">
        <div class="card"><h2>Importa rose da CSV</h2>
          <p class="muted small">Colonne: <code>nome;ruolo;squadra;prezzo</code> (ruolo P, D, C o A; squadra = nome o sigla come nell'elenco). Se il giocatore esiste già, aggiorna ruolo e prezzo. Le squadre nuove vengono create.</p>
          <input type="file" id="p-csv" accept=".csv,text/csv">
          <p class="small"><a href="giocatori-esempio.csv" download>Scarica file di esempio</a></p>
        </div>
        <form class="card" id="p-new"><h2>Aggiungi giocatore</h2>
          <div class="form-row">
            <label>Nome<input name="name" required></label>
            <label>Ruolo<select name="role"><option>P</option><option>D</option><option>C</option><option>A</option></select></label>
            <label>Prezzo<input name="price" type="number" min="1" value="10" required></label>
          </div>
          <button class="btn btn-primary">Aggiungi a squadra selezionata</button>
        </form>
      </div>
      <div class="card">
        <div class="form-row">
          <label>Squadra<select id="p-club">${clubs.map((c) => `<option value="${c.id}" ${c.id === clubId ? 'selected' : ''}>${esc(c.name)} (${counts.get(c.id) || 0})</option>`).join('')}</select></label>
        </div>
        <p class="muted small">${players.length} giocatori in totale. Modifica e premi Salva sulla riga.</p>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Foto</th><th>Ruolo</th><th>Nome</th><th>Prezzo</th><th>Attivo</th><th>Link foto</th><th></th></tr></thead>
          <tbody>${list.map((p) => `<tr data-id="${p.id}">
            <td>${face(p, ...clubColors(clubs.find((c) => c.id === p.club_id)?.name), 'face-sm')}</td>
            <td><select name="role">${'PDCA'.split('').map((r) => `<option ${r === p.role ? 'selected' : ''}>${r}</option>`).join('')}</select></td>
            <td><input name="name" value="${esc(p.name)}"></td>
            <td><input name="price" type="number" min="1" value="${p.price}" class="nin"></td>
            <td><input name="active" type="checkbox" ${p.active ? 'checked' : ''}></td>
            <td><input name="photo_url" value="${esc(p.photo_url || '')}" placeholder="https://…" class="url-in" title="${esc(p.photo_credit || '')}"></td>
            <td><button class="btn btn-sm btn-primary" data-save>Salva</button></td></tr>`).join('') || '<tr><td colspan="7" class="muted">Nessun giocatore: importa il CSV.</td></tr>'}
          </tbody></table></div>
      </div>`;

    $('#p-club').onchange = (e) => { clubId = +e.target.value; draw(); };
    $$('tr[data-id]', body).forEach((tr) => {
      $('[data-save]', tr).onclick = async () => {
        const pl = players.find((p) => p.id === +tr.dataset.id);
        const url = $('[name=photo_url]', tr).value.trim() || null;
        const upd = { role: $('[name=role]', tr).value, name: $('[name=name]', tr).value.trim(), price: +$('[name=price]', tr).value, active: $('[name=active]', tr).checked, photo_url: url };
        if (url !== (pl.photo_url || null)) { upd.photo_credit = url ? 'Foto inserita manualmente' : null; upd.photo_page = null; }
        try { await q(sb.from('players').update(upd).eq('id', +tr.dataset.id)); Object.assign(players.find((p) => p.id === +tr.dataset.id), upd); invalidatePlayers(); toast('Salvato'); }
        catch (e) { toast(errMsg(e), 'err'); }
      };
    });
    $('#p-new').onsubmit = async (e) => {
      e.preventDefault(); const f = e.target;
      try {
        const [p] = await q(sb.from('players').insert({ name: f.name.value.trim(), role: f.role.value, price: +f.price.value, club_id: clubId }).select());
        players.push(p); counts.set(clubId, (counts.get(clubId) || 0) + 1); invalidatePlayers(); toast('Giocatore aggiunto'); draw();
      } catch (err) { toast(errMsg(err), 'err'); }
    };
    $('#p-csv').onchange = importPlayers;
    $('#ph-missing').onclick = () => searchPhotos(false);
    $('#ph-all').onclick = () => { if (confirm('Ricercare le foto di tutti i giocatori? Le foto inserite a mano verranno sostituite se ne viene trovata una.')) searchPhotos(true); };
  }

  async function searchPhotos(all) {
    const todo = players.filter((p) => p.active && (all || !p.photo_url)).map((p) => ({ id: p.id, name: p.name }));
    if (!todo.length) return toast('Tutti i giocatori hanno già una foto');
    const box = $('#ph-progress'); box.hidden = false;
    $$('.photo-actions .btn', body).forEach((b) => { b.disabled = true; });
    const bar = $('i', box); const label = $('span', box);
    try {
      const rows = await findPhotos(todo, (done, total, found) => {
        bar.style.width = `${Math.round(done / total * 100)}%`;
        label.textContent = `${done}/${total} controllati · ${found} foto trovate`;
      });
      label.textContent = `Salvataggio di ${rows.length} foto…`;
      for (let i = 0; i < rows.length; i += 200) await q(sb.rpc('set_player_photos', { p_rows: rows.slice(i, i + 200) }));
      rows.forEach((r) => Object.assign(players.find((p) => p.id === r.id), r));
      invalidatePlayers();
      toast(`Trovate ${rows.length} foto su ${todo.length} giocatori`);
      draw();
    } catch (e) {
      toast(errMsg(e), 'err');
      $$('.photo-actions .btn', body).forEach((b) => { b.disabled = false; });
    }
  }

  async function importPlayers(e) {
    const file = e.target.files[0]; if (!file) return;
    const rows = parseCSV(await file.text());
    const clubByName = new Map(); clubs.forEach((c) => { clubByName.set(norm(c.name), c.id); if (c.short) clubByName.set(norm(c.short), c.id); });
    try {
      // crea squadre mancanti
      const newClubs = [...new Set(rows.map((r) => r.squadra?.trim()).filter((s) => s && !clubByName.has(norm(s))))];
      if (newClubs.length) {
        const created = await q(sb.from('clubs').insert(newClubs.map((name) => ({ name }))).select());
        created.forEach((c) => clubByName.set(norm(c.name), c.id));
      }
      const bad = []; const map = new Map();
      for (const r of rows) {
        const role = (r.ruolo || '').trim().toUpperCase().charAt(0);
        const cid = clubByName.get(norm(r.squadra));
        if (!r.nome || !'PDCA'.includes(role) || !role || !cid) { bad.push(r.nome || '(vuoto)'); continue; }
        map.set(`${r.nome.trim()}|${cid}`, { name: r.nome.trim(), role, club_id: cid, price: Math.max(1, Math.round(+String(r.prezzo || 10).replace(',', '.')) || 10), active: true });
      }
      const up = [...map.values()];
      for (let i = 0; i < up.length; i += 500) await q(sb.from('players').upsert(up.slice(i, i + 500), { onConflict: 'name,club_id' }));
      invalidatePlayers();
      toast(`Importati ${up.length} giocatori${bad.length ? `, ${bad.length} righe scartate` : ''}`, bad.length ? 'warn' : 'ok');
      playersTab(body);
    } catch (err) { toast(errMsg(err), 'err'); }
  }
  draw();
}

// ---------------------------------------------------------------- IMPOSTAZIONI
async function settingsTab(body) {
  const s = await getSettings();
  const B = [['gol', 'Gol segnato'], ['assist', 'Assist'], ['ammonizione', 'Ammonizione'], ['espulsione', 'Espulsione'],
    ['rigore_parato', 'Rigore parato'], ['rigore_sbagliato', 'Rigore sbagliato'], ['autogol', 'Autogol'],
    ['gol_subito', 'Gol subito (portiere)'], ['porta_inviolata', 'Porta inviolata (portiere)']];
  body.innerHTML = `
    <form class="card" id="st"><h2>Regole</h2>
      <div class="form-row">
        <label>Budget rosa<input name="budget" type="number" min="0" value="${s.budget ?? ''}" placeholder="vuoto = nessun limite"></label>
        <label>Max giocatori stessa squadra<input name="max_per_club" type="number" min="1" value="${s.max_per_club ?? ''}" placeholder="vuoto = nessun limite"></label>
        <label>Max sostituzioni<input name="max_subs" type="number" min="0" max="7" value="${s.max_subs}"></label>
      </div>
      ${s.squad_p !== undefined ? `
      <h3>Rosa e mercato</h3>
      <div class="form-row wrap">
        <label>Portieri<input name="squad_p" type="number" min="1" value="${s.squad_p}"></label>
        <label>Difensori<input name="squad_d" type="number" min="1" value="${s.squad_d}"></label>
        <label>Centrocampisti<input name="squad_c" type="number" min="1" value="${s.squad_c}"></label>
        <label>Attaccanti<input name="squad_a" type="number" min="1" value="${s.squad_a}"></label>
      </div>
      <div class="form-row wrap">
        <label>Rose libere fino a<input name="squad_deadline" type="datetime-local" value="${s.squad_deadline ? toLocalInput(s.squad_deadline) : ''}"></label>
        <label>Mercato dal<input name="market_from" type="datetime-local" value="${s.market_from ? toLocalInput(s.market_from) : ''}"></label>
        <label>Mercato fino al<input name="market_to" type="datetime-local" value="${s.market_to ? toLocalInput(s.market_to) : ''}"></label>
        <label>Cambi al mercato<input name="market_max" type="number" min="0" max="25" value="${s.market_max}"></label>
      </div>
      <p class="muted small">Dopo "Rose libere fino a" la rosa resta bloccata; si può cambiare solo tra "Mercato dal" e "Mercato fino al".</p>` : '<p class="notice">Esegui <code>rosa-e-mercato.sql</code> in Supabase per attivare la rosa da 25 e il mercato.</p>'}
      <h3>Bonus e malus</h3>
      <div class="form-row wrap">${B.map(([k, l]) => `<label>${l}<input name="b_${k}" type="number" step="0.5" value="${s.bonus[k]}"></label>`).join('')}</div>
      <button class="btn btn-primary">Salva impostazioni</button>
      <p class="muted small">Dopo aver cambiato i bonus, ricalcola le giornate già giocate dal tab "Voti e calcolo".</p>
    </form>`;
  $('#st').onsubmit = async (e) => {
    e.preventDefault(); const f = e.target;
    const bonus = {}; B.forEach(([k]) => { bonus[k] = +f[`b_${k}`].value || 0; });
    try {
      await q(sb.from('settings').update({
        budget: f.budget.value === '' ? null : +f.budget.value,
        max_per_club: f.max_per_club.value === '' ? null : +f.max_per_club.value,
        max_subs: +f.max_subs.value, bonus,
        ...(s.squad_p !== undefined ? {
          squad_p: +f.squad_p.value, squad_d: +f.squad_d.value, squad_c: +f.squad_c.value, squad_a: +f.squad_a.value,
          squad_deadline: f.squad_deadline.value ? new Date(f.squad_deadline.value).toISOString() : null,
          market_from: f.market_from.value ? new Date(f.market_from.value).toISOString() : null,
          market_to: f.market_to.value ? new Date(f.market_to.value).toISOString() : null,
          market_max: +f.market_max.value,
        } : {}),
      }).eq('id', 1));
      toast('Impostazioni salvate');
    } catch (err) { toast(errMsg(err), 'err'); }
  };
}
