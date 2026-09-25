// The column contract the SCHEMA role writes (data/schema/<domain>.contract.json):
// only the parts the generator reads are typed here.

import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import type { Cell } from "./lib/csv.js";

export interface Column {
  name: string;
  ermine: string;          // Int | Double | String | Date | Nullable T
  nullable: boolean;
  maxLength?: number;
  hint?: { kind: string; [k: string]: unknown };
}

export interface Table {
  name: string;
  kind: string;
  pk: string[];
  unique: string[][];
  fks: { columns: string[]; ref: string; refColumns: string[] }[];
  rows: Record<string, number>;
  columns: Column[];
  xs: { rows: Record<string, Cell>[] };
}

export interface Contract {
  version: number;
  domain: string;
  database: string;
  tiers: Record<string, { factRows: number; dateRange: string }>;
  loadOrder: string[];
  tables: Table[];
  views: { name: string; columns: Column[] }[];
  xsPinned: Record<string, unknown>;
  /** sha256 of the contract file's bytes, recorded in the manifest */
  sha256: string;
  path: string;
}

/** data/ (the package root), from dist/src/contract.js or src/contract.ts. */
export const DATA_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

export function contractPath(domain: string): string { return join(DATA_ROOT, "schema", `${domain}.contract.json`); }

export function loadContract(domain: string, path = contractPath(domain)): Contract {
  const bytes = readFileSync(path);
  const c = JSON.parse(bytes.toString("utf8")) as Contract;
  if (c.domain !== domain) throw new Error(`${path}: domain is ${c.domain}, not ${domain}`);
  c.sha256 = createHash("sha256").update(bytes).digest("hex");
  c.path = path;
  return c;
}

export function table(c: Contract, name: string): Table {
  const t = c.tables.find((x) => x.name === name);
  if (!t) throw new Error(`contract has no table ${name}`);
  return t;
}

/** The base type of an Ermine column type: "Nullable Int" -> "Int". */
export function baseType(ermine: string): string { return ermine.replace(/^Nullable\s+/, ""); }
