// Essai du graphe de marche : plus court chemin (A*) entre des points du monde,
// dessine sur la carte des noeuds (couleur selon la hauteur ; rouge : chemins).
//
// Usage : node chemin.js <graphe.json> <sortie.png> "nord,ouest>nord,ouest" ["..."]
const fs = require('fs');
const png = require('./png.js');

const [, , file, out, ...args] = process.argv;
const pairs = args.filter(a => !a.startsWith('--'));
// --zones=AreaTable.csv : noms des zones traversees
const zoneCsv = (args.find(a => a.startsWith('--zones=')) || '').slice(8);
const zoneOf = {};
if (zoneCsv) {
  const { parseCsv } = require('./liquides.js');
  const rows = parseCsv(fs.readFileSync(zoneCsv, 'utf8'));
  const head = rows.shift();
  const at = {};
  for (const r of rows) at[+r[head.indexOf('ID')]] = { name: r[head.indexOf('AreaName_lang')], parent: +r[head.indexOf('ParentAreaID')] };
  for (const id of Object.keys(at)) {
    let a = at[id], guard = 0;
    while (a && a.parent && at[a.parent] && guard++ < 5) a = at[a.parent];
    zoneOf[id] = a ? a.name : '?';
  }
}
const g = JSON.parse(fs.readFileSync(file, 'utf8'));
const N = g.nodes.length;
const adj = Array.from({ length: N }, () => []);
for (const [a, b] of g.edges) adj[a].push(b);
const SWIM = 1.5;

function cost(a, b) {
  const p = g.nodes[a], q = g.nodes[b];
  const d = Math.hypot(p[0] - q[0], p[1] - q[1], (p[2] - q[2]) * 0.5);
  return d * ((p[3] || q[3]) ? SWIM : 1);
}

// grand ensemble : celui qui a le plus de noeuds
const sccCount = {};
for (const n of g.nodes) sccCount[n[5]] = (sccCount[n[5]] || 0) + 1;
function nearest(n, w) {
  let best = -1, bd = Infinity;
  for (let i = 0; i < N; i++) {
    const p = g.nodes[i];
    const d = Math.hypot(p[0] - n, p[1] - w) - Math.min(200, sccCount[p[5]]) * 0.05;
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}

function astar(s, t) {
  const gs = new Float64Array(N).fill(Infinity), prev = new Int32Array(N).fill(-1), done = new Uint8Array(N);
  const heap = [];
  const push = (i, f) => {
    heap.push([f, i]);
    let k = heap.length - 1;
    while (k > 0) { const p = (k - 1) >> 1; if (heap[p][0] <= heap[k][0]) break; [heap[p], heap[k]] = [heap[k], heap[p]]; k = p; }
  };
  const pop = () => {
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
    return top;
  };
  const h = i => Math.hypot(g.nodes[i][0] - g.nodes[t][0], g.nodes[i][1] - g.nodes[t][1]);
  gs[s] = 0;
  push(s, h(s));
  let visited = 0;
  while (heap.length) {
    const [, u] = pop();
    if (done[u]) continue;
    done[u] = 1;
    visited++;
    if (u === t) break;
    for (const v of adj[u]) {
      const nd = gs[u] + cost(u, v);
      if (nd < gs[v]) { gs[v] = nd; prev[v] = u; push(v, nd + h(v)); }
    }
  }
  if (!isFinite(gs[t])) return { path: null, visited };
  const path = [];
  for (let i = t; i >= 0; i = prev[i]) path.push(i);
  return { path: path.reverse(), len: gs[t], visited };
}

// image : 1 pixel = 12 m
const PX = 12;
let nMax = -Infinity, nMin = Infinity, wMax = -Infinity, wMin = Infinity, zMin = Infinity, zMax = -Infinity;
for (const p of g.nodes) {
  nMax = Math.max(nMax, p[0]); nMin = Math.min(nMin, p[0]); wMax = Math.max(wMax, p[1]); wMin = Math.min(wMin, p[1]);
  zMin = Math.min(zMin, p[2]); zMax = Math.max(zMax, p[2]);
}
const IW = Math.ceil((wMax - wMin) / PX) + 40, IH = Math.ceil((nMax - nMin) / PX) + 40;
const rgb = new Uint8ClampedArray(IW * IH * 3).fill(12);
const xy = (n, w) => [Math.round((wMax - w) / PX) + 20, Math.round((nMax - n) / PX) + 20];
const dot = (x, y, c, r = 1) => {
  for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
    const px = x + dx, py = y + dy;
    if (px < 0 || py < 0 || px >= IW || py >= IH) continue;
    const i = (py * IW + px) * 3;
    rgb[i] = c[0]; rgb[i + 1] = c[1]; rgb[i + 2] = c[2];
  }
};
const mainScc = +Object.keys(sccCount).sort((a, b) => sccCount[b] - sccCount[a])[0];
for (const p of g.nodes) {
  const t = (p[2] - zMin) / Math.max(1, zMax - zMin);
  const main = p[5] === mainScc;
  const c = p[3] ? [40, 90, 200] : p[4] ? [180, 90, 220] : [60 + 160 * t, 120 + 100 * t, 50 + 60 * t];
  const [x, y] = xy(p[0], p[1]);
  // bloc entier colore (carte lisible), plus sombre hors du grand ensemble
  const r = Math.max(0, Math.floor((g.block || 66.7) / PX / 2));
  dot(x, y, main ? c : c.map(v => v * 0.45), r);
}
const line = (a, b, c) => {
  const [x0, y0] = xy(a[0], a[1]), [x1, y1] = xy(b[0], b[1]);
  const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1);
  for (let k = 0; k <= n; k++) dot(Math.round(x0 + (x1 - x0) * k / n), Math.round(y0 + (y1 - y0) * k / n), c, 2);
};
for (const pr of pairs) {
  const [a, b] = pr.split('>').map(s => s.split(',').map(Number));
  const s = nearest(a[0], a[1]), t = nearest(b[0], b[1]);
  const t0 = Date.now();
  const r = astar(s, t);
  const straight = Math.hypot(a[0] - b[0], a[1] - b[1]);
  if (!r.path) { console.log(`${pr} : PAS DE CHEMIN (noeuds visites ${r.visited})`); continue; }
  for (let i = 1; i < r.path.length; i++) line(g.nodes[r.path[i - 1]], g.nodes[r.path[i]], [255, 30, 30]);
  const [xa, ya] = xy(a[0], a[1]), [xb, yb] = xy(b[0], b[1]);
  dot(xa, ya, [0, 0, 0], 7); dot(xa, ya, [255, 255, 255], 5); dot(xb, yb, [0, 0, 0], 7); dot(xb, yb, [255, 230, 0], 5);
  const zones = [];
  for (const i of r.path) { const z = zoneOf[g.nodes[i][6]] || g.nodes[i][6]; if (zones[zones.length - 1] !== z) zones.push(z); }
  console.log(`${pr} : ${Math.round(r.len)} m a pied (ligne droite ${Math.round(straight)} m, x${(r.len / straight).toFixed(2)}) | ${r.path.length} noeuds | visites ${r.visited} | ${Date.now() - t0} ms`);
  if (zoneCsv) console.log('    ' + zones.join(' > '));
}
fs.writeFileSync(out, png.encode(IW, IH, rgb));
console.log(`noeuds ${N} | liens ${g.edges.length} | grand ensemble ${sccCount[mainScc]} | image ${IW}x${IH}`);
