#!/usr/bin/env node
// Verifies the SQLite twin WITHOUT a server (tracker/db/SCHEMA-SALES.md §6):
//   1. applies sales.sqlite.sql to a fresh file-backed database, TWICE (idempotence);
//   2. loads the contract's xs rows (dates as epoch ms at 00:00 GMT, the D-2 rule);
//   3. checks the views equal the FetchData.e / Sales.e / FetchCrosstab.e literals;
//   4. runs sales.smoke.sqlite.sql and diffs it against sales.smoke.expected-xs.txt;
//   5. checks FK enforcement and the NOT NULL policy reject bad rows.
// Uses node's built-in node:sqlite (node >= 22.5), no dependencies.
// Usage: node data/schema/verify-sqlite.mjs [db-file]   (default: a temp file, removed after)
// Exit 0 = all checks passed; 1 = a check failed (the first failure is printed).

import { DatabaseSync } from 'node:sqlite';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const contract = JSON.parse(read('sales.contract.json'));
const tmp = process.argv[2] ? null : mkdtempSync(join(tmpdir(), 'ermine-sales-'));
const file = process.argv[2] ?? join(tmp, 'sales.db');

let failures = 0;
const check = (name, ok, detail = '') => {
  if (!ok) { failures++; console.error(`FAIL ${name} ${detail}`); }
};
const epoch = (iso) => { const [y, m, d] = iso.split('-').map(Number); return Date.UTC(y, m - 1, d); };

const db = new DatabaseSync(file);
db.exec(read('sales.sqlite.sql'));
db.exec(read('sales.sqlite.sql')); // idempotent: a second run must succeed

db.exec('PRAGMA foreign_keys = ON');
db.exec('BEGIN');
for (const t of contract.loadOrder.map((n) => contract.tables.find((x) => x.name === n))) {
  const cols = t.columns.map((c) => c.name);
  const ins = db.prepare(`INSERT INTO ${t.name} (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`);
  for (const r of t.xs.rows) {
    ins.run(...t.columns.map((c) => {
      const v = r[c.name];
      if (v === null || v === undefined) return null;
      if (c.ermine.endsWith('Date')) return epoch(v);
      if (c.ermine.endsWith('Double')) return Number(v); // REAL
      return v;
    }));
  }
}
db.exec('COMMIT');

// 3. the views equal the literals
const fetchData = [
  ['north', '2026-01-05', 1200.5, 3], ['north', '2026-01-19', 840.0, 2], ['north', '2026-02-14', 2310.25, 7],
  ['south', '2026-01-09', 615.75, 1], ['south', '2026-02-02', 1990.0, 5], ['east', '2026-02-20', 75.5, 1],
  ['east', '2026-03-03', 4100.0, 11], ['west', '2026-03-17', 1550.0, 4],
];
const key = (a) => JSON.stringify(a);
const sales = db.prepare('SELECT region, day, amount, units FROM sales').all()
  .map((r) => key([r.region, new Date(r.day).toISOString().slice(0, 10), r.amount, r.units])).sort();
check('view sales == FetchData.e literal', key(sales) === key(fetchData.map(key).sort()), key(sales));
const salesTypes = db.prepare('SELECT DISTINCT typeof(day) d, typeof(amount) a, typeof(units) u FROM sales').all();
check('view sales column storage classes', key(salesTypes) === key([{ d: 'integer', a: 'real', u: 'integer' }]), key(salesTypes));
const items = db.prepare('SELECT region, day, item FROM sales_items').all().map((r) => `${r.region} ${new Date(r.day).toISOString().slice(0, 10)} ${r.item}`).sort();
const salesE = ['north 2026-01-05 widget', 'north 2026-01-19 gizmo', 'north 2026-02-14 widget', 'south 2026-01-09 doohickey',
  'south 2026-02-02 widget', 'east 2026-02-20 gizmo', 'east 2026-03-03 doohickey', 'west 2026-03-17 widget'].sort();
check('view sales_items == Sales.e items', key(items) === key(salesE), key(items));
const targets = db.prepare('SELECT region, target FROM targets ORDER BY region').all().map((r) => [r.region, r.target]);
check('view targets == FetchData.e literal', key(targets) === key([['east', 2000], ['north', 4000], ['south', 3000], ['west', 2500]]), key(targets));
const cal = db.prepare('SELECT day, monthName FROM calendar ORDER BY day').all().map((r) => [new Date(r.day).toISOString().slice(0, 10), r.monthName]);
const calLit = ['2026-01-05', '2026-01-09', '2026-01-19', '2026-02-02', '2026-02-14', '2026-02-20', '2026-03-03', '2026-03-17'].map((d) => [d, d.slice(0, 7)]);
check('view calendar == FetchCrosstab.e literal', key(cal) === key(calLit), key(cal));
// a filter written the way SqliteEmitter writes it: day >= <epoch ms literal>
const n = db.prepare(`SELECT COUNT(*) n FROM sales WHERE day >= ${epoch('2026-01-05')} AND day <= ${epoch('2026-02-20')}`).get().n;
check('Date literal filter (Sales.e example range) selects 6 rows', n === 6, String(n));

// 4. smoke
const smokeSql = read('sales.smoke.sqlite.sql');
const out = db.prepare(smokeSql.split('\n').filter((l) => !l.startsWith('--')).join('\n').trim().replace(/;$/, '')).all()
  .map((r) => `${r.k}|${r.v}`).join('\n') + '\n';
const expected = read('sales.smoke.expected-xs.txt');
check('smoke output == sales.smoke.expected-xs.txt', out === expected, `\n--- got\n${out}--- expected\n${expected}`);

// 5. integrity rejections
const rejects = (name, sql) => { let threw = false; try { db.exec(sql); } catch { threw = true; } check(name, threw); };
rejects('FK rejects an unknown region', `INSERT INTO dim_rep VALUES (99, 'x', 42, 't', ${epoch('2020-01-01')}, NULL)`);
rejects('NOT NULL rejects NULL lineAmount', `INSERT INTO fact_order_line VALUES (99, 1, ${epoch('2026-01-05')}, 1, 1, 1, 1, 1, 1, 1.0, 0.0, NULL, NULL)`);
rejects('STRICT rejects a text date', `INSERT INTO dim_date VALUES ('2026-04-01', 2026, 2, 4, '2026-04', '2026-Q2', 3, 'Wednesday')`);
rejects('PK rejects a duplicate order line', `INSERT INTO fact_order_line VALUES (1, 1, ${epoch('2026-01-05')}, 1, 1, 1, 1, 1, 1, 1.0, 0.0, 1.0, NULL)`);

const counts = Object.fromEntries([...contract.tables, ...contract.views].map((t) => [t.name, db.prepare(`SELECT COUNT(*) n FROM ${t.name}`).get().n]));
db.close();
if (tmp) rmSync(tmp, { recursive: true, force: true });
console.log(`${failures === 0 ? 'PASS' : 'FAIL'} verify-sqlite: ${failures} failed checks; xs row counts ${JSON.stringify(counts)}`);
process.exit(failures === 0 ? 0 : 1);
