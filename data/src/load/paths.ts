// Where a domain's files are: the contract names its DDL per dialect; the smoke
// files follow the schema role's naming (data/schema/<domain>.smoke*.sql).

import { existsSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { DATA_ROOT, type Contract } from "../contract.js";

export interface DomainFiles { mssqlDdl: string; sqliteDdl: string; mssqlSmoke: string; sqliteSmoke: string; expectedXs: string }

export function domainFiles(c: Contract & { dialects?: Record<string, { ddl?: string }> }): DomainFiles {
  const repo = join(DATA_ROOT, "..");
  const rel = (p: string | undefined, dflt: string) => {
    const q = p ?? dflt;
    return isAbsolute(q) ? q : join(repo, q);
  };
  const d = c.domain;
  return {
    mssqlDdl: rel(c.dialects?.mssql?.ddl, `data/schema/${d}.mssql.sql`),
    sqliteDdl: rel(c.dialects?.sqlite?.ddl, `data/schema/${d}.sqlite.sql`),
    mssqlSmoke: join(DATA_ROOT, "schema", `${d}.smoke.sql`),
    sqliteSmoke: join(DATA_ROOT, "schema", `${d}.smoke.sqlite.sql`),
    expectedXs: join(DATA_ROOT, "schema", `${d}.smoke.expected-xs.txt`),
  };
}

export function outDir(domain: string, tier: string): string { return join(DATA_ROOT, "out", domain, tier); }

export function need(p: string): string { if (!existsSync(p)) throw new Error(`missing ${p}`); return p; }
