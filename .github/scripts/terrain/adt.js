// Cartes du monde (WDT) et tuiles de terrain (ADT) du client.
// Ecrit pour CorpUI d apres la description publique des formats (wowdev.wiki).
//
// Monde : x vers le nord, y vers l ouest (comme les tables du jeu et l API) ;
// une tuile fait 533,33 m, decoupee en 16 x 16 morceaux (MCNK) de 8 x 8
// cases de 4,17 m. Tuile (col, lig) : nord = (32 - lig) * TILE, ouest = (32 - col) * TILE.
const TILE = 1600 / 3;
const CHUNK = TILE / 16;
const UNIT = CHUNK / 8;

// morceaux "MAGIC" (stockes a l envers dans le fichier) : { magic, at, size }
function chunks(buf, from = 0, to = buf.length) {
  const out = [];
  let pos = from;
  while (pos + 8 <= to) {
    const magic = buf.toString('ascii', pos, pos + 4).split('').reverse().join('');
    const size = buf.readUInt32LE(pos + 4);
    out.push({ magic, at: pos + 8, size });
    pos += 8 + size;
  }
  return out;
}

// WDT : tuiles presentes et numeros de leurs fichiers
function readWdt(buf) {
  const tiles = [];
  for (const c of chunks(buf)) {
    if (c.magic === 'MAID') {
      for (let i = 0; i < 4096; i++) {
        const p = c.at + i * 32;
        const root = buf.readUInt32LE(p);
        if (!root) continue;
        tiles.push({ col: i % 64, row: Math.floor(i / 64), root, obj0: buf.readUInt32LE(p + 4), obj1: buf.readUInt32LE(p + 8),
                     tex0: buf.readUInt32LE(p + 12), lod: buf.readUInt32LE(p + 16), minimap: buf.readUInt32LE(p + 28) });
      }
    }
  }
  return tiles;
}

// ADT racine : hauteurs des 256 morceaux, trous, eau
//   -> { chunks: [ { ix, iy, north, west, base, heights: Float32Array(145), holes: bits 8x8 (BigInt), area } ],
//        water: [ { ix, iy, layers: [ { type, min, max, x, y, w, h, exists(fn), height(fn) } ] } ] }
function readAdt(buf) {
  const out = { chunks: [], water: [] };
  for (const c of chunks(buf)) {
    if (c.magic === 'MCNK') {
      const h = c.at;
      const flags = buf.readUInt32LE(h);
      const ch = {
        ix: buf.readUInt32LE(h + 4), iy: buf.readUInt32LE(h + 8),
        area: buf.readUInt32LE(h + 0x34),
        north: buf.readFloatLE(h + 0x68), west: buf.readFloatLE(h + 0x6c), base: buf.readFloatLE(h + 0x70),
        holes: 0n,
      };
      if (flags & 0x10000) {
        ch.holes = buf.readBigUInt64LE(h + 0x14);
      } else {
        // anciens trous : 4 x 4, chacun couvre 2 x 2 cases
        const low = buf.readUInt16LE(h + 0x3c);
        let bits = 0n;
        for (let r = 0; r < 8; r++) {
          for (let q = 0; q < 8; q++) {
            if (low & (1 << ((r >> 1) * 4 + (q >> 1)))) bits |= 1n << BigInt(r * 8 + q);
          }
        }
        ch.holes = bits;
      }
      for (const s of chunks(buf, h + 0x80, c.at + c.size)) {
        if (s.magic === 'MCVT') {
          ch.heights = new Float32Array(145);
          for (let i = 0; i < 145; i++) ch.heights[i] = buf.readFloatLE(s.at + i * 4) + ch.base;
        }
      }
      out.chunks.push(ch);
    } else if (c.magic === 'MH2O') {
      const base = c.at;
      for (let i = 0; i < 256; i++) {
        const p = base + i * 12;
        const ofs = buf.readUInt32LE(p), count = buf.readUInt32LE(p + 4);
        if (!ofs || !count) continue;
        const layers = [];
        for (let l = 0; l < count; l++) {
          const q = base + ofs + l * 24;
          const type = buf.readUInt16LE(q), lvf = buf.readUInt16LE(q + 2);
          const min = buf.readFloatLE(q + 4), max = buf.readFloatLE(q + 8);
          const x = buf[q + 12], y = buf[q + 13], w = buf[q + 14], hh = buf[q + 15];
          const exOfs = buf.readUInt32LE(q + 16), vOfs = buf.readUInt32LE(q + 20);
          const exists = (cx, cy) => {
            if (cx < x || cy < y || cx >= x + w || cy >= y + hh) return false;
            if (!exOfs) return true;
            const bit = (cy - y) * w + (cx - x);
            return (buf[base + exOfs + (bit >> 3)] >> (bit & 7)) & 1;
          };
          // hauteur de l eau a un sommet (formats 0 et 1 : hauteurs en tete)
          const height = (vx, vy) => {
            if (vOfs && lvf <= 1 && min !== max) {
              const k = (vy - y) * (w + 1) + (vx - x);
              if (k >= 0 && k < (w + 1) * (hh + 1)) return buf.readFloatLE(base + vOfs + k * 4);
            }
            return max;
          };
          layers.push({ type, lvf, min, max, x, y, w, h: hh, exists, height });
        }
        out.water.push({ index: i, layers });
      }
    }
  }
  return out;
}

// hauteur d un sommet exterieur (lig 0-8, col 0-8) ou du centre d une case (0-7)
function outer(heights, r, q) { return heights[r * 17 + q]; }
function inner(heights, r, q) { return heights[r * 17 + 9 + q]; }

module.exports = { TILE, CHUNK, UNIT, chunks, readWdt, readAdt, outer, inner };
