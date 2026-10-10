import { sb, q, state, loadProfile } from '../api.js';
import { $, esc, toast, errMsg, avatar } from '../ui.js';
import { SUPABASE_URL } from '../config.js';

export async function renderProfile(app) {
  const p = state.profile;
  const name = () => p.team_name || p.username;
  const paid = p.subscription_paid;
  const paidDate = p.subscription_paid_at
    ? new Date(p.subscription_paid_at).toLocaleDateString('it-IT', { day: 'numeric', month: 'long', year: 'numeric' })
    : null;

  app.innerHTML = `
    <section class="profile-hero">
      <div class="ph-badges">${avatar(name())}</div>
      <div class="ph-text">
        <div class="hero-eyebrow">La tua squadra</div>
        <h1 class="hero-title">${esc(name())}</h1>
        <div class="hero-sub">${esc(p.username)}${p.is_admin ? ' · Amministratore' : ''}</div>
      </div>
    </section>

    <section class="card sub-card ${paid ? 'sub-paid' : 'sub-unpaid'}">
      <div class="card-head"><h2>Abbonamento Champions 2026/27</h2></div>
      ${paid ? `
        <div class="sub-status">
          <span class="sub-badge ok">Abbonato</span>
          <p class="muted small">Pagamento confermato${paidDate ? ` il ${paidDate}` : ''}. Valido per tutta la durata della manifestazione.</p>
        </div>
      ` : `
        <div class="sub-status">
          <span class="sub-badge warn">Non abbonato</span>
          <p>Per creare la rosa e schierare le formazioni serve l'abbonamento unico di <b>25€</b>, valido per tutta la Champions League 2026/27.</p>
          <button class="btn btn-gold btn-block" id="pay-paypal">Paga 25€ con PayPal</button>
          <p class="muted small" id="pay-wait" style="display:none">Reindirizzamento a PayPal…</p>
        </div>
      `}
    </section>

    <div class="profile-grid">
      <form class="card" id="pf">
        <div class="card-head"><h2>Dati squadra</h2></div>
        <label>Nome squadra<input name="team_name" value="${esc(p.team_name || '')}" maxlength="40"></label>
        <label>Nome utente<input name="username" value="${esc(p.username)}" required minlength="3" maxlength="24"></label>
        <p class="muted small">Email: ${esc(state.session.user.email)}${p.is_admin ? ' · <b>Amministratore</b>' : ''}</p>
        <button class="btn btn-primary">Salva</button>
      </form>

      <section class="card">
        <div class="card-head"><h2>Sicurezza account</h2></div>
        <form id="pw-form">
          <label>Nuova password<input type="password" name="password" placeholder="Almeno 6 caratteri" minlength="6" autocomplete="new-password"></label>
          <label>Conferma password<input type="password" name="confirm" placeholder="Ripeti la nuova password" minlength="6" autocomplete="new-password"></label>
          <button class="btn btn-primary" type="submit">Cambia password</button>
        </form>
        <hr class="divider">
        <form id="email-form">
          <label>Nuova email<input type="email" name="email" value="${esc(state.session.user.email)}" required></label>
          <button class="btn btn-ghost" type="submit">Cambia email</button>
        </form>
      </section>
    </div>

    <div class="profile-actions">
      <button class="btn btn-ghost" id="logout">Esci</button>
      <a class="link" href="#/crediti">Crediti foto</a>
    </div>`;

  $('#pf').onsubmit = async (e) => {
    e.preventDefault();
    try {
      await q(sb.from('profiles').update({ username: e.target.username.value.trim(), team_name: e.target.team_name.value.trim() }).eq('id', p.id));
      await loadProfile(); toast('Profilo aggiornato');
      document.dispatchEvent(new Event('profile-changed'));
    } catch (err) { toast(errMsg(err).includes('duplicate') ? 'Nome utente già usato' : errMsg(err), 'err'); }
  };

  $('#pw-form').onsubmit = async (e) => {
    e.preventDefault();
    const f = e.target;
    const pw = f.password.value;
    const cf = f.confirm.value;
    if (pw.length < 6) return toast('La password deve avere almeno 6 caratteri', 'err');
    if (pw !== cf) return toast('Le password non coincidono', 'err');
    try {
      const { error } = await sb.auth.updateUser({ password: pw });
      if (error) throw error;
      f.reset();
      toast('Password aggiornata');
    } catch (err) { toast(errMsg(err), 'err'); }
  };

  $('#email-form').onsubmit = async (e) => {
    e.preventDefault();
    const f = e.target;
    const newEmail = f.email.value.trim();
    if (newEmail === state.session.user.email) return toast('L\'email è già questa', 'warn');
    try {
      const { error } = await sb.auth.updateUser({ email: newEmail });
      if (error) throw error;
      toast('Email aggiornata: controlla la vecchia e la nuova email per confermare');
    } catch (err) { toast(errMsg(err), 'err'); }
  };

  $('#logout').onclick = () => sb.auth.signOut();

  const payBtn = $('#pay-paypal');
  if (payBtn) {
    payBtn.onclick = async () => {
      payBtn.disabled = true;
      $('#pay-wait').style.display = 'block';
      try {
        const { data: { session } } = await sb.auth.getSession();
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/paypal-create-order`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${session.access_token}`,
            'Content-Type': 'application/json',
          },
        });
        const data = await resp.json();
        if (!resp.ok) throw new Error(data.error || 'Errore PayPal');
        window.location.href = data.approveUrl;
      } catch (err) {
        toast(errMsg(err), 'err');
        payBtn.disabled = false;
        $('#pay-wait').style.display = 'none';
      }
    };
  }

  // Gestione ritorno da PayPal
  const params = new URLSearchParams(window.location.search);
  if (params.get('paypal') === 'ok') {
    const orderId = params.get('token') || params.get('orderId');
    if (orderId) {
      try {
        const { data: { session } } = await sb.auth.getSession();
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/paypal-capture`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${session.access_token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ orderId }),
        });
        const data = await resp.json();
        if (!resp.ok) throw new Error(data.error || 'Errore conferma');
        await loadProfile();
        toast('Abbonamento attivo!');
        document.dispatchEvent(new Event('profile-changed'));
      } catch (err) {
        toast('Pagamento in elaborazione: se non si attiva entro qualche minuto, riprova', 'warn');
      }
    }
  }
}
