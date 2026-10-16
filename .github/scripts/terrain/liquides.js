// Nature des eaux du client (table LiquidType du jeu, export CSV de wago.tools) :
// "ocean" (son de la mer), "lava" (lave, vase, gangrene : matiere 2 ou 13),
// sinon "water". Sans table : tout est de l eau douce.
const fs = require('fs');

function parseCsv(text) {
  const rows = [];
  let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; } else field += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field.replace(/\r$/, '')); rows.push(row); row = []; field = ''; }
    else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows;
}

function liquidKinds(csvPath) {
  const kinds = new Map();
  if (csvPath && fs.existsSync(csvPath)) {
    const rows = parseCsv(fs.readFileSync(csvPath, 'utf8'));
    const head = rows.shift();
    const col = n => head.indexOf(n);
    for (const r of rows) {
      const id = +r[col('ID')], sound = +r[col('SoundBank')], mat = +r[col('MaterialID')];
      kinds.set(id, (mat === 2 || mat === 13 || sound === 2 || sound === 3) ? 'lava' : sound === 1 ? 'ocean' : 'water');
    }
  }
  return type => kinds.get(type) || 'water';
}

module.exports = { liquidKinds, parseCsv };
