// npm run timings -- [--tiers xs,s,m,l] [--seed 42]: generate each tier into
// data/out and print a markdown table (wall time, fact rows, CSV bytes, peak
// RSS).  One process per run of this script; tiers run in the order given.

import { join } from "node:path";
import { DATA_ROOT, loadContract } from "./contract.js";
import { salesDomain } from "./domains/sales.js";
import { emit } from "./emit.js";
import { resolveTier } from "./tiers.js";

const args = process.argv.slice(2);
const opt = (k: string, d: string) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] ?? d : d; };
const tiers = opt("tiers", "xs,s,m,l").split(",");
const seed = Number(opt("seed", "42"));
const contract = loadContract("sales");
console.log("| tier | fact rows | tables' rows | CSV bytes | wall s | peak RSS MB |");
console.log("|---|---|---|---|---|---|");
for (const t of tiers) {
  const r = resolveTier(contract, t);
  const t0 = process.hrtime.bigint();
  const { manifest } = emit({ contract, domain: salesDomain(), tier: r.spec, seed, outRoot: join(DATA_ROOT, "out"), dateRange: r.dateRange });
  const s = Number(process.hrtime.bigint() - t0) / 1e9;
  const rows = Object.values(manifest.tables).reduce((a, v) => a + v.rows, 0);
  const bytes = Object.values(manifest.tables).reduce((a, v) => a + v.bytes, 0);
  console.log(`| ${t} | ${manifest.factRows} | ${rows} | ${bytes} | ${s.toFixed(2)} | ${(process.resourceUsage().maxRSS / 1024).toFixed(0)} |`);
}
