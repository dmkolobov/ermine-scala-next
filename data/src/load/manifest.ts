// The generator's manifest (src/emit.ts Manifest) as the loader reads it, and
// the two comparisons the loader makes against it: the CSV bytes on disk, and
// the row counts a database reports back.

import { createReadStream, existsSync, readFileSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import type { Manifest } from "../emit.js";

export type { Manifest };

export function readManifest(dir: string): Manifest {
  const p = join(dir, "manifest.json");
  if (!existsSync(p)) throw new Error(`no manifest.json in ${dir}`);
  const m = JSON.parse(readFileSync(p, "utf8")) as Manifest;
  if (!m.tables || typeof m.tables !== "object") throw new Error(`${p}: no tables`);
  return m;
}

export function manifestSha(dir: string): string {
  return createHash("sha256").update(readFileSync(join(dir, "manifest.json"))).digest("hex");
}

export async function fileSha256(path: string): Promise<string> {
  const h = createHash("sha256");
  for await (const c of createReadStream(path, { highWaterMark: 1 << 20 })) h.update(c as Buffer);
  return h.digest("hex");
}

/** Every CSV the manifest names exists with its recorded size and sha256; returns the problems. */
export async function checkFiles(dir: string, m: Manifest): Promise<string[]> {
  const bad: string[] = [];
  for (const [t, r] of Object.entries(m.tables)) {
    const p = join(dir, r.file);
    if (!existsSync(p)) { bad.push(`${t}: ${r.file} missing`); continue; }
    const size = statSync(p).size;
    if (size !== r.bytes) { bad.push(`${t}: ${size} bytes, manifest says ${r.bytes}`); continue; }
    const sha = await fileSha256(p);
    if (sha !== r.sha256) bad.push(`${t}: sha256 ${sha.slice(0, 12)}.. manifest says ${r.sha256.slice(0, 12)}..`);
  }
  return bad;
}

export interface CountCheck { table: string; expected: number | null; actual: number | null; ok: boolean }

/** Row counts per table against the manifest; a table on one side only is a mismatch. */
export function compareCounts(m: Manifest, actual: Record<string, number>, tables?: readonly string[]): CountCheck[] {
  const names = tables ?? [...new Set([...Object.keys(m.tables), ...Object.keys(actual)])];
  return names.map((table) => {
    const expected = m.tables[table]?.rows ?? null;
    const a = Object.prototype.hasOwnProperty.call(actual, table) ? actual[table]! : null;
    return { table, expected, actual: a, ok: expected !== null && a === expected };
  });
}

/** Does the directory hold what `load --tier T --seed S` asks for?  null = yes, else why not. */
export function staleReason(m: Manifest | null, tier: string, seed: number, contractSha256: string): string | null {
  if (!m) return "no manifest";
  if (m.tier !== tier) return `manifest tier ${m.tier}`;
  if (tier !== "xs" && m.seed !== seed) return `manifest seed ${m.seed}, asked ${seed}`;
  if (m.contractSha256 !== contractSha256) return "the contract changed since generation";
  return null;
}
