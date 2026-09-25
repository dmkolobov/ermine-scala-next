# REPORTS: the DB-backed twins of the Doc fixtures

DB-PLAN S1, role reports, 2026-09-24 (D7 (a), D8, D13). MEASURED = run here; MINED = read in
the source at the cited line.

## 1. The twins

| Twin | Original | What changed | Data comes from |
|---|---|---|---|
| `core/src/test/resources/doc/DbFetchData.e` | `doc/FetchData.e` | the two literals became `table` statements; the same five fields, the same types, the same exported names `sales` and `targets` | the views `sales` and `targets` in ErmineSales (`tracker/db/SCHEMA-SALES.md` §2), or the same views in the SQLite twin |
| `doc/DbFetchCrosstab.e` | `doc/FetchCrosstab.e` | module name, header, `import DbFetchData`; `calendar` STAYS a literal (see §4) | `sales` table + a `VALUES` literal, joined in SQL |
| `doc/DbFetchFragments.e` | `doc/FetchFragments.e` | module name, header, `import DbFetchData` | `sales`, `targets` |
| `doc/DbFetchHeadline.e` | `doc/FetchHeadline.e` | same | `sales` |
| `doc/DbFetchRunning.e` | `doc/FetchRunning.e` | same | `sales`, `targets` |
| `doc/DbFetchTabs.e` | `doc/FetchTabs.e` | same | `sales` |
| `doc/DbFetchTopN.e` | `doc/FetchTopN.e` | same | `sales`, `targets` |
| `core/src/test/resources/modules/Doc/DbSalesReport.e` | `modules/Doc/SalesReport.e` | module name, header, and `sales = sales_report` over one `table` in place of the `mkRelation#` literal | the base table `sales_report` |

The six `DbFetch*` twins differ from their originals in exactly the module line, a 7-line
header and the one import (`diff doc/FetchX.e doc/DbFetchX.e`); FetchCrosstab's twin has 3
more header lines explaining the calendar.

## 2. The exact `table` lines

```
-- DbFetchData.e
field region : String
field day    : Date
field amount : Double
field units  : Int
field target : Double

table sales   : [region, day, amount, units]
table targets : [region, target]

-- Doc/DbSalesReport.e
field srRegion : String
field srSales : Double
field srDelta : Double

table sales_report : [srRegion, srSales, srDelta]
```

Bare names with no `database "..."` block, as schema recommended (`SCHEMA-SALES.md` §7): the
connection decides the database, MSSQL resolves `sales` through the login's default schema
`dbo`, and SQLite would read `dbo.sales` as an attached database. The types are the contract's
`ermine` values (`data/schema/sales.contract.json`).

| Parser question | Answer |
|---|---|
| Does a bare `table` parse? | Yes. `tableStatementP` (`SurfaceParsers.scala:654`) takes a `dottedDefName` (`:648-652`), which is one identifier or several joined by `.`; `SortTest.e:8` was the only precedent. MEASURED: the twins compile and run. |
| Can a table name hold `_`? | Yes: `sales_report` binds a term of that name (MEASURED, DbSalesReport renders). |
| Can a `table` statement sit beside ordinary bindings? | Yes: `DbSalesReport.e` has the `table`, `sales = sales_report` and `report` (MEASURED). `DbFetchCrosstab.e` joins an IMPORTED table with a LOCAL literal (MEASURED). A single module that declares both a `table` and a literal relation is not separately tested; nothing in the parser separates them (`table` is one more statement, `Session.processTableStatement`, `Session.scala:2050`). |

## 3. How to run them

| What | Command |
|---|---|
| The whole comparison, once, live | `tracker/tools/db-reports.sh` (password from `~/.config/ermine/db.env` into the sbt JVM's environment only, as `tracker/tools/db-smoke.sh`); the database must hold tier xs |
| Skip mode | `tracker/tools/db-reports.sh --skip`: both sets SKIP by name |
| Another database / file | `ERMINE_DB_URL`, `ERMINE_DB_USER`, `ERMINE_DB_SQLITE` (default `data/out/sales/xs/sales.sqlite`) |
| The test | `scalacheck-binding/src/main/scala/TestDbReports.scala` (`core/testOnly com.clarifi.reporting.TestDbReports`) |

How the test reaches the database: the runner takes any `(Run[DB], Scanner[DB])` pair
(`RunnerConfig`, `json/Runner.scala:171-179`). The SQL Server runner is
`RunnerConfig(run = DB.RunUser("com.microsoft.sqlserver.jdbc.SQLServerDriver")(url, user,
password), scanner = Scanners.MicrosoftSQLServer(SMEnv.dummySmenv))`: one connection per request
with a login (`DB.scala:129-138`, which had no caller before this). The SQLite twin's runner is
`Runners.SQLite("jdbc:sqlite:<abs path>")` with `Scanners.SQLite`. The originals run on
`jdbc:sqlite::memory:`, as in `TestRunner`.

Per backend there is one property per twin and one for the totals:

* **Same document.** Each twin is rendered with the requests `TestRunner` (fx1-fx6, b3z) sends
  to its original (13 requests in all, one with `data.default = deferred`). The masked documents
  (tokens and expiry times blanked) must be equal once the inline `rows` of every relation object
  are sorted. A `[db-reports]` line records, per request, whether the bytes were equal WITHOUT
  the sort.
* **Totals.** These are read from the twins' own documents: the four region amounts and the whole
  (crosstab row totals and grand total), 34 units, the headline's 8 rows and 12682.0, Other =
  4155.75 at keep 2, 2 targets met, the running total ending at 12682.0, and srSales 529.5 over
  3 rows.

## 4. What differs from the in-memory originals

| Difference | Where | Status |
|---|---|---|
| Where the rows come from: a scan of a table/view on the connection instead of a `VALUES` literal | all seven | by design |
| The ORDER of inline rows of an unordered relation | 8 of the 13 requests on SQL Server | MEASURED: the documents are byte-identical once rows are sorted; SQL Server returns an unordered scan in its own order. The 5 requests whose relations are all ordered or empty are byte-identical as sent. |
| `calendar` in DbFetchCrosstab is still a literal | `DbFetchCrosstab.e` | chosen: ErmineSales has a `calendar` view, but the module declares `monthName` itself, and joining a table to a literal on one connection is worth exercising. A twin over `table calendar : [day, monthName]` would need the field moved to DbFetchData (schema's §7 sketch) |
| Tiers above xs | all | the equality holds at xs only; at s and above the numbers are the generator's, and `sales_report` is derived per region group |

## 5. Live results

MEASURED 2026-09-24 22:22. This was one run of `tracker/tools/db-reports.sh` against
`ermine-mssql` (2022 CU27) with ErmineSales at tier xs (8 sales rows and 8 fact lines, checked
first). The whole sbt run took 11 s.

```
[db-reports] mssql DbFetchTopN request 1: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql DbFetchHeadline request 1: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql DbFetchRunning request 1: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql DbFetchTabs request 1: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql DbFetchFragments request 1: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql Doc.DbSalesReport request 1: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql DbFetchCrosstab request 1: status 200, bytes EQUAL, modulo row order EQUAL
[db-reports] mssql DbFetchTabs request 2: status 200, bytes EQUAL, modulo row order EQUAL
[db-reports] mssql DbFetchRunning request 2: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql DbFetchHeadline request 2: status 200, bytes EQUAL, modulo row order EQUAL
[db-reports] mssql DbFetchTopN request 2: status 200, bytes EQUAL, modulo row order EQUAL
[db-reports] mssql DbFetchHeadline request 3: status 200, bytes differ, modulo row order EQUAL
[db-reports] mssql DbFetchCrosstab request 2: status 200, bytes EQUAL, modulo row order EQUAL
[db-reports] mssql totals: regions Map(east -> 4175.5, north -> 4350.75, south -> 2605.75, west -> 1550.0), all Some(12682.0), units Some(34.0), headline rows Some(8.0) total Some(12682.0), Other Some(4155.75), met Some(2.0), running ends Some(12682.0), srSales 529.5 over 3 rows
[info] + DB-backed report twins (DB-PLAN S1).mssql: ... (7 twin properties + totals): OK, proved property.
[info] + DB-backed report twins (DB-PLAN S1).sqlite-twin SKIPPED: no file at data/out/sales/xs/sales.sqlite ...   (the file did not exist yet; R-4)
[info] Passed: Total 9, Failed 0, Errors 0, Passed 9
```

These checks were made after the run:
* `dbo` in ErmineSales still holds 9 tables and 4 views, so no `MemoHash_*` table was left behind.
* `tempdb` holds 0 `##` tables.
* A grep of the log for the password found 0 hits.

The SQLite-twin set was run once after the loader's handoff with the SQL Server set skipped (no ERMINE_DB_* in the environment): `Passed: Total 9`, see R-4.

Skip mode, also run once: `Passed: Total 2` (the `mssql SKIPPED` and `sqlite-twin SKIPPED`
properties).

## 6. Dialect differences observed (DB-PLAN §9)

| # | Observation | Status |
|---|---|---|
| R-1 | SQL Server returns an unordered relation's rows in a different order from in-memory SQLite. Every scan the reports ORDER (`scanRelationInOrder`, `scanInOrder`) and every widget that sorts (the crosstab's axes, the tab labels) came out identical. | MEASURED |
| R-2 | No T-SQL error from any Fetch report. The following all ran on SQL Server with the documents equal: `groupBy {region} (sumBy amount)` (TopN, Fragments), the ordered scans (ascending and `invert_Srt`), `filterEq` (Headline, Tabs), `#` projections, the combine/cast of `units` to Double (Crosstab), the natural `join` of a `VALUES` literal with a table (Running, Fragments, Crosstab), and deferred delivery with token resolution (Tabs). None of the six uses a window operator (`Relation.Windowed`), so this run does not exercise the §9.2 window sites. | MEASURED |
| R-3 | `date` columns read back as the same `Date` values (the wire shows `2026-01-05` and so on, equal to the literals'). | MEASURED |
| R-4 | The SQLite twin (D13), same properties over `jdbc:sqlite:` (a copy of the loader's `data/out/sales/xs/sales.sqlite`, written 22:58): all 7 twins EQUAL modulo row order, totals identical, `Passed: Total 9, Failed 0`. The file's INTEGER epoch-ms `day` column reads back as the same `Date` values (SCHEMA-SALES §8's open INFERRED item, now MEASURED). Byte-identical without the sort for 6 of 13 requests (as SQL Server's 5, plus TopN keep 2): the row order of a view scan differs from a `VALUES` literal's on SQLite too. | MEASURED 2026-09-24 ~23:00 |

**Emitter gaps (WP-15/16):** none surfaced on SQL Server or on the SQLite twin by these seven reports.

## 7. The connection-path finding

For a test, or for any host that builds `RunnerConfig` itself, nothing is missing. The pair is
the whole interface, and `DB.RunUser` supplies a login. The gaps are on the product paths only,
as `SERVER.md` §1 already records:
* `RunnerConfig.backend` and `ermine-serve --db` take no user or password.
* The preview is fixed to `jdbc:sqlite::memory:` (`Preview.scala:2221-2222`).

Both belong to WP-12(b)/WP-13.
