// Graphe de marche d un continent, tire du terrain et des batiments du client.
//
// Le continent est traite par paquets de 4 x 4 tuiles (plus une marge d un
// bloc). Dans chaque bloc de 66,7 m (8 x 8 blocs par tuile), les surfaces
// praticables reliees entre elles (sans chute) forment une "piece" : un
// noeud du graphe, place sur la surface la plus proche de son centre. Deux
// pieces sont reliees si on passe de l une a l autre a pied (ou en tombant,
// dans un seul sens). On ne garde ensuite que les grands ensembles relies
// dans les deux sens (vallees, villes, routes) : les sommets et les recoins
// qu on ne peut pas atteindre disparaissent.
//
// Eau : la nage n est gardee qu a moins de deux blocs d une terre (pas de
// traversee par la haute mer) ; lave et vase sont exclues.
// Ensembles gardes : ceux qui contiennent un point de vol ou un quai (places
// avec leur altitude, tables du jeu), et les tres grands.
//
// Usage : node graphe.js <dossier WoW> <produit> <Azeroth|Kalimdor|Zephras> <sortie.json> <LiquidType.csv>
const fs = require('fs');
const { Casc } = require('./casc.js');
const A = require('./adt.js');
const W = require('./wmo.js');
const path = require('path');
const { Field, S_WMO, S_SWIM, S_LAVA } = require('./voxel.js');
const { liquidKinds } = require('./liquides.js');

const MAPS = { Azeroth: { wdt: 775971, cont: 0 }, Kalimdor: { wdt: 782779, cont: 1 }, Zephras: { wdt: 7198644, cont: 2991 } };
const ST = 4;                       // tuiles par paquet (cote)
const PER_TILE = 512;               // colonnes par tuile
const CS = A.TILE / PER_TILE;       // 1,04 m
const BLOCK = +(process.env.BLOC || 64);   // colonnes par bloc (64 : 66,7 m ; 128 : 133 m)
const BPT = PER_TILE / BLOCK;       // blocs par tuile
const BIG_SCC = 3000;               // ensemble garde meme sans point de vol
const SHORE = 2;                    // blocs : nage gardee pres d une terre

const [, , wow, product, mapName, out, liquidCsv] = process.argv;
const liquid = liquidKinds(liquidCsv);
const map = MAPS[mapName];
const casc = new Casc(wow, product);
const tiles = A.readWdt(casc.file(map.wdt));
const tileAt = new Map(tiles.map(t => [t.col + ':' + t.row, t]));
const cols = tiles.map(t => t.col), rows = tiles.map(t => t.row);
const TX0 = Math.min(...cols), TX1 = Math.max(...cols), TY0 = Math.min(...rows), TY1 = Math.max(...rows);
const load = W.loader(casc);

const nodes = new Map();            // "bx,by,k" -> { bx, by, k, n, w, z, size, wmo, swim }
const edges = new Set();            // "a|b"
const t0 = Date.now();
let packs = 0;

for (let ty = TY0; ty <= TY1; ty += ST) {
  for (let tx = TX0; tx <= TX1; tx += ST) {
    let any = false;
    for (let y = ty; y < ty + ST && !any; y++) for (let x = tx; x < tx + ST; x++) if (tileAt.has(x + ':' + y)) { any = true; break; }
    if (!any) continue;
    packs++;
    const n0 = (32 - ty) * A.TILE + BLOCK * CS, w0 = (32 - tx) * A.TILE + BLOCK * CS;
    const size = ST * PER_TILE + 2 * BLOCK;
    const f = new Field(n0, w0, size, size, CS, { liquid });
    const placed = new Map();
    for (let y = ty - 1; y <= ty + ST; y++) {
      for (let x = tx - 1; x <= tx + ST; x++) {
        const t = tileAt.get(x + ':' + y);
        if (!t) continue;
        const rb = casc.file(t.root);
        if (rb) f.addTerrain(A.readAdt(rb));
        const ob = t.obj0 && casc.file(t.obj0);
        if (ob) for (const p of W.readPlacements(ob)) if (p.byId) placed.set(p.uid, p);
      }
    }
    for (const p of placed.values()) {
      const tris = load(p.fdid);
      if (!tris) continue;
      const tf = W.transform(p);
      for (let i = 0; i < tris.length; i += 9) {
        f.addTri(tf(tris[i], tris[i + 1], tris[i + 2]), tf(tris[i + 3], tris[i + 4], tris[i + 5]), tf(tris[i + 6], tris[i + 7], tris[i + 8]));
      }
    }
    const nSurf = f.surfaces();
    const comp = new Int32Array(nSurf).fill(-1);
    const compKey = [];
    const queue = new Int32Array(nSurf);
    const blocks = size / BLOCK;
    // pieces de chaque bloc (liens dans les deux sens, sans sortir du bloc)
    for (let by = 0; by < blocks; by++) {
      for (let bx = 0; bx < blocks; bx++) {
        const gbx = tx * BPT - 1 + bx, gby = ty * BPT - 1 + by;
        const core = bx > 0 && by > 0 && bx < blocks - 1 && by < blocks - 1;
        let k = 0;
        for (let r = by * BLOCK; r < (by + 1) * BLOCK; r++) {
          for (let q = bx * BLOCK; q < (bx + 1) * BLOCK; q++) {
            const c = r * size + q;
            for (let s = f.sStart[c]; s < f.sStart[c + 1]; s++) {
              if (comp[s] >= 0 || (f.sFlag[s] & S_LAVA)) continue;
              const id = compKey.length;
              const key = gbx + ',' + gby + ',' + k++;
              compKey.push(key);
              let qh = 0, qt = 0;
              comp[s] = id;
              queue[qt++] = s;
              while (qh < qt) {
                const i = queue[qh++];
                const ci = f.sCol[i], col = ci % size, row = (ci - col) / size;
                for (let dy = -1; dy <= 1; dy++) {
                  const rr = row + dy;
                  if (rr < by * BLOCK || rr >= (by + 1) * BLOCK) continue;
                  for (let dx = -1; dx <= 1; dx++) {
                    if (!dx && !dy) continue;
                    const qq = col + dx;
                    if (qq < bx * BLOCK || qq >= (bx + 1) * BLOCK) continue;
                    const kk = rr * size + qq;
                    for (let j = f.sStart[kk]; j < f.sStart[kk + 1]; j++) {
                      if (comp[j] >= 0 || (f.sFlag[j] & S_LAVA)) continue;
                      if (Math.abs(f.sTop[j] - f.sTop[i]) > f.climb) continue;
                      if (Math.min(f.sCeil[i], f.sCeil[j]) - Math.max(f.sTop[i], f.sTop[j]) < f.agentH) continue;
                      comp[j] = id;
                      queue[qt++] = j;
                    }
                  }
                }
              }
              if (!core) continue;
              // point de la piece : la surface la plus proche du centre
              let sn = 0, sw = 0, sz = 0, wmo = 0, swim = 0;
              for (let m = 0; m < qt; m++) {
                const i = queue[m], ci = f.sCol[i], col = ci % size, row = (ci - col) / size;
                sn += row; sw += col; sz += f.sTop[i];
                if (f.sFlag[i] & S_WMO) wmo++;
                if (f.sFlag[i] & S_SWIM) swim++;
              }
              sn /= qt; sw /= qt; sz /= qt;
              let best = queue[0], bd = Infinity;
              for (let m = 0; m < qt; m++) {
                const i = queue[m], ci = f.sCol[i], col = ci % size, row = (ci - col) / size;
                const d = (row - sn) ** 2 + (col - sw) ** 2 + ((f.sTop[i] - sz) / CS) ** 2;
                if (d < bd) { bd = d; best = i; }
              }
              const ci = f.sCol[best], col = ci % size, row = (ci - col) / size;
              nodes.set(key, { bx: gbx, by: gby, k: k - 1, n: n0 - (row + 0.5) * CS, w: w0 - (col + 0.5) * CS, z: f.sTop[best], area: f.area[ci],
                               size: qt, wmo: wmo / qt, swim: swim / qt });
            }
          }
        }
      }
    }
    // liens entre pieces, depuis les blocs du coeur du paquet
    for (let i = 0; i < nSurf; i++) {
      if (comp[i] < 0) continue;
      const ci = f.sCol[i], col = ci % size, row = (ci - col) / size;
      if (col < BLOCK || row < BLOCK || col >= size - BLOCK || row >= size - BLOCK) continue;
      const a = compKey[comp[i]];
      f.neighbors(i, j => {
        if (comp[j] >= 0 && comp[j] !== comp[i]) edges.add(a + '|' + compKey[comp[j]]);
      });
    }
    process.stdout.write(`\rpaquets ${packs} | noeuds ${nodes.size} | liens ${edges.size} | ${Math.round((Date.now() - t0) / 1000)} s   `);
  }
}
console.log();

// nage loin des terres : retiree (blocs avec une piece de terre ferme)
const land = new Set();
for (const nd of nodes.values()) if (nd.swim <= 0.5) land.add(nd.bx + ',' + nd.by);
let offshore = 0;
for (const [key, nd] of nodes) {
  if (nd.swim <= 0.5) continue;
  let near = false;
  for (let dy = -SHORE; dy <= SHORE && !near; dy++) for (let dx = -SHORE; dx <= SHORE; dx++) {
    if (land.has((nd.bx + dx) + ',' + (nd.by + dy))) { near = true; break; }
  }
  if (!near) { nodes.delete(key); offshore++; }
}

// ensembles relies dans les deux sens (Tarjan, sans recursion)
const keys = [...nodes.keys()];
const index = new Map(keys.map((k, i) => [k, i]));
const adj = keys.map(() => []);
for (const e of edges) {
  const [a, b] = e.split('|');
  if (index.has(a) && index.has(b)) adj[index.get(a)].push(index.get(b));
}
const N = keys.length;
const idx = new Int32Array(N).fill(-1), low = new Int32Array(N), onStack = new Uint8Array(N), scc = new Int32Array(N).fill(-1);
const stack = [];
let counter = 0, nScc = 0;
for (let s = 0; s < N; s++) {
  if (idx[s] >= 0) continue;
  const work = [[s, 0]];
  while (work.length) {
    const top = work[work.length - 1];
    const v = top[0];
    if (top[1] === 0) { idx[v] = low[v] = counter++; stack.push(v); onStack[v] = 1; }
    let pushed = false;
    while (top[1] < adj[v].length) {
      const w = adj[v][top[1]++];
      if (idx[w] < 0) { work.push([w, 0]); pushed = true; break; }
      if (onStack[w]) low[v] = Math.min(low[v], idx[w]);
    }
    if (pushed) continue;
    if (low[v] === idx[v]) {
      let w;
      do { w = stack.pop(); onStack[w] = 0; scc[w] = nScc; } while (w !== v);
      nScc++;
    }
    work.pop();
    if (work.length) { const u = work[work.length - 1][0]; low[u] = Math.min(low[u], low[v]); }
  }
}
const sccSize = new Int32Array(nScc);
for (let i = 0; i < N; i++) sccSize[scc[i]]++;

// points de vol et quais du continent (Donnees.lua du module Voyage, avec
// leur altitude) : la piece la plus proche en 3D, dans un grand ensemble
const donnees = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'CorpUI_Voyage', 'Voyage', 'Donnees.lua'), 'utf8');
const pois = [];
for (const m of donnees.matchAll(/\[(\d+)\] = "(-?\d+),(-?[\d.]+),(-?[\d.]+),(\d+),(-?[\d.]+)"/g)) {
  if (+m[2] === map.cont) pois.push({ kind: 'node', id: +m[1], n: +m[3], w: +m[4], z: +m[6] });
}
for (const m of donnees.matchAll(/\[(\d+)\] = "([-\d.:\/]+)"/g)) {
  m[2].split('/').forEach((leg, k) => {
    const p = leg.split(':').map(Number);
    if (p.length >= 6 && p[0] === map.cont) pois.push({ kind: 'dock', id: +m[1], k: k + 1, n: p[1], w: p[2], z: p[5] });
  });
}
// entrees des liaisons (tram, portail) : gardent aussi leur ensemble (le haut de Teldrassil...)
for (const m of donnees.matchAll(/"(tram|portal),([-\d.,]+)"/g)) {
  const v = m[2].split(',').map(Number);
  for (const k of [0, 4]) if (v[k] === map.cont) pois.push({ kind: m[1], id: k ? 2 : 1, n: v[k + 1], w: v[k + 2], z: v[k + 3] });
}
const allPos = keys.map(k => nodes.get(k));
function snap(p, minScc) {
  let best = -1, bd = Infinity;
  for (let i = 0; i < N; i++) {
    if (sccSize[scc[i]] < minScc) continue;
    const q = allPos[i];
    const d2 = Math.hypot(q.n - p.n, q.w - p.w);
    if (d2 > 120) continue;
    // quais : l eau du bateau est au niveau 0, on cherche la terre ou le ponton
    const dz = p.kind === 'dock' ? Math.max(0, q.z - p.z - 15) : Math.abs(q.z - p.z);
    const d = d2 + dz * 2 + (q.swim > 0.5 ? 40 : 0);
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}
const keepScc = new Set();
for (let s = 0; s < nScc; s++) if (sccSize[s] >= BIG_SCC) keepScc.add(s);
for (const p of pois) {
  p.node = snap(p, 30);
  if (p.node >= 0) keepScc.add(scc[p.node]);
}
const keep = new Uint8Array(N);
let kept = 0;
for (let i = 0; i < N; i++) if (keepScc.has(scc[i])) { keep[i] = 1; kept++; }
const outNodes = [], newIdx = new Int32Array(N).fill(-1);
for (let i = 0; i < N; i++) {
  if (!keep[i]) continue;
  const nd = nodes.get(keys[i]);
  newIdx[i] = outNodes.length;
  outNodes.push([+nd.n.toFixed(1), +nd.w.toFixed(1), +nd.z.toFixed(1), nd.swim > 0.5 ? 1 : 0, nd.wmo > 0.5 ? 1 : 0, scc[i], nd.area]);
}
const outEdges = [];
for (let i = 0; i < N; i++) {
  if (!keep[i]) continue;
  for (const j of adj[i]) if (keep[j]) outEdges.push([newIdx[i], newIdx[j]]);
}
const outPois = pois.map(p => ({ kind: p.kind, id: p.id, k: p.k, node: p.node >= 0 ? newIdx[p.node] : -1 }));
const lost = outPois.filter(p => p.node < 0).map(p => p.kind + ' ' + p.id + (p.k ? ':' + p.k : ''));
const big = [...keepScc].map(s => sccSize[s]).sort((a, b) => b - a);
fs.writeFileSync(out, JSON.stringify({ build: casc.buildName, map: mapName, cont: map.cont, block: BLOCK * CS, nodes: outNodes,
                                       edges: outEdges, pois: outPois }));
console.log(`${casc.buildName} | ${mapName} | paquets ${packs} | pieces ${N + offshore} (haute mer retiree ${offshore}) | ensembles ${nScc} | gardes ${keepScc.size} ensembles, ${kept} noeuds, ${outEdges.length} liens | plus grands : ${big.slice(0, 10).join(', ')} | points de vol/quais ${pois.length}, sans piece : ${lost.join(', ') || 'aucun'} | ${Math.round((Date.now() - t0) / 1000)} s`);
