// A canonical text form of a table's rows, identical whichever side produced
// them: the CSV on disk, a SQL Server dump, or a SQLite dump.  Each row is
// re-rendered with the generator's own field() (so NULL = empty, "" quoted,
// numbers in plain decimal); rows are sorted by that text, so the physical
// order of either side does not matter; the digest is sha256 over the lines.
// A float that SQL Server parsed 1 ulp away, a date shifted by a timezone, or
// a string that lost a character all change the digest.

import { createHash } from "node:crypto";
import { field, numberText } from "../lib/csv.js";
import { baseType } from "../contract.js";
import type { Field } from "./csvstream.js";

export interface CanonColumn { name: string; ermine: string }
export type DbValue = string | number | bigint | null;

export function canonCell(c: CanonColumn, v: DbValue | undefined): string {
  if (v === null || v === undefined) return field(null);
  switch (baseType(c.ermine)) {
    case "Int":
    case "Double": {
      const n = Number(v);
      if (!Number.isFinite(n)) throw new Error(`${c.name}: not a number: ${v}`);
      return numberText(n);
    }
    case "Date": {
      if (typeof v === "number" || typeof v === "bigint") return new Date(Number(v)).toISOString().slice(0, 10); // SQLite: epoch ms at 00:00 GMT
      return String(v).slice(0, 10);
    }
    default:
      return field(String(v));
  }
}

export function canonRow(cols: readonly CanonColumn[], vals: readonly (DbValue | undefined)[]): string {
  return cols.map((c, i) => canonCell(c, vals[i])).join(",");
}

export class Digest {
  private lines: string[] = [];
  constructor(private readonly cols: readonly CanonColumn[]) {}
  add(vals: readonly (DbValue | Field | undefined)[]): void { this.lines.push(canonRow(this.cols, vals)); }
  get rows(): number { return this.lines.length; }
  hex(): string {
    const h = createHash("sha256");
    for (const l of [...this.lines].sort()) h.update(l + "\n");
    return h.digest("hex");
  }
}
