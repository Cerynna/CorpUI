// Diagnostic du graphe : grands ensembles relies (taille, etendue) et ensemble
// de quelques points.  Usage : node ensembles.js <graphe.json> ["nom:nord,ouest" ...]
const fs = require('fs');
const [, , file, ...probes] = process.argv;
const g = JSON.parse(fs.readFileSync(file, 'utf8'));
const by = {};
for (const n of g.nodes) {
  const b = by[n[5]] || (by[n[5]] = { c: 0, swim: 0, wmo: 0, n0: Infinity, n1: -Infinity, w0: Infinity, w1: -Infinity });
  b.c++; b.swim += n[3]; b.wmo += n[4];
  b.n0 = Math.min(b.n0, n[0]); b.n1 = Math.max(b.n1, n[0]); b.w0 = Math.min(b.w0, n[1]); b.w1 = Math.max(b.w1, n[1]);
}
for (const [s, b] of Object.entries(by).sort((a, b) => b[1].c - a[1].c).slice(0, 12)) {
  console.log(`ensemble ${s} : ${b.c} noeuds (nage ${b.swim}, batiments ${b.wmo}) | nord ${Math.round(b.n0)} a ${Math.round(b.n1)} | ouest ${Math.round(b.w0)} a ${Math.round(b.w1)}`);
}
for (const p of probes) {
  const [name, pos] = p.split(':');
  const [n, w] = pos.split(',').map(Number);
  let best = -1, bd = Infinity;
  g.nodes.forEach((q, i) => { const d = (q[0] - n) ** 2 + (q[1] - w) ** 2; if (d < bd) { bd = d; best = i; } });
  const q = g.nodes[best];
  console.log(`${name} : ensemble ${q[5]} (${by[q[5]].c} noeuds), noeud a ${Math.round(Math.sqrt(bd))} m, z ${q[2]}, nage ${q[3]}, batiment ${q[4]}`);
}
