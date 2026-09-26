# Typed widget columns (WP-37)

Branch `typed-columns`, worktree `ermine-scala-wt-typedcols`, base `74405fea` (widget-preview).
Board: `scratch-widget-preview/typedcols/BOARD.md`. Proven sketch: `scratch-widget-preview/typedcols/TypedCols.e`.

## 0. Decisions (the user, 2026-09-25)

| # | Decision |
|---|---|
| D1 | Widget props never name a relation column by a `String` in the authoring API. A column is named by a `Field`, and the relation row proves membership (`Has r h`, settled where the columns meet the relation). |
| D2 | Table constructors are `col`, `numCol`, `dateCol`. `textColumn`, `numberColumn` and the string `simpleTable : List TableColumn -> ...` are REMOVED, not deprecated. |
| D3 | The wire is unchanged: `TableColumn`/`TableProps` stay the JSON records, the schema exporter, `client/src/generated/widgets.ts` and the client bundle do not change (the `generated` gate must stay "fresh and exact"). |
| D4 | Fixed column roles (a headline's measure, a crosstab's two keys and measure, a pie's label and value, a scorecard's label/value/delta, drilldown parent/child/label) take named `Field h a` slots in a server-side Source record, with a partition constraint in the `...Of` function so the fields are provably distinct. Open lists of columns (table columns, chart series/category/extra columns) take `List (Column r)`. |
| D5 | Sorts and row groups are marked ON the column (`sortAsc`/`sortDesc`, `groupRows`); the wire indices are computed when lowering to `TableProps`. No index is written by a user. |
| D6 | The default `col` picks kind and alignment from the field's runtime `PrimT` (`fieldType`): numeric -> `NumberColumn`/right, temporal -> `DateColumn`/left, else `OtherColumn`/left. `numCol` (`PrimitiveNum a`, takes a `CellFormat`) and `dateCol` (`PrimitiveTemporal a`) exist so a format on the wrong value type is a TYPE error. Header defaults to `fieldName`; `withHeader`, `withFormat`, `alignLeft`, `alignRight` override. |
| D7 | Escape hatch for runtime-named fields: `Layout.Widgets.Table.Unsafe` exports `rawColumn : String -> Column r` (and the equivalent for other widgets' unsafe modules). Nothing in the stdlib or the fixtures may import it. |
| D8 | Documents are byte-identical before and after the migration: the JSON a report renders to must not change. Proof = a before/after dump of every migrated report (see §3). |
| D10 | (orchestrator, 2026-09-25 19:5x) The ONE accepted deviation from D8: a `Date` field that the old fixtures showed with `textColumn` now lowers to `kind: DateColumn` (D6), in 7 documents (13 cells of the dump). It is a presentation hint (sort type and CSS), not data; keeping `OtherColumn` would need an override the API should not have. The expected dump is `before/` with that one substitution applied. |
| D11 | (orchestrator, 20:1x) `headingOf` takes a `Column r` for its sort column, not a `Field h a` slot: a heading's sort column may be chosen at run time among fields of different value types (Sales.e: Date, Double, Int), which one typed slot cannot hold; `Column r` still proves membership in `r`. D4's rule reads: a fixed slot whose VALUE type is fixed (measure Double, key String) is a `Field h a`; a slot whose value type is open is a `Column r`. |
| D9 | The projection option (shrinking the wire to the used columns via an unsafe row) is a separate ticket (WP-38), NOT in scope. |

## 1. The design, as type-checked

```
data Column (r : rho) = Column TableColumn          -- phantom r; the wire column inside

col     : Has r h                        => Field h a -> Column r
numCol  : (Has r h, PrimitiveNum a)      => Field h a -> CellFormat -> Column r
dateCol : (Has r h, PrimitiveTemporal a) => Field h a -> Column r

withHeader : String -> Column r -> Column r
withFormat : CellFormat -> Column r -> Column r
alignLeft, alignRight, sortAsc, sortDesc, groupRows : Column r -> Column r

simpleTable : List (Column r) -> [..r] -> TableProps r
```

REPL results on the sketch (type checking on): `col day : forall r. (exists c. r <- ((|day|), c)) => Column r`;
`[col day, col amount]` merges to one constraint `r <- ((|amount, day|), a)`; `simpleTable [col target] sales` is
refused ("Row partitions are unsatisfiable at field target"); `simpleTable [col region, col day] (sales # {region})`
is refused (day not in the projection); `numCol region` -> "No instance for (PrimitiveNum String)"; `dateCol amount`
-> "No instance for (PrimitiveTemporal Double)".

## 2. Roles

| Role | Owns | Hands off when |
|---|---|---|
| core-api | `Layout/Widgets/Table.e` (+ `Table/Unsafe.e`), a `Column` marker representation that the other roles can reuse (a shared `Layout/Widgets/Column.e` if the marks/lowering are widget-neutral), property tests for acceptance AND refusal (ErmineFixture `typeChecks` / `no(...)`), the sort/group index lowering | the module compiles, the tests pass, the API is frozen and posted on the board |
| migration | every stdlib module and fixture that used `textColumn`/`numberColumn`/string `simpleTable`; the before/after document dump (§3) | all migrated, dump equal, TestRunner/TestDbReports/TestSchema green |
| widgets | D4 for Chart, PieChart, Scorecard, Drilldown, DrilldownBar, StyleBox, Heading (21 string props); their fixtures; their tests | same as migration for those widgets |
| docs | `docs/JSON-GUIDE.md`, `tracker/JSON-WIDGET-PLAYGROUND.md` (WP-37 row, WP-38 ticket), `editor/vscode/README.md` if it shows a table example, this file's §4 log | every example in the docs is the new API and compiles (the guide's snippets are checked by which test? find out and say) |
| verifier | independent review of design fidelity (D1-D9) and implementation; reverse mutants; the dump equality re-run | REVIEW-TYPEDCOLS.md on the board dir: GREEN/GREEN or must-fixes |

## 3. The document-equality proof (D8)

Before any migration edit: for every report module that will change, render its document JSON (the `TestRunner`
fixtures already do this for the `doc/*.e` reports; `TestDbReports` for the DB twins at tier xs; for a report
without a test, `bin/ermine-serve --root ... --preload M` + `curl`), and store them under
`scratch-widget-preview/typedcols/before/<Module>.json` with the exact params used. After: the same, under
`after/`. `diff -r before after` must be empty. The migration role owns the dump; the verifier re-runs it.

## 4. Log

(filled by the roles: what landed, when, evidence)

| When | Role | What landed | Evidence |
|---|---|---|---|
| 2026-09-25 19:32 | core-api | Typed API in `Layout/Widgets/Table.e` (`Column r`, col/numCol/dateCol, withHeader/withFormat/alignLeft/alignRight, sortAsc/sortDesc/groupRows, columnWire/columnName, typed `simpleTable`); `Layout/Widgets/Table/Unsafe.e` (`rawColumn`); `Layout/Widgets/Column.e` (FieldKind/fieldKind/primName, D6 by PrimT.name: Byte/Short/Int/Long/Double numeric, Date/Timestamp temporal, else Other); `scalacheck-binding/.../TestTypedColumns.scala` (12 props); widgets.ts regenerated (hash/comment lines only). Transitional: `legacySimpleTable`, `textColumn`, `numberColumn` still present, to be removed by core-api after migration. | TestTypedColumns Passed 12/12; TestSchema Passed 31/31; reverse mutant: 4/4 refusals red; check-fresh fresh and exact (logs `scratch-widget-preview/typedcols/core-api-{3,4,5-mutant,6}.log`) |
| 2026-09-25 19:50 | migration | Every table caller on the typed API (no legacySimpleTable/textColumn/numberColumn/hand-built TableColumn lists left in fixtures): doc/{Sales,FetchRunning,FetchTabs,FetchFragments,FetchHeadline}.e + Db twins, modules/Doc/{TraceReport,SalesReport,DbSalesReport}.e; sorts as marks (Sales `sortedBy`, TraceReport, SalesReport). Before/after dump: 17 docs, scratch-widget-preview/typedcols/{before,after}/ + PARAMS.md + migration-dump.sh. | diff -r before after: 7 files, 13 occurrences, all the `day` column's kind OtherColumn -> DateColumn (D6; day : Date, was textColumn); before-dayfix (that one sed) vs after EMPTY; accepted pending orchestrator OK. core/testOnly *TestRunner* *TestSchema* *TestTolerantCheck* *TestDbReports*: Passed: Total 131, Failed 0 (migration-2.log; TestDbReports registered 0 DB props: no ERMINE_DB_URL/USER, DB at tier s; twins differ from originals only in module/import/comment lines, diff). corpus-sweep: loaded=89 rejected=79 unknown=0 of 168 (migration-3.log, no baseline). |

| Role | When | What landed | Evidence |
|---|---|---|---|
| docs | 2026-09-25 | `docs/JSON-GUIDE.md` §8 "Table columns" (new) + Sales.e/SalesReport.e walkthroughs, widget table, §12 WP-38 row; `docs/examples/Regions.e` on the new API; `tracker/JSON-WIDGET-PLAYGROUND.md` WP-37 + WP-38 rows | Refusal messages and sort/rowGroup lowering MEASURED with bin/ermine (scratch `docs-probe/`); guide snippets = fixture lines (0 missing, script check); Regions.e table JSON = old `TableProps` (diff empty, both orders). NOTHING in any suite or gate reads `docs/` (grep 0 hits): Regions.e is checked by hand only. |
| 2026-09-25 19:56 | core-api | Phase 2 (D2): `legacySimpleTable`, `textColumn`, `numberColumn` deleted; Crosstab.e:9 comment; 2 removal props (undefined; String-column simpleTable refused); widgets.ts regenerated after widgets hand-off (sha lines only). | TestTypedColumns 14/14 + TestSchema 31/31 (Passed: Total 45, Failed 0, core-api-7.log); check-fresh fresh and exact |
| 2026-09-25 19:58 | widgets | D1/D4 for the 21 string column props outside the table; wire Props unchanged and still exported (D3). Open lists: `Chart.Series r` (`seriesOf`, `simpleSeries`, `seriesWire`) of `Table.Column r`, lowered by `AxisChart.axisChartOf` / `simpleAxisChart`. Fixed roles: `PieSource`/`pieChartOf`, `ScorecardSource`/`scorecardOf` (+ typed `simpleScorecard`), `DrilldownSource`/`drilldownTableOf` (columns = `List (Column r)`, lowered as `simpleTable`), `DrilldownBarSource`/`drilldownBarOf`, `StyleBoxSource`/`styleBoxOf` (positions `Field h Int`), each with the partition `r <- (slots.., t)`; `Maybe` slots absent = free row var (accepted). Heading: `HeadingSource`/`headingOf` takes a `Column r` + the relation it is over (not a `Field h a`: Sales.e picks the sort column at run time among Date/Double/Int fields). Removed: string `simpleDrilldownTable`; string `simpleSeries`/`simpleScorecard`/`simpleAxisChart` retyped. No widget Unsafe module (no user needs one; a chart's runtime-named column is `Table.Unsafe.rawColumn`). Fixtures: Doc/{SalesReport,DbSalesReport,TraceReport}.e, doc/{FetchTopN,DbFetchTopN,FetchFragments,DbFetchFragments,Sales}.e; `TestLspRobustness` D's Sales.e text anchor -> `HeadingSource "Sales"`. New `TestTypedWidgets.scala` (16 props). | TestTypedWidgets Passed: Total 16, Failed 0 (widgets-4.log); reverse mutant (partitions dropped, series/heading decoupled): 7/7 refusal props red, 9 acceptance green (widgets-3-mutant.log), restored sha256 7/7 OK; *TestWidgets* *TestSchema* Passed 39/39 (widgets-5.log); TestLspRobustness -f D: 22/22 (widgets-6.log); migration re-dump after my edits: `diff -r expected after` EMPTY, 16 docs (re-checked by me). NOT run by me: TestRunner/TestDbReports (migration's). |
| 2026-09-25 20:16 | verifier | Review `scratch-widget-preview/typedcols/REVIEW-TYPEDCOLS.md`: D1-D8, D10, D11 GREEN; implementation GREEN; 0 must-fixes, 7 nits (N1 TestRunner pins no column kind/sort index; N2 `Column#`/`Series#` exported by convention; N3 no widget Unsafe; N4 stale old-API quotes in WP-7 checklist:1141 + Fetch/DbFetchCrosstab comments; N5 `HeadingSource rel` unconstrained; N6 drilldown drops groupRows silently; N7 §4 two headers). Docs question answered on the board (blame orientation, not a solver bug). | MEASURED: 5 suites Passed: Total 161, Failed 0 (verifier-1.log); reverse mutants 4/4 killed (verifier-mutant-{a,b,c,d}.log: 6/1/4/2 red), restored sha256 3/3 OK; `diff -r expected verifier-after` EMPTY and `diff -r before verifier-before` (base oracle) EMPTY, 16 docs each; check-fresh fresh and exact, check-generated up to date; Regions.e :load OK. Db twins not dumped: UNVERIFIED. |
| 2026-09-25 20:18 | core-api | N1: real-fixture property (Sales x2 sort orders, FetchTabs) pinning kinds/sorts/rowGroup to expected/; stale refs fixed in WP-7-MANUAL-CHECKLIST.md, db/DOGFOOD.md, FetchCrosstab.e, DbFetchCrosstab.e. | TestTypedColumns 15/15; mutants (c) 4 red, (d) 3 red, both incl. the new prop; restored sha256 OK |
