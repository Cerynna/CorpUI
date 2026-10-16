// Genere CorpUI_Voyage/Voyage/Donnees.lua : points de vol, liaisons de vol
// (longueur du trace), transports (bateaux, zeppelins : quais et longueurs
// entre quais), liaisons a part (tram des profondeurs, portail de
// Darnassus), tires des tables du jeu Forever (DB2, produit "wowf" sur
// wago.tools). Aucune donnee d un autre addon.
//
// Liaisons : les deux entrees sont des declencheurs (AreaTrigger) du jeu ;
// on sait ou mene chacun (le serveur les relie), on lit leur position.
// Tram : duree tiree de son animation (TransportAnimation) : marche et
// chargements, attente moyenne d une rame, trajet.
//
// Usage (Git Bash, depuis le depot) :
//   B=1.60.1.70245; mkdir -p /tmp/voyage
//   for t in TaxiNodes TaxiPath TaxiPathNode AreaTrigger TransportAnimation; do
//     curl -s "https://wago.tools/db2/$t/csv?build=$B" -o /tmp/voyage/$t.csv; done
//   node .github/scripts/voyage_donnees.js /tmp/voyage $B
const fs = require('fs');
const path = require('path');

const SRC = process.argv[2];
const BUILD = process.argv[3] || '?';
const OUT = path.join(__dirname, '..', '..', 'CorpUI_Voyage', 'Voyage', 'Donnees.lua');

function parse(file) {
  const text = fs.readFileSync(path.join(SRC, file + '.csv'), 'utf8');
  const rows = [];
  let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; } else field += c;
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
const num = v => Number(v) || 0;
const r1 = v => Math.round(v * 10) / 10;

// points de vol : continent, position monde (x nord, y ouest), factions
// (monture 0 : Horde, monture 1 : Alliance ; 1 Horde, 2 Alliance, 3 les deux)
const tn = parse('TaxiNodes');
const nodes = new Map();
for (const r of tn.rows) {
  const id = num(r[tn.col.ID]);
  const h = num(r[tn.col.MountCreatureID_0]) > 0, a = num(r[tn.col.MountCreatureID_1]) > 0;
  const side = (h ? 1 : 0) + (a ? 2 : 0);
  if (!side) continue;            // sans monture : pas un point de vol utilisable
  nodes.set(id, { cont: num(r[tn.col.ContinentID]), x: num(r[tn.col.Pos_0]), y: num(r[tn.col.Pos_1]), z: num(r[tn.col.Pos_2]), side });
}

// traces : points par chemin, dans l ordre
const tpn = parse('TaxiPathNode');
const pts = new Map();
for (const r of tpn.rows) {
  const p = num(r[tpn.col.PathID]);
  if (!pts.has(p)) pts.set(p, []);
  pts.get(p).push({ i: num(r[tpn.col.NodeIndex]), cont: num(r[tpn.col.ContinentID]), x: num(r[tpn.col.Loc_0]),
                    y: num(r[tpn.col.Loc_1]), z: num(r[tpn.col.Loc_2]), delay: num(r[tpn.col.Delay]) });
}
for (const list of pts.values()) list.sort((a, b) => a.i - b.i);
function length(list, from = 0, to = list.length - 1) {
  let d = 0;
  for (let k = from + 1; k <= to; k++) {
    const a = list[k - 1], b = list[k];
    if (a.cont === b.cont) d += Math.hypot(b.x - a.x, b.y - a.y);
  }
  return d;
}

// liaisons de vol entre deux points de vol utilisables
const tp = parse('TaxiPath');
const flights = [];
const transports = [];
for (const r of tp.rows) {
  const id = num(r[tp.col.ID]), from = num(r[tp.col.FromTaxiNode]), to = num(r[tp.col.ToTaxiNode]);
  const list = pts.get(id) || [];
  if (from && to) {
    if (nodes.has(from) && nodes.has(to) && list.length) {
      flights.push([from, to, Math.round(length(list)), num(r[tp.col.Cost])]);
    }
  } else if (list.some(p => p.delay > 0)) {
    // transport : quais (arrets avec delai) et longueur de chaque troncon
    const stops = [];
    list.forEach((p, k) => { if (p.delay > 0) stops.push(k); });
    const legs = [];
    for (let s = 0; s < stops.length; s++) {
      const a = stops[s], b = stops[(s + 1) % stops.length];
      const d = b > a ? length(list, a, b) : length(list, a) + length(list, 0, b);
      const pa = list[a];
      legs.push([pa.cont, r1(pa.x), r1(pa.y), pa.delay, Math.round(d), r1(pa.z)].join(':'));
    }
    transports.push([id, legs.join('/')]);
  }
}

// liaisons a part : [type, declencheur A, declencheur B, duree (s) ou null = calculee]
const LINKS = [
  ['tram', 2173, 2175, null],       // Hurlevent (quartier des Nains) <-> Forgefer (Brikabrok)
  ['portal', 542, 527, 5],          // Rut'theran <-> Darnassus
];
const at = parse('AreaTrigger');
const trig = new Map(at.rows.map(r => [num(r[at.col.ID]), r]));
const ta = parse('TransportAnimation');
function tramTime() {
  // rame 176080 : arrets aux deux bouts, trajet entre eux ; deux rames par voie
  const keys = ta.rows.filter(r => num(r[ta.col.TransportID]) === 176080)
    .map(r => [num(r[ta.col.TimeIndex]) / 1000, num(r[ta.col.Pos_1])]).sort((a, b) => a[0] - b[0]);
  if (!keys.length) return 130;
  const cycle = keys[keys.length - 1][0];
  const far = Math.max(...keys.map(k => Math.abs(k[1])));
  const leave = keys.find(k => Math.abs(k[1]) > 1)[0];
  const arrive = keys.find(k => Math.abs(Math.abs(k[1]) - far) < 1)[0];
  return Math.round(40 + cycle / 4 + (arrive - leave));
}
const links = [];
for (const [kind, a, b, t] of LINKS) {
  const ra = trig.get(a), rb = trig.get(b);
  if (!ra || !rb) { console.log('declencheur absent :', kind, a, b); continue; }
  const pos = r => [num(r[at.col.ContinentID]), r1(num(r[at.col.Pos_0])), r1(num(r[at.col.Pos_1])), r1(num(r[at.col.Pos_2]))];
  links.push([kind, ...pos(ra), ...pos(rb), t == null ? tramTime() : t]);
}

let out = '';
out += '--[[--------------------------------------------------------------------------\n';
out += '    CorpUI - module Voyage : points de vol, vols et transports (fichier\n';
out += '    GENERE, ne pas editer). Genere par .github/scripts/voyage_donnees.js\n';
out += '    depuis les tables du jeu Forever (DB2, wago.tools, ' + BUILD + ').\n';
out += '    noeud      : "continent,x,y,camps,z" (monde : x nord, y ouest, z haut ; camps : 1\n';
out += '                 Horde, 2 Alliance, 3 les deux)\n';
out += '    vol        : "depart,arrivee,longueur,prix" (metres, cuivre)\n';
out += '    transport  : quais "continent:x:y:arret (s):longueur jusqu au quai suivant:z",\n';
out += '                 separes par "/", dans l ordre du trajet (boucle)\n';
out += '    liaison    : "type,continent,x,y,z,continent,x,y,z,duree (s)" (dans les deux sens)\n';
out += '----------------------------------------------------------------------------]]\n\n';
out += 'local _, ns = ...\n';
out += 'if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)\n\n';
out += 'ns.VoyageData = {\n    build = "' + BUILD + '",\n    nodes = {\n';
for (const [id, n] of [...nodes.entries()].sort((a, b) => a[0] - b[0])) {
  out += '        [' + id + '] = "' + [n.cont, r1(n.x), r1(n.y), n.side, r1(n.z)].join(',') + '",\n';
}
out += '    },\n    flights = {\n';
for (const f of flights) out += '        "' + f.join(',') + '",\n';
out += '    },\n    transports = {\n';
for (const [id, legs] of transports) out += '        [' + id + '] = "' + legs + '",\n';
out += '    },\n    links = {\n';
for (const l of links) out += '        "' + l.join(',') + '",\n';
out += '    },\n}\n';
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, out);
console.log('noeuds :', nodes.size, '| vols :', flights.length, '| transports :', transports.length, '| liaisons :', links.map(l => l[0] + ' ' + l[9] + ' s').join(', '), '| octets :', out.length);
