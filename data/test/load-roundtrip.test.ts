// A hand-made two-table sample (parent/child FK, a view, NULLs, "" strings,
// quoted commas and quotes, a leading space, non-ASCII text, awkward floats,
// ("" only in a NOT NULL column: SQL Server's BULK INSERT loads a quoted "" in
// a NULLABLE column as NULL, MEASURED, tracker/db/LOADER.md known gaps),
// dates) through the loaders: SQLite always; SQL Server only when
// `scripts/db.sh status` is OK (the test is then SKIPPED by name).  The MSSQL
// run uses ErmineScience with loader_sample_* tables and removes them again.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { loadContract } from "../src/contract.js";
import { line, type Cell } from "../src/lib/csv.js";
import type { DomainFiles } from "../src/load/paths.js";
import { loadSqlite, verifySqlite } from "../src/load/sqlite.js";
import { LOAD_DIR, sql, status } from "../src/load/dbsh.js";
import { load, unload, verify } from "../src/load/mssql.js";

const P = "loader_sample_parent", C = "loader_sample_child", V = "loader_sample_v";
const col = (name: string, ermine: string, nullable = false, maxLength?: number) => ({ name, ermine, nullable, ...(maxLength ? { maxLength } : {}) });
const parentCols = [col("id", "Int"), col("name", "String", false, 40), col("since", "Date"), col("weight", "Double")];
const childCols = [col("id", "Int"), col("parentId", "Int"), col("note", "Nullable String", true, 40), col("score", "Nullable Int", true), col("amount", "Double")];
const parentRows: Cell[][] = [
  [1, "Zoë 中文", "2026-01-05", 0.1], [2, 'a,b "q"', "1999-02-28", 0.30000000000000004],
  [3, " lead", "2026-12-31", 123456789.12345679], [4, "", "2000-02-29", -2310.25],
];
const childRows: Cell[][] = [
  [10, 1, null, null, 1200.5], [11, 1, "e", 7, 0.0000001], [12, 2, "x, y", null, 840],
  [13, 3, "Ωmega", -3, 1e15], [14, 4, "  both  ", 0, 75.5],
];

function sample(): { dir: string; files: DomainFiles; contractPath: string } {
  const dir = mkdtempSync(join(tmpdir(), "ermine-loader-sample-"));
  const tables = [
    { name: C, kind: "table", pk: ["id"], unique: [], fks: [{ columns: ["parentId"], ref: P, refColumns: ["id"] }], rows: { s: childRows.length }, columns: childCols, xs: { rows: [] } },
    { name: P, kind: "table", pk: ["id"], unique: [["name"]], fks: [], rows: { s: parentRows.length }, columns: parentCols, xs: { rows: [] } },
  ];
  const contract = { version: 1, domain: "loadersample", database: "ErmineScience", tiers: { s: { factRows: 5, dateRange: "" } },
    loadOrder: [P, C], tables, views: [{ name: V, columns: [col("name", "String"), col("amount", "Double")] }], xsPinned: {} };
  const contractPath = join(dir, "loadersample.contract.json");
  writeFileSync(contractPath, JSON.stringify(contract));
  const man: Record<string, { file: string; rows: number; bytes: number; sha256: string }> = {};
  for (const [name, cols, rows] of [[P, parentCols, parentRows], [C, childCols, childRows]] as const) {
    const text = line(cols.map((c) => c.name)) + rows.map((r) => line(r)).join("");
    const b = Buffer.from(text, "utf8");
    writeFileSync(join(dir, `${name}.csv`), b);
    man[name] = { file: `${name}.csv`, rows: rows.length, bytes: b.length, sha256: createHash("sha256").update(b).digest("hex") };
  }
  writeFileSync(join(dir, "manifest.json"), JSON.stringify({ generator: "hand-made", domain: "loadersample", database: "ErmineScience", tier: "s", seed: 42,
    factRows: 5, dateRange: "", contractVersion: 1, contractSha256: "-", tables: man }));
  writeFileSync(join(dir, "mssql.sql"), `SET NOCOUNT ON;
DROP VIEW IF EXISTS dbo.${V};
DROP TABLE IF EXISTS dbo.${C};
DROP TABLE IF EXISTS dbo.${P};
GO
CREATE TABLE dbo.${P} ([id] int NOT NULL PRIMARY KEY, [name] nvarchar(40) NOT NULL UNIQUE, [since] date NOT NULL, [weight] float NOT NULL);
CREATE TABLE dbo.${C} ([id] int NOT NULL PRIMARY KEY, [parentId] int NOT NULL REFERENCES dbo.${P} ([id]), [note] nvarchar(40) NULL, [score] int NULL, [amount] float NOT NULL);
GO
CREATE VIEW dbo.${V} AS SELECT p.name, SUM(c.amount) AS amount FROM dbo.${C} AS c JOIN dbo.${P} AS p ON p.id = c.parentId GROUP BY p.name;
GO
`);
  writeFileSync(join(dir, "sqlite.sql"), `PRAGMA foreign_keys = ON;
DROP VIEW IF EXISTS ${V}; DROP TABLE IF EXISTS ${C}; DROP TABLE IF EXISTS ${P};
CREATE TABLE ${P} (id INTEGER NOT NULL PRIMARY KEY, name TEXT NOT NULL UNIQUE, since INTEGER NOT NULL, weight REAL NOT NULL) STRICT;
CREATE TABLE ${C} (id INTEGER NOT NULL PRIMARY KEY, parentId INTEGER NOT NULL REFERENCES ${P} (id), note TEXT, score INTEGER, amount REAL NOT NULL) STRICT;
CREATE VIEW ${V} AS SELECT p.name, SUM(c.amount) AS amount FROM ${C} AS c JOIN ${P} AS p ON p.id = c.parentId GROUP BY p.name;
`);
  const none = join(dir, "none");
  return { dir, contractPath, files: { mssqlDdl: join(dir, "mssql.sql"), sqliteDdl: join(dir, "sqlite.sql"), mssqlSmoke: none, sqliteSmoke: none, expectedXs: none } };
}

test("round trip, SQLite: the sample loads in FK order, dumps equal the CSVs, and a changed value is caught", async () => {
  const { dir, files, contractPath } = sample();
  try {
    const c = loadContract("loadersample", contractPath);
    const log: string[] = [];
    const db = join(dir, "sample.sqlite");
    const r = await loadSqlite(c, { tier: "s", seed: 42, from: dir, db }, (s) => log.push(s), files);
    assert.ok(r.ok, log.join("\n"));
    assert.equal(r.rows, 9);
    assert.match(log[0]!, new RegExp(`^insert ${P} rows=4`), "parent first although the contract lists the child first");
    assert.ok(log.some((l) => l.startsWith(`table ${C} rows=5 manifest=5 sha256=`) && l.includes("csv=same")), log.join("\n"));
    assert.ok(log.some((l) => l === `view ${V} rows=4`), log.join("\n"));
    const h = new DatabaseSync(db);
    assert.deepEqual({ ...(h.prepare(`SELECT name FROM ${P} WHERE id = 4`).get() as object) }, { name: "" });
    assert.deepEqual({ ...(h.prepare(`SELECT note, score FROM ${C} WHERE id = 10`).get() as object) }, { note: null, score: null });
    assert.equal((h.prepare(`SELECT since FROM ${P} WHERE id = 1`).get() as { since: number }).since, Date.UTC(2026, 0, 5));
    h.exec(`UPDATE ${P} SET weight = 0.1000000000000001 WHERE id = 1`);
    h.close();
    const log2: string[] = [];
    assert.equal(verifySqlite(c, dir, db, (s) => log2.push(s), files), false);
    assert.ok(log2.some((l) => l.startsWith(`table ${P}`) && l.includes("DIFFERS")), log2.join("\n"));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

const live = status().ok;
test("round trip, SQL Server (skipped when db.sh status is not OK)", { skip: live ? false : "db.sh status is not OK" }, async () => {
  const { dir, files, contractPath } = sample();
  const c = loadContract("loadersample", contractPath);
  try {
    const log: string[] = [];
    const r = await load(c, { tier: "s", seed: 42, from: dir }, (s) => log.push(s), files);
    assert.ok(r.ok, log.join("\n"));
    assert.match(log.find((l) => l.startsWith("bulk "))!, new RegExp(`^bulk ${P} rows=4 manifest=4`));
    assert.ok(log.some((l) => l.startsWith(`table ${C} rows=5`) && l.includes("csv=same")), log.join("\n"));
    assert.ok(log.some((l) => /^fk count=\d+ not-trusted=0 disabled=0/.test(l)), log.join("\n"));
    assert.ok(!existsSync(join(LOAD_DIR, "loadersample")), "the stage dir is removed after a good load");
    sql(c.database, `UPDATE dbo.${C} SET note = N'changed' WHERE id = 12`);
    const log2: string[] = [];
    assert.equal(verify(c, (s) => log2.push(s), files), false);
    assert.ok(log2.some((l) => l.startsWith(`table ${C}`) && l.includes("DIFFERS")), log2.join("\n"));
  } finally {
    const log3: string[] = [];
    const ok = unload(c, (s) => log3.push(s));
    rmSync(dir, { recursive: true, force: true });
    assert.ok(ok, log3.join("\n"));
    assert.match(log3[0]!, /tables=0 views=0 stamp=0/);
  }
});
