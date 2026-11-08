// Genere CorpUI_Guide/Donnees/Guides.lua (ignore par git, usage prive) a
// partir des guides de WoW Forever Tools telecharges par guide_telecharger.js.
//   - parties (tranches de niveaux) dedoublonnees entre guides : G.E ;
//   - guides : race, faction, classe, avec donjons ou non, liste de parties ;
//   - noms des quetes, PNJ, objets, sorts une seule fois : G.Q, G.N, G.I, G.S ;
//   - zone de chaque partie : carte du jeu (UiMap en francais, wago.tools) ;
//     partie sans zone : zone citee dans son titre, sinon aucune.
// Etapes en texte balise (HTML du site converti) :
//   {qaN} quete a prendre, {qtN} a rendre, {qoN} a faire, {qxN} a abandonner,
//   {qN} quete citee ; {nN} PNJ, {mN} monstre, {iN} objet, {sN} sort, {slN}
//   sort a apprendre ; {@x,y} coordonnees (zone de la partie) ; {l:texte}
//   lieu, {N:texte} PNJ, {M:texte} monstre, {I:texte} objet, {S:texte} sort
//   sans numero ; {c:Hunter} reserve a une race ou une classe ; {vN} niveau
//   N atteint (cache) ; {!} : la suite est une remarque.
// Le role d une quete vient du verbe le plus proche avant elle dans la meme
// proposition (Acceptez, Rendez, Abandonnez, Tuez...).
//
// Usage (Git Bash, depuis le depot) :
//   node .github/scripts/guide_telecharger.js fr
//   B=1.60.1.70790; D=/tmp/guide; mkdir -p $D
//   curl -s "https://wago.tools/db2/UiMap/csv?build=$B&locale=frFR" -o $D/UiMap.frFR.csv
//   node .github/scripts/guide_donnees.js $D/UiMap.frFR.csv [fr]
const fs = require('fs');
const path = require('path');

const UIMAP = process.argv[2];
const LANG = process.argv[3] || 'fr';
const SRC = path.join(__dirname, '..', '..', '.prive', 'wft');
const OUT = path.join(__dirname, '..', '..', 'CorpUI_Guide', 'Donnees', 'Guides.lua');

// ---------------------------------------------------------------- cartes
function csvRows(txt) {
    const rows = [];
    for (const line of txt.split(/\r?\n/)) {
        if (!line) continue;
        const r = [];
        let cur = '', q = false;
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (q) {
                if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; }
                else if (ch === '"') q = false;
                else cur += ch;
            } else if (ch === '"') q = true;
            else if (ch === ',') { r.push(cur); cur = ''; }
            else cur += ch;
        }
        r.push(cur);
        rows.push(r);
    }
    return rows;
}
const norm = s => s.toLowerCase().replace(/[’']/g, "'").normalize('NFC').trim();
const MAPS = new Map();           // nom -> uiMapID (zones du systeme 0)
{
    const rows = csvRows(fs.readFileSync(UIMAP, 'utf8'));
    const h = rows.shift();
    const col = n => h.indexOf(n);
    for (const r of rows) {
        if (r[col('Type')] !== '3' || r[col('System')] !== '0') continue;
        const k = norm(r[col('Name_lang')]);
        if (!MAPS.has(k)) MAPS.set(k, +r[col('ID')]);
    }
}
// orthographes du site et sous-zones citees dans les titres de parties
const ALIAS = {
    'hautes-terres arathies': 1417, 'feralas': 1444,
    'camp mojache': 1444, 'pennelune': 1444, 'hache-tripes': 1444, 'colosses jumeaux': 1444, 'thalanaar': 1444,
    'griffes farouches': 1444, 'côte oubliée': 1444, 'griffebois': 1444, 'gordunni': 1444, 'isildien': 1444,
    'crique de faldir': 1417, "trépas-d'orgrim": 1417, 'pierres de lien': 1417, 'stromgarde': 1417,
    'rochepoing': 1417, 'clé de voûte': 1417, 'dalaran': 1416, 'theramore': 1445, 'gadgetzan': 1446,
    'carmines': 1433, 'auberdine': 1439,
};
for (const [k, id] of Object.entries(ALIAS)) if (!MAPS.has(k)) MAPS.set(k, id);
const ZONE_NAMES = [...MAPS.keys()].sort((a, b) => b.length - a.length);
const zoneProblems = new Map();
function zoneOf(st) {
    if (st.zone) {
        const id = MAPS.get(norm(st.zone));
        if (!id) zoneProblems.set(st.zone, (zoneProblems.get(st.zone) || 0) + 1);
        return { name: st.zone, id: id || 0 };
    }
    const t = norm(st.title);
    for (const k of ZONE_NAMES) if (t.includes(k)) return { name: null, id: MAPS.get(k) };
    return { name: null, id: 0 };
}

// ---------------------------------------------------------------- texte
const Q = new Map(), N = new Map(), I = new Map(), S = new Map();
const unknownTags = new Map();
const decode = s => s.replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16))).replace(/&amp;/g, '&');
const unbracket = s => s.replace(/^\[/, '').replace(/\]$/, '');
const put = (map, id, name) => { if (!map.has(id) && name) map.set(id, name); };

const ACCEPT = ['acceptez', 'prenez', 'reprenez'];
const TURNIN = ['rendez', 'rendez-la', 'rendez-le', 'rendez-lui', 'rendez-les', 'remettez', 'remettez-la',
    'remettez-le', 'remettez-les', 'apportez', 'apportez-la', 'rapportez', 'rapportez-la', 'livrez'];
const ABANDON = ['abandonnez', 'abandonnez-la'];
const OBJECTIVE = ['tuez', 'tuez-le', 'tuez-les', 'terminez', 'terminez-la', 'finissez', 'complétez', 'faites',
    'ramassez', 'récupérez', 'fouillez', 'utilisez', 'utilisez-la', 'utilisez-le', 'nettoyez', 'atteignez',
    'explorez', 'trouvez', 'pillez', 'ouvrez', 'cliquez', 'parlez', 'escortez', 'protégez', 'détruisez',
    'collectez', 'cueillez', 'capturez', 'ciblez', 'lancez', 'placez', 'allumez', 'éteignez', 'continuez'];
const VERB = new Map();
for (const w of ACCEPT) VERB.set(w, 'a');
for (const w of TURNIN) VERB.set(w, 't');
for (const w of ABANDON) VERB.set(w, 'x');
for (const w of OBJECTIVE) VERB.set(w, 'o');

// role d une quete d apres le texte qui la precede (proposition en cours)
function roleBefore(text) {
    const plain = text.replace(/\{@[^}]*\}/g, ' ').replace(/\{[^}]*\}/g, ' X ');
    const clause = plain.split(/[.!?;:](?!\d)|\bsi\b|\bsinon\b/i).pop().toLowerCase();
    const words = clause.split(/[\s,«»()]+/).filter(Boolean);
    for (let i = words.length - 1; i >= 0; i--) {
        const w = words[i];
        if (w === 'rendez-vous') continue;
        if (VERB.has(w)) return VERB.get(w);
    }
    return '';
}

const roles = { a: 0, t: 0, o: 0, x: 0, '': 0 };
function convert(html) {
    let s = html.replace(/<<([^<>]+)>>/g, '{c:$1}');
    // remarque finale : separee
    let note = null;
    const ni = s.indexOf('<span class="note">');
    if (ni >= 0 && /<\/span>\s*$/.test(s)) {
        note = s.slice(ni + '<span class="note">'.length).replace(/<\/span>\s*$/, '');
        s = s.slice(0, ni);
    }
    const one = part => {
        let out = '';
        let last = 0;
        const re = /<(a|button|b|span)\b([^>]*)>([\s\S]*?)<\/\1>/g;
        let m;
        while ((m = re.exec(part))) {
            out += decode(part.slice(last, m.index).replace(/<[^>]*>/g, t => { unknownTags.set(t, (unknownTags.get(t) || 0) + 1); return ''; }));
            last = re.lastIndex;
            const [, tag, attrs, inner] = m;
            const cls = (attrs.match(/class="([^"]*)"/) || [])[1];
            const wh = (attrs.match(/data-wh="(\w+)=(\d+)"/) || []);
            const txt = decode(inner.replace(/<[^>]*>/g, ''));
            if (tag === 'a' && cls === 'q' && wh[2]) {
                put(Q, +wh[2], txt);
                const r = roleBefore(out);
                roles[r]++;
                out += `{q${r}${wh[2]}}`;
            } else if (tag === 'a' && cls === 'npc' && wh[2]) { put(N, +wh[2], txt); out += `{n${wh[2]}}`; }
            else if (tag === 'a' && cls === 'mob' && wh[2]) { put(N, +wh[2], txt); out += `{m${wh[2]}}`; }
            else if (tag === 'a' && cls === 'item' && wh[2]) { put(I, +wh[2], unbracket(txt)); out += `{i${wh[2]}}`; }
            else if (tag === 'a' && cls === 'spell' && wh[2]) {
                put(S, +wh[2], unbracket(txt));
                const learn = /(apprenez|entraînez|entrainez|achetez)[^.;]*$/i.test(out);
                out += `{s${learn ? 'l' : ''}${wh[2]}}`;
            } else if (tag === 'button' && cls === 'xy') {
                const w = attrs.match(/data-way="\/way ([\d.]+) ([\d.]+)"/);
                out += w ? `{@${w[1]},${w[2]}}` : txt;
            } else if (tag === 'b' && cls === 'loc') out += `{l:${txt}}`;
            else if (tag === 'b' && cls === 'npc') out += `{N:${txt}}`;
            else if (tag === 'b' && cls === 'mob') out += `{M:${txt}}`;
            else if (tag === 'span' && cls === 'item') out += `{I:${unbracket(txt)}}`;
            else if (tag === 'span' && cls === 'spell') out += `{S:${unbracket(txt)}}`;
            else if (tag === 'b' && !cls) out += txt;
            else {
                // balise inconnue ou imbriquee : contenu garde, converti
                unknownTags.set(`<${tag} class=${cls}>`, (unknownTags.get(`<${tag} class=${cls}>`) || 0) + 1);
                out += one(inner);
            }
        }
        out += decode(part.slice(last).replace(/<[^>]*>/g, t => { unknownTags.set(t, (unknownTags.get(t) || 0) + 1); return ''; }));
        return out;
    };
    let text = one(s).replace(/\s+/g, ' ').trim();
    const lvl = text.match(/(?:jusqu'au|atteignez le|au) niveau (\d+)/i);
    if (lvl) text += `{v${lvl[1]}}`;
    if (note !== null) {
        const n = one(note).replace(/\s+/g, ' ').trim().replace(/^REMARQUE\s*:\s*/i, '');
        text += '{!}' + n;
    }
    return text;
}

// ---------------------------------------------------------------- guides
const index = JSON.parse(fs.readFileSync(path.join(SRC, `leveling.${LANG}.json`), 'utf8'));
const chunkCache = new Map();
const chunk = id => {
    if (!chunkCache.has(id)) chunkCache.set(id, JSON.parse(fs.readFileSync(path.join(SRC, 'c', id + '.json'), 'utf8')));
    return chunkCache.get(id);
};
const stageIds = new Map();       // contenu -> numero
const stages = [];
const guides = [];
const mismatch = [];
for (const key of Object.keys(index)) {
    const meta = index[key];
    const g = JSON.parse(fs.readFileSync(path.join(SRC, `${key}.${LANG}.json`), 'utf8'));
    const list = [];
    for (const c of g.chunks) for (const st of chunk(c)) {
        const k = JSON.stringify([st.title, st.zone || null, st.steps]);
        if (!stageIds.has(k)) {
            const z = zoneOf(st);
            stages.push({ title: decode(st.title), zone: z.name ? decode(z.name) : null, map: z.id, steps: st.steps.map(convert) });
            stageIds.set(k, stages.length);
        }
        list.push(stageIds.get(k));
    }
    if (list.length !== meta.stages.length) mismatch.push(`${key}: ${list.length} / ${meta.stages.length}`);
    guides.push({ key, meta, list });
}

// ---------------------------------------------------------------- Lua
const lstr = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"';
const dict = (name, map) => {
    const ids = [...map.keys()].sort((a, b) => a - b);
    return `G.${name} = {\n` + ids.map(id => `[${id}]=${lstr(map.get(id))},`).join('\n') + '\n}\n';
};
let lua = `-- Genere par .github/scripts/guide_donnees.js : guides de WoW Forever Tools
-- (ConquestCapped), langue ${LANG}. Usage prive : fichier ignore par git, hors
-- paquet. Ne pas modifier a la main.
local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end
local G = {}
ns.GuideData = G
G.LANG = ${lstr(LANG)}
`;
lua += dict('Q', Q) + dict('N', N) + dict('I', I) + dict('S', S);
lua += 'G.E = {\n' + stages.map(st =>
    `{${lstr(st.title)},${st.map},${st.zone ? lstr(st.zone) : 'false'},{\n` + st.steps.map(s => lstr(s) + ',').join('\n') + '\n}},'
).join('\n') + '\n}\n';
lua += 'G.G = {\n' + guides.map(({ key, meta, list }) => {
    const f = [`k=${lstr(key)}`, `f=${lstr(meta.faction)}`];
    if (meta.race) f.push(`r=${lstr(meta.race)}`);
    if (meta.class) f.push(`c=${lstr(meta.class)}`);
    if (meta.variant === 'dungeons') f.push('d=true');
    if (meta.reference === 'dungeons') f.push('ref=true');
    if (meta.levels) f.push(`lv=${lstr(meta.levels)}`);
    if (meta.from) f.push(`from=${lstr(decode(meta.from))}`);
    f.push(`e={${list.join(',')}}`);
    return '{' + f.join(',') + '},';
}).join('\n') + '\n}\n';

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, lua);
const steps = stages.reduce((n, st) => n + st.steps.length, 0);
console.log(`${guides.length} guides, ${stages.length} parties, ${steps} etapes, ${Q.size} quetes, ${N.size} PNJ, ${I.size} objets, ${S.size} sorts`);
console.log(`roles des quetes : prendre ${roles.a}, rendre ${roles.t}, faire ${roles.o}, abandonner ${roles.x}, cite ${roles['']}`);
console.log(`${OUT} : ${(lua.length / 1048576).toFixed(2)} Mo`);
if (mismatch.length) console.log('nombre de parties different : ' + mismatch.join(' ; '));
if (zoneProblems.size) console.log('zones sans carte : ' + [...zoneProblems].map(([z, n]) => `${z} (${n})`).join(', '));
const noMap = stages.filter(st => !st.map).length;
console.log(`parties sans carte : ${noMap}`);
if (unknownTags.size) console.log('balises ignorees : ' + [...unknownTags].map(([t, n]) => `${t} ${n}`).join(', '));
