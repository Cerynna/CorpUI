// Champ de hauteurs en colonnes (facon "voxels") d une region du monde :
// chaque colonne de cs x cs metres garde ses tranches solides [bas, haut],
// venues du sol (terrain des tuiles) et des batiments (WMO). On en tire les
// surfaces praticables (dessus d une tranche dont la pente se marche, avec
// assez de place au-dessus) et les passages d une colonne a sa voisine.
// Ecrit pour CorpUI ; meme principe que les generateurs de cartes de
// navigation (Recast), refait simplement.
const A = require('./adt.js');

const F_WALK = 1, F_WMO = 2;
const S_WALK = 1, S_WMO = 2, S_SWIM = 4, S_LAVA = 8, S_OCEAN = 16;

class Field {
  // region : nord max N0, ouest max W0, colonnes vers l est, lignes vers le sud
  constructor(N0, W0, cols, rows, cs, opts = {}) {
    Object.assign(this, { N0, W0, cols, rows, cs });
    this.maxSlope = opts.maxSlope || 50;
    this.walkCos = Math.cos(this.maxSlope * Math.PI / 180);
    this.agentH = opts.agentH || 2.2;
    this.climb = opts.climb || 1.8;
    this.fall = opts.fall || 12;
    this.liquid = opts.liquid || (() => 'water');      // type d eau -> water, ocean, lava
    this.head = new Int32Array(cols * rows).fill(-1);
    this.cap = 1 << 20;
    this.zmin = new Float32Array(this.cap);
    this.zmax = new Float32Array(this.cap);
    this.flag = new Uint8Array(this.cap);
    this.next = new Int32Array(this.cap);
    this.n = 0;
    this.free = -1;
    this.water = new Float32Array(cols * rows).fill(NaN);
    this.wtype = new Uint16Array(cols * rows);
    this.area = new Uint32Array(cols * rows);       // zone du terrain (AreaTable)
  }

  alloc() {
    if (this.free >= 0) { const i = this.free; this.free = this.next[i]; return i; }
    if (this.n >= this.cap) {
      const cap = this.cap * 2;
      for (const k of ['zmin', 'zmax', 'flag', 'next']) {
        const a = new this[k].constructor(cap);
        a.set(this[k]);
        this[k] = a;
      }
      this.cap = cap;
    }
    return this.n++;
  }

  // ajoute une tranche ; fusionne celles qui se touchent (le dessus garde le
  // drapeau de la tranche la plus haute, praticable si les deux hauts sont proches)
  add(col, row, lo, hi, fl) {
    const c = row * this.cols + col;
    let prev = -1, s = this.head[c];
    while (s >= 0) {
      if (this.zmin[s] > hi + 0.1) break;
      if (this.zmax[s] < lo - 0.1) { prev = s; s = this.next[s]; continue; }
      // chevauchement : fusion
      if (Math.abs(this.zmax[s] - hi) <= 0.6) fl |= this.flag[s];
      else if (this.zmax[s] > hi) fl = this.flag[s];
      lo = Math.min(lo, this.zmin[s]);
      hi = Math.max(hi, this.zmax[s]);
      const nx = this.next[s];
      this.next[s] = this.free;
      this.free = s;
      if (prev >= 0) this.next[prev] = nx; else this.head[c] = nx;
      s = nx;
    }
    const i = this.alloc();
    this.zmin[i] = lo; this.zmax[i] = hi; this.flag[i] = fl;
    this.next[i] = s;
    if (prev >= 0) this.next[prev] = i; else this.head[c] = i;
  }

  // colonne d un point du monde
  colOf(west) { return Math.floor((this.W0 - west) / this.cs); }
  rowOf(north) { return Math.floor((this.N0 - north) / this.cs); }

  // terrain d une tuile : hauteur au centre de chaque colonne (4 triangles par
  // case du terrain, autour de son centre), pente du triangle, trous, eau
  addTerrain(adt) {
    const U = A.UNIT, cs = this.cs;
    const water = {};
    for (const w of adt.water) water[w.index] = w.layers;
    for (const ch of adt.chunks) {
      if (!ch.heights) continue;
      const hs = ch.heights;
      const layers = water[ch.iy * 16 + ch.ix] || [];
      const c0 = Math.max(0, Math.ceil((this.W0 - ch.west) / cs - 0.5));
      const c1 = Math.min(this.cols - 1, Math.floor((this.W0 - (ch.west - A.CHUNK)) / cs - 0.5));
      const r0 = Math.max(0, Math.ceil((this.N0 - ch.north) / cs - 0.5));
      const r1 = Math.min(this.rows - 1, Math.floor((this.N0 - (ch.north - A.CHUNK)) / cs - 0.5));
      for (let row = r0; row <= r1; row++) {
        const north = this.N0 - (row + 0.5) * cs;
        const fy = (ch.north - north) / U;            // 0..8 vers le sud
        const r = Math.min(7, Math.floor(fy));
        const v = fy - r;
        for (let col = c0; col <= c1; col++) {
          const west = this.W0 - (col + 0.5) * cs;
          const fx = (ch.west - west) / U;            // 0..8 vers l est
          const q = Math.min(7, Math.floor(fx));
          const u = fx - q;
          this.area[row * this.cols + col] = ch.area;
          if (ch.holes & (1n << BigInt(r * 8 + q))) continue;
          const h00 = A.outer(hs, r, q), h01 = A.outer(hs, r, q + 1), h10 = A.outer(hs, r + 1, q), h11 = A.outer(hs, r + 1, q + 1);
          const hc = A.inner(hs, r, q);
          // triangle : nord (h00,h01), est (h01,h11), sud (h11,h10), ouest (h10,h00)
          let pa, pb, ax, ay, bx, by;
          const du = u - 0.5, dv = v - 0.5;
          if (Math.abs(dv) >= Math.abs(du)) {
            if (dv < 0) { pa = h00; ax = 0; ay = 0; pb = h01; bx = 1; by = 0; } else { pa = h11; ax = 1; ay = 1; pb = h10; bx = 0; by = 1; }
          } else if (du > 0) { pa = h01; ax = 1; ay = 0; pb = h11; bx = 1; by = 1; } else { pa = h10; ax = 0; ay = 1; pb = h00; bx = 0; by = 0; }
          // plan passant par le centre (0.5, 0.5, hc), a et b
          const e1x = (ax - 0.5) * U, e1y = (ay - 0.5) * U, e1z = pa - hc;
          const e2x = (bx - 0.5) * U, e2y = (by - 0.5) * U, e2z = pb - hc;
          const nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x;
          const len = Math.hypot(nx, ny, nz) || 1;
          const px = (u - 0.5) * U, py = (v - 0.5) * U;
          const h = Math.abs(nz) > 1e-6 ? hc - (nx * px + ny * py) / nz : hc;
          const walk = Math.abs(nz) / len >= this.walkCos;
          this.add(col, row, h - 3, h, walk ? F_WALK : 0);
          for (const l of layers) {
            if (l.exists(q, r)) {
              const wl = l.height(q, r);
              const k = row * this.cols + col;
              if (wl > h && (isNaN(this.water[k]) || wl > this.water[k])) { this.water[k] = wl; this.wtype[k] = l.type; }
              break;
            }
          }
        }
      }
    }
  }

  // un triangle (monde : nord, ouest, haut) : decoupe colonne par colonne
  addTri(a, b, c) {
    const cs = this.cs;
    // repere des colonnes : x vers l est, y vers le sud
    const P = [a, b, c].map(p => [(this.W0 - p[1]) / cs, (this.N0 - p[0]) / cs, p[2]]);
    const e1 = [P[1][0] - P[0][0], P[1][1] - P[0][1], P[1][2] - P[0][2]];
    const e2 = [P[2][0] - P[0][0], P[2][1] - P[0][1], P[2][2] - P[0][2]];
    const nx = (e1[1] * e2[2] - e1[2] * e2[1]) * cs, ny = (e1[2] * e2[0] - e1[0] * e2[2]) * cs, nz = (e1[0] * e2[1] - e1[1] * e2[0]) * cs * cs;
    const len = Math.hypot(nx, ny, nz);
    if (len < 1e-9) return;
    const fl = F_WMO | (Math.abs(nz) / len >= this.walkCos ? F_WALK : 0);
    let x0 = Math.min(P[0][0], P[1][0], P[2][0]), x1 = Math.max(P[0][0], P[1][0], P[2][0]);
    let y0 = Math.min(P[0][1], P[1][1], P[2][1]), y1 = Math.max(P[0][1], P[1][1], P[2][1]);
    if (x1 < 0 || y1 < 0 || x0 >= this.cols || y0 >= this.rows) return;
    const ry0 = Math.max(0, Math.floor(y0)), ry1 = Math.min(this.rows - 1, Math.floor(y1));
    let poly = P;
    for (let row = ry0; row <= ry1; row++) {
      const [inRow, rest] = split(poly, 1, row + 1);
      poly = rest;
      if (inRow.length < 3) continue;
      let rp = inRow;
      const xs = rp.map(p => p[0]);
      const rx0 = Math.max(0, Math.floor(Math.min(...xs))), rx1 = Math.min(this.cols - 1, Math.floor(Math.max(...xs)));
      for (let col = rx0; col <= rx1; col++) {
        const [cell, r2] = split(rp, 0, col + 1);
        rp = r2;
        if (cell.length < 3) continue;
        let lo = Infinity, hi = -Infinity;
        for (const p of cell) { if (p[2] < lo) lo = p[2]; if (p[2] > hi) hi = p[2]; }
        this.add(col, row, lo, hi, fl);
      }
    }
  }

  // surfaces praticables de chaque colonne
  surfaces() {
    const n = this.cols * this.rows;
    const start = new Int32Array(n + 1);
    const top = [], ceil = [], flags = [];
    for (let c = 0; c < n; c++) {
      start[c] = top.length;
      const wl = this.water[c];
      for (let s = this.head[c]; s >= 0; s = this.next[s]) {
        const nx = this.next[s];
        const t = this.zmax[s], up = nx >= 0 ? this.zmin[nx] : Infinity;
        if (!(this.flag[s] & F_WALK) && !(wl > t)) continue;
        if (up - t < this.agentH) continue;
        let f = (this.flag[s] & F_WMO) ? S_WMO : S_WALK;
        let z = t;
        const kind = wl > t ? this.liquid(this.wtype[c]) : null;
        if (kind === 'lava' && wl < up) {
          f = S_LAVA;                     // lave, vase : on n y va pas, meme peu profonde
        } else if (wl > t + 1.6 && wl < up) {
          // eau profonde : on nage a la surface
          f = S_SWIM | (kind === 'ocean' ? S_OCEAN : 0);
          z = wl;
        } else if (!(this.flag[s] & F_WALK)) continue;
        top.push(z); ceil.push(up); flags.push(f);
      }
    }
    start[n] = top.length;
    this.sStart = start;
    this.sTop = Float32Array.from(top);
    this.sCeil = Float32Array.from(ceil);
    this.sFlag = Uint8Array.from(flags);
    this.sCol = new Int32Array(top.length);
    for (let c = 0; c < n; c++) for (let i = start[c]; i < start[c + 1]; i++) this.sCol[i] = c;
    return top.length;
  }

  // passages depuis la surface i (8 voisines) : appelle fn(j)
  neighbors(i, fn) {
    const c = this.sCol[i], col = c % this.cols, row = (c - col) / this.cols;
    const t = this.sTop[i], up = this.sCeil[i];
    if (this.sFlag[i] & S_LAVA) return;
    for (let dy = -1; dy <= 1; dy++) {
      const r = row + dy;
      if (r < 0 || r >= this.rows) continue;
      for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dy) continue;
        const q = col + dx;
        if (q < 0 || q >= this.cols) continue;
        const k = r * this.cols + q;
        for (let j = this.sStart[k]; j < this.sStart[k + 1]; j++) {
          if (this.sFlag[j] & S_LAVA) continue;
          const dz = this.sTop[j] - t;
          if (dz > this.climb || dz < -this.fall) continue;
          if (Math.min(up, this.sCeil[j]) - Math.max(t, this.sTop[j]) < this.agentH) continue;
          fn(j);
        }
      }
    }
  }

  // surface la plus proche d un point (z inconnu : celle du dessus)
  surfaceAt(north, west, z) {
    const col = this.colOf(west), row = this.rowOf(north);
    let best = -1, bd = Infinity;
    for (let r = row - 3; r <= row + 3; r++) {
      for (let q = col - 3; q <= col + 3; q++) {
        if (r < 0 || q < 0 || r >= this.rows || q >= this.cols) continue;
        const k = r * this.cols + q;
        for (let j = this.sStart[k]; j < this.sStart[k + 1]; j++) {
          const d = Math.hypot(r - row, q - col) * this.cs + (z === undefined ? -this.sTop[j] * 0.01 : Math.abs(this.sTop[j] - z));
          if (d < bd) { bd = d; best = j; }
        }
      }
    }
    return best;
  }

  // surfaces atteignables depuis une surface (parcours en largeur)
  reach(seed) {
    const seen = new Uint8Array(this.sTop.length);
    const queue = new Int32Array(this.sTop.length);
    let qh = 0, qt = 0;
    seen[seed] = 1;
    queue[qt++] = seed;
    while (qh < qt) {
      const i = queue[qh++];
      this.neighbors(i, j => {
        if (!seen[j]) { seen[j] = 1; queue[qt++] = j; }
      });
    }
    return seen;
  }
}

// coupe un polygone par la droite axe = v : [partie < v, partie >= v]
function split(poly, axis, v) {
  const a = [], b = [];
  for (let i = 0; i < poly.length; i++) {
    const p = poly[i], q = poly[(i + 1) % poly.length];
    const pa = p[axis] < v, qa = q[axis] < v;
    if (pa) a.push(p); else b.push(p);
    if (pa !== qa) {
      const t = (v - p[axis]) / (q[axis] - p[axis]);
      const m = [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t];
      a.push(m); b.push(m);
    }
  }
  return [a, b];
}

module.exports = { Field, S_WALK, S_WMO, S_SWIM, S_LAVA, S_OCEAN };
