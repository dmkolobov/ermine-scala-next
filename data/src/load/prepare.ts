// Make sure a tier's CSVs exist and are intact: run the generator when the
// directory is missing, holds another seed/tier, or predates the contract;
// then check every CSV against its manifest (bytes + sha256).

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { DATA_ROOT, type Contract } from "../contract.js";
import { checkFiles, readManifest, staleReason, type Manifest } from "./manifest.js";
import { outDir } from "./paths.js";

export class LoadError extends Error {
  constructor(msg: string, readonly code: number) { super(msg); }
}

export interface Prepared { dir: string; manifest: Manifest; generated: string | null }

export async function prepare(c: Contract, tier: string, seed: number, from?: string, log: (s: string) => void = console.log): Promise<Prepared> {
  let dir = from, generated: string | null = null;
  if (!dir) {
    dir = outDir(c.domain, tier);
    const m = existsSync(join(dir, "manifest.json")) ? readManifest(dir) : null;
    const why = staleReason(m, tier, seed, c.sha256);
    if (why) {
      const cli = join(DATA_ROOT, "dist", "src", "cli.js");
      const r = spawnSync(process.execPath, [cli, "--domain", c.domain, "--tier", tier, "--seed", String(seed)], { encoding: "utf8" });
      if (r.status !== 0) throw new LoadError(`generator failed (${why}): ${(r.stderr || r.stdout).trim().slice(0, 400)}`, 7);
      generated = r.stdout.trim();
      log(`${generated} (${why})`);
    }
  }
  const manifest = readManifest(dir);
  if (manifest.domain !== c.domain) throw new LoadError(`${dir}: manifest domain ${manifest.domain}, not ${c.domain}`, 2);
  for (const t of c.tables) if (!manifest.tables[t.name]) throw new LoadError(`${dir}: manifest lacks table ${t.name}`, 1);
  const bad = await checkFiles(dir, manifest);
  if (bad.length) throw new LoadError(`${dir}: CSVs do not match the manifest: ${bad.join("; ")}`, 1);
  return { dir, manifest, generated };
}
