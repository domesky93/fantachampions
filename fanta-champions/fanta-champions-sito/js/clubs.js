// Colori maglia delle squadre (corpo, maniche/colletto)
export const CLUB_COLORS = {
  'Paris Saint-Germain': ['#0a2d6e', '#e30613'], 'Bayern Monaco': ['#dc052d', '#ffffff'],
  'Real Madrid': ['#ffffff', '#febe10'], 'Liverpool': ['#c8102e', '#c8102e'],
  'Inter': ['#0068a8', '#111111'], 'Manchester City': ['#6cabdd', '#ffffff'],
  'Arsenal': ['#ef0107', '#ffffff'], 'Barcellona': ['#a50044', '#004d98'],
  'Atlético Madrid': ['#cb3524', '#ffffff'], 'Borussia Dortmund': ['#fde100', '#111111'],
  'Roma': ['#8e1f2f', '#f0bc42'], 'Sporting CP': ['#00805b', '#ffffff'],
  'Aston Villa': ['#670e36', '#95bfe5'], 'Porto': ['#003893', '#ffffff'],
  'Manchester United': ['#da291c', '#ffffff'], 'Club Brugge': ['#0067b1', '#111111'],
  'Real Betis': ['#00954c', '#ffffff'], 'PSV Eindhoven': ['#ed1c24', '#ffffff'],
  'Feyenoord': ['#e2001a', '#ffffff'], 'Lille': ['#e01e13', '#1d2a5b'],
  'Bodø/Glimt': ['#ffe500', '#111111'], 'Napoli': ['#12a0d7', '#ffffff'],
  'RB Lipsia': ['#ffffff', '#dd0741'], 'Villarreal': ['#ffe667', '#005187'],
  'Fenerbahçe': ['#002d72', '#ffed00'], 'Shakhtar Donetsk': ['#f26522', '#111111'],
  'Galatasaray': ['#a90432', '#fdb912'], 'Slavia Praga': ['#ffffff', '#e2001a'],
  'Slovan Bratislava': ['#8fc8f0', '#ffffff'], 'Stoccarda': ['#ffffff', '#e32219'],
  'AEK Atene': ['#ffd700', '#111111'], 'LASK': ['#111111', '#ffffff'],
  'Como': ['#1d4e9e', '#ffffff'], 'Lens': ['#fbd000', '#e2001a'],
  'Viking': ['#002f6c', '#ffffff'], 'Sabah': ['#0b1e3d', '#e6b54a'],
};

export const clubColors = (name) => CLUB_COLORS[name] || ['#8a94a6', '#ffffff'];

// Sigle a 3 lettere per avversari e calendario
const CLUB_SHORT = {
  'Paris Saint-Germain': 'PSG', 'Bayern Monaco': 'BAY', 'Real Madrid': 'RMA', 'Liverpool': 'LIV',
  'Inter': 'INT', 'Manchester City': 'MCI', 'Arsenal': 'ARS', 'Barcellona': 'BAR',
  'Atlético Madrid': 'ATM', 'Borussia Dortmund': 'BVB', 'Roma': 'ROM', 'Sporting CP': 'SCP',
  'Aston Villa': 'AVL', 'Porto': 'POR', 'Manchester United': 'MUN', 'Club Brugge': 'BRU',
  'Real Betis': 'BET', 'PSV Eindhoven': 'PSV', 'Feyenoord': 'FEY', 'Lille': 'LIL',
  'Bodø/Glimt': 'BOD', 'Napoli': 'NAP', 'RB Lipsia': 'RBL', 'Villarreal': 'VIL',
  'Fenerbahçe': 'FEN', 'Shakhtar Donetsk': 'SHA', 'Galatasaray': 'GAL', 'Slavia Praga': 'SLA',
  'Slovan Bratislava': 'SLO', 'Stoccarda': 'STO', 'AEK Atene': 'AEK', 'LASK': 'LAS',
  'Como': 'COM', 'Lens': 'RCL', 'Viking': 'VIK', 'Sabah': 'SAB',
};
export const clubShort = (club) => CLUB_SHORT[club?.name] || club?.short || (club?.name || '?').slice(0, 3).toUpperCase();

// Pallino nei colori della squadra (calendario)
export const clubDot = (name) => { const [a, b] = clubColors(name); return `<span class="club-dot" style="--c1:${a};--c2:${b}"></span>`; };
