// npm run generate -- --domain sales --tier s --seed 42 [--rows N] [--out DIR] [--contract FILE]
//
// Writes <out>/<domain>/<tier>/<table>.csv for every base table of the
// contract, plus manifest.json (seed, tier, rows, bytes and sha256 per CSV),
// and prints ONE line.  Exit codes: 0 written; 2 usage; 1 any other failure
// (a contract violation names the table, row and column).

import { join } from "node:path";
import { DATA_ROOT, loadContract } from "./contract.js";
import { DOMAINS } from "./domains/index.js";
import { emit } from "./emit.js";
import { resolveTier } from "./tiers.js";

const HELP = `usage: npm run generate -- --domain <d> --tier <xs|s|m|l> [--seed N] [--rows N] [--out DIR] [--contract FILE]

  --domain    ${Object.keys(DOMAINS).join(", ")}
  --tier      xs = exactly the contract's literal rows (seed ignored);
              s, m, l = generated, sizes and date range from the contract
  --seed      unsigned integer, default 42; same (seed, tier, domain) => same bytes
  --rows      exact fact row count; keeps the tier's dimensions and dates; output dir <tier>-<N>
  --out       output root, default data/out; files go to <out>/<domain>/<tier>/
  --contract  default data/schema/<domain>.contract.json

Prints one line: domain, tier, seed, rows per table, bytes, wall time.
Exit: 0 ok, 2 usage error, 1 generation failed (the message names table/row/column).`;

function main(argv: string[]): number {
  const a: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i]!;
    if (k === "--help" || k === "-h") { console.log(HELP); return 0; }
    if (!k.startsWith("--") || argv[i + 1] === undefined) { console.error(`bad argument ${k}\n${HELP}`); return 2; }
    a[k.slice(2)] = argv[++i]!;
  }
  for (const k of Object.keys(a)) if (!["domain", "tier", "seed", "rows", "out", "contract"].includes(k)) { console.error(`unknown option --${k}`); return 2; }
  const domainName = a.domain, tierName = a.tier;
  if (!domainName || !tierName) { console.error(HELP); return 2; }
  const mk = DOMAINS[domainName];
  if (!mk) { console.error(`unknown domain ${domainName}`); return 2; }
  const seed = a.seed === undefined ? 42 : Number(a.seed);
  if (!Number.isSafeInteger(seed) || seed < 0) { console.error(`--seed must be a non-negative integer`); return 2; }
  const rows = a.rows === undefined ? undefined : Number(a.rows);
  const contract = loadContract(domainName, a.contract);
  let tier;
  try { tier = resolveTier(contract, tierName, rows); } catch (e) { console.error((e as Error).message); return 2; }
  const t0 = process.hrtime.bigint();
  const { dir, manifest } = emit({ contract, domain: mk(), tier: tier.spec, seed, outRoot: a.out ?? join(DATA_ROOT, "out"), dateRange: tier.dateRange });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  const counts = Object.entries(manifest.tables).map(([k, v]) => `${k}=${v.rows}`).join(" ");
  const bytes = Object.values(manifest.tables).reduce((s, v) => s + v.bytes, 0);
  console.log(`generate ${domainName} tier=${manifest.tier} seed=${manifest.seed ?? "-"} ${counts} bytes=${bytes} wall=${(ms / 1000).toFixed(2)}s -> ${dir}`);
  return 0;
}

try { process.exitCode = main(process.argv.slice(2)); }
catch (e) { console.error(`generate: ${(e as Error).message}`); process.exitCode = 1; }
