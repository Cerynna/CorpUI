// Carte praticable d une region (terrain + batiments), et ce qu on atteint a
// pied depuis un point de depart. Image : vert = terrain atteint, violet =
// sol de batiment atteint, bleu = nage atteinte, gris = praticable mais pas
// atteint depuis le depart, rouge = trop raide, noir = rien.
//
// Usage :
//   node praticable.js <dossier WoW> <produit> <Azeroth|Kalimdor|Zephras> <col0> <col1> <lig0> <lig1>
//                      <nord depart> <ouest depart> <sortie.png> [nord,ouest;nord,ouest... a tester]
const fs = require('fs');
const { Casc } = require('./casc.js');
const A = require('./adt.js');
const W = require('./wmo.js');
const { Field, S_WMO, S_SWIM, S_LAVA } = require('./voxel.js');
const png = require('./png.js');

const MAPS = { Azeroth: 775971, Kalimdor: 782779, Zephras: 7198644 };
const [, , wow, product, mapName, c0, c1, r0, r1, sn, sw, out, probes] = process.argv;
const CS = A.UNIT / 4;
const casc = new Casc(wow, product);
const tiles = A.readWdt(casc.file(MAPS[mapName])).filter(t => t.col >= +c0 && t.col <= +c1 && t.row >= +r0 && t.row <= +r1);
const N0 = (32 - +r0) * A.TILE, W0 = (32 - +c0) * A.TILE;
const cols = Math.round((+c1 - +c0 + 1) * A.TILE / CS), rows = Math.round((+r1 - +r0 + 1) * A.TILE / CS);
const f = new Field(N0, W0, cols, rows, CS);
const t0 = Date.now();
const placed = new Map();
for (const t of tiles) {
  f.addTerrain(A.readAdt(casc.file(t.root)));
  const ob = casc.file(t.obj0);
  if (ob) for (const p of W.readPlacements(ob)) if (p.byId) placed.set(p.uid, p);
}
const tTerrain = Date.now() - t0;
const load = W.loader(casc);
let nTri = 0;
for (const p of placed.values()) {
  const tris = load(p.fdid);
  if (!tris) continue;
  const tf = W.transform(p);
  for (let i = 0; i < tris.length; i += 9) {
    f.addTri(tf(tris[i], tris[i + 1], tris[i + 2]), tf(tris[i + 3], tris[i + 4], tris[i + 5]), tf(tris[i + 6], tris[i + 7], tris[i + 8]));
    nTri++;
  }
}
const tWmo = Date.now() - t0 - tTerrain;
const nSurf = f.surfaces();
const seed = f.surfaceAt(+sn, +sw);
const seen = f.reach(seed);
let reached = 0;
for (let i = 0; i < seen.length; i++) reached += seen[i];

// image : une colonne sur deux
const S = 2, IW = Math.floor(cols / S), IH = Math.floor(rows / S);
const rgb = new Uint8ClampedArray(IW * IH * 3);
for (let y = 0; y < IH; y++) {
  for (let x = 0; x < IW; x++) {
    const c = (y * S) * cols + x * S;
    let pick = -1, pickReached = false;
    for (let j = f.sStart[c]; j < f.sStart[c + 1]; j++) {
      const r = seen[j] === 1;
      if (pick < 0 || (r && !pickReached) || (r === pickReached && f.sTop[j] > f.sTop[pick])) { pick = j; pickReached = r; }
    }
    let col;
    if (pick < 0) {
      // rien de praticable : trop raide si une tranche existe
      col = f.head[c] >= 0 ? [170, 45, 40] : [0, 0, 0];
      if (f.head[c] >= 0) {
        const nc = c + cols < cols * rows ? c + cols : c;
        const dz = (f.head[c] >= 0 && f.head[nc] >= 0) ? 0 : 0;
        col = col.map(v => v * (0.9 + dz));
      }
    } else {
      const fl = f.sFlag[pick];
      if (!pickReached) col = [120, 120, 120];
      else if (fl & S_LAVA) col = [255, 120, 0];
      else if (fl & S_SWIM) col = [50, 110, 220];
      else if (fl & S_WMO) col = [190, 90, 230];
      else col = [90, 170, 70];
      // ombre selon la hauteur voisine (relief)
      const east = x * S + 1 < cols ? c + 1 : c;
      let zE = f.sTop[pick];
      if (f.sStart[east + 1] > f.sStart[east]) zE = f.sTop[f.sStart[east + 1] - 1];
      const sh = Math.max(0.55, Math.min(1.3, 1 + (zE - f.sTop[pick]) * 0.15));
      col = col.map(v => v * sh);
    }
    const i = (y * IW + x) * 3;
    rgb[i] = col[0]; rgb[i + 1] = col[1]; rgb[i + 2] = col[2];
  }
}
// depart (blanc) et points testes (jaune : atteint, rouge vif : pas atteint)
const mark = (n, w, rgbc) => {
  const x = Math.floor(f.colOf(w) / S), y = Math.floor(f.rowOf(n) / S);
  for (let dy = -5; dy <= 5; dy++) for (let dx = -5; dx <= 5; dx++) {
    const px = x + dx, py = y + dy;
    if (px < 0 || py < 0 || px >= IW || py >= IH) continue;
    const e = Math.abs(dx) === 5 || Math.abs(dy) === 5;
    const i = (py * IW + px) * 3;
    rgb[i] = e ? 0 : rgbc[0]; rgb[i + 1] = e ? 0 : rgbc[1]; rgb[i + 2] = e ? 0 : rgbc[2];
  }
};
mark(+sn, +sw, [255, 255, 255]);
const res = [];
for (const pr of (probes || '').split(';').filter(Boolean)) {
  const [pn, pw] = pr.split(',').map(Number);
  // un point est atteint si une surface atteinte est a moins de 6 m
  const col = f.colOf(pw), row = f.rowOf(pn);
  let ok = false;
  for (let r = row - 6; r <= row + 6 && !ok; r++) for (let q = col - 6; q <= col + 6 && !ok; q++) {
    if (r < 0 || q < 0 || r >= rows || q >= cols) continue;
    const k = r * cols + q;
    for (let j = f.sStart[k]; j < f.sStart[k + 1]; j++) if (seen[j]) { ok = true; break; }
  }
  res.push(`${pn},${pw}: ${ok ? 'atteint' : 'PAS atteint'}`);
  mark(pn, pw, ok ? [255, 230, 0] : [255, 0, 0]);
}
fs.writeFileSync(out, png.encode(IW, IH, rgb));
console.log(`${casc.buildName} | tuiles ${tiles.length} | batiments ${placed.size} (${nTri} triangles) | surfaces ${nSurf} | atteintes ${reached} | terrain ${tTerrain} ms, batiments ${tWmo} ms, total ${Date.now() - t0} ms`);
for (const r of res) console.log('  ' + r);
