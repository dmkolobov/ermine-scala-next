// Shared test plumbing: generate a tier into a scratch dir once per process
// and read its CSVs back, typed by the contract.

import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { baseType, Contract, loadContract } from "../src/contract.js";
import { salesDomain } from "../src/domains/sales.js";
import { emit, Manifest } from "../src/emit.js";
import { parse } from "../src/lib/csv.js";
import { resolveTier } from "../src/tiers.js";

export type Val = string | number | null;
export type TRow = Record<string, Val>;
export interface Loaded { contract: Contract; dir: string; manifest: Manifest; tables: Map<string, TRow[]>; raw: Map<string, string> }

export const contract = loadContract("sales");
const scratch = mkdtempSync(join(tmpdir(), "ermine-data-test-"));
process.on("exit", () => rmSync(scratch, { recursive: true, force: true }));

export function generate(tier: string, seed = 42, rows?: number, out = scratch): { dir: string; manifest: Manifest } {
  const t = resolveTier(contract, tier, rows);
  return emit({ contract, domain: salesDomain(), tier: t.spec, seed, outRoot: out, dateRange: t.dateRange });
}

export function freshDir(): string { return mkdtempSync(join(scratch, "run-")); }

export function load(dir: string, manifest: Manifest): Loaded {
  const tables = new Map<string, TRow[]>(), raw = new Map<string, string>();
  for (const t of contract.tables) {
    const text = readFileSync(join(dir, `${t.name}.csv`), "utf8");
    raw.set(t.name, text);
    const [header, ...body] = parse(text);
    if (!header || header.join(",") !== t.columns.map((c) => c.name).join(",")) throw new Error(`${t.name}: header ${header}`);
    tables.set(t.name, body.map((cells) => {
      const r: TRow = {};
      t.columns.forEach((c, i) => {
        const v = cells[i] ?? null;
        const bt = baseType(c.ermine);
        r[c.name] = v === null ? null : bt === "Int" || bt === "Double" ? Number(v) : v;
      });
      return r;
    }));
  }
  return { contract, dir, manifest, tables, raw };
}

const cache = new Map<string, Loaded>();
export function tier(name: string, seed = 42): Loaded {
  const key = `${name}/${seed}`;
  let l = cache.get(key);
  if (!l) { const { dir, manifest } = generate(name, seed); l = load(dir, manifest); cache.set(key, l); }
  return l;
}

export function rowsOf(l: Loaded, t: string): TRow[] { const r = l.tables.get(t); if (!r) throw new Error(`no ${t}`); return r; }
