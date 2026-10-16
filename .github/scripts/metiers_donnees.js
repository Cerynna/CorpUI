// Genere CorpUI_Metiers/Metiers/Donnees.lua : recettes des metiers (seuils
// orange / jaune / gris, composants, objet fabrique) et objets (prix chez les
// marchands, emplacement, niveau), tires des tables du jeu Forever (DB2,
// produit "wowf" sur wago.tools). Aucune donnee d un autre addon.
//
// Usage (Git Bash, depuis le depot) :
//   B=1.60.1.70245; mkdir -p /tmp/metiers
//   for t in SkillLine SkillLineAbility SpellReagents SpellEffect ItemSparse Item; do
//     curl -s "https://wago.tools/db2/$t/csv?build=$B" -o /tmp/metiers/$t.csv; done
//   node .github/scripts/metiers_donnees.js /tmp/metiers $B
const fs = require('fs');
const path = require('path');

const SRC = process.argv[2];
const BUILD = process.argv[3] || '?';
const OUT = path.join(__dirname, '..', '..', 'CorpUI_Metiers', 'Metiers', 'Donnees.lua');

// CSV avec champs entre guillemets ("" = guillemet)
function parse(file) {
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
    else if (c === '\n') { row.push(field.replace(/\r$/, '')); rows.push(row); row = []; field = ''; }
    else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  const col = {};
  head.forEach((h, i) => { col[h] = i; });
  return { rows, col };
}
const int = v => parseInt(v, 10) || 0;

// metiers de Classic (et poisons du voleur) : les autres competences de la
// categorie (profession de test, "Comprehension"...) sont ecartees
const KEEP = new Set([164, 165, 171, 182, 185, 186, 197, 202, 333, 393, 129, 356, 40]);
const skillLine = parse('SkillLine');
const profs = new Map();
for (const r of skillLine.rows) {
  const cat = int(r[skillLine.col.CategoryID]);
  const id = int(r[skillLine.col.ID]);
  if ((cat === 11 || cat === 9) && KEEP.has(id)) profs.set(id, r[skillLine.col.DisplayName_lang]);
}

// recettes : une competence avec une plage (gris > 0)
const sla = parse('SkillLineAbility');
const recipes = new Map();
for (const r of sla.rows) {
  const skill = int(r[sla.col.SkillLine]);
  const gray = int(r[sla.col.TrivialSkillLineRankHigh]);
  if (!profs.has(skill) || gray <= 0) continue;
  const spell = int(r[sla.col.Spell]);
  if (recipes.has(spell)) continue;
  recipes.set(spell, {
    skill, min: int(r[sla.col.MinSkillLineRank]), yellow: int(r[sla.col.TrivialSkillLineRankLow]), gray,
    acquire: int(r[sla.col.AcquireMethod]), ups: int(r[sla.col.NumSkillUps]) || 1, reagents: [], item: 0, count: 1,
  });
}

const sr = parse('SpellReagents');
for (const r of sr.rows) {
  const rec = recipes.get(int(r[sr.col.SpellID]));
  if (!rec) continue;
  for (let k = 0; k < 8; k++) {
    const id = int(r[sr.col['Reagent_' + k]]);
    const n = int(r[sr.col['ReagentCount_' + k]]);
    if (id > 0 && n > 0) rec.reagents.push([id, n]);
  }
}

// objet fabrique : effet 24 (creer un objet)
const se = parse('SpellEffect');
for (const r of se.rows) {
  if (int(r[se.col.Effect]) !== 24) continue;
  const rec = recipes.get(int(r[se.col.SpellID]));
  if (!rec || rec.item) continue;
  rec.item = int(r[se.col.EffectItemType]);
  rec.count = Math.max(1, Math.round(parseFloat(r[se.col.EffectBasePointsF]) || 1));
}

// objets utiles : composants et objets fabriques
const wanted = new Set();
for (const rec of recipes.values()) {
  if (rec.item) wanted.add(rec.item);
  for (const [id] of rec.reagents) wanted.add(id);
}
const isp = parse('ItemSparse');
const items = new Map();
for (const r of isp.rows) {
  const id = int(r[isp.col.ID]);
  if (!wanted.has(id)) continue;
  items.set(id, {
    buy: int(r[isp.col.BuyPrice]), stack: int(r[isp.col.VendorStackCount]) || 1, sell: int(r[isp.col.SellPrice]),
    inv: int(r[isp.col.InventoryType]), ilvl: int(r[isp.col.ItemLevel]), req: int(r[isp.col.RequiredLevel]),
    q: int(r[isp.col.OverallQualityID]),
  });
}
const it = parse('Item');
for (const r of it.rows) {
  const e = items.get(int(r[it.col.ID]));
  if (e) { e.cls = int(r[it.col.ClassID]); e.sub = int(r[it.col.SubclassID]); }
}

// sortie : chaines compactes, decodees a la demande
//   recette : "metier,requis,jaune,gris,objet,nombre,acquisition,montees,composant:n/composant:n"
//   objet   : "achat,lot,vente,emplacement,niveau,niveau requis,qualite,classe,sous-classe"
let out = '';
out += '--[[--------------------------------------------------------------------------\n';
out += '    CorpUI - module Metiers : recettes et objets (fichier GENERE, ne pas editer)\n';
out += '    Genere par .github/scripts/metiers_donnees.js depuis les tables du jeu\n';
out += '    Forever (DB2, wago.tools, ' + BUILD + ').\n';
out += '    recette : "metier,requis,jaune,gris,objet,nombre,acquisition,montees,\n';
out += '               composant:n/composant:n" (vert = milieu de jaune et gris)\n';
out += '    objet   : "achat,lot,vente,emplacement,niveau,niveau requis,qualite,\n';
out += '               classe,sous-classe" (prix en pieces de cuivre)\n';
out += '----------------------------------------------------------------------------]]\n\n';
out += 'local _, ns = ...\n';
out += 'if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)\n\n';
out += 'ns.CraftData = {\n    build = "' + BUILD + '",\n    profs = {';
out += [...profs.keys()].sort((a, b) => a - b).join(', ');
out += ' },\n    recipes = {\n';
for (const [spell, r] of [...recipes.entries()].sort((a, b) => a[0] - b[0])) {
  const reag = r.reagents.map(([id, n]) => id + ':' + n).join('/');
  out += '        [' + spell + '] = "' + [r.skill, r.min, r.yellow, r.gray, r.item, r.count, r.acquire, r.ups, reag].join(',') + '",\n';
}
out += '    },\n    items = {\n';
for (const [id, e] of [...items.entries()].sort((a, b) => a[0] - b[0])) {
  out += '        [' + id + '] = "' + [e.buy, e.stack, e.sell, e.inv, e.ilvl, e.req, e.q, e.cls || 0, e.sub || 0].join(',') + '",\n';
}
out += '    },\n}\n';
fs.writeFileSync(OUT, out);
const byProf = {};
for (const r of recipes.values()) byProf[profs.get(r.skill)] = (byProf[profs.get(r.skill)] || 0) + 1;
console.log('recettes :', recipes.size, '| objets :', items.size, '| octets :', out.length);
console.log(JSON.stringify(byProf));
