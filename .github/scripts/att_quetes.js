// Genere CorpUI_Leveling/Leveling/Donnees.lua : les quetes a prendre (donneur,
// position, conditions), tirees de la base compilee d AllTheThings pour
// Forever (db/Camelot/Categories/*.lua, licence MIT).
//
// Les fichiers d AllTheThings sont LUS, jamais executes : analyse syntaxique
// (luaparse), puis releve des appels q(<id>, { ... }) et de leurs champs.
//
// Usage (Git Bash, depuis le depot) :
//   mkdir -p /tmp/att && for f in Zones Instances Professions; do
//     gh api "repos/ATTWoWAddon/AllTheThings/contents/db/Camelot/Categories/$f.lua?ref=master" \
//       -H "Accept: application/vnd.github.raw" > /tmp/att/$f.lua; done
//   gh api "repos/ATTWoWAddon/AllTheThings/commits?path=db/Camelot/Categories/Zones.lua&per_page=1" --jq '.[0].sha' > /tmp/att/sha
//   npm install --prefix /tmp/att luaparse
//   NODE_PATH=/tmp/att/node_modules node .github/scripts/att_quetes.js /tmp/att
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const SRC = process.argv[2];
const OUT = path.join(__dirname, '..', '..', 'CorpUI_Leveling', 'Leveling', 'Donnees.lua');
const FILES = ['Zones', 'Instances', 'Professions'];

// valeur litterale d une expression (nombres, chaines, booleens, tables)
function lit(e) {
  if (!e) return undefined;
  switch (e.type) {
    case 'NumericLiteral': return e.value;
    case 'StringLiteral': return e.raw.slice(1, -1);
    case 'BooleanLiteral': return e.value;
    case 'UnaryExpression': {
      const v = e.operator === '-' ? lit(e.argument) : undefined;
      return typeof v === 'number' ? -v : undefined;
    }
    case 'TableConstructorExpression': {
      const arr = [], obj = {};
      let isArr = true;
      for (const f of e.fields) {
        if (f.type === 'TableValue') arr.push(lit(f.value));
        else if (f.type === 'TableKeyString') { obj[f.key.name] = lit(f.value); isArr = false; }
        else if (f.type === 'TableKey') { const k = lit(f.key); if (k !== undefined) obj[k] = lit(f.value); isArr = false; }
      }
      if (isArr) return arr;
      if (arr.length) obj.__list = arr;
      return obj;
    }
    default: return undefined;
  }
}

const quests = new Map();
function visit(n) {
  if (!n || typeof n !== 'object') return;
  if (Array.isArray(n)) { for (const x of n) visit(x); return; }
  if (n.type === 'CallExpression' && n.base && n.base.type === 'Identifier' && n.base.name === 'q') {
    const id = lit(n.arguments[0]);
    const tNode = n.arguments[1];
    if (typeof id === 'number' && tNode && tNode.type === 'TableConstructorExpression') {
      const prev = quests.get(id) || {};
      for (const f of tNode.fields) {
        if (f.type === 'TableKeyString' && f.key.name !== 'g' && prev[f.key.name] === undefined) prev[f.key.name] = lit(f.value);
      }
      quests.set(id, prev);
    }
  }
  for (const k of Object.keys(n)) {
    const v = n[k];
    if (v && typeof v === 'object') visit(v);
  }
}

for (const f of FILES) {
  const file = path.join(SRC, f + '.lua');
  if (!fs.existsSync(file)) continue;
  const src = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  visit(luaparse.parse(src, { comments: false, locations: false, ranges: false, luaVersion: '5.1' }));
}

const nums = v => Array.isArray(v) ? v.filter(x => typeof x === 'number') : [];
const fmt = v => (Math.round(v * 10) / 10).toFixed(1).replace(/\.0$/, '');
// une quete par carte ou son donneur se trouve :
// id,x,y,niv,camp,prealables,nb requis,exclusives,classes,races,ajout,retrait,reputation,marques
const byMap = new Map();
let kept = 0, skipped = 0;
for (const [id, t] of [...quests.entries()].sort((a, b) => a[0] - b[0])) {
  // hors leveling : metiers, repetables, retirees du jeu
  if (t.requireSkill || t.repeatable || t.isDaily || t.isWeekly || t.isYearly || t.u !== undefined) { skipped++; continue; }
  if (!t.coords || typeof t.coords !== 'object') { skipped++; continue; }
  const rep = Array.isArray(t.minReputation) && t.minReputation.length >= 2 ? t.minReputation[0] + ':' + t.minReputation[1] : '';
  const fields = [
    id, null, null,
    typeof t.lvl === 'number' ? t.lvl : '',
    t.r === 1 || t.r === 2 ? t.r : '',
    nums(t.sourceQuests).join('/'),
    typeof t.sqreq === 'number' ? t.sqreq : '',
    nums(t.altQuests).join('/'),
    nums(t.c).join('/'),
    nums(t.races).join('/'),
    typeof t.awp === 'number' ? t.awp : '',
    typeof t.rwp === 'number' ? t.rwp : '',
    rep,
    t.isBreadcrumb ? 'b' : '',
  ];
  let any = false;
  for (const [map, pts] of Object.entries(t.coords)) {
    if (!Array.isArray(pts) || !Array.isArray(pts[0])) continue;
    const [x, y] = pts[0];
    if (typeof x !== 'number' || typeof y !== 'number') continue;
    const f = fields.slice();
    f[1] = fmt(x); f[2] = fmt(y);
    while (f.length > 3 && f[f.length - 1] === '') f.pop();
    if (!byMap.has(map)) byMap.set(map, []);
    byMap.get(map).push(f.join(','));
    any = true;
  }
  if (any) kept++; else skipped++;
}

const sha = fs.existsSync(path.join(SRC, 'sha')) ? fs.readFileSync(path.join(SRC, 'sha'), 'utf8').trim() : '?';
const license = [
  'MIT License',
  '',
  'Copyright (c) 2026 AllTheThings WoW Addon',
  '',
  'Permission is hereby granted, free of charge, to any person obtaining a copy',
  'of this software and associated documentation files (the "Software"), to deal',
  'in the Software without restriction, including without limitation the rights',
  'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell',
  'copies of the Software, and to permit persons to whom the Software is',
  'furnished to do so, subject to the following conditions:',
  '',
  'The above copyright notice and this permission notice shall be included in all',
  'copies or substantial portions of the Software.',
  '',
  'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR',
  'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,',
  'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE',
  'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER',
  'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,',
  'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE',
  'SOFTWARE.',
];
let out = '';
out += '--[[--------------------------------------------------------------------------\n';
out += '    CorpUI - module Leveling : quetes a prendre (fichier GENERE, ne pas editer)\n';
out += '    Genere par .github/scripts/att_quetes.js depuis la base de quetes\n';
out += '    d AllTheThings pour Forever (db/Camelot), commit ' + sha.slice(0, 10) + '.\n';
out += '    Par carte : "id,x,y,niv,camp,prealables,nb requis,exclusives,classes,\n';
out += '    races,ajout,retrait,reputation,marques" ; quetes separees par ";",\n';
out += '    listes par "/". Lu a la demande, carte par carte (Moteur.lua).\n\n';
out += '    Donnees d AllTheThings :\n\n';
for (const l of license) out += (l ? '    ' + l : '') + '\n';
out += '----------------------------------------------------------------------------]]\n\n';
out += 'local _, ns = ...\n';
out += 'if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)\n\n';
out += 'ns.LevelingOffers = {\n';
for (const map of [...byMap.keys()].sort((a, b) => a - b)) {
  out += '    [' + map + '] = "' + byMap.get(map).join(';') + '",\n';
}
out += '}\n';
fs.writeFileSync(OUT, out);
console.log('quetes gardees :', kept, '| ecartees :', skipped, '| cartes :', byMap.size, '| octets :', out.length);
