// The T-SQL BULK INSERT statement for one staged CSV.  Why each option
// (MEASURED on the ermine-mssql container, 2022 CU27, tracker/db/LOADER.md §3):
//   FORMAT='CSV' + FIELDQUOTE='"'  RFC 4180 quoting: commas, quotes and LFs inside "..."
//   DATAFILETYPE='widechar'        CODEPAGE is refused on Linux (Msg 16202) and the default
//                                  code page mangles UTF-8 ("Zoë" -> "Zo├½"); the stager
//                                  transcodes each CSV to UTF-16LE with a BOM instead
//   ROWTERMINATOR='\n'             the generator writes LF; with widechar + FORMAT='CSV' an
//                                  LF-only file loads with no stray CR (measured)
//   FIRSTROW=2                     skip the header line
//   TABLOCK                        one table lock instead of row locks (less lock overhead);
//                                  NOT minimal logging: the Ermine* databases are in FULL
//                                  recovery, where bulk import is fully logged (log 328 MB
//                                  after tier l). BULK_LOGGED/SIMPLE recovery would allow
//                                  minimal logging: an option for tier l, not taken
//   CHECK_CONSTRAINTS              otherwise BULK INSERT skips FK/CHECK validation and marks
//                                  the foreign keys NOT TRUSTED
//   MAXERRORS=0                    the default (10) SKIPS up to 10 bad rows and still commits
//                                  the rest (measured: 2 of 3 rows loaded); 0 aborts the table
//   KEEPNULLS                      only where the contract has a Nullable column: an empty
//                                  unquoted field stays NULL; a quoted "" ALSO loads as NULL
//                                  in a nullable column (measured, with or without
//                                  KEEPNULLS); only a NOT NULL column keeps it as ''

export interface BulkSpec {
  database: string;
  schema: string;
  table: string;
  /** the path INSIDE the container, e.g. /load/sales/dim_rep.csv */
  file: string;
  keepNulls: boolean;
}

function checkText(what: string, s: string): void {
  if (s === "" || /[\0\r\n]/.test(s)) throw new Error(`bulk: bad ${what}: ${JSON.stringify(s)}`);
  // sqlcmd substitutes $(var) in -Q text and -i files; a name holding one would be rewritten
  if (s.includes("$(")) throw new Error(`bulk: ${what} contains "$(": ${s}`);
}

export function bracket(id: string): string { checkText("identifier", id); return `[${id.replace(/]/g, "]]")}]`; }
export function nstring(s: string): string { checkText("string", s); return `N'${s.replace(/'/g, "''")}'`; }

export function bulkInsertSql(b: BulkSpec): string {
  const opts = [
    "FORMAT = 'CSV'", "DATAFILETYPE = 'widechar'", "FIELDQUOTE = '\"'", "FIELDTERMINATOR = ','",
    "ROWTERMINATOR = '\\n'", "FIRSTROW = 2", "TABLOCK", "CHECK_CONSTRAINTS", "MAXERRORS = 0",
  ];
  if (b.keepNulls) opts.push("KEEPNULLS");
  return `BULK INSERT ${bracket(b.database)}.${bracket(b.schema)}.${bracket(b.table)} FROM ${nstring(b.file)} WITH (${opts.join(", ")});`;
}

/** Sum of the "(N rows affected)" lines sqlcmd prints; go-sqlcmd groups digits: "(1,000 rows affected)" (MEASURED). */
export function rowsAffected(out: string): number | null {
  let n: number | null = null;
  for (const m of out.matchAll(/\((\d[\d,.'\u00a0\u202f]*) rows? affected\)/g)) n = (n ?? 0) + Number(m[1]!.replace(/\D/g, ""));
  return n;
}
