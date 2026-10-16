// Graphe(s) de marche -> CorpUI_Voyage/Voyage/Chemins.lua (donnees de l addon).
//
// Par continent :
//   nodes : une piece par 6 caracteres (base 64) : nord (3), ouest (3)... voir
//           ENCODAGE ci-dessous ; les pieces sont rangees par bloc
//   edges : pour chaque piece, son nombre de liens (1) puis chaque lien en
//           2 caracteres : direction du bloc voisin (0-8) et rang de la piece
//           dans ce bloc
//   pois  : point de vol, quai, entree de tram ou de portail -> piece
//   pd    : distances a pied (m) entre ces points, calculees ici une fois
//
// Usage : node export.js <sortie.lua> <graphe.json> [graphe.json ...]
const fs = require('fs');

const B64 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/';
const enc = (v, n) => {
  let s = '';
  for (let i = 0; i < n; i++) { s = B64[v & 63] + s; v = Math.floor(v / 64); }
  return s;
};
const MID = 32 * 1600 / 3;
const SWIM = 1.5;

const [, , out, ...files] = process.argv;
let lua = '--[[--------------------------------------------------------------------------\n';
lua += '    CorpUI - module Voyage : chemins a pied (fichier GENERE, ne pas editer).\n';
lua += '    Genere par .github/scripts/terrain/graphe.js puis export.js depuis le\n';
lua += '    terrain et les batiments du client (lecture locale du jeu installe).\n';
lua += '    ENCODAGE (base 64 "' + B64 + '") :\n';
lua += '      piece : nord + 131072 (3), ouest + 131072 (3), haut + 2048 (2),\n';
lua += '              drapeaux (1 : nage, 2 : batiment), nombre de liens (1)\n';
lua += '      lien  : bloc voisin (dy + 1) * 3 + (dx + 1) (1), rang dans le bloc (1)\n';
lua += '    Blocs : bx = (17066,67 - ouest) / bloc, by = (17066,67 - nord) / bloc.\n';
lua += '----------------------------------------------------------------------------]]\n\n';
lua += 'local _, ns = ...\nif CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)\n\n';
lua += 'ns.VoyageWalkData = ns.VoyageWalkData or {}\n';

for (const file of files) {
  const g = JSON.parse(fs.readFileSync(file, 'utf8'));
  const B = g.block;
  const N = g.nodes.length;
  const blk = g.nodes.map(p => [Math.floor((MID - p[1]) / B), Math.floor((MID - p[0]) / B)]);
  // ordre : par bloc (ligne, colonne), puis ordre d origine
  const order = [...Array(N).keys()].sort((a, b) => (blk[a][1] - blk[b][1]) || (blk[a][0] - blk[b][0]) || (a - b));
  const rank = new Int32Array(N), pos = new Int32Array(N);
  const count = new Map();
  order.forEach((i, p) => {
    const key = blk[i][1] * 1024 + blk[i][0];
    const k = count.get(key) || 0;
    rank[i] = k;
    count.set(key, k + 1);
    pos[i] = p;
  });
  const maxK = Math.max(...count.values());
  if (maxK > 64) throw new Error('trop de pieces dans un bloc : ' + maxK);
  const adj = Array.from({ length: N }, () => []);
  for (const [a, b] of g.edges) if (!adj[a].includes(b)) adj[a].push(b);
  let nodes = '', edges = '', skipped = 0;
  for (const i of order) {
    const p = g.nodes[i];
    const outs = adj[i].filter(j => Math.abs(blk[j][0] - blk[i][0]) <= 1 && Math.abs(blk[j][1] - blk[i][1]) <= 1);
    skipped += adj[i].length - outs.length;
    if (outs.length > 63) outs.length = 63;
    nodes += enc(Math.round(p[0]) + 131072, 3) + enc(Math.round(p[1]) + 131072, 3) + enc(Math.max(0, Math.min(4095, Math.round(p[2]) + 2048)), 2)
      + B64[(p[3] ? 1 : 0) | (p[4] ? 2 : 0)] + B64[outs.length];
    for (const j of outs) edges += B64[(blk[j][1] - blk[i][1] + 1) * 3 + (blk[j][0] - blk[i][0] + 1)] + B64[rank[j]];
  }
  // distances a pied entre les points (Dijkstra depuis chacun)
  const cost = (a, b) => {
    const p = g.nodes[a], q = g.nodes[b];
    return Math.hypot(p[0] - q[0], p[1] - q[1], (p[2] - q[2]) * 0.5) * ((p[3] || q[3]) ? SWIM : 1);
  };
  const linkIdx = { tram: 1, portal: 2 };
  const pois = {};
  for (const p of g.pois) {
    if (p.node < 0) continue;
    const key = p.kind === 'node' ? 'n' + p.id : p.kind === 'dock' ? 'd' + p.id + '_' + p.k : 'g' + linkIdx[p.kind] + '_' + p.id;
    pois[key] = p.node;
  }
  const keys = Object.keys(pois);
  const pd = [];
  for (const ka of keys) {
    const dist = new Float64Array(N).fill(Infinity);
    const done = new Uint8Array(N);
    const heap = [[0, pois[ka]]];
    dist[pois[ka]] = 0;
    while (heap.length) {
      // tas binaire
      const top = heap[0], last = heap.pop();
      if (heap.length) {
        heap[0] = last;
        let k = 0;
        for (;;) {
          const l = 2 * k + 1, r = l + 1;
          let m = k;
          if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
          if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
          if (m === k) break;
          [heap[m], heap[k]] = [heap[k], heap[m]]; k = m;
        }
      }
      const u = top[1];
      if (done[u]) continue;
      done[u] = 1;
      for (const v of adj[u]) {
        const nd = dist[u] + cost(u, v);
        if (nd < dist[v]) {
          dist[v] = nd;
          heap.push([nd, v]);
          let k = heap.length - 1;
          while (k > 0) { const pp = (k - 1) >> 1; if (heap[pp][0] <= heap[k][0]) break; [heap[pp], heap[k]] = [heap[k], heap[pp]]; k = pp; }
        }
      }
    }
    for (const kb of keys) if (kb !== ka && isFinite(dist[pois[kb]])) pd.push(ka + ':' + kb + ':' + Math.round(dist[pois[kb]]));
  }
  lua += `\nns.VoyageWalkData[${g.cont}] = {\n    build = "${g.build}", block = ${+B.toFixed(4)}, count = ${N},\n`;
  lua += '    nodes = "' + nodes + '",\n';
  lua += '    edges = "' + edges + '",\n';
  lua += '    pois = { ' + keys.map(k => `${k} = ${pos[pois[k]] + 1}`).join(', ') + ' },\n';
  lua += '    pd = "' + pd.join(';') + '",\n}\n';
  console.log(`${g.map} : ${N} pieces, ${g.edges.length} liens (hors voisins : ${skipped}), points ${keys.length}, distances ${pd.length}, pieces par bloc max ${maxK}, ${Math.round((nodes.length + edges.length) / 1024)} Ko`);
}
fs.writeFileSync(out, lua);
console.log('fichier :', out, Math.round(lua.length / 1024), 'Ko');
