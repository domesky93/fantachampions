import { getPlayers, getClubs } from '../api.js';
import { esc, face, norm } from '../ui.js';
import { clubColors } from '../clubs.js';

// Elenco autori e licenze delle foto (richiesto dalle licenze Creative Commons)
export async function renderCredits(app) {
  const [players, clubs] = await Promise.all([getPlayers(), getClubs()]);
  const cById = new Map(clubs.map((c) => [c.id, c]));
  const list = players.filter((p) => p.photo_url).sort((a, b) => a.name.localeCompare(b.name));

  app.innerHTML = `
    <h1 class="page-title">Crediti foto</h1>
    <p class="page-sub">Le foto dei giocatori provengono da Wikimedia Commons / Wikipedia e sono usate secondo le rispettive licenze libere. Tocca un credito per vedere la pagina originale dell'immagine. Le foto non sono state modificate, se non ritagliate nella visualizzazione.</p>
    <div class="card">
      <input type="search" id="cr-q" placeholder="Cerca giocatore…" style="width:100%;margin-bottom:10px">
      <div id="cr-list" class="credit-list"></div>
    </div>`;

  const draw = (qs = '') => {
    const rows = list.filter((p) => !qs || norm(p.name).includes(norm(qs)));
    document.getElementById('cr-list').innerHTML = rows.map((p) => {
      const club = cById.get(p.club_id)?.name;
      return `<div class="credit-row">${face(p, ...clubColors(club), 'face-sm')}
        <span class="credit-name"><b>${esc(p.name)}</b><small>${esc(club || '')}</small></span>
        <span class="credit-src">${p.photo_page ? `<a href="${esc(p.photo_page)}" target="_blank" rel="noopener">${esc(p.photo_credit || 'Wikimedia Commons')}</a>` : esc(p.photo_credit || '')}</span></div>`;
    }).join('') || '<div class="empty-state">Nessuna foto caricata.</div>';
  };
  document.getElementById('cr-q').oninput = (e) => draw(e.target.value);
  draw();
}
