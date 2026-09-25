// The D13 twin: the same CSVs into a file-backed SQLite database with
// node:sqlite (no sqlite3 CLI on this box), sales.sqlite.sql as the DDL
// (STRICT tables, Date = INTEGER epoch ms at 00:00 GMT), and the same verify
// as the SQL Server side: counts vs manifest, sha256 dumps vs the CSVs, the
// FK check and the smoke file.

import { DatabaseSync } from "node:sqlite";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { baseType, type Column, type Contract } from "../contract.js";
import { Digest } from "./canon.js";
import { csvRows, type Field } from "./csvstream.js";
import { compareCounts, readManifest, type Manifest } from "./manifest.js";
import { csvDigestSync, DUMP_MAX, loadOrder, smoke } from "./mssql.js";
import { domainFiles, type DomainFiles } from "./paths.js";
import { LoadError, prepare } from "./prepare.js";

type Log = (s: string) => void;

export function sqliteFile(dir: string, domain: string): string { return join(dir, `${domain}.sqlite`); }

export function epochMs(iso: string): number {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) throw new Error(`not a YYYY-MM-DD date: ${iso}`);
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

export function sqliteValue(c: Column, v: Field): string | number | null {
  if (v === null) return null;
  switch (baseType(c.ermine)) {
    case "Int": case "Double": {
      const n = Number(v);
      if (v.trim() === "" || !Number.isFinite(n)) throw new Error(`${c.name}: not a number: ${v}`);
      return n;
    }
    case "Date": return epochMs(v);
    default: return v;
  }
}

export interface SqliteLoadOpts { tier: string; seed: number; from?: string; db?: string }

export async function loadSqlite(c: Contract, o: SqliteLoadOpts, log: Log = console.log, files: DomainFiles = domainFiles(c)): Promise<{ rows: number; ms: number; ok: boolean; file: string }> {
  const t0 = Date.now();
  const order = loadOrder(c);
  const p = await prepare(c, o.tier, o.seed, o.from, log);
  const file = o.db ?? sqliteFile(p.dir, c.domain);
  for (const f of [file, `${file}-journal`, `${file}-wal`, `${file}-shm`]) rmSync(f, { force: true });
  const db = new DatabaseSync(file);
  let rows = 0, ok = true;
  try {
    db.exec(readFileSync(files.sqliteDdl, "utf8"));
    db.exec("PRAGMA foreign_keys = ON; PRAGMA synchronous = OFF; PRAGMA journal_mode = MEMORY;");
    for (const name of order) {
      const t = c.tables.find((x) => x.name === name)!;
      const tt = Date.now();
      const ins = db.prepare(`INSERT INTO ${name} (${t.columns.map((x) => x.name).join(", ")}) VALUES (${t.columns.map(() => "?").join(", ")})`);
      let n = 0, header = true;
      db.exec("BEGIN");
      try {
        for await (const row of csvRows(join(p.dir, p.manifest.tables[name]!.file))) {
          if (header) { header = false; if (row.join(",") !== t.columns.map((x) => x.name).join(",")) throw new LoadError(`${name}: CSV header differs from the contract`, 1); continue; }
          if (row.length !== t.columns.length) throw new LoadError(`${name} row ${n + 1}: ${row.length} fields, ${t.columns.length} columns`, 1);
          ins.run(...t.columns.map((col, i) => sqliteValue(col, row[i]!)));
          n++;
        }
        db.exec("COMMIT");
      } catch (e) { db.exec("ROLLBACK"); throw e; }
      const want = p.manifest.tables[name]!.rows, good = n === want;
      ok &&= good; rows += n;
      log(`insert ${name} rows=${n} manifest=${want} ms=${Date.now() - tt} ${good ? "OK" : "MISMATCH"}`);
    }
  } finally { db.close(); }
  if (!ok) throw new LoadError("row counts differ from the manifest", 1);
  const loadMs = Date.now() - t0;
  const v = verifySqlite(c, p.dir, file, log, files);
  log(`load ${c.domain} sqlite tier=${p.manifest.tier} seed=${p.manifest.seed ?? "-"} rows=${rows} load=${(loadMs / 1000).toFixed(2)}s rows/s=${Math.round(rows / (loadMs / 1000))} file=${file} verify=${v ? "OK" : "FAILED"}`);
  return { rows, ms: loadMs, ok: v, file };
}

export function verifySqlite(c: Contract, dir: string, file: string, log: Log = console.log, files: DomainFiles = domainFiles(c)): boolean {
  if (!existsSync(file)) { log(`verify ${c.domain} sqlite: no ${file}`); return false; }
  const m: Manifest = readManifest(dir);
  const db = new DatabaseSync(file);
  let ok = true;
  try {
    const counts: Record<string, number> = {};
    for (const n of [...c.tables.map((t) => t.name), ...c.views.map((v) => v.name)]) counts[n] = Number((db.prepare(`SELECT COUNT(*) AS n FROM ${n}`).get() as { n: number }).n);
    const cc = compareCounts(m, counts, c.tables.map((t) => t.name));
    for (const t of c.tables) {
      const r = cc.find((x) => x.table === t.name)!;
      let good = r.ok, dump = `dump=skipped(>${DUMP_MAX})`;
      if ((r.expected ?? 0) <= DUMP_MAX) {
        const d = new Digest(t.columns);
        const cols = t.columns.map((x) => x.name);
        for (const row of db.prepare(`SELECT ${cols.join(", ")} FROM ${t.name} ORDER BY ${t.pk.join(", ")}`).all() as Record<string, string | number | null>[]) d.add(cols.map((k) => row[k] ?? null));
        const csv = csvDigestSync(dir, m, t);
        const same = d.hex() === csv.hex();
        good &&= same;
        dump = `sha256=${d.hex().slice(0, 16)} csv=${same ? "same" : csv.hex().slice(0, 16) + " DIFFERS"}`;
      }
      ok &&= good;
      log(`table ${t.name} rows=${r.actual} manifest=${r.expected} ${dump} ${good ? "OK" : "FAIL"}`);
    }
    for (const v of c.views) log(`view ${v.name} rows=${counts[v.name]}`);
    const fkBad = db.prepare("PRAGMA foreign_key_check").all().length;
    const fkN = c.tables.reduce((s, t) => s + t.fks.length, 0);
    ok &&= fkBad === 0;
    log(`fk count=${fkN} violations=${fkBad} ${fkBad === 0 ? "OK" : "FAIL"}`);
    if (existsSync(files.sqliteSmoke)) {
      const smokeSql = readFileSync(files.sqliteSmoke, "utf8").split("\n").filter((l) => !l.startsWith("--")).join("\n").trim().replace(/;$/, "");
      const out = (db.prepare(smokeSql).all() as { k: string; v: string }[]).map((r) => `${r.k}|${r.v}`);
      ok = smoke(c, m.tier, m, out, log, files.expectedXs) && ok;
    } else log("smoke none (no smoke file)");
  } finally { db.close(); }
  log(`verify ${c.domain} sqlite tier=${m.tier} seed=${m.seed ?? "-"} file=${file} ${ok ? "OK" : "FAILED"}`);
  return ok;
}

export function fileSha(file: string): string { return createHash("sha256").update(readFileSync(file)).digest("hex"); }
