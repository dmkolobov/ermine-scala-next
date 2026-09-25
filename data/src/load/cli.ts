// node dist/src/load/cli.js <mssql|sqlite> [load|unload|verify] --domain D [--tier T] [--seed S] [--from DIR] [--db FILE]
//   npm run load:mssql  -- --domain sales --tier s        (what `scripts/db.sh load sales --tier s` runs)
//   npm run load:sqlite -- --domain sales --tier s        (D13 twin: data/out/<domain>/<tier>/<domain>.sqlite)
// Exit: 0 ok; 1 verify/row-count mismatch; 2 usage; 3 db.sh/env; 5 SQL failed; 7 generator failed.

import { loadContract } from "../contract.js";
import { SqlError } from "./dbsh.js";
import { load, unload, verify } from "./mssql.js";
import { outDir } from "./paths.js";
import { LoadError } from "./prepare.js";
import { loadSqlite, sqliteFile, verifySqlite } from "./sqlite.js";

const HELP = `usage: cli.js mssql  load   --domain D --tier xs|s|m|l [--seed N] [--from DIR]
       cli.js mssql  unload --domain D
       cli.js mssql  verify --domain D
       cli.js sqlite [load] --domain D --tier T [--seed N] [--from DIR] [--db FILE]
       cli.js sqlite verify --domain D --tier T [--from DIR] [--db FILE]
exit: 0 ok, 1 mismatch, 2 usage, 3 db.sh/env, 5 SQL failed, 7 generator failed`;

async function main(argv: string[]): Promise<number> {
  const [dialect, maybeVerb, ...rest] = argv;
  if (!dialect || dialect === "--help" || dialect === "-h") { console.log(HELP); return dialect ? 0 : 2; }
  let verb = maybeVerb, args = rest;
  if (!verb || verb.startsWith("--")) { verb = "load"; args = maybeVerb ? [maybeVerb, ...rest] : rest; }
  const a: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    const k = args[i]!;
    if (k === "--help" || k === "-h") { console.log(HELP); return 0; }
    if (!k.startsWith("--") || args[i + 1] === undefined || !["domain", "tier", "seed", "from", "db"].includes(k.slice(2))) { console.error(`bad argument ${k}\n${HELP}`); return 2; }
    a[k.slice(2)] = args[++i]!;
  }
  if (!a.domain) { console.error(HELP); return 2; }
  const seed = a.seed === undefined ? 42 : Number(a.seed);
  if (!Number.isSafeInteger(seed) || seed < 0) { console.error("--seed must be a non-negative integer"); return 2; }
  const c = loadContract(a.domain);
  if (dialect === "mssql") {
    if (verb === "load") { if (!a.tier) { console.error(HELP); return 2; } return (await load(c, { tier: a.tier, seed, from: a.from })).ok ? 0 : 1; }
    if (verb === "unload") return unload(c) ? 0 : 1;
    if (verb === "verify") return verify(c) ? 0 : 1;
  } else if (dialect === "sqlite") {
    if (!a.tier && !a.from) { console.error(HELP); return 2; }
    if (verb === "load") return (await loadSqlite(c, { tier: a.tier ?? "xs", seed, from: a.from, db: a.db })).ok ? 0 : 1;
    if (verb === "verify") { const dir = a.from ?? outDir(c.domain, a.tier!); return verifySqlite(c, dir, a.db ?? sqliteFile(dir, c.domain)) ? 0 : 1; }
  }
  console.error(HELP); return 2;
}

main(process.argv.slice(2)).then((rc) => { process.exitCode = rc; }, (e) => {
  const code = e instanceof LoadError || e instanceof SqlError ? e.code : 1;
  console.error(`load: ${(e as Error).message}`); process.exitCode = code;
});
