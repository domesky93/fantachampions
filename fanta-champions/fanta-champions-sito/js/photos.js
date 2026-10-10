// Ricerca automatica delle foto dei giocatori su Wikipedia / Wikimedia Commons.
// Gira nel browser dell'amministratore: Wikipedia permette queste richieste (origin=*).
// Si usano solo immagini con licenza libera (pilicense=free) e si salvano autore e licenza.

const WP = 'https://en.wikipedia.org/w/api.php';
const COMMONS = 'https://commons.wikimedia.org/w/api.php';
const BASE = { action: 'query', format: 'json', formatversion: '2', origin: '*' };
const PAGE_PROPS = { prop: 'pageimages|description|pageprops', piprop: 'thumbnail|name', pithumbsize: '250', pilicense: 'free', ppprop: 'disambiguation', redirects: '1' };

const FOOTBALL = /football|soccer|goalkeeper|calciat|futbol|fútbol/i;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(url, params) {
  const u = new URL(url);
  Object.entries({ ...BASE, ...params }).forEach(([k, v]) => u.searchParams.set(k, v));
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch(u, { headers: { 'Api-User-Agent': 'FantaChampions/1.0 (app di fantacalcio amatoriale)' } });
    if (res.ok) return res.json();
    await sleep(1000 * (attempt + 1));
  }
  throw new Error('Wikipedia non risponde, riprova più tardi');
}

const okPage = (p) => p && !p.missing && !p.pageprops?.disambiguation && p.thumbnail?.source && FOOTBALL.test(p.description || '');

// Cerca la pagina giusta per un gruppo di nomi (max 50)
async function lookupTitles(names) {
  const data = await api(WP, { ...PAGE_PROPS, titles: names.join('|') });
  const q = data.query || {};
  const map = new Map(names.map((n) => [n, n]));
  for (const step of [q.normalized || [], q.redirects || []]) {
    for (const { from, to } of step) for (const [n, t] of map) if (t === from) map.set(n, to);
  }
  const pages = new Map((q.pages || []).map((p) => [p.title, p]));
  const out = new Map();
  for (const [n, t] of map) { const p = pages.get(t); if (okPage(p)) out.set(n, p); }
  return out;
}

// Ricerca libera per i nomi ambigui (es. "Rodri", "Wesley")
async function searchOne(name) {
  const data = await api(WP, { ...PAGE_PROPS, generator: 'search', gsrsearch: `${name} footballer`, gsrlimit: '3' });
  const pages = (data.query?.pages || []).sort((a, b) => (a.index || 0) - (b.index || 0));
  return pages.find(okPage) || null;
}

const stripHtml = (s) => String(s || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();

// Autore e licenza delle immagini (max 50 file per richiesta)
async function credits(files) {
  const out = new Map();
  for (let i = 0; i < files.length; i += 50) {
    const chunk = files.slice(i, i + 50);
    for (const base of [COMMONS, WP]) {
      const missing = chunk.filter((f) => !out.has(f));
      if (!missing.length) break;
      const data = await api(base, { prop: 'imageinfo', iiprop: 'extmetadata|url', iiextmetadatafilter: 'Artist|LicenseShortName', titles: missing.map((f) => `File:${f}`).join('|') });
      const norm = new Map((data.query?.normalized || []).map((n) => [n.to, n.from]));
      for (const p of data.query?.pages || []) {
        const ii = p.imageinfo?.[0]; if (!ii) continue;
        const md = ii.extmetadata || {};
        const file = (norm.get(p.title) || p.title).replace(/^File:/, '');
        const artist = stripHtml(md.Artist?.value) || 'Autore sconosciuto';
        const lic = stripHtml(md.LicenseShortName?.value) || 'Licenza libera';
        out.set(file, { credit: `${artist} · ${lic}`, page: ii.descriptionurl });
      }
    }
  }
  return out;
}

/**
 * Trova le foto per una lista di giocatori.
 * players: [{id, name}]   onProgress(done, total, found)
 * Ritorna [{id, photo_url, photo_credit, photo_page}]
 */
export async function findPhotos(players, onProgress = () => {}) {
  const found = new Map(); // id -> page
  let done = 0;
  const total = players.length;

  // 1) ricerca veloce per titolo esatto, 50 alla volta
  for (let i = 0; i < players.length; i += 50) {
    const chunk = players.slice(i, i + 50);
    const res = await lookupTitles([...new Set(chunk.map((p) => p.name))]);
    chunk.forEach((p) => { if (res.has(p.name)) found.set(p.id, res.get(p.name)); });
    done += chunk.length * 0.5;
    onProgress(Math.round(done), total, found.size);
  }

  // 2) ricerca libera per chi manca (4 richieste alla volta)
  const misses = players.filter((p) => !found.has(p.id));
  const perMiss = (total / 2) / Math.max(1, misses.length);
  let idx = 0;
  async function worker() {
    while (idx < misses.length) {
      const p = misses[idx++];
      try { const page = await searchOne(p.name); if (page) found.set(p.id, page); } catch { /* salta */ }
      done += perMiss; onProgress(Math.round(done), total, found.size);
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()]);

  // 3) crediti delle immagini
  const files = [...new Set([...found.values()].map((p) => p.pageimage).filter(Boolean))];
  const cr = await credits(files);
  onProgress(total, total, found.size);

  return [...found.entries()].map(([id, page]) => ({
    id,
    photo_url: page.thumbnail.source,
    photo_credit: cr.get(page.pageimage)?.credit || 'Wikimedia Commons · licenza libera',
    photo_page: cr.get(page.pageimage)?.page || `https://en.wikipedia.org/wiki/File:${encodeURIComponent(page.pageimage || '')}`,
  }));
}
