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


## Stage 2 (profile, trace, extension, panel, dogfood), folded 2026-09-25

Source: `scratch-widget-preview/db/BOARD.md`, every stage-2 `[decision]` entry, one line each. The user's answers
Q-S1..Q-S5 and the orchestrator's Q-O1..Q-O6 are in `tracker/db/DECISIONS.md`.

## Decisions on the board

| Time | Role | Decision |
|---|---|---|
| 09-24 16:30 | orchestrator | Stage 2 opens: S2a profile + S2b trace in parallel, then S2c extension, S2d panel, S2e dogfood guide (S2f Ermine-driven trace if the night allows); Q-S (a,a,a,a,b), Q-O all (a); morning target = DbFetchTopN from ErmineSales tier s after one password prompt, plus a Trace view |
| 09-24 23:30 | panel | Owns fenced `// ---- S2d trace (panel) ----` regions: traceOf/traceSummary/traceStatusSuffix/traceOutputLine/traceMessage, panelView.trace, a tenth panel message kind `trace`; never touches connect/password code |
| 09-24 23:30 | server-profile | Owns `// ===== WP-13 profile =====` regions of Preview.scala: connect/disconnect jobs, 503 not-connected + isValid before placement, Reason gains NotConnected + four connect-* values, scrub extended |
| 09-24 23:31 | server-trace | New RenderTrace.scala + TraceJson.scala; explicit Preview -> Runner -> Interp (WriteConfig.trace), thread-local only for the last hop into SqlExecution/SqlScanner; `trace` LAST on answers of jobs that ran |
| 09-24 23:38 | extension | Owns one WP-13 section in preview-core.js (profilesCheck, profileKey = sha256(id,url,user), passwordPrompt, connectRequest, connectReduce...) + glue blocks in extension.js; new unconfirmed trigger TRIGGER_RECONNECTED. (Its "resource scope" choice was SUPERSEDED at 23:48.) |
| 09-24 23:38 | extension | The connection gets its OWN lazy status bar item; statusBarState stays the preview item's (panel adds the trace suffix to the idle arm) |
| 09-24 23:45 | panel | Reconciled to server-trace's keys as built (path, running.path/phase, db = connect + db-execute + db-fetch); status bar idle arm gains " · N ms" + tooltip line |
| 09-24 23:47 | server-trace | Container loaded at tier m for the S2b interleaved A/B, reloaded to s at 00:03 |
| 09-24 23:48 | extension | Tracker §8.1 A2 RESTORED (orchestrator): both settings USER scope only (`application`, `inspect().globalValue`); a workspace/folder value ignored and named once |
| 09-25 00:03 | server-profile | Container loaded at tier xs for ONE TestPreviewDbLive run, reloaded to s (seed 42, verify OK) |
| 09-25 00:10 | dogfood | S2e: DOGFOOD.md steps, checklist group F (NEVER RUN, EXPECTED cited file:line, checked by dogfood-citecheck.py), MORNING-2026-09-25.md; docs only |

Decisions recorded outside `[decision]` tags but binding (from findings/handoffs):
- 23:48/23:49 server-profile + extension: connect class `connect` is spelled **`unreachable`** as built; tracker §4 updated; the extension also accepts `connect`.
- 00:06 server-trace: the attributed per-relation phase is **`scan`** (was `encode`); phases are disjoint and sum to wallMs; `fetchMs` stays (A/B at tier m: +0.2% / +1.5% median).
- 00:08 panel: the rowsRead > rows note reads "the database returned N rows; Ermine reduced them to M" (not "duplicates").
- 00:10 extension: panelView takes a `connection` field {id, dialect, host, database} of the HELD connection only; never url or user.

## Open questions for the user

1. **Commit `.ermine/preview/Sales/report.params.json`?** It differs from HEAD (`toDay` 2026-12-31 -> 2026-01-30, mtime 2026-09-23 21:05, before stage 2): it is the user's own edit and should stay OUT of the stage-2 commit unless the user says otherwise.
2. **Q-O3 was answered for tier l; the A/B ran at tier m** (15,402 and 7,716 rows read). Accept m as the landing measurement, or run the tier-l A/B (~15+ min live, needs the container at l)?
3. **The host-bundle cap** (`client/test/bundle.test.ts:187`, 64 KiB): ermine-host.js is 61,724 B, 3,812 B (5.8%) headroom. The cap guards against zod being pulled in (zod is ~154 KiB) and a zod regex already does that. Raise to 96 KiB, or keep 64 KiB and trim?
4. The orchestrator answered Q-O1..Q-O6 overnight; the user has not been asked (DECISIONS.md says so). Confirm on waking.

## Findings worth a ticket

| # | Finding | Evidence | Suggested owner |
|---|---|---|---|
| F-1 | **groupBy/sumBy is not pushed into SQL.** `DbFetchTopN`'s `$.fetch[1]` (`groupBy {region} (sumBy amount) sales`) is a `Mem`: the SQL is a plain `select amount, day, region, units from sales order by region`; SQL Server returns 388 rows at tier s (7,701 at m) and Ermine reduces them to 8 (12). 30.7 ms of a 51 ms render is `scan`. At tier l (2.05 M fact rows) it would dominate. | OBSERVABILITY.md §4 MEASURED trace (rowsRead 388, rows 8, SQL text quoted); re-rendered by the verifier from that trace: the Trace view shows "the database returned 388 rows; Ermine reduced them to 8" | engine ticket candidate (optimizer: push Mem group/aggregate to SqlPrg for SQL-capable scanners) |
| F-2 | Evaluation, not the DB, dominates `DbFetchRunning` at tier m (eval 317 of 574 ms). | OBSERVABILITY.md §7 | perf roadmap |
| F-3 | A profile switch costs a full session boot (~1.6-2.2 s) because the scanner is baked into the Runner. | SERVER.md §6.3, OBSERVABILITY.md §9.3 | WP-13 follow-on |
| F-4 | `##` temp tables accumulate on the held connection until disconnect (WP-14's 1-hour count not run). | SERVER.md §6.4 P2 | WP-14 |
| F-5 | A stuck `rs.next()` loop shows rowsRead 0 in the partial trace (counters fold at close). | OBSERVABILITY.md §10 T-2 | leave until seen |

## Added after the dogfood handoff (verifier, 00:28)

| Time | Role | Decision / change |
|---|---|---|
| 09-25 00:17 | dogfood | S2e DONE: DOGFOOD.md steps 0-12, checklist group F F1-F12 (NEVER RUN), PLAYTEST-RESULTS group F, PLAYTEST-SETUP §14, MORNING-2026-09-25.md with an ORCHESTRATOR FILLS block; citecheck 121/121 |
| 09-25 00:22 | extension | **NEW-2 FIXED (posted as a finding; should be logged as a decision):** a failed `unreachable`/`connect`/`driver` connect with the password held is retried unattended after 5 s and 15 s (3 attempts in all), and a render answered 503 connects ONCE when it can without a prompt; auth / kept:false / profile are never retried; Disconnect cancels; status `<id>: reconnecting (n/3)`; 461 tests. Makes DOGFOOD F11 and MORNING's NEW-2 row stale (REVIEW-S2 MF-2) |

Open for the user (additions): NEW-1 (dogfood) the auth notification says `<user> @ <host>` (server scrub) while the prompt names `ermine @ 127.0.0.1`: keep the scrub or re-label in the extension. NEW-2's retry policy (5 s, 15 s, 3 attempts, no setting): accept.

Also decided overnight by the orchestrator, after a dogfood finding (NEW-2): a failed connect of class unreachable or driver with a held password is retried after 5 s and 15 s (three attempts in all; cancelled by Disconnect, a server stop, a profile change or teardown), and a render that gets the 503 with a held password tries one connect first; no setting. The user has NOT been asked.
