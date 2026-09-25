// SQL Server side: stage -> DDL (as ermine) -> BULK INSERT per table in FK
// order (as sa: `ermine` lacks ADMINISTER BULK OPERATIONS, Msg 4834) -> stamp
// -> verify.  unload drops the domain's views and tables, never the database.

import { chmodSync, createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { once } from "node:events";
import { join } from "node:path";
import { baseType, type Contract, type Table } from "../contract.js";
import { bracket, bulkInsertSql, nstring, rowsAffected } from "./bulk.js";
import { Digest } from "./canon.js";
import { parseAll } from "./csvstream.js";
import { createHash } from "node:crypto";
import { LOAD_DIR, LOAD_MOUNT, lines, sql, sqlFile, SqlError } from "./dbsh.js";
import { compareCounts, manifestSha, readManifest, type Manifest } from "./manifest.js";
import { fkOrder, respectsFks } from "./order.js";
import { domainFiles, type DomainFiles } from "./paths.js";
import { LoadError, prepare } from "./prepare.js";

/** The load stamp: a database-level extended property per domain (JSON), so verify reads what is really loaded. */
export const stampName = (domain: string) => `ermine.load.${domain}`;
/** Tables up to this many rows get the sha256 dump comparison in verify. */
export const DUMP_MAX = Number(process.env.ERMINE_DUMP_MAX ?? 20000);

export interface Stamp { domain: string; tier: string; seed: number | null; dir: string; manifestSha256: string; loadedAt: string }

type Log = (s: string) => void;

/** UTF-8 CSV -> UTF-16LE with a BOM (bulk.ts says why), world-readable for the container's uid. */
export async function stageFile(src: string, dst: string): Promise<void> {
  const out = createWriteStream(dst, { mode: 0o644 });
  out.write(Buffer.from([0xff, 0xfe]));
  for await (const chunk of createReadStream(src, { encoding: "utf8", highWaterMark: 1 << 20 })) {
    if (!out.write(Buffer.from(chunk as string, "utf16le"))) await once(out, "drain");
  }
  out.end(); await once(out, "finish");
  chmodSync(dst, 0o644);
}

function stageDir(domain: string): string { return join(LOAD_DIR, domain); }

export function loadOrder(c: Contract): string[] {
  const order = fkOrder(c.tables);
  const bad = respectsFks(c.loadOrder, c.tables);
  if (bad) throw new LoadError(`contract loadOrder is not an FK order: ${bad}`, 2);
  return order;
}

function stampSql(c: Contract, s: Stamp | null): string {
  const n = nstring(stampName(c.domain));
  const drop = `IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 0 AND name = ${n}) EXEC sys.sp_dropextendedproperty @name = ${n};`;
  return s ? `${drop} EXEC sys.sp_addextendedproperty @name = ${n}, @value = ${nstring(JSON.stringify(s))};` : drop;
}

export function readStamp(c: Contract): Stamp | null {
  const r = lines(sql(c.database, `SET NOCOUNT ON; SELECT CAST(value AS nvarchar(4000)) FROM sys.extended_properties WHERE class = 0 AND name = ${nstring(stampName(c.domain))}`, ["-h", "-1", "-W", "-y", "0"]));
  return r.length ? JSON.parse(r[0]!) as Stamp : null;
}

export interface LoadOpts { tier: string; seed: number; from?: string }

export async function load(c: Contract, o: LoadOpts, log: Log = console.log, files: DomainFiles = domainFiles(c)): Promise<{ rows: number; ms: number; ok: boolean }> {
  const t0 = Date.now();
  const order = loadOrder(c);
  const p = await prepare(c, o.tier, o.seed, o.from, log);
  // stage
  const tS = Date.now();
  const sd = stageDir(c.domain);
  rmSync(sd, { recursive: true, force: true });
  mkdirSync(sd, { recursive: true, mode: 0o755 }); chmodSync(sd, 0o755);
  for (const t of order) await stageFile(join(p.dir, p.manifest.tables[t]!.file), join(sd, `${t}.csv`));
  const stageMs = Date.now() - tS;
  // DDL as ermine (idempotent drop/create); the old stamp goes first so a failed load leaves none
  sql(c.database, stampSql(c, null));
  const ddl = sqlFile(c.database, files.mssqlDdl, ["-b"]);
  log(`ddl ${c.database} ${files.mssqlDdl.replace(/.*\/data\//, "data/")} ms=${ddl.ms.toFixed(0)} stage=${sd} ms=${stageMs}`);
  // BULK INSERT in FK order, as sa
  let rows = 0, ok = true;
  for (const name of order) {
    const t = c.tables.find((x) => x.name === name)!;
    const stmt = bulkInsertSql({ database: c.database, schema: "dbo", table: name, file: `${LOAD_MOUNT}/${c.domain}/${name}.csv`, keepNulls: t.columns.some((x) => x.nullable) });
    let r;
    try { r = sql(c.database, stmt, [], { sa: true }); }
    catch (e) { throw new LoadError(`bulk ${name}: ${(e as Error).message}`, e instanceof SqlError ? e.code : 5); }
    const n = rowsAffected(r.out), want = p.manifest.tables[name]!.rows;
    const good = n === want; ok &&= good; rows += n ?? 0;
    log(`bulk ${name} rows=${n} manifest=${want} ms=${r.ms.toFixed(0)} ${good ? "OK" : "MISMATCH"}`);
  }
  if (!ok) throw new LoadError("row counts differ from the manifest (see the bulk lines)", 1);
  const stamp: Stamp = { domain: c.domain, tier: p.manifest.tier, seed: p.manifest.seed, dir: p.dir, manifestSha256: manifestSha(p.dir), loadedAt: new Date().toISOString() };
  sql(c.database, stampSql(c, stamp));
  rmSync(sd, { recursive: true, force: true });  // data/out keeps the source of truth
  const loadMs = Date.now() - t0;
  const v = verify(c, log, files);
  const ms = Date.now() - t0;
  log(`load ${c.domain} mssql tier=${p.manifest.tier} seed=${p.manifest.seed ?? "-"} rows=${rows} load=${(loadMs / 1000).toFixed(2)}s rows/s=${Math.round(rows / (loadMs / 1000))} total=${(ms / 1000).toFixed(2)}s verify=${v ? "OK" : "FAILED"}`);
  return { rows, ms: loadMs, ok: v };
}

/** One SELECT per row rendering it as a JSON array; floats as 17-digit strings (style 3). */
export function dumpSql(database: string, t: Table): string {
  const cell = (name: string, ermine: string) => {
    const c = bracket(name);
    switch (baseType(ermine)) {
      case "Int": return `ISNULL(CAST(${c} AS varchar(20)), 'null')`;
      case "Double": return `ISNULL('"' + CONVERT(varchar(30), ${c}, 3) + '"', 'null')`;
      case "Date": return `ISNULL('"' + CONVERT(char(10), ${c}, 23) + '"', 'null')`;
      default: return `ISNULL(N'"' + STRING_ESCAPE(${c}, 'json') + N'"', N'null')`;
    }
  };
  const parts = t.columns.flatMap((x, i) => [...(i ? ["','"] : []), cell(x.name, x.ermine)]);
  return `SET NOCOUNT ON; SELECT CONCAT('[', ${parts.join(", ")}, ']') FROM ${bracket(database)}.[dbo].${bracket(t.name)} ORDER BY ${t.pk.map(bracket).join(", ")};`;
}

/** Prints one line per table, per view, then fk, smoke and a verdict line; true = all OK. */
export function verify(c: Contract, log: Log = console.log, files: DomainFiles = domainFiles(c)): boolean {
  const stamp = readStamp(c);
  if (!stamp) { log(`verify ${c.domain} mssql: nothing loaded (no ${stampName(c.domain)} stamp on ${c.database})`); return false; }
  let ok = true;
  const m = readManifest(stamp.dir);
  if (manifestSha(stamp.dir) !== stamp.manifestSha256) { log(`manifest ${stamp.dir}: changed since the load (regenerated?)`); ok = false; }
  const names = [...c.tables.map((t) => t.name), ...c.views.map((v) => v.name)];
  const cq = names.map((n) => `SELECT N'${n}', COUNT_BIG(*) FROM [dbo].${bracket(n)}`).join(" UNION ALL ");
  const counts: Record<string, number> = {};
  for (const l of lines(sql(c.database, `SET NOCOUNT ON; ${cq};`, ["-h", "-1", "-W", "-s", "|"]))) {
    const [k, v] = l.split("|"); counts[k!] = Number(v);
  }
  const cc = compareCounts(m, counts, c.tables.map((t) => t.name));
  for (const t of c.tables) {
    const r = cc.find((x) => x.table === t.name)!;
    let dump = "dump=skipped(>" + DUMP_MAX + ")";
    let good = r.ok;
    if ((r.expected ?? 0) <= DUMP_MAX) {
      const db = new Digest(t.columns);
      for (const l of lines(sql(c.database, dumpSql(c.database, t), ["-h", "-1", "-W", "-y", "0"]))) db.add(JSON.parse(l));
      const csv = csvDigestSync(stamp.dir, m, t);
      const same = db.hex() === csv.hex();
      good &&= same;
      dump = `sha256=${db.hex().slice(0, 16)} csv=${same ? "same" : csv.hex().slice(0, 16) + " DIFFERS"}`;
    }
    ok &&= good;
    log(`table ${t.name} rows=${r.actual} manifest=${r.expected} ${dump} ${good ? "OK" : "FAIL"}`);
  }
  for (const v of c.views) log(`view ${v.name} rows=${counts[v.name]}`);
  const own = c.tables.map((t) => nstring(t.name)).join(", ");
  const fk = lines(sql(c.database, `SET NOCOUNT ON; SELECT CONCAT(COUNT(*), '|', ISNULL(SUM(CAST(is_not_trusted AS int)), 0), '|', ISNULL(SUM(CAST(is_disabled AS int)), 0)) FROM sys.foreign_keys WHERE OBJECT_NAME(parent_object_id) IN (${own})`, ["-h", "-1", "-W"]))[0]!.split("|").map(Number);
  const fkOk = fk[1] === 0 && fk[2] === 0 && fk[0] === c.tables.reduce((s, t) => s + t.fks.length, 0);
  ok &&= fkOk;
  log(`fk count=${fk[0]} not-trusted=${fk[1]} disabled=${fk[2]} ${fkOk ? "OK" : "FAIL"}`);
  ok = (existsSync(files.mssqlSmoke) ? smoke(c, stamp.tier, m, lines(sqlFile(c.database, files.mssqlSmoke, ["-h", "-1", "-W", "-s", "|"])), log, files.expectedXs) : (log("smoke none (no smoke file)"), true)) && ok;
  log(`verify ${c.domain} mssql tier=${stamp.tier} seed=${stamp.seed ?? "-"} loaded=${stamp.loadedAt} ${ok ? "OK" : "FAILED"}`);
  return ok;
}

/** The smoke's k|v lines: at xs byte-equal to the expected file; above xs its counts equal the manifest. */
export function smoke(c: Contract, tier: string, m: Manifest, out: string[], log: Log, expectedXs: string): boolean {
  const kv = new Map(out.map((l) => { const i = l.indexOf("|"); return [l.slice(0, i), l.slice(i + 1)] as const; }));
  const key = ["amount.all", "units.all", "target.all", "targets.met", "srSales.all", "null.repScore"].filter((k) => kv.has(k)).map((k) => `${k}=${kv.get(k)}`).join(" ");
  const sha = createHashHex(out.join("\n") + "\n").slice(0, 16);
  if (tier === "xs") {
    const expected = readFileSync(expectedXs, "utf8");
    const same = out.join("\n") + "\n" === expected;
    log(`smoke lines=${out.length} sha256=${sha} ${key} ${same ? "== expected-xs OK" : "!= expected-xs FAIL"}`);
    return same;
  }
  const bad = c.tables.filter((t) => kv.has(`count.${t.name}`) && Number(kv.get(`count.${t.name}`)) !== m.tables[t.name]?.rows).map((t) => t.name);
  log(`smoke lines=${out.length} sha256=${sha} ${key} counts ${bad.length ? "DIFFER: " + bad.join(",") + " FAIL" : "== manifest OK"}`);
  return bad.length === 0;
}

function createHashHex(s: string): string { return createHash("sha256").update(s).digest("hex"); }

/** Small tables only (DUMP_MAX): read whole. */
export function csvDigestSync(dir: string, m: Manifest, t: Table): Digest {
  const [header, ...body] = parseAll(readFileSync(join(dir, m.tables[t.name]!.file), "utf8"));
  if (!header || header.join(",") !== t.columns.map((x) => x.name).join(",")) throw new LoadError(`${t.name}: CSV header differs from the contract`, 1);
  const d = new Digest(t.columns);
  for (const r of body) d.add(r);
  return d;
}

export function unload(c: Contract, log: Log = console.log): boolean {
  const views = [...c.views].reverse().map((v) => v.name), tables = [...loadOrder(c)].reverse();
  const drops = [...views.map((v) => `DROP VIEW IF EXISTS [dbo].${bracket(v)};`), ...tables.map((t) => `DROP TABLE IF EXISTS [dbo].${bracket(t)};`)];
  const r = sql(c.database, `SET NOCOUNT ON; ${stampSql(c, null)} ${drops.join(" ")}`);
  rmSync(stageDir(c.domain), { recursive: true, force: true });
  const inList = (xs: string[]) => xs.map((x) => nstring(x)).join(", ");
  const left = lines(sql(c.database, `SET NOCOUNT ON; SELECT CONCAT(
    (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0 AND name IN (${inList(tables)})), '|',
    (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped = 0 AND name IN (${inList(views.length ? views : ["-"])})), '|',
    (SELECT COUNT(*) FROM sys.extended_properties WHERE class = 0 AND name = ${nstring(stampName(c.domain))}), '|',
    (SELECT COUNT(*) FROM sys.objects WHERE is_ms_shipped = 0 AND type IN ('U', 'V') AND name NOT IN (${inList([...tables, ...views])})))`, ["-h", "-1", "-W"]))[0]!.split("|").map(Number);
  const ok = left.slice(0, 3).every((n) => n === 0);
  log(`unload ${c.domain} mssql database=${c.database} (kept) tables=${left[0]} views=${left[1]} stamp=${left[2]} other-objects=${left[3]} stage-dir=removed ms=${r.ms.toFixed(0)} ${ok ? "OK" : "LEFTOVERS"}`);
  return ok;
}
