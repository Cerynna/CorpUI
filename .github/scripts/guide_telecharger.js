// Telecharge les guides de leveling de WoW Forever Tools (ceux qu affiche
// ConquestCapped) dans .prive/wft, pour guide_donnees.js.
// Ces guides n ont pas de licence : ils restent sur ce poste. .prive/ et les
// donnees generees sont ignores par git, et CorpUI_Guide n est pas dans le
// paquet (HORS_PAQUET de release.yml).
//   - index : data/leveling.<langue>.json (un guide par race, faction,
//     classe, avec ou sans donjons) ;
//   - guide : data/leveling/<cle>.<langue>.json = liste de morceaux ;
//   - morceau : data/leveling/c/<hash>.json = etapes (HTML) par tranche de
//     niveaux, partage entre guides (deja telecharge : garde).
// Usage (Git Bash, depuis le depot) :
//   node .github/scripts/guide_telecharger.js [langue=fr]
const fs = require('fs');
const path = require('path');

const BASE = 'https://wowforevertools.vercel.app/data/';
const LANG = process.argv[2] || 'fr';
const DIR = path.join(__dirname, '..', '..', '.prive', 'wft');
const PARALLEL = 4;

fs.mkdirSync(path.join(DIR, 'c'), { recursive: true });

async function get(rel, file, keep) {
    const out = path.join(DIR, file);
    if (keep && fs.existsSync(out)) return JSON.parse(fs.readFileSync(out, 'utf8'));
    for (let essai = 1; ; essai++) {
        try {
            const r = await fetch(BASE + rel);
            if (!r.ok) throw new Error(r.status + ' ' + rel);
            const txt = await r.text();
            const data = JSON.parse(txt);
            fs.writeFileSync(out, txt);
            return data;
        } catch (e) {
            if (essai >= 3) throw e;
            await new Promise(ok => setTimeout(ok, 1000 * essai));
        }
    }
}

async function parLots(items, fn) {
    let i = 0;
    const travail = async () => { while (i < items.length) { const it = items[i++]; await fn(it); } };
    await Promise.all(Array.from({ length: PARALLEL }, travail));
}

(async () => {
    const index = await get(`leveling.${LANG}.json`, `leveling.${LANG}.json`, false);
    await get('races.json', 'races.json', false);
    const cles = Object.keys(index);
    const morceaux = new Set();
    await parLots(cles, async cle => {
        const g = await get(`leveling/${cle}.${LANG}.json`, `${cle}.${LANG}.json`, false);
        for (const c of g.chunks || []) morceaux.add(c);
    });
    let neufs = 0;
    const liste = [...morceaux];
    await parLots(liste, async c => {
        const f = path.join('c', c + '.json');
        if (!fs.existsSync(path.join(DIR, f))) neufs++;
        await get(`leveling/c/${c}.json`, f, true);
    });
    console.log(`${cles.length} guides, ${liste.length} morceaux (${neufs} nouveaux) dans ${DIR}`);
})().catch(e => { console.error(e.message); process.exit(1); });
