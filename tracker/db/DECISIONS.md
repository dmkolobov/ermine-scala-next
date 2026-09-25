# DB programme: decisions folded from the message board

The board itself is `scratch-widget-preview/db/BOARD.md` (append-only, ephemeral); this file is the durable record, folded by the orchestrator at each stage commit (tracker/DB-PLAN.md §3). Entries are condensed to one line each with role and time; open questions and tickets follow.

## Stage 0 and stage 1 (Sales), folded 2026-09-24 (all three review rounds included)

For the orchestrator to fold into `tracker/db/DECISIONS.md` at the S1 commit. One line per board
[decision], in board order, with role and stamp as posted (loader's first three stamps were
guessed, corrected by loader 22:24). Superseded decisions are marked.

## Decisions

| # | Stamp | Role | Decision |
|---|---|---|---|
| 1 | 11:20 | orchestrator | DB-PLAN approved with every §0 recommendation (D1-D15). |
| 2 | 22:10 | server | `com.microsoft.sqlserver:mssql-jdbc:13.6.0.jre11`, Compile scope of `core`; smoke = `TestMsSqlSmoke` + `tracker/tools/db-smoke.sh` (password via env only). |
| 3 | 22:14 | infra | Two 24-char passwords `[A-Za-z0-9_.-]` in `~/.config/ermine/db.env` (600/700) only; container gets only the SA line via `--env-file <(grep ...)`; sqlcmd via `SQLCMDPASSWORD`; CREATE LOGIN via sqlcmd `$(ERMINE_DB_PASSWORD)` substitution. |
| 4 | 22:14 | infra | Client go-sqlcmd v1.10.0 at `~/.local/bin/sqlcmd` (sha256 checked); every call `-S tcp:127.0.0.1,1433 -C -N`. |
| 5 | 22:14 | infra | Grants: `ermine` = db_owner on ErmineSales/HR/Science; tempdb db_ddladmin + datareader + datawriter, re-applied on every `up`; no bulkadmin. |
| 6 | 22:16 | schema | Contract v1 (supersedes v0 22:24): single source `data/schema/build-sales-schema.mjs` -> contract.json, mssql/sqlite DDL, smoke files, expected-xs; 9 base tables + 4 views; `xs.rows` embedded; tier row targets; camelCase columns, snake_case tables; CSV convention (NULL = empty unquoted). |
| 7 | 22:16 | schema | T-SQL DDL columns are `[bracketed]` (LINENO reserved, Msg 156 measured). |
| 8 | 22:16 | schema (handoff, adopted by reports 22:40) | `table` statements use BARE names, no `database "..."` block (departs from DB-PLAN D8's `dbo.x` example); relies on `ermine`'s default schema dbo. |
| 9 | 22:19 | verifier | BULK INSERT stays sa-only (`db.sh sql --sa`, BULK batch only); `ermine` does NOT get ADMINISTER BULK OPERATIONS; revisit only with a separate `ermine_loader` login. |
| 10 | 22:20 | generator | `data/` = ESM TypeScript package (NodeNext); in-house PCG32 with one stream per (domain, table, purpose); faker 10.6.0 pinned exact, reseeded per entity; lockfile sha512 for 4 packages; node_modules/dist/out gitignored. |
| 11 | 22:23 | generator | No generic hint interpreter: the sales model covers every contract column by name; every written value checked for type, nullability, maxLength. |
| 12 | 22:23 | infra | REVIEW-S0 M1 fixed: refused sa login -> `up`/`down` exit 3 at once (down does not kill), `status` prints `login sa FAILED`, exit 1; load_env parses two keys only, checks owner, enforces the password charset. Image digest NOT pinned (known gap 7). |
| 13 | 22:24 (posted as 22:30) | loader | Code in `data/src/load/`; two script lines added to `data/package.json`; uses `node:sqlite` (no sqlite3 binary); manifest shape is the generator/loader contract. |
| 14 | 22:24 (posted as 22:30) | loader | Per-domain `load/unload/verify` EXTEND `scripts/db.sh`; never DROP DATABASE (unload drops views+tables, user and grants survive); `/load/<domain>/` per domain, replaced per load, removed after success and on unload; BULK as sa, DDL/verify/unload as ermine. |
| 15 | 22:24 (loader finding, a de-facto decision) | loader | BULK options: no CODEPAGE (Msg 16202 on Linux); CSVs staged as UTF-16LE+BOM with `DATAFILETYPE='widechar'`; `FORMAT='CSV'`, `FIELDQUOTE='"'`, `ROWTERMINATOR='\n'`, `FIRSTROW=2`, `TABLOCK`, `CHECK_CONSTRAINTS`, `MAXERRORS=0`, `KEEPNULLS` only on tables with a Nullable column. |
| 16 | 22:40 | reports | Twins: `doc/DbFetchData.e` (two bare `table`s) + six `doc/DbFetch*.e` importing it + `modules/Doc/DbSalesReport.e` over `table sales_report`; `TestDbReports` env-gated; FetchCrosstab's `calendar` stays a literal. |
| 17 | 22:50-23:02 (reports findings, recorded as the assertion design) | reports | Twin-vs-original equality is "equal after masking tokens/expiry and sorting the inline `rows` of every relation object"; byte equality is printed, not asserted. |
| 18 | tracker edit (no board [decision]) | server/reports | WP-12 row: (a) marked BUILT; "connect FROM THE PREVIEW and the prompted-password path end to end" MOVED from WP-12(a)'s done-when to WP-13. **Needs the orchestrator's/user's ack: it changes a user-set done-when.** |
| 19 | 22:46 | server | M1: without `ERMINE_DB_*` the DB suites register NOTHING and print "DB suites: not requested"; a new PR-tier `db` gate (scripts/gates.sh) runs them with db.env, UNAVAILABLE with a remedy when the container is down or ErmineSales is not at tier xs, builds its own SQLite twin into GATE_OUT, and is keyed also by ErmineSales's load stamp via a new `GATE_KEYFN` hook (scripts/gate.sh). Documented in SERVER.md §5, the WP-12 row and docs/gate-policy.md. |
| 20 | 22:49 | server | The `db` gate body runs with ErmineSales at tier xs; afterwards server reloads s (seed 42) and verifies. Recorded stage-2 nit: the gate should load xs into its OWN database instead of depending on the tier the user has loaded. |
| 21 | 22:49 (loader finding, a de-facto decision) | loader | M2: TABLOCK kept for lock overhead, with no minimal-logging claim (FULL recovery). SIMPLE/BULK_LOGGED recovery recorded as an option for tier l, NOT taken (compare ticket T1). |
| 22 | 22:50 | schema | M3: `csv.null` = an empty field (quoted or unquoted) means NULL; no String column holds `''`; 11th invariant added. |
| 23 | 22:50 (generator finding; rule G10 in GENERATOR.md) | generator | M3: `checkCell` rejects `''` in nullable columns (3 tests, npm test 41/41); CSVs byte-identical; `pinned-s42.json` unchanged. |
| 24 | round 3 (server + generator) | server, generator | A gate whose GATE_KEYFN fails or prints nothing runs UNCACHEABLE (unique key, result not written, reason printed); the `db` gate's password check reads its pattern from a pipe, never argv; `checkCell` rejects `''` in EVERY column (contract invariant 11), 42/42. |
## Open questions for the user

| # | From | Question | Options (role's framing) |
|---|---|---|---|
| Q-S1 | server | Preview profile setting shape | (a) `ermine.preview.profiles` list + active id; (b) one `ermine.preview.database` object; (c) profiles file outside settings |
| Q-S2 | server | What a render does while disconnected | (a) 503 "not connected" until reconnect; (b) fall back to in-memory SQLite with a badge |
| Q-S3 | server | Refusals before any socket | (a) new connect class `profile`; (b) fold into `driver` |
| Q-S4 | server | Panel `reason` for a connect failure | (a) extend `Preview.Reason` (wire change); (b) `reason: null`, class in the message |
| Q-S5 | server | Relative `jdbc:sqlite:` paths | (a) resolve against the first workspace folder; (b) refuse |
| Q-V1 | generator 22:23 | Vendoring the 4 npm tarballs for the closed network | (a) `npm pack` into `data/vendor/` (~5 MB in the repo) with `file:` resolved; (b) an internal registry mirror; (c) defer |
| Q-V2 | server §4 | Vendoring `mssql-jdbc-13.6.0.jre11` (.jar + .pom, sha256 in SERVER.md §0) | internal Maven registry or a copy of the coursier cache; when: before the first sbt on the work machine |
| Q-V3 | verifier (this review) | Accept WP-12(a)'s re-scope (row 18 above)? | ack / restore the preview connect to WP-12(a) |
| Q-V4 | infra gaps / verifier | Pin the image by digest (`@sha256:4402d880...`)? SA password visible to the same user via `podman inspect` (gap 2): accept for a local dev box? | pin / leave by tag; accept / change |

## Open questions between roles (not for the user)

| From | To | Question | State |
|---|---|---|---|
| loader 22:27 | schema + generator | Add the invariant "a Nullable String column never holds ''" to the contract and to `checkCell` (MSSQL loads a quoted `""` as NULL in a nullable column) | OPEN: not in `sales.contract.json` (10 invariants, none about it) nor in `src/emit.ts` `checkCell`; `contract.csv.null` still says "an empty STRING is \"\" quoted" without the nullable caveat |
| loader 22:29 | schema | Smoke files disagree above xs (`amount.<region>` over zero rows: MSSQL `NULL`, SQLite `0.00`) | OPEN; verifier: a smoke-file bug (SQLite `printf('%.2f', NULL)`), not a §9 dialect difference — SUM over zero rows is NULL on both engines |

## Findings worth a ticket

| # | Owner | Finding |
|---|---|---|
| T0 | server + reports | FIXED round 2. pr gate `suites` FAILS on SKIPPED-named properties (REVIEW-S1 M1); fix in progress (server 22:46). |
| T1 | infra | Corpus databases are in the FULL recovery model (inherited from `model`); Microsoft's "Prerequisites for minimal logging in bulk import" says bulk import under FULL is fully logged, so LOADER.md §3's "TABLOCK: minimal logging" does not hold here; ErmineSales data+log files are 328+328 MB after tier l and stay so. Fix: `ALTER DATABASE [..] SET RECOVERY SIMPLE` in `db.sh up`'s provisioning. |
| T2 | reports/server | `TestDbReports` (in core's Test sources) runs its sqlite-twin set in every `sbt core/test` whenever the gitignored `data/out/sales/xs/sales.sqlite` exists, and skips it silently (by name) on a fresh checkout: the pr gate's coverage depends on a local artefact. It also opens that file read-write. |
| T3 | reports | `TestDbReports` against a database NOT at tier xs fails with "documents differ" rather than a clear "database holds tier s" message; read the `ermine.load.sales` stamp first. |
| T4 | server | JDBC encryption: the smoke reads NULL (`CONNECTIONPROPERTY`); the verifier MEASURED it from the sa side during db-reports: ermine JDBC sessions `encrypt_option=TRUE`, TCP. Record in SERVER.md §3; no ticket needed. |
| T5 | loader | ERMINE_DUMP_MAX=20000: fact table at m/l and customers at l are not dump-verified (documented gap). |
| T7 | server | FIXED round 3. REVIEW-S1 round 2 R2-1/R2-2: the `GATE_KEYFN` fallback can serve a cached PASS without the DB; the `db` gate puts the password in grep's argv (gates.sh:274). |
| T6 | generator | l tier not covered by integrity tests (memory); documented. |

## Answers taken by the user, 2026-09-24

Q-S1 (a) profiles list + active id; Q-S2 (a) 503 not-connected until the automatic reconnect; Q-S3 (a) a fourth `profile` class; Q-S4 (a) the closed reason vocabulary gains connect-auth, connect-driver, connect-unreachable, connect-profile; Q-S5 (b) absolute `jdbc:sqlite:` paths only ("go with your recommendations"). Stage 2 also gains OBSERVABILITY ("we want to see the queries generated, the results scanned, time spent in db vs elsewhere ... valuing minimal configuration") and the option that the trace UI is itself an Ermine report ("perhaps the UI for extension could itself be driven by ermine in some way?"); a read-only design review (`scratch-widget-preview/db/DESIGN-OBSERVABILITY.md`, ephemeral, folded at the stage-2 commit) evaluates both.

## Observability answers taken BY THE ORCHESTRATOR overnight 2026-09-24 (the user asleep; "Let's see something impressive when I return"), on the design review's recommendations (`scratch-widget-preview/db/DESIGN-OBSERVABILITY.md`, folded at the stage-2 commit); the user has NOT been asked

Q-O1 (a) the trace rides inside every render answer (ok, failed, stuck: a partial trace naming the running query) under a last key `trace`, carrying the generation for free; Q-O2 (a) SQL text shown as is (it is the user's own query in their own editor), through `scrubUrls` as a backstop, capped at 16 KiB with a truncation marker; Q-O3 (a) no setting, always on; an interleaved on/off comparison on landing decides whether the per-row fetch clock stays (drop `fetchMs` rather than add a switch if it costs more than ~3% at tier l); Q-O4 (a) the hand-built Trace view now (Document | JSON | Trace), the trace JSON shaped so Ermine can decode it, and the Ermine-driven follow-on S2f (`Layout.Trace` types, an example trace report, `Ermine: Save Render Trace`) built after S2e if the night allows; Q-O5 (a) one output-channel line per render; Q-O6 (a) the phase bar in the Trace view only. Facts the design rests on: the server already computes per-relation stats on every render (`Write.scala:44-60`, `Interp.scala:124/149/185`) and the preview discards them at `Preview.scala:1510`; the SQL text and execute time exist at `SqlExecution.scala:34-58` and reach only a log4j TRACE line.
