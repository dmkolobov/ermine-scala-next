# LOADER: loading the corpus databases (DB-PLAN S1, D11-D13)

The loader takes the generator's CSVs (`data/out/<domain>/<tier>/`, with a `manifest.json`) and puts them into two places: SQL Server (`ErmineSales`, …) and a file-backed SQLite twin. Every load ends with a verify. The code is in `data/src/load/` and the tests are in `data/test/load-*.test.ts`.

## 1. How to load, verify and unload

| Command | What it does |
|---|---|
| `scripts/db.sh load sales --tier s [--seed 42] [--from DIR]` | Runs the generator if `data/out/sales/s` is missing, or holds another tier or seed, or predates the contract. Checks every CSV's size and sha256 against the manifest. Stages the CSVs into `/load/sales/`. Applies `data/schema/sales.mssql.sql` as `ermine`, which drops and recreates the objects. BULK INSERTs the tables in FK order as `sa`, comparing each table's row count with the manifest. Stamps the database, removes the staged files, then verifies. |
| `scripts/db.sh verify sales` | Prints one line per table, then one line per view, then the fk, smoke and verdict lines (§4). |
| `scripts/db.sh unload sales` | Drops the domain's views and tables and its stamp, and removes `/load/sales/`. The database, the `ermine` user and its grants stay. It then counts what is left. |
| `cd data && npm run load:mssql -- [load\|unload\|verify] --domain sales [--tier s]` | Same as above, without db.sh's build check. |
| `cd data && npm run load:sqlite -- --domain sales --tier s` | The D13 twin: writes `data/out/sales/s/sales.sqlite` with `sales.sqlite.sql` (STRICT tables, Date stored as INTEGER epoch ms at 00:00 GMT) and runs the same verify. Use `sqlite verify` to check it again later. It uses node's `node:sqlite`, because this box has no `sqlite3` binary. |

The exit codes are the ones in `db.sh --help`: 0 ok, 1 a count/dump/smoke mismatch, 2 usage, 3 env or db.sh, 5 SQL failed, 7 generator failed, 8 loader build failed. db.sh rebuilds `data/dist` when a source file is newer than it.

The stamp is a database-level extended property named `ermine.load.<domain>`. It holds a JSON record of tier, seed, source directory, manifest sha256 and load time. `verify` reads it, so it checks what is actually loaded, whatever the command line says. Regenerating the source directory after a load shows up as `manifest … changed since the load`. Because the generator deletes and rewrites `data/out/<domain>/<tier>/`, it also deletes that tier's `sales.sqlite`; run `load:sqlite` again afterwards.

## 2. Tiers and timings (MEASURED 2026-09-24, seed 42, one run each)

The load time runs from the start of the command through the last BULK INSERT: manifest sha256 check, staging, DDL and inserts, not verify. The total includes verify. Each db.sh `sql` call costs about 42 ms (one sqlcmd process), so the small tiers are dominated by that fixed cost. Container memory is the peak of `podman stats --no-stream`, sampled every 1-2 s during the load, against the 2048 MB MSSQL cap. Before the loads it was 927 MB.

| Tier | Fact rows | All rows | CSV (data/out) | Staged in /load (UTF-16) | MSSQL load | Rows/s | MSSQL total with verify | Peak container memory | ErmineSales data + log after | SQLite load | SQLite file |
|---|---|---|---|---|---|---|---|---|---|---|---|
| xs | 8 | 39 | 2.0 KB | ~4 KB | 0.65 s | 60 | 1.15 s | 927 MB | 8 + 8 MB | 0.21 s | 96 KB |
| s | 1 000 | 1 676 | 83 KB | 163 KB | 0.66 s | 2 559 | 1.23 s | 955 MB | 8 + 8 MB | 0.19 s | 240 KB |
| m | 100 000 | 106 106 | 5.9 MB | ~12 MB | 1.91 s | 55 611 | 3.03 s | 974 MB | 72 + 72 MB | 1.15 s | 12 MB |
| l | 2 000 000 | 2 052 515 | 116 MB | 241 MB | 25.72 s (fact table 24.5 s) | 79 808 | 27.49 s | 1.57 GB during, 1.68 GB after | 328 + 328 MB | 24.24 s (41.5 s with verify) | 250 MB |

Disk: the podman volume grew from 194.5 MB (after s) to 329 MB (after m) and 1.47 GB (after l). Unload and smaller reloads do not shrink it, because SQL Server keeps its grown files. `/load` is 0 B between loads, since the stage directory is removed after every successful load. tempdb stayed at 64 + 8 MB. Free disk went from 38 GB to 37 GB. After l, sqlservr keeps about 1.68 GB of memory, since its buffer pool does not give memory back. `scripts/db.sh down` then `up` resets it; that is infra's call to make, not the loader's.

Plan targets (DB-PLAN §4 S1): "tier xs loads exactly today's 8+4 rows" is MET: the smoke output equals `sales.smoke.expected-xs.txt` byte for byte. "Tier s in < 30 s" is MET: 1.2 s with verify.

## 3. The BULK INSERT options, and why (all MEASURED on 2022 CU27, Linux)

`BULK INSERT [db].[dbo].[t] FROM N'/load/<domain>/<t>.csv' WITH (FORMAT='CSV', DATAFILETYPE='widechar', FIELDQUOTE='"', FIELDTERMINATOR=',', ROWTERMINATOR='\n', FIRSTROW=2, TABLOCK, CHECK_CONSTRAINTS, MAXERRORS=0[, KEEPNULLS])`, built by `data/src/load/bulk.ts`.

| Option | Why |
|---|---|
| no `CODEPAGE` | `CODEPAGE='65001'` fails on Linux with Msg 16202 ("not supported on the 'Linux' platform"). Without it, UTF-8 is read in the OEM code page: "Zoë 中文" was stored as "Zo├½ Σ╕¡µûç". |
| `DATAFILETYPE='widechar'` | The fix for the above: the stager transcodes each CSV to UTF-16LE with a BOM. Non-ASCII names round-trip; at s (81 customers, 7 reps) and m (1 910, 18) the sha256 dumps equal the CSVs. This doubles the staged size. |
| `FORMAT='CSV'`, `FIELDQUOTE='"'` | RFC 4180 quoting: commas in company names, doubled quotes, an LF inside quotes, and leading or trailing spaces all survive. |
| `ROWTERMINATOR='\n'` | The generator writes LF only. With widechar and FORMAT='CSV', an LF-only file loads with no stray CR (the length of the last column was checked). `'0x0a00'` behaves the same. |
| `FIRSTROW=2` | Skips the header row. The loader checks the header against the contract itself (the SQLite side and the dump compare do this). |
| `TABLOCK` | One table lock instead of row locks, so less locking overhead. It does NOT give minimal logging here: `ErmineSales`, `ErmineHR` and `ErmineScience` are in the FULL recovery model (`sys.databases.recovery_model_desc`), and there bulk import is fully logged. That is consistent with the 328 MB log after tier l. Switching the database to BULK_LOGGED or SIMPLE recovery would allow minimal logging: an option for tier l, not taken. |
| `CHECK_CONSTRAINTS` | Without it, BULK INSERT skips FK and CHECK validation and leaves the FKs marked NOT TRUSTED. verify prints `fk count=9 not-trusted=0 disabled=0`. |
| `MAXERRORS=0` | The default of 10 SKIPS bad rows and commits the rest: 2 of 3 rows loaded, a Msg 4864 was printed, and the batch went on. With 0 the whole table aborts. The row-count compare is the second guard. |
| `KEEPNULLS` | Added only for tables with a Nullable column (`dim_rep`, `fact_order_line`). An empty unquoted field loads as NULL. A quoted `""` in a nullable column ALSO loads as NULL, with or without KEEPNULLS (§7). |
| `ISO dates`, `.` decimals | `YYYY-MM-DD` goes straight into `date`. Floats round-trip exactly: 0.1, 0.30000000000000004 and 123456789.12345679 were checked with `CONVERT(varchar, f, 3)`, and every dumped table matches its CSV. |

Rows affected: go-sqlcmd groups digits in thousands, e.g. `(1,000 rows affected)`, and the parser allows for it. The first tier-s run failed on this, before the fix.

**sa or `ermine` (verifier [decision] 2026-09-24 22:19, followed):** BULK INSERT runs as `sa` through `db.sh sql --sa`, and only the BULK statement does. DDL, the stamp, verify and unload all run as `ermine`. `ermine` does NOT get ADMINISTER BULK OPERATIONS: it is the login a playtest types, it stands in for the work server's report login, and the grant would let it read any file the mssql uid can reach. No password passes through node: the loader only calls `db.sh sql`, which reads `~/.config/ermine/db.env` itself.

**The staging directory (rootless):** the host directory `scratch-widget-preview/db/load` is `/load:ro` in the container. The container's mssql uid is mapped to a subuid, so it reads through the "other" permission bits. The loader creates `/load/<domain>/` with mode 0755 and the files with 0644. It replaces that directory on each load, removes it after a successful load (a failed load keeps it for diagnosis), and removes it again on unload. It never touches other files in `/load`.

## 4. What verify checks

- For each table: `COUNT_BIG(*)` against the manifest. For every table up to `ERMINE_DUMP_MAX` rows (20 000 by default; all of xs and s, everything but the fact table at m, and the dims except customers at l), a sha256 over a canonical dump. On MSSQL the dump is one JSON array per row: floats in style-3 notation (17 significant digits), dates in style 23, strings through STRING_ESCAPE. On SQLite it is a plain SELECT. Each row is re-rendered with the generator's own CSV `field()` rules, the rows are sorted, and the result is hashed. The CSV side goes through the same path. So a float that is 1 ulp off, a date shifted by a timezone, or a NULL that became `''` changes the digest. The MSSQL and SQLite digests are identical, table by table, at xs and s.
- For each view: its row count, printed.
- FKs: MSSQL counts the domain's FKs and requires none to be untrusted or disabled. SQLite requires `PRAGMA foreign_key_check` to find 0 rows.
- The smoke: the schema role's `sales.smoke.sql` or `sales.smoke.sqlite.sql`. At xs its output must equal `sales.smoke.expected-xs.txt` byte for byte. Above xs its `count.*` lines must equal the manifest. The key totals are printed.

Pinned totals at xs, from the database (MSSQL and SQLite agree): north 4350.75, south 2605.75, east 4175.50, west 1550.00, all 12682.00 (FetchData.e:18-19); units 34; target 11500.00; 2 targets met (north and east, as the FetchData.e targets comment says); srSales 529.50; 1 NULL repScore.

## 5. What tear-down leaves behind

- `db.sh unload sales` leaves the database `ErmineSales` (empty `dbo`), the `ermine` user with db_owner, and the grown data and log files (§2). It reports `tables=0 views=0 stamp=0 other-objects=N`, where `other-objects` counts user objects the loader does not own. The ones expected are `MemoHash_*` tables that `memoRelWithPK` creates in the connected database. These are the scanner's, not the loader's, and the loader does not drop them.
- The `##<guid>` temporary tables in `tempdb` are the SERVER's: the scanner makes them per session, and SQL Server removes them when the session ends. The loader never creates or drops anything in tempdb.
- `data/out/<domain>/<tier>/` (the CSVs, the manifest and `<domain>.sqlite`) is gitignored and stays until the generator rewrites it or you delete it.
- `db.sh down --all` (infra's command) removes the container and the volume, which takes everything above with it except `data/out`.

## 6. Tests (`cd data && npm test`, which also runs the generator's tests; 38/38 passing on 2026-09-24)

`load-units.test.ts` covers:
- the FK-order sort, on the sales contract and on synthetic cycles, self-references and unknown parents;
- the BULK statement builder: exact text, `]` and `'` quoting, refusing newlines and sqlcmd `$(` variables, KEEPNULLS only when needed;
- the rows-affected parser, including digit grouping;
- the manifest comparisons: counts, stale tier/seed/contract, and a missing, resized or altered CSV;
- the streaming CSV reader at every chunk split point;
- the canonical digest.

`load-roundtrip.test.ts` covers a hand-made two-table sample (FK, a view, NULLs, `""`, quotes, commas, spaces, non-ASCII text, 1e-7, 1e15, a leap day):
- through SQLite, always, including a changed float that the dump catches;
- through SQL Server, in `ErmineScience` as `loader_sample_*`, including a changed string that the dump catches, and an unload that leaves 0 objects. This test is skipped by name when `db.sh status` is not OK.

## 7. Known gaps

- **A `""` in a NULLABLE column becomes NULL on MSSQL.** BULK INSERT with FORMAT='CSV' does this with or without KEEPNULLS (MEASURED); in a NOT NULL column `""` stays `''`, and SQLite keeps `''` in both cases. No generated CSV contains `""` today. The board proposes a contract invariant for it, and verify's dump would catch a violation.
- The smoke files diverge above xs: `amount.<region>` over zero rows is `NULL` on MSSQL and `0.00` on SQLite (`printf`). This is the schema role's file, and it is on the board. The data itself is identical.
- The fact table at m and l, and customers at l, are checked by row count, FKs and smoke totals, but not by the sha256 dump. Setting `ERMINE_DUMP_MAX` higher covers them, at a cost of about 100 MB of sqlcmd output at l.
- Each BULK INSERT is one transaction, with no BATCHSIZE. At l the log file grew to 328 MB. A much larger `--rows` run would want BATCHSIZE, and it would lose all-or-nothing loading per table.
- The volume and sqlservr's memory do not shrink after unload (§2).
- There is no parallel loading. At l the fact table is 95% of the time and cannot be split under TABLOCK and FK checks.
