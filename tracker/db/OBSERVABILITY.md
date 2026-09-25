# OBSERVABILITY: the render trace, as built (DB programme stage 2b, server half)

Built 2026-09-24/25 by the server-trace role on `widget-preview` (HEAD `a0919f57` plus the
uncommitted stage-2 tree). NOT REVIEWED, NOT COMMITTED. The design is
`scratch-widget-preview/db/DESIGN-OBSERVABILITY.md` (§1-§5). The user's answers Q-O1..Q-O6 are all
(a) (`tracker/db/DECISIONS.md`): the trace goes inside the answer, data values in SQL are shown as
they are, there is no setting, and the view is hand-built (the panel half, S2d, is in tracker §14
WP-35). **MEASURED** means it was run and the output is quoted. **INFERRED** means it was reasoned
from the code and not run.

The user's brief was: *"we want to see the queries generated, the results scanned, time spent in db vs
elsewhere, etc. ... valuing minimal configuration."* Every `ermine/render` answer from a render that
ran now carries a `trace` key. It needs no setting.

## 1. What is captured, and where

| Datum | Captured at (file:line as built) | Measured or attributed |
|---|---|---|
| Queue time (enqueue to job start) | `Render.trace` is created WITH the job, on the dispatch thread (`lsp/Preview.scala:2688`). It is started as the job leaves the queue, before `beforeJob` (`:992`) | measured |
| `session` / `boot` (roots, session, mtime scan, placement) | `tracedSession` around `placeAndSession` (`Preview.scala:2260`). The phase is named `boot` when this job built the render session | measured |
| `parse`, `compile` (`cached`), `decode` | `Runner.renderText`/`render` overloads that take a trace (`json/Runner.scala:469`, `:506`) | measured |
| `eval`, `layout` | summed over every evaluation step, including the continuations after each fetch (`Runner.scala:993-994`) | measured |
| `connect` | from `Runner.drive` entering `Run[DB].run` to `Interp.run`'s first action, plus from its last action to `run` returning (`Runner.scala:958-963`, `Interp.scala:113,129`). About 0 on a held connection | measured |
| Per relation: path, delivery, rows, scanned, columns, bytes, wall ms | `Interp` brackets every `Call`/`Splice`/`Token` with `enter`/`exit`, and `failed` on the failure path (`json/Interp.scala:125,139,166,245,255`). The figures are `RelationStats`' own | measured |
| `sql-emit` | `Optimizer.optimize` + `compileRel`/`compileMem` (`relational/SqlScanner.scala:287,306`) and `emitSql` (`sql/SqlExecution.scala:37-42`) | measured |
| SQL text, dialect | `SqlExecution.scanQuery` hands `query.run` to the trace before `prepareStatement` (`SqlExecution.scala:42`) | the text as sent |
| `execMs` (prepare + `executeQuery`) | `SqlExecution.scala:68` | measured |
| `fetchMs`, `rowsRead` | a `nanoTime` pair around each `rs.next()` only (`SqlExecution.scala:109`), folded in when the result set closes (`:118`) | measured |
| Setup statements (temp, create, load, memo `created`, drop) | `SqlScanner.traced` wraps each `sequenceSql` statement and each temp-table drop, and times it when it RUNS (`SqlScanner.scala:250`). This fixes the cumulative-ms oddity of the old TRACE log line | measured |
| `scan` | per relation: wall time minus database time minus `sql-emit`, summed | **attributed** (see §3) |
| `check` | the document size count and `Json.parse` (`Preview.scala:1637,1644`) | measured |
| `other` | wall time minus every phase above | **attributed** (the remainder) |
| Connection line | `traceConnection()` (`Preview.scala:2271`), read at job start: server-profile's `activeConnection` plus the connect answer's `database`; the implicit `local` is `{kind: "in-memory", dialect: "sqlite"}` | as held |

## 2. How it travels (design D1, as built)

| Hop | Mechanism | Why |
|---|---|---|
| Preview → Runner | an argument: `runner.renderText(module, binding, body, out, r.trace)` | explicit |
| Runner → Interp | `WriteConfig.trace`, the last field, defaults to `RenderTrace.Off` (`json/Write.scala`) | `WriteConfig` already reaches every Interp arm |
| Interp → SqlExecution / SqlScanner | a **thread-local**, `RenderTrace.installed(tr)(cfg.run.run(...))` in `Runner.drive` | the `Scanner` interface (4 implementations) does not change |

**Why a thread-local is acceptable.** A `DB` action runs on the thread that calls `Run[DB].run`.
The preview's whole render, scans included, runs on the one `ermine-preview` thread. The
thread-local is set and restored around exactly that call (`installed`'s `finally`, which the
`(off)` property pins even when the body throws).

**The HTTP server path (`bin/ermine-serve`) and every other caller** (`Runner.data`'s token re-fetch,
the legacy writers, the tests) never install a trace, so `RenderTrace.current` answers `Off`. Every
recording method returns at its first test, and the row driver is the original line with no clock.
**Nothing is captured there. The cost is one `ThreadLocal.get` per query** (INFERRED from the code).

**Threads.** Only the preview thread writes. The watchdog's timer thread reads a partial snapshot:
every value it reads is an immutable object behind a `@volatile` field and is replaced at each
event (relation entered or left, query started or executed, statement run, phase ended). The
per-row counters are plain fields folded in when the result set closes. So a partial trace shows a
running query's rows as of its last event.

## 3. Measured vs attributed

| Figure | How |
|---|---|
| every phase except `scan` and `other`, and every per-query ms | a `System.nanoTime` difference around the work it names |
| `scan` (ATTRIBUTED) | per relation, `ms - dbMs - sqlEmitMs`, summed. It is what Ermine does WITH the rows as they arrive: decoding them, relational work the SQL did not do, and JSON-encoding inline rows. **MEASURED example:** `DbFetchTopN`'s `$.fetch[1]` is `groupBy {region} (sumBy amount) sales`. It is a `Mem`, so at tier s the SQL reads all **388** rows and Ermine groups them into the **8** the report gets. That grouping is most of the relation's 36.7 ms, of which 6.4 ms is database time |
| `other` (ATTRIBUTED) | `wallMs` minus every phase. Unbracketed time shows up here instead of vanishing |
| `totals.dbMs` | `connect + db-execute + db-fetch`, where `db-execute` is setup statements plus `execMs` |
| `totals.otherMs` | `wallMs - dbMs`, **by construction, never a sum**, so `dbMs + otherMs == wallMs` exactly before rounding to 0.1 ms |
| phases | disjoint, and they sum to `wallMs` (the `(sum)` property). Queue time is NOT in `wallMs`: it is `totals.queueMs` |
| `rowsRead` vs `rows` | `rowsRead` counts what the database returned (`rs.next()` true). `rows` counts what went to the report or the wire (`RelationStats`). They differ after a `Mem` operation (above), after `uniqSorted` removed duplicates, or when a scan stopped at the threshold |

## 4. The `trace` key: JSON schema (version 1)

`trace` is the **LAST** key of every `ermine/render` answer from a job that RAN: ok, failed (a Runner
4xx/5xx, a placement 404, the 503 not-connected, the document-size 500, a crash) and the
watchdog's stuck answer. It is **absent** on renders refused before they ran (displaced -32800,
refused while stuck, drained from the queue behind a wedge) and on answers the extension builds
itself.

| Key | Type | Meaning |
|---|---|---|
| `v` | int | 1 |
| `generation` | any | the answer's own `generation`, so a client can check that the pair belongs together |
| `partial` | bool | true only on the watchdog's stuck answer |
| `wallMs` | number | from the job leaving the queue to the answer being built (0.1 ms) |
| `phases[]` | `{name, ms, attributed?: true, cached?: bool}` | in pipeline order: `session`\|`boot`, `parse`, `compile` (`cached`), `decode`, `eval`, `layout`, `connect`, `sql-emit`, `db-execute`, `db-fetch`, `scan` (attributed), `check`, `other` (attributed). A phase that took exactly 0 ns (never entered) is omitted; one under 0.05 ms prints as 0 |
| `queries[]` | object | one per relation, **in execution order**: fetch scans first, then the wire relations in document order. At most 200 |
| `queries[].path` | string | the relation's `$`-path (`$.fetch[1]`, `$.children[0].props.pieRows`): the same path as the JSON tab and errors |
| `.delivery` | string | `fetched` \| `inline` \| `deferred` |
| `.dialect`, `.sql`, `.sqlBytes`, `.statements` | string, string, int, int | present when SQL ran. `sql` is capped at 16 KiB UTF-8 at a character boundary, followed by `\n-- [ermine: truncated, N more bytes]`. `sqlBytes` is the full length. `statements` is the number of SELECTs this relation ran (1 today) |
| `.setup[]` | `{kind, table?, created?, ms, error?}` | `kind`: `temp` \| `create` \| `load` \| `memo` (`created` tells made from reused) \| `drop` \| `statement`. Absent when empty |
| `.sqlEmitMs`, `.execMs`, `.fetchMs`, `.dbMs`, `.ms` | number | generation, prepare+execute, the `rs.next()` clock, setup+exec+fetch, and the relation's wall time |
| `.rowsRead`, `.rows`, `.scanned`, `.columns`, `.bytes` | int | §3; `bytes` is the relation object's UTF-8 length (0 for a fetch) |
| `.deferred`, `.overThreshold?`, `.error?`, `.message?` | bool, bool, bool, string | a failed relation is the LAST entry, with `error: true`, the message and the SQL that failed |
| `totals` | `{dbMs, otherMs, wallMs, queueMs, relations, queries, rowsRead, rows, bytes, documentBytes?}` | the totals count every relation, including any past the 200 cap |
| `connection` | `{kind, dialect, database?, profile?}` | `kind`: `in-memory` (the per-render SQLite) or `profile`. It never carries a URL, user, host or password |
| `running?` | `{path?, phase?, sql?, sinceMs}` | only when `partial`: the relation and SQL still running, or the phase (e.g. `eval`) |
| `truncated?` | `{queries, sqlShortened}` | entries dropped by the 200 cap or the 256 KiB whole-trace cap, and whether every SQL text was cut to 1 KiB first |

**MEASURED example.** This is a warm `DbFetchTopN {"keep":2}` render through the preview's real
wire, held connection `sales-mssql`, ErmineSales at **tier s** (seed 42). It is from
`TestRenderTraceLive`, 2026-09-25 00:0x, printed as `EXAMPLE trace`.

```json
{"v":1,"generation":110,"partial":false,"wallMs":51,
 "phases":[{"name":"session","ms":4.5},{"name":"parse","ms":0},{"name":"compile","ms":0,"cached":true},
  {"name":"decode","ms":0.1},{"name":"eval","ms":2.6},{"name":"layout","ms":0.1},{"name":"connect","ms":0},
  {"name":"sql-emit","ms":0.8},{"name":"db-execute","ms":9.2},{"name":"db-fetch","ms":1.8},
  {"name":"encode","ms":30.7,"attributed":true},{"name":"check","ms":0.1},{"name":"other","ms":1.2,"attributed":true}],
 "queries":[
  {"path":"$.fetch[1]","delivery":"fetched","dialect":"mssql",
   "sql":"select ([t1030144].[amount]) [amount], ([t1030144].[day]) [day], ([t1030144].[region]) [region], ([t1030144].[units]) [units] from [sales] [t1030144] order by [t1030144].[region] asc",
   "sqlBytes":182,"statements":1,"sqlEmitMs":0.4,"execMs":4.7,"fetchMs":1.7,"dbMs":6.4,"ms":36.7,
   "rowsRead":388,"rows":8,"scanned":8,"columns":0,"bytes":0,"deferred":false},
  {"path":"$.fetch[2]","delivery":"fetched","dialect":"mssql",
   "sql":"select ([t1031168].[region]) [region], ([t1031168].[target]) [target] from [targets] [t1031168]",
   "sqlBytes":95,"statements":1,"sqlEmitMs":0.2,"execMs":3.5,"fetchMs":0,"dbMs":3.6,"ms":4.1,
   "rowsRead":8,"rows":8,"scanned":8,"columns":0,"bytes":0,"deferred":false},
  {"path":"$.children[0].props.pieRows","delivery":"inline","dialect":"mssql",
   "sql":"select [amount],[region] from (values (225449.87999999998, 'china'), (172784.89, 'us-south'), (652859.45, 'Other')) as lit([amount],[region])",
   "sqlBytes":141,"statements":1,"sqlEmitMs":0.2,"execMs":0.9,"fetchMs":0,"dbMs":0.9,"ms":1.6,
   "rowsRead":3,"rows":3,"scanned":3,"columns":2,"bytes":225,"deferred":false}],
 "totals":{"dbMs":11,"otherMs":40,"wallMs":51,"queueMs":0,"relations":3,"queries":3,
           "rowsRead":399,"rows":19,"bytes":225,"documentBytes":717},
 "connection":{"kind":"profile","dialect":"mssql","database":"ErmineSales","profile":"sales-mssql"}}
```

This example was captured just before the attributed phase was renamed `encode` → `scan` (§3 says
why). The same render today prints `{"name":"scan","ms":30.7,"attributed":true}` in that position.
Nothing else changed. Reading it: 51 ms of wall time, of which 11 ms was in SQL Server (3 queries).
Most of the other 40 ms (30.7 ms `scan`) is Ermine grouping 388 sales rows into 8 regions, because
`groupBy ... (sumBy ...)` is not pushed into the SQL. Each `rowsRead` was checked against the
database: the suite ran each query's own SQL text over JDBC and got 388, 8 and 3 rows.

## 5. Ordering hazards (design §4, as built)

| Hazard | As built | Pinned by |
|---|---|---|
| A displaced render's trace on a later answer | The trace is a field of its `Render` job (`Preview.scala:2688`): created with it, answered with it, and `Rpc.Answer` is one-shot. A displaced job is answered -32800, which has no result and so no trace | `TestRenderTrace` (t7): B displaced, no trace; A's and C's traces carry generations 21 and 23 |
| A job that finishes after the watchdog answered it | `finish` sends nothing. The late job's trace summary goes to the LOG only: `preview: job 3 finished after the watchdog answered it: trace wall 312.1 ms, db 1.4 ms, 3 queries, 14 rows read` (MEASURED, the t4 run) | (t4) |
| Stuck: which query is hung | `fire` (timer thread) answers `withTrace(job, job.stuckRefusal(why), partial = true)`: `stuck: true`, then `trace` last, `partial: true` and `running: {path, sql, sinceMs}`. A query whose `executeQuery` has not returned counts as db time so far | (t4): a render held inside `$.fetch[1]`'s query past a 300 ms watchdog. The answer named `$.fetch[1]` and its SELECT, and `db-execute` was 292.6 ms of 300.9 ms wall (MEASURED) |
| Refused before it ran | `trace.started` is false, so no trace | by construction; (t7) |
| Building the trace fails | `withTrace` catches, logs `preview: trace not attached: ...` and sends the answer unchanged | by construction |

## 6. Caps and redaction

| Rule | As built |
|---|---|
| SQL per query | 16 KiB UTF-8, cut at a character boundary (a surrogate pair is never split), plus the marker. `sqlBytes` is the full length (`(cap)`: 100 generated texts including multi-byte characters and emoji) |
| Entries | 200. `truncated.queries` counts the rest, and `totals` count everything (`(max)`: 250 relations → 200 kept, 50 counted, totals 250) |
| Whole trace | 256 KiB, estimated as the SQL bytes plus 400 B per entry. Over it, every SQL text is cut to 1 KiB (the marker counts from the FULL length), then entries are dropped from the end (`(max)`: 40 × 20 KB SQL → 40 kept, `sqlShortened: true`) |
| Password / URL / user / host | never held by the trace (`connection` holds kind, dialect, database and profile id). Every SQL text and message goes through `scrubUrls` and server-profile's `scrubProfile` (A10) as a backstop (`(json)`: a `jdbc:...;password=...` literal inside SQL and inside a message is gone from the printed trace). The live suite greps the log and every frame for the password: 0 hits |
| Data values in SQL | shown as they are (Q-O2 (a)): the `VALUES` literal in the example is the user's own data |

## 7. The cost: interleaved A/B at tier m

MEASURED on 2026-09-25 with `ERMINE_TRACE_AB=1 core/testOnly *TestRenderTraceLive`, ErmineSales at
tier m (seed 42, 106,106 rows loaded). `Runner` was driven directly on ONE held MSSQL connection.
Each report got 3 warm-up renders, then 5 rounds of {`Off`, trace with the per-row clock, trace
without it}, rotating the order each round. Figures are wall ms per render, median of 5.

| Report | rows read | Off | trace + row clock | Δ | trace, no row clock | Δ |
|---|---|---|---|---|---|---|
| `DbFetchRunning` | 15,402 | 572.8 (553.8-643.3) | 573.7 (565.7-609.1) | **+0.2%** | 586.8 (553.1-646.7) | +2.4% |
| `DbFetchTopN` | 7,716 | 103.8 (100.3-127.4) | 105.3 (100.3-127.8) | **+1.5%** | 107.8 (101.0-125.4) | +3.9% |

**Decision: `fetchMs` stays (Q-O3 (a), no setting).** With the row clock, the median moved +0.2% and
+1.5%, below the ~3% bar. The row clock cannot be separated from noise at 5 rounds: the variant
WITHOUT the row clock came out slower than the one with it, and each column's own spread is 10-20%.
So the honest statement is "no cost resolvable at this sample size, and under 3% in both medians".

Also MEASURED in that run: `DbFetchRunning` at tier m spends wall 573.7 ms = eval 317.4 +
db-execute 164.9 + db-fetch 1.4 + scan 87.9 + small change. `db-fetch` is only 1.4 ms over 15,402
`rs.next()` calls. INFERRED: the driver buffers rows (`setFetchSize(10000)`,
`SqlExecution.scala`), so most calls read memory and the network wait lands in `execMs`. A trace
therefore reports the database wait mostly as `db-execute`.

## 8. Tests and evidence

| Suite | Where it runs | Result (MEASURED, once each unless noted) |
|---|---|---|
| `TestRenderTrace` (8 properties: cap, sum, part ×2, max, off, json, and the preview-path property with t1/t3/t4/t7) | `core/test` (`suites`), no environment | **8/8 passed**, 12 s. Two properties were red on the first run, both test expectations: the whole-trace cap was correctly cutting a 200×2 KB trace, and FetchTopN's `$.fetch[1]` reads 8 rows and uses 4. Fixed in the test; one re-run |
| `TestRenderTraceLive` (live, env-gated, registers nothing without `ERMINE_DB_*`) | the `db` gate (`scripts/gates.sh`: added to its `testOnly` list and description) | tier s: **1/1 passed**, 20 s. The first run was red on DbFetchHeadline's shape above xs, because `onlyRegion: "north"` does not exist at s. The shape check is now xs-only; one re-run. Per twin, every rerunnable query's `rowsRead` equals the JDBC row count of its own SQL (e.g. DbFetchTabs: 8, 80, 32, 42, 54, 41, 45, 55, 39). Dialect mssql, database ErmineSales. The SQLite twin's trace says dialect sqlite. Tier m (the A/B run): **2/2 passed**, 914 s. The live property was re-evaluated 100 times: its conjunction ended `True` instead of `Proof`. It now runs once (`minSuccessfulTests 1`) |
| Password grep over each log | here | 0 hits |

The `db` gate itself was NOT run by this role. It needs tier xs, and `TestRenderTraceLive`'s shape
check (twin entries == original entries) is xs-only by design.

## 9. Findings for the user

1. **Ermine aggregates in memory what looks like SQL.** `groupBy {region} (sumBy amount) sales` is a
   `Mem`: the database returns every row and Ermine does the grouping. At tier s that is 388 rows
   for 8 regions. At tier m, 7,701 rows for 12. At tier l (2,052,515 fact rows) this would be the
   dominant cost of `DbFetchTopN`. The trace makes it visible as `rowsRead` much larger than `rows`,
   and as a large `scan`.
2. **Evaluation dominates `DbFetchRunning` at tier m** (eval 317 ms of 574 ms), not the database
   (166 ms).
3. **A profile switch costs a session boot** (~1.6-1.7 s `boot` in the first render after
   `connect`), because the scanner is baked into the `Runner` (SERVER.md §2, §7.2 step 4).

## 10. Open

| # | Question | Recommendation |
|---|---|---|
| T-1 | `statements` is always 1 today: a relation runs one SELECT. Keep the key (future `ExtSM` scans could run several) or drop it? | keep; it costs nothing |
| T-2 | The partial trace shows a running query's rows as of its last event (the counters fold in at close), so a stuck `rs.next()` loop shows `rowsRead` 0. Publish the counter every N rows? | leave it until a stuck FETCH (not EXECUTE) is seen in practice |

## 11. The trace as Ermine data (S2f, built 2026-09-25; NOT REVIEWED, NOT COMMITTED)

Design §3.6's recommendation (Q-O4 a): the hand-built Trace view stays THE view, and the trace is
also the PARAMETERS of an ordinary Ermine report. No wire change, no new setting, no new widget.

| Part | What | Where |
|---|---|---|
| The types | `Trace` and one record per nested object (`TracePhase`, `TraceQuery`, `TraceSetup`, `TraceTotals`, `TraceConnection`, `TraceRunning`, `TraceTruncated`). Field names = the §4 keys, so Decode reads the server's JSON unchanged. A key the server leaves out is a `Maybe` field (absent -> Nothing). `generation` is `Json`. One module per record, because `ms`, `rows`, `path`, `sql`, `kind` and `queries` are keys of several records and a selector is module-global. `table` (setup) and `database` (connection) are Ermine KEYWORDS, so those two records carry a `Spread Json` that gathers them | `core/src/main/resources/modules/Layout/Trace.e`, `Layout/Trace/*.e` |
| The helpers | `traceQueries`, `tracePhases`, `traceSql`, `traceTimes`, `traceRowCounts` build relations with `relationWithHeader`, so an empty trace still gives typed, empty relations (the Q21 lesson). Plus the numbers (`traceWallMs`, `traceDbMs`, ...) and the text (`traceConnectionLine`, `traceCaveat`). A relation has no row order, so the phase label carries its position (`01 session`) for the chart's ascending axis | the same |
| The report | `report : Trace -> Node`: a headline (queries, wall ms, slowest relation ms), a caption, time and row scorecards, a bar chart of time by phase, the relations table sorted by total ms, a pie of time by relation, and the SQL table (a String column; the server's 16 KiB cap is stated under it) | `core/src/test/resources/modules/Doc/TraceReport.e` |
| The fixture | §4's example with `encode` renamed `scan` | `core/src/test/resources/doc/trace-sample.json` |
| The commands | **Ermine: Save Render Trace** writes the trace of the answer the panel shows (`panelAnswers.last`) to `.ermine/preview/Doc.TraceReport/report.params.json` (the dotted module name is the directory, as for every params file) through `applyWritePlan`. An existing file is replaced only after a modal. A newer answer arriving while the modal is open means nothing is written. **Ermine: Preview Render Trace** saves, then picks `Doc.TraceReport.report` through `commitPick`, the picker's own tail, so the wedge guard, the queue and the params watcher apply as they do to any report. Only the keys the types declare are written (`traceParamsOf`), so no url, user or host can reach a file that may be committed | `editor/vscode/src/preview-core.js` and `extension.js`, fenced `S2f trace as params` |

**The recursion rule.** The trace report's own render is traced like any other: its answer carries
the trace of its VALUES scans (on the held profile those are queries on the user's database, one per
relation widget). Saving while it is picked writes THAT trace over the params file it is showing.
The modal guards exactly that, and nothing re-saves automatically, so there is no loop.

**The decoder's rule for unknown keys.** A record is CLOSED: an unknown key is REFUSED with a 400 at
its path (`$.params.nope`, `$.params.queries[1].rowz`: MEASURED). Inside the two `Spread Json`
records (setup, connection), an unknown key is GATHERED, not refused. The extension writes only the
declared keys, so a newer server's extra key never reaches the report through the command.

**Evidence (MEASURED, 2026-09-25).** `sbt 'core/testOnly com.clarifi.reporting.TestRunner -- -f trace'`: 2/2.
`(trace-doc)`: 9 widgets `headline,text,scorecard,scorecard,axisChart,table,pieChart,table,text`;
headline total 51, rowCount 3, largest 36.7; time {wall 51, db 11, other 40, queue 0}; rows {read 399,
used 19}; 3 query rows with rowsRead 388/8/3; 13 phases. An empty trace renders 200, with 4 empty
relations that keep their columns and the text `partial: still running eval after 300.9 ms`. The
document goes to `core/target/trace-report/TraceReport.document.json`. `(trace-decode)`: the sample
round-trips through an echo report; 8 optional keys each absent -> 200 and round-trip; setup (with
`table`), running, truncated and a failed query round-trip; an unknown key -> 400 at its path; a
missing `totals.rowsRead` -> 400 at `$.params.totals`; an unknown key in `connection` is gathered.
`npm run test:preview` 476/476 (15 new in `test/trace-save.test.js`: the projection, the decisions, a
glue model, glue pins, and the reverse mutants "trace saved from a stale generation", "writer
bypassing the modal", "pick bypassing the guard" and "whitelist", each killed by name).
Headless: `scratch-widget-preview/db/s2f/shot.js` feeds that document to the real panel as a render
answer: `trace-report-dark.png`, `-light.png`, `-narrow.png` (390 px), no console errors.

**Finding S2f-1 (MEASURED headlessly; affected every chart, not only this report). FIXED
2026-09-25 by linking the sheet (below).** In the panel the `axisChart` and `pieChart` drew as BLACK boxes. The writers render Highcharts in styled mode
(`styledMode: true` in `htmlwriter.js`), and the styled-mode rules live only in `javafxwriter.css`,
which the panel deliberately does not load (tracker WP-11 D6). With those rules alone (508 of
`javafxwriter.css`'s 780 rules, filtered by the harness) the charts draw:
`scratch-widget-preview/db/s2f/old/trace-report-dark-with-chart-subset.png` (the pie's legend table
still overlaps). Loading the whole file with no counters overlaps the charts (`old/...-with-chart-css.png`: its `.timeseries` is `position:fixed`). The checklist's
E10 ("a pieChart draws") would have failed the same way.

**The fix, chosen by measurement: LINK the sheet, not a copied subset.** `javafxwriter.css` is the
fourth `<link>` (`preview-core.js` `PREVIEW_WRITERS_STYLES`; a writers folder without it is `half`,
with the banner naming it). It has no `url()` except the in-document `#posNegGradient`, so no
console noise. Three of its effects came from JavaFX's one-chart window and are countered in
`client/src/host/page.ts` (`CHART_HEIGHT`): `body{background-color:white}` (the body is given the
editor background back), `.timeseries{position:fixed;width:100%;height:100%}`, and the writers
sizing each chart div to the WINDOW (`getHighestParentSize` climbs to `body` unless a parent has an
INLINE height, then uses `$(window).height()`). A chart div is now `height:320px!important;
width:100%!important`. Highcharts reads its container when it draws, so the chart is drawn at that
size, not clipped. A RightTable pie legend's SVG symbols are hidden, as `common.css` already does
for the drilldown pie. The headline figures and scorecard cards are laid out as a row (CSS only).
MEASURED in both themes, 1100 px and 390 px: every chart container 1040x320 (330-335x320 narrow)
with its SVG the same size (none clipped); fills `rgb(0, 187, 221)`, not black; table rows 19 px
with stripes #fff / #E9E9E9, as before; no horizontal page scroll (390 of 390; it was 420 before);
no console line. Screenshots: `scratch-widget-preview/db/s2f/salesreport-{dark,light}.png`,
`trace-report-{dark,light}.png` (+ `-narrow`); the before shots are in `old/`. Tests:
`npm run test:preview` 476/476 (the 3->4 sheet pins moved); client `npm run bundle && npm test`
157 (156 pass, 1 skipped), with `(pg-s2f-charts)` new; `ermine-host.js` is 64,165 B of the 96 KiB cap.
