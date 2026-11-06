// Genere CorpUI_Jeux/Podometre/Creatures.lua : cartes de creatures du classeur
// du podometre.
//   - boss de donjon et de raid : rencontres du jeu Forever (DungeonEncounter,
//     noms dans les 10 langues), ecran de chargement de l instance (Map,
//     LoadingScreens), dernier boss d une instance (LFGDungeons) ; modele 3D,
//     niveau et type : base CMaNGOS Classic (creature_template) ;
//   - elites de zone : creatures elites, rares et elites rares de la base
//     CMaNGOS Classic (rangs 1, 4, 2), sans fonction de PNJ, dans une seule
//     zone (positions des apparitions, UiMapAssignment du jeu) ; noms :
//     locales_creature (8 langues ; pt et it : nom anglais).
// Seuls des faits sont repris (identifiants, noms, niveaux), aucun code. Les
// rencontres propres a Forever, absentes de la base Classic, n ont pas de
// modele : elles sont ecartees (liste affichee).
// L ordre des cartes deja generees est garde (classeur partage en bits) :
// les nouvelles vont a la fin, aucune ne disparait.
//
// Usage (Git Bash, depuis le depot) :
//   B=1.60.1.70790; D=/tmp/cartes; mkdir -p $D
//   for t in DungeonEncounter Map LoadingScreens UiMapAssignment UiMap LFGDungeons CreatureType; do
//     curl -s "https://wago.tools/db2/$t/csv?build=$B" -o $D/$t.csv; done
//   for l in frFR deDE esES ptBR itIT ruRU zhCN zhTW koKR; do for t in DungeonEncounter Map CreatureType; do
//     curl -s "https://wago.tools/db2/$t/csv?build=$B&locale=$l" -o $D/$t.$l.csv; done; done
//   curl -sL https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz | gzip -dc > $D/classicdb.sql
//   node .github/scripts/cartes_donnees.js $D $B
const fs = require('fs');
const path = require('path');

const SRC = process.argv[2];
const BUILD = process.argv[3] || '?';
const OUT = path.join(__dirname, '..', '..', 'CorpUI_Jeux', 'Podometre', 'Creatures.lua');
const LOCALES = ['frFR', 'deDE', 'esES', 'ptBR', 'itIT', 'ruRU', 'zhCN', 'zhTW', 'koKR'];

// ---------------------------------------------------------------------------
// Tables du jeu (CSV de wago.tools, champs entre guillemets, "" = guillemet)

function csv(file) {
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
  return rows.filter(r => r.length === head.length).map(r => Object.fromEntries(head.map((h, i) => [h, r[i]])));
}
const int = v => parseInt(v, 10) || 0;

// ---------------------------------------------------------------------------
// Base CMaNGOS (export SQL) : colonnes de CREATE TABLE, lignes des INSERT

const sql = fs.readFileSync(path.join(SRC, 'classicdb.sql'), 'utf8');

function columns(table) {
  const start = sql.indexOf('CREATE TABLE `' + table + '` (');
  if (start < 0) throw new Error('table absente : ' + table);
  const end = sql.indexOf(') ENGINE', start);
  const cols = [];
  for (const line of sql.slice(start, end).split('\n').slice(1)) {
    const m = line.match(/^\s+`([^`]+)`/);
    if (m) cols.push(m[1]);
  }
  return cols;
}

function rows(table) {
  const cols = columns(table);
  const out = [];
  const head = 'INSERT INTO `' + table + '` VALUES ';
  let at = sql.indexOf(head);
  while (at >= 0) {
    let i = at + head.length;
    const n = sql.length;
    while (i < n && sql[i] === '(') {
      i++;
      const vals = [];
      for (;;) {
        let v;
        if (sql[i] === "'") {
          i++;
          let s = '';
          while (sql[i] !== "'") {
            if (sql[i] === '\\') { i++; s += sql[i] === 'n' ? '\n' : sql[i]; } else s += sql[i];
            i++;
          }
          i++;
          v = s;
        } else {
          let j = i;
          while (sql[j] !== ',' && sql[j] !== ')') j++;
          const raw = sql.slice(i, j);
          v = raw === 'NULL' ? null : raw;
          i = j;
        }
        vals.push(v);
        if (sql[i] === ',') { i++; continue; }
        i++;   // ')'
        break;
      }
      const o = {};
      cols.forEach((c, k) => { o[c] = vals[k]; });
      out.push(o);
      if (sql[i] === ',') i++;
    }
    at = sql.indexOf(head, i);
  }
  return out;
}

const templates = new Map();
for (const t of rows('creature_template')) templates.set(int(t.Entry), t);
const byName = new Map();
for (const t of templates.values()) {
  const k = t.Name.toLowerCase();
  if (!byName.has(k)) byName.set(k, []);
  byName.get(k).push(t);
}
const spawns = new Map();   // entry -> [{ map, x, y }]
for (const s of rows('creature')) {
  const id = int(s.id);
  if (!id) continue;
  if (!spawns.has(id)) spawns.set(id, []);
  spawns.get(id).push({ map: int(s.map), x: parseFloat(s.position_x), y: parseFloat(s.position_y) });
}
const locNames = new Map();   // entry -> { frFR: ..., ... }
const LOC_COL = { koKR: 'name_loc1', frFR: 'name_loc2', deDE: 'name_loc3', zhCN: 'name_loc4', zhTW: 'name_loc5', esES: 'name_loc6', ruRU: 'name_loc8' };
for (const l of rows('locales_creature')) {
  const o = {};
  for (const [loc, col] of Object.entries(LOC_COL)) if (l[col]) o[loc] = l[col];
  locNames.set(int(l.entry), o);
}
const model = t => int(t.ModelId1) || int(t.ModelId2) || int(t.ModelId3) || int(t.ModelId4);

// ---------------------------------------------------------------------------
// Boss : rencontres du jeu Forever

const enc = csv('DungeonEncounter');
const encLoc = {};
const mapLoc = {};
for (const l of LOCALES) {
  encLoc[l] = new Map(csv('DungeonEncounter.' + l).map(e => [e.ID, e.Name_lang]));
  mapLoc[l] = new Map(csv('Map.' + l).map(m => [m.ID, m.MapName_lang]));
}
const maps = new Map(csv('Map').map(m => [m.ID, m]));
const screens = new Map(csv('LoadingScreens').map(s => [s.ID, s]));
const finals = new Set(csv('LFGDungeons').map(d => d.FinalEncounterID).filter(v => v && v !== '0'));

// cartes de test ou scenarios
const SKIP_MAPS = new Set(['0', '13', '2720', '2921', '3002']);
// instances propres a Forever (absentes de la base Classic : pas de modele) ; restent
// les boss mondiaux que Forever a ranges dans une carte a eux
const WORLD_BOSS_MAPS = new Set(['2789', '2791', '2804', '2832']);
// rencontres de plusieurs creatures : celle qui pose pour la carte
const STAND_IN = {
  'the lost dwarves': 'Baelog', 'ring of law': 'Gorosh the Dervish', 'the vault': 'Watchman Doomgrip',
  'the seven': "Doom'rel", 'silithid royalty': 'Princess Yauj', 'twin emperors': "Emperor Vek'lor",
  'the four horsemen': 'Highlord Mograine', 'edge of madness': "Gri'lek",
  kirtonos: 'Kirtonos the Herald', 'ras frostwhisperer': 'Ras Frostwhisper',
};
// derniers boss des donjons (un par aile) : LFGDungeons.FinalEncounterID est vide dans Forever
const FINAL_NAMES = new Set(['Taragaman the Hungerer', 'Edwin VanCleef', 'Mutanus the Devourer', 'Archmage Arugal', "Aku'mai",
  'Bazil Thredd', 'Charlga Razorflank', 'Mekgineer Thermaplugg', 'Herod', 'Arcanist Doan', 'Bloodmage Thalnos',
  'High Inquisitor Whitemane', 'Amnennar the Coldbringer', 'Archaedas', 'Chief Ukorz Sandscalp', 'Princess Theradras',
  'Shade of Eranikus', 'Emperor Dagran Thaurissan', 'Alzzin the Wildshaper', 'Prince Tortheldrin', 'King Gordok',
  'Balnazzar', 'Baron Rivendare', 'Darkmaster Gandling', 'Overlord Wyrmthalak', 'General Drakkisath']);
// fins de raid de Classic : legendaires
const RAID_ENDS = new Set(['672', '1084', '617', '793', '723', '717', '1114']);

function bestTemplate(name, mapID) {
  const list = byName.get((STAND_IN[name.toLowerCase()] || name).toLowerCase()) || [];
  if (!list.length) return null;
  const score = t => ((spawns.get(int(t.Entry)) || []).some(s => s.map === mapID) ? 100 : 0) + int(t.Rank) * 10 + (model(t) ? 1 : 0);
  return list.slice().sort((a, b) => score(b) - score(a) || int(a.Entry) - int(b.Entry))[0];
}

const instances = new Map();   // mapID -> { raid, ls, name, names, bosses: [] }
const skipped = [];
for (const e of enc) {
  if (SKIP_MAPS.has(e.MapID) || (int(e.MapID) >= 2700 && !WORLD_BOSS_MAPS.has(e.MapID))) continue;
  const m = maps.get(e.MapID);
  if (!m || (m.InstanceType !== '1' && m.InstanceType !== '2')) continue;
  if (!instances.has(e.MapID)) {
    const s = screens.get(m.LoadingScreenID);
    const ls = s ? (int(s.NarrowScreenFileDataID) || int(s.MainImageFileDataID) || int(s.WideScreenFileDataID)) : 0;
    const names = {};
    for (const l of LOCALES) { const n = mapLoc[l].get(e.MapID); if (n && n !== m.MapName_lang) names[l] = n; }
    instances.set(e.MapID, { id: int(e.MapID), raid: m.InstanceType === '2', ls, name: m.MapName_lang, names, bosses: [], seen: new Set() });
  }
  const inst = instances.get(e.MapID);
  const t = bestTemplate(e.Name_lang, int(e.MapID));
  if (!t || !model(t)) { skipped.push(`${m.MapName_lang} : ${e.Name_lang}`); continue; }
  // doublons (versions d une meme rencontre) : une carte par creature
  if (inst.seen.has(t.Entry)) continue;
  inst.seen.add(t.Entry);
  const names = {};
  for (const l of LOCALES) { const n = encLoc[l].get(e.ID); if (n && n !== e.Name_lang) names[l] = n; }
  inst.bosses.push({ enc: e.ID, order: int(e.OrderIndex), t, name: e.Name_lang, names, final: finals.has(e.ID) || FINAL_NAMES.has(e.Name_lang) });
}

// ---------------------------------------------------------------------------
// Elites de zone

const uiMaps = new Map(csv('UiMap').map(u => [u.ID, u]));
const assign = csv('UiMapAssignment').filter(a => (a.MapID === '0' || a.MapID === '1') && uiMaps.get(a.UiMapID) && uiMaps.get(a.UiMapID).Type === '3')
  .map(a => ({ ui: int(a.UiMapID), area: int(a.AreaID), map: int(a.MapID), x0: +a.Region_0, y0: +a.Region_1, x1: +a.Region_3, y1: +a.Region_4 }));
const areaToUi = new Map(assign.map(a => [a.area, a.ui]));
// les rectangles sont ceux des images de la carte du monde : ils debordent sur
// les zones voisines. Ecart au centre de l image : 0 au centre, 0.5 au bord
function offCenter(a, s) {
  if (a.map !== s.map || s.x < a.x0 || s.x > a.x1 || s.y < a.y0 || s.y > a.y1) return null;
  return Math.max(Math.abs((s.x - a.x0) / (a.x1 - a.x0) - 0.5), Math.abs((s.y - a.y0) / (a.y1 - a.y0) - 0.5));
}
// reperes : la zone d une quete (ZoneOrSort) etiquette ses cibles, celui qui la
// donne et celui qui la rend ; une creature garde la zone de la plupart de ses
// quetes, et chacune de ses apparitions devient un repere
const votes = new Map();   // entry -> { ui: n }
function vote(entry, ui) {
  if (!votes.has(entry)) votes.set(entry, {});
  const v = votes.get(entry);
  v[ui] = (v[ui] || 0) + 1;
}
const questZone = new Map();
const questTargets = new Set();      // creatures a tuer pour une quete (ou dont il faut un objet)
const questItems = new Set();
const zoneQuestLevels = new Map();   // ui -> niveaux des quetes
for (const qt of rows('quest_template')) {
  const ui = areaToUi.get(int(qt.ZoneOrSort));
  if (!ui) continue;
  questZone.set(int(qt.entry), ui);
  if (int(qt.QuestLevel) > 0) {
    if (!zoneQuestLevels.has(ui)) zoneQuestLevels.set(ui, []);
    zoneQuestLevels.get(ui).push(int(qt.QuestLevel));
  }
  for (let k = 1; k <= 4; k++) { const c = int(qt['ReqCreatureOrGOId' + k]); if (c > 0) { vote(c, ui); questTargets.add(c); } }
  for (let k = 1; k <= 4; k++) { const it = int(qt['ReqItemId' + k]); if (it > 0) questItems.add(it); }
}
// niveau d une zone : mediane de ses quetes
const zoneLevel = new Map();
for (const [ui, l] of zoneQuestLevels) { l.sort((a, b) => a - b); zoneLevel.set(ui, l[Math.floor(l.length / 2)]); }
// la tete de X, le journal de Y : butin de quete (chance negative) d une seule creature
const lootOwners = new Map();   // LootId -> [entry]
for (const t of templates.values()) { const l = int(t.LootId); if (l) { if (!lootOwners.has(l)) lootOwners.set(l, []); lootOwners.get(l).push(int(t.Entry)); } }
const itemDroppers = new Map();
for (const r of rows('creature_loot_template')) {
  const it = int(r.item);
  if (!questItems.has(it) || parseFloat(r.ChanceOrQuestChance) >= 0) continue;
  for (const e of lootOwners.get(int(r.entry)) || []) { if (!itemDroppers.has(it)) itemDroppers.set(it, new Set()); itemDroppers.get(it).add(e); }
}
for (const set of itemDroppers.values()) if (set.size === 1) for (const e of set) questTargets.add(e);
for (const t of ['creature_questrelation', 'creature_involvedrelation']) {
  for (const r of rows(t)) { const ui = questZone.get(int(r.quest)); if (ui) vote(int(r.id), ui); }
}
const GRID = 250;
const marks = new Map();   // "map:gx:gy" -> [{ x, y, ui }]
for (const [entry, v] of votes) {
  const total = Object.values(v).reduce((s, n) => s + n, 0);
  const ui = Object.keys(v).sort((a, b) => v[b] - v[a])[0];
  if (v[ui] < total * 0.8) continue;
  for (const s of spawns.get(entry) || []) {
    if (s.map !== 0 && s.map !== 1) continue;
    const k = s.map + ':' + Math.floor(s.x / GRID) + ':' + Math.floor(s.y / GRID);
    if (!marks.has(k)) marks.set(k, []);
    marks.get(k).push({ x: s.x, y: s.y, ui: int(ui) });
  }
}
// zone d un point : parmi les images qui le contiennent, celle des reperes
// voisins (plus pres, plus de poids), sauf si son niveau ne va pas du tout a
// la creature ; sans repere, l image la plus centree
function zoneAt(s, level) {
  const inside = new Map();
  for (const a of assign) { const d = offCenter(a, s); if (d !== null) inside.set(a.ui, d); }
  if (!inside.size) return null;
  const w = {};
  for (let r = 1; r <= 3 && !Object.keys(w).length; r++) {
    const gx = Math.floor(s.x / GRID), gy = Math.floor(s.y / GRID);
    for (let dx = -r; dx <= r; dx++) for (let dy = -r; dy <= r; dy++) {
      for (const m of marks.get(s.map + ':' + (gx + dx) + ':' + (gy + dy)) || []) {
        if (!inside.has(m.ui)) continue;
        const d = Math.hypot(m.x - s.x, m.y - s.y);
        if (d > GRID * r) continue;
        w[m.ui] = (w[m.ui] || 0) + 1 / (d + 25);
      }
    }
  }
  const maxW = Math.max(0, ...Object.values(w));
  let best = null, bestS = -Infinity;
  for (const [ui, d] of inside) {
    const zl = zoneLevel.get(ui);
    const pen = zl && level ? Math.max(0, Math.abs(level - zl) - 8) / 10 : 0;
    // reperes d abord ; a egalite (aucun repere), l image la plus centree
    const sc = (maxW > 0 ? (w[ui] || 0) / maxW : 0) - pen - d / 10;
    if (sc > bestS) { best = ui; bestS = sc; }
  }
  return best;
}
// ordre des zones : celui des cartes de zone du classeur (Cartes.lua)
const ZONE_ORDER = [1429, 1426, 1420, 1436, 1432, 1421, 1433, 1431, 1437, 1424, 1416, 1417, 1434, 1435, 1418, 1425,
  1427, 1428, 1419, 1422, 1423, 1430, 1411, 1412, 1438, 1413, 1439, 1440, 1442, 1441, 1443, 1445, 1444, 1446, 1447,
  1448, 1449, 1452, 1451, 1450];
const BAD_NAME = /\b(UNUSED|DND|Test|Trigger|Dummy|Invisible|Bunny|Spawner|Visual|Controller|NYI|DEPRECATED|OLD)\b|[\[\(]/i;
const elites = [];
for (const t of templates.values()) {
  const rank = int(t.Rank);
  if (rank !== 1 && rank !== 2 && rank !== 4) continue;
  if (int(t.NpcFlags) !== 0 || int(t.RacialLeader) !== 0 || !model(t)) continue;
  const type = int(t.CreatureType);
  if (type < 1 || type > 9 || type === 8) continue;
  if (BAD_NAME.test(t.Name)) continue;
  const sp = (spawns.get(int(t.Entry)) || []).filter(s => s.map === 0 || s.map === 1);
  if (!sp.length) continue;
  // elite ordinaire : nomme seulement s il n apparait qu a un ou deux endroits
  // et qu une quete demande sa tete (les autres sont des gardes, des soldats)
  if (rank === 1 && (sp.length > 2 || !questTargets.has(int(t.Entry)))) continue;
  const count = {};
  for (const s of sp) { const z = zoneAt(s, int(t.MinLevel)); if (z) count[z] = (count[z] || 0) + 1; }
  const zone = Object.keys(count).sort((a, b) => count[b] - count[a])[0];
  if (!zone || count[zone] < sp.length * 0.7 || !ZONE_ORDER.includes(int(zone))) continue;
  elites.push({ t, zone: int(zone), rank });
}
// un nom porte par plusieurs creatures (variantes) : la premiere
const seenName = new Set();
const eliteList = elites
  .sort((a, b) => ZONE_ORDER.indexOf(a.zone) - ZONE_ORDER.indexOf(b.zone) || int(a.t.MinLevel) - int(b.t.MinLevel) || a.t.Name.localeCompare(b.t.Name))
  .filter(e => { const k = e.zone + ':' + e.t.Name.toLowerCase(); if (seenName.has(k)) return false; seenName.add(k); return true; });

// ---------------------------------------------------------------------------
// Cartes (dans l ordre deja publie, nouvelles a la fin)

const cards = new Map();
const instOrder = [...instances.values()].filter(i => i.bosses.length)
  .map(i => ({ i, lvl: i.bosses.reduce((s, b) => s + int(b.t.MinLevel), 0) / i.bosses.length }))
  .sort((a, b) => (a.i.raid - b.i.raid) || a.lvl - b.lvl).map(x => x.i);
for (const inst of instOrder) {
  inst.bosses.sort((a, b) => a.order - b.order);
  for (const b of inst.bosses) {
    let r;
    if (inst.raid) r = RAID_ENDS.has(b.enc) ? 5 : 4;
    else r = b.final ? 4 : 3;
    const id = 'b' + b.enc;
    cards.set(id, { id, s: inst.raid ? 'R' : 'D', r, npc: int(b.t.Entry), disp: model(b.t), lvl: int(b.t.MaxLevel),
      at: inst.id, type: int(b.t.CreatureType), name: b.name, names: b.names });
  }
}
for (const e of eliteList) {
  const id = 'e' + e.t.Entry;
  const names = {};
  const ln = locNames.get(int(e.t.Entry)) || {};
  for (const l of LOCALES) if (ln[l] && ln[l] !== e.t.Name) names[l] = ln[l];
  cards.set(id, { id, s: 'E', r: e.rank === 2 ? 3 : 2, npc: int(e.t.Entry), disp: model(e.t), lvl: int(e.t.MaxLevel),
    at: e.zone, type: int(e.t.CreatureType), name: e.t.Name, names });
}

let order = [];
if (fs.existsSync(OUT)) {
  const old = fs.readFileSync(OUT, 'utf8');
  const block = old.slice(old.indexOf('P.CREATURES = {'), old.indexOf('\n}\n', old.indexOf('P.CREATURES = {')));
  order = [...block.matchAll(/^\s+\{ "([a-z]\d+)",/gm)].map(m => m[1]);
  const lost = order.filter(id => !cards.has(id));
  if (lost.length) { console.error('cartes deja publiees absentes (jamais en retirer) : ' + lost.join(' ')); process.exit(1); }
}
for (const id of cards.keys()) if (!order.includes(id)) order.push(id);

// types de creature (noms du jeu)
const TYPES = new Set(['1', '2', '3', '4', '5', '6', '7', '9', '10']);
const types = new Map(csv('CreatureType').filter(t => TYPES.has(t.ID)).map(t => [t.ID, t.Name_lang]));
const typesLoc = {};
for (const l of LOCALES) typesLoc[l] = new Map(csv('CreatureType.' + l).filter(t => TYPES.has(t.ID)).map(t => [t.ID, t.Name_lang]));

// ---------------------------------------------------------------------------
// Ecriture

const q = s => '"' + String(s).split('\\').join('\\\\').split('"').join('\\"').split('\n').join(' ') + '"';
const out = [];
out.push('-- Genere par .github/scripts/cartes_donnees.js (build ' + BUILD + ') : ne pas modifier a la main.');
out.push('-- Boss : rencontres du jeu Forever ; modeles, niveaux, elites : base CMaNGOS Classic (GPL-3.0, faits seulement).');
out.push('local _, ns = ...');
out.push('if CorpUI and next(ns) == nil then ns = CorpUI end');
out.push('ns.Pedo = ns.Pedo or {}');
out.push('local P = ns.Pedo');
out.push('');
out.push('-- instances : [carte] = { ecran de chargement, raid, nom anglais }');
out.push('P.INSTANCES = {');
for (const i of instOrder) out.push(`    [${i.id}] = { ls = ${i.ls}, raid = ${i.raid}, name = ${q(i.name)} },`);
out.push('}');
out.push('');
out.push('-- cartes : id, serie (D donjons, R raids, E elites), rarete, PNJ, modele, niveau,');
out.push('-- lieu (instance pour un boss, carte de zone pour un elite), type de creature');
out.push('P.CREATURES = {');
for (const id of order) {
  const c = cards.get(id);
  out.push(`    { ${q(c.id)}, "${c.s}", ${c.r}, ${c.npc}, ${c.disp}, ${c.lvl}, ${c.at}, ${c.type} },`);
}
out.push('}');
out.push('');
out.push('-- noms (cartes ; i<carte> : instance ; t<type> : type de creature) : anglais,');
out.push('-- puis ceux qui different dans la langue du client');
out.push('local N = {}');
out.push('N.enUS = {');
for (const id of order) out.push(`    ${id} = ${q(cards.get(id).name)},`);
for (const i of instOrder) out.push(`    ["i${i.id}"] = ${q(i.name)},`);
for (const [id, n] of types) out.push(`    t${id} = ${q(n)},`);
out.push('}');
for (const l of LOCALES) {
  out.push(`N.${l} = {`);
  for (const id of order) { const n = cards.get(id).names[l]; if (n) out.push(`    ${id} = ${q(n)},`); }
  for (const i of instOrder) { const n = i.names[l]; if (n) out.push(`    ["i${i.id}"] = ${q(n)},`); }
  for (const [id, n] of typesLoc[l]) if (n !== types.get(id)) out.push(`    t${id} = ${q(n)},`);
  out.push('}');
}
out.push('local loc = GetLocale and GetLocale() or "enUS"');
out.push('if loc == "esMX" then loc = "esES" end');
out.push('P.CREATURE_NAMES_EN = N.enUS');
out.push('P.CREATURE_NAMES = N[loc] or {}');
fs.writeFileSync(OUT, out.join('\n') + '\n');

// ---------------------------------------------------------------------------
// Compte rendu

const by = {};
for (const c of cards.values()) { const k = c.s + c.r; by[k] = (by[k] || 0) + 1; }
console.log('cartes : ' + cards.size + '  ' + JSON.stringify(by));
console.log('instances : ' + instOrder.map(i => i.name + ' ' + i.bosses.length + (i.ls ? '' : ' (sans ecran)')).join(', '));
console.log('ecartees (pas dans la base Classic) : ' + skipped.length);
for (const s of skipped) console.log('  ' + s);
console.log('ecrit : ' + OUT + ' (' + fs.statSync(OUT).size + ' octets)');
