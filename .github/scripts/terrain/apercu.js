// Apercu du terrain d une region : relief ombre, pentes trop raides (rouge),
// trous du sol (noir), eau (bleu ; peu profonde : bleu clair ; magma, vase),
// points de vol (carres blancs). Une case du jeu (4,17 m) = un pixel.
//
// Usage :
//   node apercu.js <dossier WoW> <produit> <carte: Azeroth|Kalimdor> <nord max> <nord min> <ouest max> <ouest min> <sortie.png>
//   ex. node apercu.js "D:/Games/World of Warcraft" wow_classic_beta Azeroth -4300 -6700 1000 -3800 dun_morogh.png
const fs = require('fs');
const path = require('path');
const { Casc } = require('./casc.js');
const A = require('./adt.js');
const png = require('./png.js');

const MAPS = { Azeroth: { wdt: 775971, cont: 0 }, Kalimdor: { wdt: 782779, cont: 1 }, Zephras: { wdt: 7198644, cont: 2991 } };
const SLOPE = Math.tan(50 * Math.PI / 180);      // pente maximale a pied
const SHALLOW = 1.6;                              // m d eau : on marche encore

const [, , wow, product, mapName, nMax, nMin, wMax, wMin, out] = process.argv;
const N0 = +nMax, N1 = +nMin, W0 = +wMax, W1 = +wMin;
const casc = new Casc(wow, product);
const map = MAPS[mapName];
const tiles = A.readWdt(casc.file(map.wdt));

const W = Math.round((W0 - W1) / A.UNIT), H = Math.round((N0 - N1) / A.UNIT);
const rgb = new Uint8ClampedArray(W * H * 3);
// fond : mer
for (let i = 0; i < W * H; i++) { rgb[i * 3] = 18; rgb[i * 3 + 1] = 28; rgb[i * 3 + 2] = 48; }
const put = (px, py, r, g, b) => {
  if (px < 0 || py < 0 || px >= W || py >= H) return;
  const i = (py * W + px) * 3;
  rgb[i] = r; rgb[i + 1] = g; rgb[i + 2] = b;
};

let read = 0, steep = 0, cells = 0;
const t0 = Date.now();
for (const t of tiles) {
  const tn = (32 - t.row) * A.TILE, tw = (32 - t.col) * A.TILE;
  if (tn - A.TILE > N0 || tn < N1 || tw - A.TILE > W0 || tw < W1) continue;
  const buf = casc.file(t.root);
  if (!buf) continue;
  read++;
  const adt = A.readAdt(buf);
  const water = {};
  for (const wt of adt.water) water[wt.index] = wt.layers;
  for (const ch of adt.chunks) {
    if (!ch.heights) continue;
    const hs = ch.heights;
    const layers = water[ch.iy * 16 + ch.ix] || [];
    for (let r = 0; r < 8; r++) {
      for (let q = 0; q < 8; q++) {
        const north = ch.north - (r + 0.5) * A.UNIT, west = ch.west - (q + 0.5) * A.UNIT;
        const px = Math.floor((W0 - west) / A.UNIT), py = Math.floor((N0 - north) / A.UNIT);
        if (px < 0 || py < 0 || px >= W || py >= H) continue;
        cells++;
        const h00 = A.outer(hs, r, q), h01 = A.outer(hs, r, q + 1), h10 = A.outer(hs, r + 1, q), h11 = A.outer(hs, r + 1, q + 1);
        const hc = A.inner(hs, r, q);
        // pente : gradient moyen, et vers le centre (diagonale / 2)
        const de = ((h01 + h11) - (h00 + h10)) / (2 * A.UNIT);   // vers l est
        const ds = ((h10 + h11) - (h00 + h01)) / (2 * A.UNIT);   // vers le sud
        let s = Math.hypot(de, ds);
        const half = A.UNIT * Math.SQRT1_2;
        for (const h of [h00, h01, h10, h11]) s = Math.max(s, Math.abs(hc - h) / half);
        // ombre : lumiere du nord-ouest
        const shade = Math.max(0.25, Math.min(1.25, 0.8 + (de - ds) * 0.6));
        if (ch.holes & (1n << BigInt(r * 8 + q))) { put(px, py, 0, 0, 0); continue; }
        let wl = null;
        for (const l of layers) if (l.exists(q, r)) { wl = l; break; }
        if (wl) {
          const depth = wl.height(q, r) - hc;
          const k = shade;
          if (wl.type === 3 || wl.type === 7 || wl.type === 19) put(px, py, 230 * k, 110 * k, 20 * k);          // magma
          else if (wl.type === 4 || wl.type === 20) put(px, py, 90 * k, 170 * k, 40 * k);                       // vase
          else if (depth < SHALLOW) put(px, py, 90 * k, 160 * k, 220 * k);                                      // gue
          else if (wl.type === 2 || wl.type === 14) put(px, py, 25 * k, 55 * k, 130 * k);                       // ocean
          else put(px, py, 40 * k, 90 * k, 190 * k);                                                            // eau
          continue;
        }
        if (s > SLOPE) { steep++; put(px, py, 200 * shade, 50 * shade, 40 * shade); }
        else put(px, py, 120 * shade, 135 * shade, 95 * shade);
      }
    }
  }
}

// points de vol (tables du jeu, Donnees.lua du module Voyage)
const donnees = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'CorpUI_Voyage', 'Voyage', 'Donnees.lua'), 'utf8');
let nodes = 0;
for (const m of donnees.matchAll(/\[(\d+)\] = "(-?\d+),(-?[\d.]+),(-?[\d.]+),(\d+)(?:,-?[\d.]+)?"/g)) {
  if (+m[2] !== map.cont) continue;
  const px = Math.floor((W0 - +m[4]) / A.UNIT), py = Math.floor((N0 - +m[3]) / A.UNIT);
  if (px < 0 || py < 0 || px >= W || py >= H) continue;
  nodes++;
  for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
    const edge = Math.abs(dx) === 4 || Math.abs(dy) === 4;
    put(px + dx, py + dy, edge ? 0 : 255, edge ? 0 : 255, edge ? 0 : 255);
  }
}
fs.writeFileSync(out, png.encode(W, H, rgb));
console.log(`${casc.buildName} | ${mapName} | tuiles lues ${read} | cases ${cells} | trop raides ${(100 * steep / Math.max(1, cells)).toFixed(1)} % | points de vol ${nodes} | ${W}x${H} | ${Date.now() - t0} ms`);
