// Generatore di stemmi in SVG (forma + disegno + colori + simbolo + iniziali)

export const SHAPES = {
  classico: 'M50 4 L94 15 V58 C94 88 74 106 50 116 C26 106 6 88 6 58 V15 Z',
  moderno: 'M8 6 H92 V64 C92 90 72 106 50 116 C28 106 8 90 8 64 Z',
  antico: 'M6 12 Q28 2 50 12 Q72 2 94 12 V58 C94 88 72 106 50 116 C28 106 6 88 6 58 Z',
  tondo: 'M50 12 A48 48 0 1 1 49.99 12 Z',
  ottagono: 'M30 8 H70 L94 32 V88 L70 112 H30 L6 88 V32 Z',
  scudetto: 'M12 6 H88 L94 30 L50 116 L6 30 Z',
};

export const PATTERNS = ['pieno', 'verticali', 'orizzontali', 'meta', 'diagonale', 'banda', 'croce', 'chevron'];

export const SYMBOLS = {
  nessuno: '',
  stella: '<path d="M50 30 L57 49 L77 49.6 L61 62 L66.8 81.5 L50 70 L33.2 81.5 L39 62 L23 49.6 L43 49 Z"/>',
  pallone: '<circle cx="50" cy="58" r="20" fill="#fff" stroke="#111" stroke-width="2"/><path d="M50 48 L59 54.5 L55.5 65 L44.5 65 L41 54.5 Z" fill="#111"/><path d="M50 48 V38.5 M59 54.5 L68 51 M55.5 65 L61 73 M44.5 65 L39 73 M41 54.5 L32 51" stroke="#111" stroke-width="2"/>',
  corona: '<path d="M27 74 L23 42 L37 54 L50 34 L63 54 L77 42 L73 74 Z"/><rect x="27" y="76" width="46" height="7" rx="2"/>',
  fulmine: '<path d="M56 28 L32 62 H48 L42 90 L68 52 H52 Z"/>',
  aquila: '<path d="M50 36 C46 36 44 40 45 44 L36 40 C28 37 20 42 18 50 C26 47 32 49 36 52 C28 52 22 57 21 64 C28 60 35 60 41 62 L44 74 L40 84 L50 79 L60 84 L56 74 L59 62 C65 60 72 60 79 64 C78 57 72 52 64 52 C68 49 74 47 82 50 C80 42 72 37 64 40 L55 44 C56 40 54 36 50 36 Z"/>',
  luna: '<path d="M58 32 A27 27 0 1 0 72 78 A22 22 0 1 1 58 32 Z"/><path d="M66 44 L68.5 50.5 L75 51 L70 55 L71.8 61.5 L66 57.8 L60.2 61.5 L62 55 L57 51 L63.5 50.5 Z"/>',
  torre: '<path d="M32 86 V50 H38 V42 H44 V50 H47 V42 H53 V50 H56 V42 H62 V50 H68 V86 Z M45 86 V72 A5 5 0 0 1 55 72 V86 Z" fill-rule="evenodd"/>',
  iniziali: '',
};

export const PALETTE = ['#0b1f4b', '#1d4ed8', '#12a0d7', '#16a34a', '#0f766e', '#facc15', '#f5b301', '#f97316', '#dc2626', '#8e1f2f', '#7c3aed', '#111827', '#ffffff', '#9ca3af'];

let uid = 0;

function patternSvg(p, c2) {
  switch (p) {
    case 'verticali': return [14, 38, 62, 86].map((x) => `<rect x="${x - 6}" y="0" width="12" height="120" fill="${c2}"/>`).join('');
    case 'orizzontali': return [20, 52, 84].map((y) => `<rect x="0" y="${y}" width="100" height="14" fill="${c2}"/>`).join('');
    case 'meta': return `<rect x="50" y="0" width="50" height="120" fill="${c2}"/>`;
    case 'diagonale': return `<path d="M0 0 H100 L0 120 Z" fill="${c2}"/>`;
    case 'banda': return `<path d="M-10 30 L30 -10 L110 90 L70 130 Z" fill="${c2}"/>`;
    case 'croce': return `<rect x="40" y="0" width="20" height="120" fill="${c2}"/><rect x="0" y="44" width="100" height="20" fill="${c2}"/>`;
    case 'chevron': return `<path d="M0 34 L50 74 L100 34 V58 L50 98 L0 58 Z" fill="${c2}"/>`;
    default: return '';
  }
}

const escTxt = (s) => String(s || '').replace(/[&<>"']/g, '').slice(0, 3).toUpperCase();

/** Ritorna l'SVG dello stemma. cfg = {shape, pattern, c1, c2, c3, symbol, text} */
export function crestSvg(cfg = {}, cls = '') {
  const c = { shape: 'classico', pattern: 'pieno', c1: '#1d4ed8', c2: '#ffffff', c3: '#f5b301', symbol: 'stella', text: '', ...cfg };
  const d = SHAPES[c.shape] || SHAPES.classico;
  const id = `cr${++uid}`;
  const txt = escTxt(c.text);
  const sym = SYMBOLS[c.symbol] ?? '';
  const ry = ['scudetto', 'tondo'].includes(c.shape) ? 20 : 90;
  const textOnly = c.symbol === 'iniziali' || (c.symbol === 'nessuno' && txt);
  const symbolMarkup = sym
    ? `<g fill="${c.c3}" stroke="rgba(0,0,0,.25)" stroke-width="1" paint-order="stroke">${sym}</g>` : '';
  const textMarkup = txt
    ? (textOnly
      ? `<text x="50" y="${txt.length > 2 ? 70 : 72}" text-anchor="middle" font-family="'Barlow Condensed','Arial Narrow',sans-serif" font-style="italic" font-weight="800" font-size="${txt.length > 2 ? 34 : 42}" fill="${c.c3}" stroke="rgba(0,0,0,.3)" stroke-width="1.2" paint-order="stroke">${txt}</text>`
      : `<rect x="22" y="${ry}" width="56" height="15" rx="3" fill="${c.c3}"/><text x="50" y="${ry + 12}" text-anchor="middle" font-family="'Barlow Condensed','Arial Narrow',sans-serif" font-weight="800" font-size="13" fill="${c.c1}">${txt}</text>`)
    : '';
  return `<svg class="crest ${cls}" viewBox="0 0 100 120" aria-hidden="true">
    <defs><clipPath id="${id}"><path d="${d}"/></clipPath>
      <linearGradient id="${id}g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset=".55" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>
    <g clip-path="url(#${id})"><rect width="100" height="120" fill="${c.c1}"/>${patternSvg(c.pattern, c.c2)}<rect width="100" height="120" fill="url(#${id}g)"/></g>
    ${symbolMarkup}${textMarkup}
    <path d="${d}" fill="none" stroke="${c.c3}" stroke-width="5"/>
    <path d="${d}" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1"/>
  </svg>`;
}

// Stemma automatico (sempre uguale per lo stesso nome) per chi non l'ha ancora creato
export function defaultCrest(name = '') {
  let h = 7; for (const ch of String(name)) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const pick = (arr, salt) => arr[(h >>> salt) % arr.length];
  const pairs = [['#0b1f4b', '#f5b301'], ['#dc2626', '#ffffff'], ['#16a34a', '#ffffff'], ['#1d4ed8', '#ffffff'], ['#111827', '#facc15'], ['#8e1f2f', '#f5b301'], ['#7c3aed', '#ffffff'], ['#12a0d7', '#0b1f4b'], ['#f97316', '#111827']];
  const [c1, c2] = pick(pairs, 0);
  const initials = String(name).split(/\s+/).filter(Boolean).slice(0, 3).map((w) => w[0]).join('');
  return { shape: pick(Object.keys(SHAPES), 3), pattern: pick(PATTERNS, 6), c1, c2, c3: c2 === '#ffffff' ? '#f5b301' : '#ffffff', symbol: 'iniziali', text: initials || '?' };
}

export function randomCrest(name) {
  const r = (a) => a[Math.floor(Math.random() * a.length)];
  const base = defaultCrest(name + Math.random());
  return { ...base, shape: r(Object.keys(SHAPES)), pattern: r(PATTERNS), symbol: r(Object.keys(SYMBOLS).filter((s) => s !== 'nessuno')) };
}
