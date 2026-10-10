import { sb, q, state, loadProfile } from '../api.js';
import { $, esc, toast, errMsg } from '../ui.js';

export async function renderProfile(app) {
  const p = state.profile;
  app.innerHTML = `
    <h1 class="page-title">Profilo</h1>
    <form class="card" id="pf">
      <label>Nome utente<input name="username" value="${esc(p.username)}" required minlength="3" maxlength="24"></label>
      <label>Nome squadra<input name="team_name" value="${esc(p.team_name || '')}" maxlength="40"></label>
      <p class="muted small">Email: ${esc(state.session.user.email)}${p.is_admin ? ' · <b>Amministratore</b>' : ''}</p>
      <button class="btn btn-primary">Salva</button>
    </form>
    <div class="profile-actions">
      <button class="btn btn-ghost" id="logout">Esci</button>
      <a class="link" href="#/crediti">Crediti foto</a>
    </div>`;

  $('#pf').onsubmit = async (e) => {
    e.preventDefault();
    try {
      await q(sb.from('profiles').update({ username: e.target.username.value.trim(), team_name: e.target.team_name.value.trim() }).eq('id', p.id));
      await loadProfile(); toast('Profilo aggiornato');
    } catch (err) { toast(errMsg(err).includes('duplicate') ? 'Nome utente già usato' : errMsg(err), 'err'); }
  };
  $('#logout').onclick = () => sb.auth.signOut();
}
