// Genere CorpUI_HV/Encheres/DesenchantInterdits.lua : armes et armures vertes,
// bleues et violettes que le jeu interdit de desenchanter (drapeau 0x8000 du
// premier champ de drapeaux de ItemSparse : baguettes d enchanteur,
// recompenses JcJ, sceaux...), tirees des tables du jeu Forever (DB2, produit
// "wowf" sur wago.tools).
//
// Usage (Git Bash, depuis le depot) :
//   B=1.60.1.70862; mkdir -p /tmp/dez
//   for t in ItemSparse Item; do
//     curl -s "https://wago.tools/db2/$t/csv?build=$B" -o /tmp/dez/$t.csv; done
//   node .github/scripts/dez_interdits.js /tmp/dez $B
const fs = require('fs');
const path = require('path');

const SRC = process.argv[2];
const BUILD = process.argv[3] || '?';
const OUT = path.join(__dirname, '..', '..', 'CorpUI_HV', 'Encheres', 'DesenchantInterdits.lua');
const NO_DISENCHANT = 0x8000;

// CSV avec champs entre guillemets ("" = guillemet) -> objets par colonne
function load(file) {
  const text = fs.readFileSync(path.join(SRC, file + '.csv'), 'utf8');
  const rows = [];
  let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else q = false;
      } else field += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.length > 1) rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  return rows.map(r => Object.fromEntries(head.map((k, i) => [k, r[i]])));
}

const classOf = new Map(load('Item').map(o => [o.ID, +o.ClassID]));
const ids = [];
for (const s of load('ItemSparse')) {
  if (!(+s.Flags_0 & NO_DISENCHANT)) continue;
  const q = +s.OverallQualityID;
  if (q < 2 || q > 4) continue;
  const cls = classOf.get(s.ID);
  if (cls !== 2 && cls !== 4) continue;
  ids.push(+s.ID);
}
ids.sort((a, b) => a - b);

// identifiants croissants, ecarts en base 36 separes par des virgules
let prev = 0;
const deltas = ids.map(id => { const d = (id - prev).toString(36); prev = id; return d; });
const lines = [];
for (let i = 0; i < deltas.length; i += 40) lines.push('    "' + deltas.slice(i, i + 40).join(',') + ',"');

const lua = `--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : objets qui ne se desenchantent pas

    Genere par .github/scripts/dez_interdits.js (tables du jeu Forever,
    build ${BUILD}) : ne pas modifier a la main.
    Armes et armures vertes a violettes que le jeu interdit de desenchanter
    (baguettes d enchanteur, recompenses JcJ, sceaux...) : ${ids.length} objets.
    Identifiants croissants, ecarts en base 36 ; lus par Desenchant.lua.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

ns.DENoDisenchant = table.concat({
${lines.join(',\n')}
})
`;
fs.writeFileSync(OUT, lua);
console.log(ids.length + ' objets -> ' + OUT);
