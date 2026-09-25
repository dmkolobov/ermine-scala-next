// The only way the loader reaches SQL Server: scripts/db.sh sql [--sa] DB ...
// db.sh reads the passwords from ~/.config/ermine/db.env itself, so no
// password ever passes through node, argv or a file this package writes.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { DATA_ROOT } from "../contract.js";

export const DBSH = process.env.ERMINE_DBSH ?? join(DATA_ROOT, "..", "scripts", "db.sh");
export const LOAD_DIR = process.env.ERMINE_DB_LOAD ?? "/home/dmitry/research/ermine/scratch-widget-preview/db/load";
/** The bind mount's path inside the container (db.sh create: -v $LOAD:/load:ro). */
export const LOAD_MOUNT = "/load";

export class SqlError extends Error {
  constructor(msg: string, readonly code: number) { super(msg); }
}

export interface SqlResult { out: string; ms: number }

function run(args: string[]): SqlResult {
  if (!existsSync(DBSH)) throw new SqlError(`no ${DBSH}`, 3);
  const t0 = process.hrtime.bigint();
  const r = spawnSync("bash", [DBSH, ...args], { encoding: "utf8", maxBuffer: 1 << 30 });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  if (r.error) throw new SqlError(`db.sh: ${r.error.message}`, 3);
  if (r.status !== 0) {
    const msg = `${r.stdout}\n${r.stderr}`.split("\n").filter((l) => /Msg \d+|db\.sh:|error/i.test(l)).slice(0, 6).join(" | ");
    throw new SqlError(`db.sh ${args[0]} exit ${r.status}: ${msg || (r.stderr || r.stdout).trim().slice(0, 400)}`, r.status ?? 5);
  }
  return { out: r.stdout, ms };
}

export interface As { sa?: boolean }

/** A query, sqlcmd flags after it (e.g. -h -1 -W). */
export function sql(db: string, query: string, flags: string[] = [], as: As = {}): SqlResult {
  return run(["sql", ...(as.sa ? ["--sa"] : []), db, query, ...flags]);
}

export function sqlFile(db: string, file: string, flags: string[] = [], as: As = {}): SqlResult {
  return run(["sql", ...(as.sa ? ["--sa"] : []), db, "-i", file, ...flags]);
}

/** Result lines of a headerless query, the trailing blank line dropped. */
export function lines(r: SqlResult): string[] {
  return r.out.split("\n").map((l) => l.replace(/\r$/, "")).filter((l) => l !== "" && !/^\(\d+ rows? affected\)$/.test(l));
}

export function status(): { ok: boolean; out: string } {
  if (!existsSync(DBSH)) return { ok: false, out: "no db.sh" };
  const r = spawnSync("bash", [DBSH, "status"], { encoding: "utf8", timeout: 60_000 });
  return { ok: r.status === 0, out: r.stdout };
}
