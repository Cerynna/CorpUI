// Lecture du stockage local du jeu (CASC, dossier Data de l installation) :
// rien n est telecharge, on lit les fichiers du client deja installe.
//
//   .build.info       -> cle de la build du produit (wow_classic_beta, wowf...)
//   Data/config       -> fichier de build : cles de l encodage et de la racine
//   Data/data/*.idx   -> index locaux (16 seaux) : cle encodee -> archive, position, taille
//   Data/data/data.N  -> archives : en-tete de 30 octets puis bloc BLTE
//   encodage          -> cle de contenu -> cle encodee
//   racine            -> numero de fichier (FileDataID) -> cle de contenu
//
// Ecrit pour CorpUI d apres la description publique des formats (wowdev.wiki).
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function blte(buf) {
  if (buf.readUInt32BE(0) !== 0x424c5445) throw new Error('pas un bloc BLTE');
  const headerSize = buf.readUInt32BE(4);
  const chunks = [];
  let pos;
  if (headerSize > 0) {
    const flags = buf[8];
    const count = buf.readUIntBE(9, 3);
    const entry = flags === 0x10 ? 40 : 24;
    let p = 12;
    for (let i = 0; i < count; i++) {
      chunks.push({ comp: buf.readUInt32BE(p), size: buf.readUInt32BE(p + 4) });
      p += entry;
    }
    pos = headerSize;
  } else {
    chunks.push({ comp: buf.length - 8, size: -1 });
    pos = 8;
  }
  const out = [];
  for (const c of chunks) {
    const data = buf.subarray(pos, pos + c.comp);
    pos += c.comp;
    const mode = data[0];
    if (mode === 0x4e) out.push(data.subarray(1));                       // N : brut
    else if (mode === 0x5a) out.push(zlib.inflateSync(data.subarray(1))); // Z : zlib
    else if (mode === 0x46) out.push(blte(data.subarray(1)));            // F : bloc imbrique
    else if (mode === 0x45) throw new Error('bloc chiffre');              // E : chiffre
    else throw new Error('mode BLTE inconnu : ' + String.fromCharCode(mode));
  }
  return Buffer.concat(out);
}

class Casc {
  constructor(wowDir, product) {
    this.dir = wowDir;
    this.data = path.join(wowDir, 'Data', 'data');
    const info = fs.readFileSync(path.join(wowDir, '.build.info'), 'utf8').split(/\r?\n/).filter(Boolean);
    const head = info[0].split('|').map(h => h.split('!')[0]);
    const rows = info.slice(1).map(l => {
      const o = {};
      l.split('|').forEach((v, i) => { o[head[i]] = v; });
      return o;
    });
    const row = rows.find(r => r.Product === product);
    if (!row) throw new Error('produit absent de .build.info : ' + product);
    this.version = row.Version;
    const key = row['Build Key'];
    const cfg = fs.readFileSync(path.join(wowDir, 'Data', 'config', key.slice(0, 2), key.slice(2, 4), key), 'utf8');
    this.config = {};
    for (const l of cfg.split(/\r?\n/)) {
      const m = l.match(/^([\w-]+) = (.*)$/);
      if (m) this.config[m[1]] = m[2].split(' ');
    }
    this.buildName = (this.config['build-name'] || [])[0];
    this.loadIndexes();
    this.fds = {};
  }

  // index locaux : la version la plus recente de chaque seau
  loadIndexes() {
    const latest = {};
    for (const f of fs.readdirSync(this.data)) {
      const m = f.match(/^([0-9a-f]{2})([0-9a-f]{8})\.idx$/i);
      if (!m) continue;
      const b = parseInt(m[1], 16), v = parseInt(m[2], 16);
      if (!latest[b] || v > latest[b].v) latest[b] = { v, f };
    }
    this.buckets = [];
    for (let b = 0; b < 16; b++) {
      if (!latest[b]) continue;
      const buf = fs.readFileSync(path.join(this.data, latest[b].f));
      const hashSize = buf.readUInt32LE(0);
      let pos = (8 + hashSize + 0x0f) & ~0x0f;
      const len = buf.readUInt32LE(pos);
      pos += 8;
      // cle (9 octets) -> entree ; une Map par seau
      const map = new Map();
      for (let i = 0; i < Math.floor(len / 18); i++, pos += 18) {
        const k = buf.toString('hex', pos, pos + 9);
        if (map.has(k)) continue;
        const hi = buf[pos + 9], lo = buf.readUInt32BE(pos + 10);
        map.set(k, { archive: (hi << 2) | (lo >>> 30), offset: lo & 0x3fffffff, size: buf.readUInt32LE(pos + 14) });
      }
      this.buckets[b] = map;
    }
  }

  static bucketOf(hex) {
    let x = 0;
    for (let i = 0; i < 9; i++) x ^= parseInt(hex.substr(i * 2, 2), 16);
    return (x & 0xf) ^ (x >> 4);
  }

  // cle encodee -> contenu decode (null si absent du stockage local)
  readEKey(ekey) {
    const k = ekey.slice(0, 18).toLowerCase();
    let e = this.buckets[Casc.bucketOf(k)] && this.buckets[Casc.bucketOf(k)].get(k);
    if (!e) {
      for (const m of this.buckets) if (m && m.has(k)) { e = m.get(k); break; }
    }
    if (!e) return null;
    const name = 'data.' + String(e.archive).padStart(3, '0');
    if (!this.fds[name]) this.fds[name] = fs.openSync(path.join(this.data, name), 'r');
    const buf = Buffer.alloc(e.size);
    fs.readSync(this.fds[name], buf, 0, e.size, e.offset);
    return blte(buf.subarray(30));
  }

  // encodage : pages triees par premiere cle de contenu (recherche a la demande)
  loadEncoding() {
    if (this.enc) return;
    const buf = this.readEKey(this.config.encoding[1]);
    if (!buf || buf.toString('ascii', 0, 2) !== 'EN') throw new Error('encodage illisible');
    const ckeySize = buf[3], ekeySize = buf[4];
    const pageSize = buf.readUInt16BE(5) * 1024;
    const pageCount = buf.readUInt32BE(9);
    const especSize = buf.readUInt32BE(18);
    let pos = 22 + especSize;
    const firsts = [];
    for (let i = 0; i < pageCount; i++, pos += ckeySize + 16) firsts.push(buf.toString('hex', pos, pos + ckeySize));
    this.enc = { buf, ckeySize, ekeySize, pageSize, firsts, pages: pos };
  }

  ekeyOf(ckey) {
    this.loadEncoding();
    const { buf, ckeySize, ekeySize, pageSize, firsts, pages } = this.enc;
    ckey = ckey.toLowerCase();
    let lo = 0, hi = firsts.length - 1, page = 0;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (firsts[mid] <= ckey) { page = mid; lo = mid + 1; } else hi = mid - 1;
    }
    let pos = pages + page * pageSize;
    const end = pos + pageSize;
    while (pos < end) {
      const n = buf[pos];
      if (n === 0) break;
      const ck = buf.toString('hex', pos + 6, pos + 6 + ckeySize);
      if (ck === ckey) return buf.toString('hex', pos + 6 + ckeySize, pos + 6 + ckeySize + ekeySize);
      pos += 6 + ckeySize + n * ekeySize;
    }
    return null;
  }

  readCKey(ckey) {
    const ek = this.ekeyOf(ckey);
    return ek ? this.readEKey(ek) : null;
  }

  // racine : numero de fichier -> cle de contenu (toutes langues ou frFR/enUS)
  loadRoot() {
    if (this.root) return;
    const buf = this.readCKey(this.config.root[0]);
    if (!buf) throw new Error('racine illisible');
    const root = new Map();
    let pos = 0;
    const magic = buf.toString('ascii', 0, 4);
    if (magic !== 'TSFM') throw new Error('format de racine non gere : ' + magic);
    let version = 1, total, named;
    const second = buf.readUInt32LE(4);
    if (second === 0x18) {
      version = buf.readUInt32LE(8); total = buf.readUInt32LE(12); named = buf.readUInt32LE(16); pos = 0x18;
    } else {
      total = second; named = buf.readUInt32LE(8); pos = 12;
    }
    const nameless = total !== named;
    const LOCALES = 0x2 | 0x10;      // enUS, frFR
    while (pos < buf.length) {
      const n = buf.readUInt32LE(pos);
      let content, locale;
      if (version === 2) {
        locale = buf.readUInt32LE(pos + 4);
        content = buf.readUInt32LE(pos + 8) | buf.readUInt32LE(pos + 12) | (buf[pos + 16] << 17);
        pos += 17;
      } else {
        content = buf.readUInt32LE(pos + 4);
        locale = buf.readUInt32LE(pos + 8);
        pos += 12;
      }
      const ids = new Array(n);
      let id = 0;
      for (let i = 0; i < n; i++, pos += 4) {
        ids[i] = id + buf.readInt32LE(pos);
        id = ids[i] + 1;
      }
      const keysAt = pos;
      pos += 16 * n;
      if (!(nameless && (content & 0x10000000))) pos += 8 * n;
      if ((locale & LOCALES) === 0 || (content & 0x80)) continue;    // autre langue, ou violence reduite
      for (let i = 0; i < n; i++) if (!root.has(ids[i])) root.set(ids[i], keysAt + 16 * i);
    }
    this.root = root;
    this.rootBuf = buf;
  }

  // fichier par numero (null si absent)
  file(fdid) {
    this.loadRoot();
    const at = this.root.get(fdid);
    if (at === undefined) return null;
    return this.readCKey(this.rootBuf.toString('hex', at, at + 16));
  }
}

module.exports = { Casc, blte };
