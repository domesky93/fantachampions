import { sb } from '../api.js';
import { $, toast, errMsg } from '../ui.js';

export async function renderLogin(app) {
  let mode = 'login';
  const draw = () => {
    app.innerHTML = `
      <section class="auth">
        <div class="auth-hero">
          <img src="assets/logo.svg" alt="" class="auth-logo">
          <h1><small>FANTA</small>CHAMPIONS</h1>
          <p>Il fantacalcio della Champions League. Ogni giornata schieri la tua formazione scegliendo tra tutti i giocatori della competizione.</p>
          <ul class="auth-points">
            <li><span>11+7</span> titolari e panchina a ogni giornata</li>
            <li><span>300</span> crediti per costruire la squadra</li>
            <li><span>+3</span> voti, bonus e malus come il fantacalcio classico</li>
          </ul>
        </div>
        <form class="card auth-card" id="auth-form">
          <div class="tabs">
            <button type="button" class="tab ${mode === 'login' ? 'active' : ''}" data-mode="login">Accedi</button>
            <button type="button" class="tab ${mode === 'signup' ? 'active' : ''}" data-mode="signup">Registrati</button>
          </div>
          ${mode === 'signup' ? `
            <label>Nome utente<input name="username" required minlength="3" maxlength="24" autocomplete="nickname"></label>
            <label>Nome della tua squadra<input name="team_name" maxlength="40" placeholder="es. Real Maida"></label>` : ''}
          <label>Email<input name="email" type="email" required autocomplete="email"></label>
          <label>Password<input name="password" type="password" required minlength="6" autocomplete="${mode === 'login' ? 'current-password' : 'new-password'}"></label>
          <button class="btn btn-primary btn-block" type="submit">${mode === 'login' ? 'Entra' : 'Crea account'}</button>
          ${mode === 'login' ? '<button type="button" class="link-btn" id="forgot">Password dimenticata?</button>' : ''}
        </form>
      </section>`;

    app.querySelectorAll('[data-mode]').forEach((b) => b.onclick = () => { mode = b.dataset.mode; draw(); });

    $('#forgot')?.addEventListener('click', async () => {
      const email = $('#auth-form').email.value.trim();
      if (!email) return toast('Scrivi prima la tua email', 'err');
      const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin });
      error ? toast(errMsg(error), 'err') : toast('Ti abbiamo inviato un\'email per reimpostare la password');
    });

    $('#auth-form').onsubmit = async (e) => {
      e.preventDefault();
      const f = e.target; const btn = f.querySelector('[type=submit]');
      btn.disabled = true;
      try {
        if (mode === 'login') {
          const { error } = await sb.auth.signInWithPassword({ email: f.email.value.trim(), password: f.password.value });
          if (error) throw error;
        } else {
          const { data, error } = await sb.auth.signUp({
            email: f.email.value.trim(),
            password: f.password.value,
            options: { data: { username: f.username.value.trim(), team_name: f.team_name.value.trim() || null }, emailRedirectTo: location.origin },
          });
          if (error) throw error;
          if (!data.session) toast('Controlla la tua email per confermare la registrazione');
        }
      } catch (err) {
        toast(errMsg(err).replace('Invalid login credentials', 'Email o password errati'), 'err');
      } finally { btn.disabled = false; }
    };
  };
  draw();
}
