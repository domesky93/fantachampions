import { sb, q, state, loadProfile } from '../api.js';
import { $, $$, esc, toast, errMsg, teamBadge, userPhoto, resizeImage } from '../ui.js';
import { crestSvg, defaultCrest, randomCrest, SHAPES, PATTERNS, SYMBOLS, PALETTE } from '../crest.js';

const SHAPE_LABEL = { classico: 'Classico', moderno: 'Moderno', antico: 'Antico', tondo: 'Tondo', ottagono: 'Ottagono', scudetto: 'Scudetto' };
const PATTERN_LABEL = { pieno: 'Pieno', verticali: 'Strisce', orizzontali: 'Bande', meta: 'Metà', diagonale: 'Diagonale', banda: 'Banda', croce: 'Croce', chevron: 'Chevron' };
const SYMBOL_LABEL = { nessuno: 'Nessuno', stella: 'Stella', pallone: 'Pallone', corona: 'Corona', fulmine: 'Fulmine', aquila: 'Aquila', luna: 'Luna', torre: 'Torre', iniziali: 'Iniziali' };

// Carica un'immagine nella cartella dell'utente e ritorna l'indirizzo pubblico
async function uploadImage(blob, name) {
  const uid = state.session.user.id;
  const ext = blob.type === 'image/png' ? 'png' : 'jpg';
  const path = `${uid}/${name}.${ext}`;
  const { error } = await sb.storage.from('profili').upload(path, blob, { upsert: true, contentType: blob.type, cacheControl: '3600' });
  if (error) throw error;
  const { data } = sb.storage.from('profili').getPublicUrl(path);
  return `${data.publicUrl}?v=${Date.now()}`;
}

export async function renderProfile(app) {
  let p = state.profile;
  const name = () => p.team_name || p.username;
  let crest = p.crest || defaultCrest(name());
  let crestTab = p.crest_url ? 'carica' : 'crea';

  const save = async (fields, msg) => {
    await q(sb.from('profiles').update(fields).eq('id', p.id));
    p = await loadProfile();
    document.dispatchEvent(new Event('profile-changed'));
    toast(msg);
  };

  function optionButtons(kind, list, labels, current) {
    return list.map((k) => {
      const preview = kind === 'shape' ? crestSvg({ ...crest, shape: k, symbol: 'nessuno', text: '' })
        : kind === 'pattern' ? crestSvg({ ...crest, pattern: k, symbol: 'nessuno', text: '' })
          : crestSvg({ ...crest, symbol: k, text: k === 'iniziali' ? (crest.text || 'FC') : '' });
      return `<button type="button" class="opt ${k === current ? 'active' : ''}" data-${kind}="${k}" aria-pressed="${k === current}">${preview}<span>${labels[k]}</span></button>`;
    }).join('');
  }

  const swatches = (key) => `<div class="swatches">${PALETTE.map((c) => `<button type="button" class="sw ${crest[key] === c ? 'active' : ''}" style="--c:${c}" data-sw="${key}" data-c="${c}" aria-label="Colore ${c}"></button>`).join('')}
    <label class="sw-custom" title="Altro colore"><input type="color" data-color="${key}" value="${crest[key]}"></label></div>`;

  function draw() {
    app.innerHTML = `
      <section class="profile-hero">
        <div class="ph-badges">${teamBadge(p, 'badge-xl')}${userPhoto(p, 'avatar-xl')}</div>
        <div class="ph-text">
          <div class="hero-eyebrow">La tua squadra</div>
          <h1 class="hero-title">${esc(name())}</h1>
          <div class="hero-sub">${esc(p.username)}${p.is_admin ? ' · Amministratore' : ''}</div>
        </div>
      </section>

      <div class="profile-grid">
        <section class="card">
          <div class="card-head"><h2>Foto profilo</h2></div>
          <div class="photo-edit">
            ${userPhoto(p, 'avatar-lg')}
            <div class="photo-edit-actions">
              <label class="btn btn-primary btn-sm file-btn">Carica foto<input type="file" id="av-file" accept="image/jpeg,image/png,image/webp" hidden></label>
              ${p.avatar_url ? '<button class="btn btn-ghost btn-sm" id="av-remove" type="button">Rimuovi</button>' : ''}
              <p class="muted small">JPG, PNG o WEBP. Viene ritagliata quadrata automaticamente.</p>
            </div>
          </div>
        </section>

        <form class="card" id="pf">
          <div class="card-head"><h2>Dati squadra</h2></div>
          <label>Nome squadra<input id="pf-team" name="team_name" value="${esc(p.team_name || '')}" maxlength="40"></label>
          <label>Nome utente<input id="pf-user" name="username" value="${esc(p.username)}" required minlength="3" maxlength="24"></label>
          <p class="muted small">Email: ${esc(state.session.user.email)}</p>
          <button class="btn btn-primary">Salva</button>
        </form>
      </div>

      <section class="card crest-card">
        <div class="card-head"><h2>Stemma della squadra</h2>
          <div class="tabs tabs-sm">
            <button type="button" class="tab ${crestTab === 'crea' ? 'active' : ''}" data-ctab="crea">Crea stemma</button>
            <button type="button" class="tab ${crestTab === 'carica' ? 'active' : ''}" data-ctab="carica">Carica immagine</button>
          </div>
        </div>

        ${crestTab === 'crea' ? `
        <div class="crest-editor">
          <div class="crest-preview">
            ${crestSvg(crest, 'crest-big')}
            <div class="crest-preview-actions">
              <button type="button" class="btn btn-ghost btn-sm" id="cr-random">🎲 Casuale</button>
              <button type="button" class="btn btn-primary" id="cr-save">Salva stemma</button>
            </div>
          </div>
          <div class="crest-controls">
            <div class="ctrl"><h3>Forma</h3><div class="opts">${optionButtons('shape', Object.keys(SHAPES), SHAPE_LABEL, crest.shape)}</div></div>
            <div class="ctrl"><h3>Disegno</h3><div class="opts">${optionButtons('pattern', PATTERNS, PATTERN_LABEL, crest.pattern)}</div></div>
            <div class="ctrl"><h3>Colori</h3>
              <div class="color-rows">
                <div><span class="muted small">Sfondo</span>${swatches('c1')}</div>
                <div><span class="muted small">Disegno</span>${swatches('c2')}</div>
                <div><span class="muted small">Simbolo e bordo</span>${swatches('c3')}</div>
              </div>
            </div>
            <div class="ctrl"><h3>Simbolo</h3><div class="opts">${optionButtons('symbol', Object.keys(SYMBOLS), SYMBOL_LABEL, crest.symbol)}</div></div>
            <div class="ctrl"><h3>Iniziali <span class="muted small">(max 3 lettere)</span></h3>
              <input id="cr-text" maxlength="3" value="${esc(crest.text || '')}" placeholder="es. RMD" class="cr-text"></div>
          </div>
        </div>` : `
        <div class="crest-upload">
          ${p.crest_url ? teamBadge({ crest_url: p.crest_url }, 'badge-xl') : '<div class="empty-state">Nessuna immagine caricata</div>'}
          <div class="photo-edit-actions">
            <label class="btn btn-primary btn-sm file-btn">Carica stemma<input type="file" id="cr-file" accept="image/png,image/webp,image/jpeg" hidden></label>
            ${p.crest_url ? '<button class="btn btn-ghost btn-sm" id="cr-remove" type="button">Usa lo stemma creato</button>' : ''}
            <p class="muted small">Meglio un PNG con sfondo trasparente. Usa solo immagini tue: niente loghi di squadre vere.</p>
          </div>
        </div>`}
      </section>

      <div class="profile-actions">
        <button class="btn btn-ghost" id="logout" type="button">Esci</button>
        <a class="link" href="#/crediti">Crediti foto</a>
      </div>`;

    bind();
  }

  function bind() {
    $$('[data-ctab]').forEach((b) => b.onclick = () => { crestTab = b.dataset.ctab; draw(); });
    $$('[data-shape]').forEach((b) => b.onclick = () => { crest.shape = b.dataset.shape; draw(); });
    $$('[data-pattern]').forEach((b) => b.onclick = () => { crest.pattern = b.dataset.pattern; draw(); });
    $$('[data-symbol]').forEach((b) => b.onclick = () => { crest.symbol = b.dataset.symbol; draw(); });
    $$('[data-sw]').forEach((b) => b.onclick = () => { crest[b.dataset.sw] = b.dataset.c; draw(); });
    $$('[data-color]').forEach((i) => i.onchange = () => { crest[i.dataset.color] = i.value; draw(); });
    const txt = $('#cr-text');
    if (txt) txt.oninput = () => { crest.text = txt.value.toUpperCase(); const pv = $('.crest-preview .crest'); pv.outerHTML = crestSvg(crest, 'crest-big'); };
    $('#cr-random')?.addEventListener('click', () => { crest = randomCrest(name()); crest.text = (txt?.value || crest.text); draw(); });
    $('#cr-save')?.addEventListener('click', async () => {
      try { await save({ crest, crest_url: null }, 'Stemma salvato'); draw(); } catch (e) { toast(errMsg(e), 'err'); }
    });

    $('#av-file')?.addEventListener('change', async (e) => {
      const f = e.target.files[0]; if (!f) return;
      try {
        toast('Caricamento foto…');
        const url = await uploadImage(await resizeImage(f, 320, 'cover'), 'avatar');
        await save({ avatar_url: url }, 'Foto profilo aggiornata'); draw();
      } catch (err) { toast(errMsg(err), 'err'); }
    });
    $('#av-remove')?.addEventListener('click', async () => {
      try { await save({ avatar_url: null }, 'Foto rimossa'); draw(); } catch (e) { toast(errMsg(e), 'err'); }
    });
    $('#cr-file')?.addEventListener('change', async (e) => {
      const f = e.target.files[0]; if (!f) return;
      try {
        toast('Caricamento stemma…');
        const url = await uploadImage(await resizeImage(f, 320, 'contain'), 'stemma');
        await save({ crest_url: url }, 'Stemma aggiornato'); draw();
      } catch (err) { toast(errMsg(err), 'err'); }
    });
    $('#cr-remove')?.addEventListener('click', async () => {
      try { await save({ crest_url: null }, 'Ora usi lo stemma creato'); crestTab = 'crea'; draw(); } catch (e) { toast(errMsg(e), 'err'); }
    });

    $('#pf').onsubmit = async (e) => {
      e.preventDefault();
      try { await save({ username: e.target.username.value.trim(), team_name: e.target.team_name.value.trim() }, 'Profilo aggiornato'); draw(); }
      catch (err) { toast(errMsg(err).includes('duplicate') ? 'Nome utente già usato' : errMsg(err), 'err'); }
    };
    $('#logout').onclick = () => sb.auth.signOut();
  }

  draw();
}
