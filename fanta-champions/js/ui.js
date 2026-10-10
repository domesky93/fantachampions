// Piccole utility per l'interfaccia

export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export const ROLE_NAME = { P: 'Portiere', D: 'Difensore', C: 'Centrocampista', A: 'Attaccante' };

export function roleBadge(role) {
  return `<span class="role role-${role}">${role}</span>`;
}

// Maglietta SVG con i colori della squadra
export function shirt(body = '#8a94a6', trim = '#ffffff', { empty = false } = {}) {
  if (empty) {
    return `<svg class="shirt" viewBox="0 0 40 38" aria-hidden="true"><path d="M13 3 L8 5 L2 12 L7.5 17 L10 15 V35 H30 V15 L32.5 17 L38 12 L32 5 L27 3 Q20 8 13 3 Z" fill="rgba(255,255,255,.18)" stroke="rgba(255,255,255,.85)" stroke-width="1.6" stroke-dasharray="3 2.5"/><path d="M20 16 V27 M14.5 21.5 H25.5" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/></svg>`;
  }
  return `<svg class="shirt" viewBox="0 0 40 38" aria-hidden="true">
    <path d="M13 3 L8 5 L2 12 L7.5 17 L10 15 V35 H30 V15 L32.5 17 L38 12 L32 5 L27 3 Q20 8 13 3 Z" fill="${body}" stroke="rgba(0,0,0,.28)" stroke-width="1"/>
    <path d="M8 5 L2 12 L7.5 17 L10 15 V9 Z M32 5 L38 12 L32.5 17 L30 15 V9 Z" fill="${trim}" opacity=".95"/>
    <path d="M13 3 Q20 8 27 3" fill="none" stroke="${trim}" stroke-width="2.2"/>
    <path d="M10 15 V35 H30 V15" fill="none" stroke="rgba(255,255,255,.18)" stroke-width="1"/>
  </svg>`;
}

// Avatar con iniziali (per le squadre degli utenti)
export function avatar(name = '?') {
  const s = String(name);
  const ini = s.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?';
  let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) % 360;
  return `<span class="avatar" style="--h:${h}">${esc(ini)}</span>`;
}

export const LOGO = '<img src="assets/logo.svg" alt="" class="logo-img">';

export function fmtPts(n) {
  if (n === null || n === undefined) return '–';
  return Number(n).toLocaleString('it-IT', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
}

export function fmtDate(d) {
  return new Date(d).toLocaleString('it-IT', {
    weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
  });
}

export function countdown(deadline) {
  const ms = new Date(deadline) - Date.now();
  if (ms <= 0) return 'chiusa';
  const d = Math.floor(ms / 86400000);
  const h = Math.floor((ms % 86400000) / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  if (d > 0) return `${d}g ${h}h ${m}m`;
  const s = Math.floor((ms % 60000) / 1000);
  return `${h}h ${m}m ${s}s`;
}

// datetime-local <-> ISO
export function toLocalInput(iso) {
  const d = new Date(iso);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

export function toast(msg, type = 'ok') {
  const root = $('#toast-root');
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.textContent = msg;
  root.appendChild(el);
  setTimeout(() => el.classList.add('out'), 3200);
  setTimeout(() => el.remove(), 3700);
}

export function errMsg(e) {
  const m = e?.message || String(e);
  return m.replace(/^.*?ERROR:\s*/, '');
}

export function openModal(title, html, { wide = false } = {}) {
  const root = $('#modal-root');
  root.innerHTML = `
    <div class="modal-backdrop">
      <div class="modal ${wide ? 'modal-wide' : ''}" role="dialog" aria-modal="true">
        <div class="modal-head"><h3>${title}</h3><button class="icon-btn" data-close aria-label="Chiudi">✕</button></div>
        <div class="modal-body">${html}</div>
      </div>
    </div>`;
  const close = () => { root.innerHTML = ''; document.removeEventListener('keydown', onKey); };
  const onKey = (e) => { if (e.key === 'Escape') close(); };
  document.addEventListener('keydown', onKey);
  root.querySelector('[data-close]').onclick = close;
  root.querySelector('.modal-backdrop').onclick = (e) => { if (e.target.classList.contains('modal-backdrop')) close(); };
  return { el: root.querySelector('.modal-body'), close };
}

// Legge un CSV con separatore ; o , (prima riga = intestazioni)
export function parseCSV(text) {
  const lines = text.replace(/\r/g, '').split('\n').filter((l) => l.trim());
  if (!lines.length) return [];
  const sep = (lines[0].match(/;/g) || []).length >= (lines[0].match(/,/g) || []).length ? ';' : ',';
  const split = (line) => {
    const out = []; let cur = ''; let q = false;
    for (const ch of line) {
      if (ch === '"') q = !q;
      else if (ch === sep && !q) { out.push(cur.trim()); cur = ''; }
      else cur += ch;
    }
    out.push(cur.trim());
    return out;
  };
  const head = split(lines[0]).map((h) => h.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, '_'));
  return lines.slice(1).map((l) => {
    const cells = split(l); const o = {};
    head.forEach((h, i) => { o[h] = cells[i] ?? ''; });
    return o;
  });
}

export const norm = (s) => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();

export function countdownParts(deadline) {
  const ms = Math.max(0, new Date(deadline) - Date.now());
  return { g: Math.floor(ms / 86400000), h: Math.floor((ms % 86400000) / 3600000), m: Math.floor((ms % 3600000) / 60000), s: Math.floor((ms % 60000) / 1000) };
}

export function countdownHtml(deadline) {
  const p = countdownParts(deadline); const z = (n) => String(n).padStart(2, '0');
  return [['g', 'giorni'], ['h', 'ore'], ['m', 'min'], ['s', 'sec']]
    .map(([k, l]) => `<div class="cd-box"><b>${z(p[k])}</b><small>${l}</small></div>`).join('');
}

// Faccia del giocatore (foto con bordo nei colori della squadra); se manca la foto mostra la maglia
export function face(p, c1 = '#8a94a6', c2 = '#ffffff', cls = '') {
  if (!p?.photo_url) return `<span class="face no-photo ${cls}">${shirt(c1, c2)}</span>`;
  return `<span class="face ${cls}" style="--c1:${c1};--c2:${c2}">${shirt(c1, c2)}<img src="${esc(p.photo_url)}" alt="" loading="lazy" onerror="this.parentNode.classList.add('no-photo');this.remove()"></span>`;
}
