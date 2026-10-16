// Batiments, ponts, grottes, villes (WMO) : triangles de collision, places
// dans le monde par les entrees MODF des tuiles (fichier obj0).
// Ecrit pour CorpUI d apres la description publique des formats (wowdev.wiki).
const { chunks } = require('./adt.js');

const MID = 32 * 1600 / 3;      // 17066,67 : centre du repere de placement

// racine : numeros des fichiers de groupes
function readRoot(buf) {
  let nGroups = 0, gfid = [];
  for (const c of chunks(buf)) {
    if (c.magic === 'MOHD') nGroups = buf.readUInt32LE(c.at + 4);
    else if (c.magic === 'GFID') {
      for (let i = 0; i < c.size / 4; i++) gfid.push(buf.readUInt32LE(c.at + i * 4));
    }
  }
  return { nGroups, groups: gfid.slice(0, nGroups) };
}

// groupe : triangles de collision (repere du modele) -> Float32Array, 9 nombres par triangle
function readGroup(buf) {
  const top = chunks(buf).find(c => c.magic === 'MOGP');
  if (!top) return new Float32Array(0);
  let mopy = null, movi = null, movt = null, mopyStride = 2;
  for (const s of chunks(buf, top.at + 0x44, top.at + top.size)) {
    if (s.magic === 'MOPY') { mopy = s; mopyStride = 2; }
    else if (s.magic === 'MPY2') { mopy = s; mopyStride = 4; }
    else if (s.magic === 'MOVI') movi = { at: s.at, size: s.size, wide: false };
    else if (s.magic === 'MOVX') movi = { at: s.at, size: s.size, wide: true };
    else if (s.magic === 'MOVT') movt = s;
  }
  if (!movi || !movt) return new Float32Array(0);
  const nTri = movi.size / (movi.wide ? 12 : 6);
  const out = [];
  for (let i = 0; i < nTri; i++) {
    if (mopy) {
      const flags = mopyStride === 2 ? buf[mopy.at + i * 2] : buf.readUInt16LE(mopy.at + i * 4);
      const render = (flags & 0x20) && !(flags & 0x04);
      if (!(flags & 0x08) && !render) continue;          // ni collision ni rendu solide
    }
    for (let k = 0; k < 3; k++) {
      const idx = movi.wide ? buf.readUInt32LE(movi.at + (i * 3 + k) * 4) : buf.readUInt16LE(movi.at + (i * 3 + k) * 2);
      const p = movt.at + idx * 12;
      out.push(buf.readFloatLE(p), buf.readFloatLE(p + 4), buf.readFloatLE(p + 8));
    }
  }
  return Float32Array.from(out);
}

// placements d une tuile (obj0) : { fdid, pos, rot (degres), scale }
function readPlacements(buf) {
  const out = [];
  for (const c of chunks(buf)) {
    if (c.magic !== 'MODF') continue;
    for (let i = 0; i < c.size / 64; i++) {
      const p = c.at + i * 64;
      const flags = buf.readUInt16LE(p + 56);
      out.push({
        fdid: buf.readUInt32LE(p), uid: buf.readUInt32LE(p + 4), byId: (flags & 0x8) !== 0,
        pos: [buf.readFloatLE(p + 8), buf.readFloatLE(p + 12), buf.readFloatLE(p + 16)],
        rot: [buf.readFloatLE(p + 20), buf.readFloatLE(p + 24), buf.readFloatLE(p + 28)],
        scale: (flags & 0x4) ? buf.readUInt16LE(p + 62) / 1024 : 1,
      });
    }
  }
  return out;
}

// repere du modele -> monde (nord, ouest, haut) : position (pos.z, pos.x, pos.y)
// dans le repere interne, rotation Z(rot.y) * Y(rot.x) * X(rot.z), puis
// nord = MID - x, ouest = MID - y
function transform(pl) {
  const d = Math.PI / 180;
  const az = pl.rot[1] * d, ay = pl.rot[0] * d, ax = pl.rot[2] * d;
  const cz = Math.cos(az), sz = Math.sin(az), cy = Math.cos(ay), sy = Math.sin(ay), cx = Math.cos(ax), sx = Math.sin(ax);
  // Rz * Ry * Rx
  const m = [
    cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx,
    sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx,
    -sy, cy * sx, cy * cx,
  ];
  const tx = pl.pos[2], ty = pl.pos[0], tz = pl.pos[1], s = pl.scale;
  return (x, y, z) => {
    const ix = tx + s * (m[0] * x + m[1] * y + m[2] * z);
    const iy = ty + s * (m[3] * x + m[4] * y + m[5] * z);
    const iz = tz + s * (m[6] * x + m[7] * y + m[8] * z);
    return [MID - ix, MID - iy, iz];
  };
}

// cache des modeles (un modele sert a plusieurs placements)
function loader(casc) {
  const cache = new Map();
  return fdid => {
    if (cache.has(fdid)) return cache.get(fdid);
    let tris = null;
    const rb = casc.file(fdid);
    if (rb) {
      const root = readRoot(rb);
      const parts = [];
      for (const g of root.groups) {
        const gb = casc.file(g);
        if (gb) parts.push(readGroup(gb));
      }
      const n = parts.reduce((a, p) => a + p.length, 0);
      tris = new Float32Array(n);
      let o = 0;
      for (const p of parts) { tris.set(p, o); o += p.length; }
    }
    cache.set(fdid, tris);
    return tris;
  };
}

module.exports = { readRoot, readGroup, readPlacements, transform, loader, MID };
