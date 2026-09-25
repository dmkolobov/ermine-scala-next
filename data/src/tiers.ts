// Tier resolution: a named tier (xs, s, m, l) takes its fact rows, its
// dimension sizes and its date range from the contract; --rows N keeps the
// named tier's dimensions and date range and generates exactly N fact rows
// (the output directory is then <tier>-<N>).

import type { Contract } from "./contract.js";
import { parseIso } from "./lib/dates.js";
import type { TierSpec } from "./model.js";

export const NAMED = ["xs", "s", "m", "l"] as const;

export function resolveTier(c: Contract, name: string, rows?: number): { spec: TierSpec; dateRange: string } {
  const base = name;
  if (rows !== undefined && !(Number.isInteger(rows) && rows >= 1)) throw new Error(`--rows must be a positive integer, not ${rows}`);
  const t = c.tiers[base];
  if (!t) throw new Error(`unknown tier ${base} (the contract has ${Object.keys(c.tiers).join(", ")})`);
  const dimRows: Record<string, number> = {};
  for (const tab of c.tables) { const n = tab.rows[base]; if (typeof n === "number") dimRows[tab.name] = n; }
  if (base === "xs") {
    if (rows !== undefined) throw new Error("--rows cannot be combined with tier xs");
    return { spec: { name: "xs", factRows: t.factRows, dimRows, from: 0, to: 0 }, dateRange: t.dateRange };
  }
  const m = /^(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})$/.exec(t.dateRange);
  if (!m) throw new Error(`tier ${base}: bad dateRange ${t.dateRange}`);
  const label = rows !== undefined && rows !== t.factRows ? `${base}-${rows}` : base;
  return { spec: { name: label, factRows: rows ?? t.factRows, dimRows, from: parseIso(m[1]!), to: parseIso(m[2]!) }, dateRange: t.dateRange };
}
