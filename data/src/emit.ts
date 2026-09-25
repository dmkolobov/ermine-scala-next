// The contract-driven emitter: one CSV per base table, in the contract's
// loadOrder, into <out>/<domain>/<tier>/, plus manifest.json.  Every value is
// checked against its column as it is written (type, nullability, length), so
// a run that finishes wrote only what the contract allows.

import { closeSync, mkdirSync, openSync, writeSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { Cell, line } from "./lib/csv.js";
import { baseType, Contract, Column, Table } from "./contract.js";
import type { Domain, Producer, Row, TierSpec } from "./model.js";

export interface TableResult { file: string; rows: number; bytes: number; sha256: string }
export interface Manifest {
  generator: string;
  domain: string;
  database: string;
  tier: string;
  seed: number | null;
  factRows: number;
  dateRange: string;
  contractVersion: number;
  contractSha256: string;
  tables: Record<string, TableResult>;
}

export const GENERATOR_VERSION = "ermine-data 0.1.0 (pcg32, faker 10.6.0)";

const ISO = /^\d{4}-\d{2}-\d{2}$/;

export function checkCell(t: Table, c: Column, v: Cell, rowNo: number): void {
  const where = () => `${t.name} row ${rowNo} column ${c.name}`;
  if (v === null || v === undefined) {
    if (!c.nullable) throw new Error(`${where()}: NULL in a non-nullable column`);
    return;
  }
  // Contract rule (REVIEW-S1 M3, amended in round 2): NO column ever holds
  // the empty string, nullable or not -- MSSQL BULK INSERT loads a quoted ""
  // as NULL in a nullable column while SQLite keeps '', so the dialects would
  // diverge.  An empty CSV field means NULL, and only NULL.
  if (v === "") throw new Error(`${where()}: empty string (the contract bans '' in every column; only NULL may be empty)`);
  switch (baseType(c.ermine)) {
    case "Int":
      if (typeof v !== "number" || !Number.isInteger(v) || v < -2147483648 || v > 2147483647) throw new Error(`${where()}: not an Int: ${v}`);
      break;
    case "Double":
      if (typeof v !== "number" || !Number.isFinite(v)) throw new Error(`${where()}: not a Double: ${v}`);
      break;
    case "String":
      if (typeof v !== "string") throw new Error(`${where()}: not a String: ${v}`);
      if (c.maxLength !== undefined && [...v].length > c.maxLength) throw new Error(`${where()}: longer than ${c.maxLength}: ${v}`);
      break;
    case "Date":
      if (typeof v !== "string" || !ISO.test(v)) throw new Error(`${where()}: not a YYYY-MM-DD date: ${v}`);
      break;
    default:
      throw new Error(`${where()}: unsupported Ermine type ${c.ermine}`);
  }
}

class Sink {
  private buf: string[] = []; private size = 0;
  readonly hash = createHash("sha256"); bytes = 0;
  constructor(private readonly fd: number) {}
  write(s: string): void {
    this.buf.push(s); this.size += s.length;
    if (this.size > 1 << 20) this.flush();
  }
  flush(): void {
    if (!this.buf.length) return;
    const b = Buffer.from(this.buf.join(""), "utf8");
    this.hash.update(b); this.bytes += b.length;
    writeSync(this.fd, b);
    this.buf = []; this.size = 0;
  }
}

export function writeTable(dir: string, t: Table, rows: Iterable<Row>): TableResult {
  const file = `${t.name}.csv`;
  const fd = openSync(join(dir, file), "w");
  const sink = new Sink(fd);
  try {
    sink.write(line(t.columns.map((c) => c.name)));
    let n = 0;
    for (const r of rows) {
      n++;
      const cells = t.columns.map((c) => {
        if (!(c.name in r)) throw new Error(`${t.name} row ${n}: the model has no column ${c.name}`);
        const v = r[c.name] as Cell;
        checkCell(t, c, v, n);
        return v;
      });
      sink.write(line(cells));
    }
    sink.flush();
    return { file, rows: n, bytes: sink.bytes, sha256: sink.hash.digest("hex") };
  } finally { closeSync(fd); }
}

export interface EmitOptions { contract: Contract; domain: Domain; tier: TierSpec; seed: number; outRoot: string; dateRange: string }

export function tierDir(outRoot: string, domain: string, tier: string): string { return join(outRoot, domain, tier); }

export function emit(o: EmitOptions): { dir: string; manifest: Manifest } {
  const { contract, tier } = o;
  const dir = tierDir(o.outRoot, contract.domain, tier.name);
  if (existsSync(dir)) rmSync(dir, { recursive: true });
  mkdirSync(dir, { recursive: true });
  const producers: Map<string, Producer> = tier.name === "xs"
    ? new Map(contract.tables.map((t) => [t.name, () => t.xs.rows as Row[]]))
    : o.domain.producers(o.seed, tier);
  const tables: Record<string, TableResult> = {};
  for (const name of contract.loadOrder) {
    const t = contract.tables.find((x) => x.name === name);
    if (!t) throw new Error(`loadOrder names ${name}, which is not a table`);
    const p = producers.get(name);
    if (!p) throw new Error(`domain ${o.domain.name} has no producer for ${name}`);
    tables[name] = writeTable(dir, t, p());
  }
  const manifest: Manifest = {
    generator: GENERATOR_VERSION, domain: contract.domain, database: contract.database, tier: tier.name,
    seed: tier.name === "xs" ? null : o.seed, factRows: tables[contract.loadOrder.find((n) => n.startsWith("fact_"))!]?.rows ?? 0,
    dateRange: o.dateRange, contractVersion: contract.version, contractSha256: contract.sha256, tables,
  };
  writeFileSync(join(dir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  return { dir, manifest };
}
