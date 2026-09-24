# J3e as built: chart and style-box prop types, the client adapters, treeMap as unsupported

(Report text written by the implementer agent, saved to this path by the orchestrator: the agent's harness blocked writing `.md` files.)

Branch `json-charts`, worktree `~/research/ermine/ermine-scala-wt-json-charts`, off 5b0cc4ee (J3d on `json-client`). Uncommitted. 2026-09-16, ~4 h of the 5 h budget, plus the review fix (`review-J3e.md`, FIX-THEN-LAND) — see "Review fixes applied" at the end.

## Files built

| File | What |
|---|---|
| `core/src/main/resources/modules/Layout/Widgets/Chart.e` (new, 136 lines) | the vocabulary the two axis-chart widgets share: `LegendLocation`, `ChartLegendOptions`, `ChartRenderHints`, `Orientation`, `DisplayScale`, `SortDir`, `ScalarType`, `AxisConstraints`, `ChartAxis`, `ChartVariant`, `ChartSeries`, `ChartMeta` + six spellings |
| `.../Layout/Widgets/AxisChart.e` (new, 37) | `AxisChartProps r`, `axisChart`, `simpleAxisChart` — widget `"axisChart"` |
| `.../Layout/Widgets/PieChart.e` (new, 49) | `PieChartProps r`, `pieChart`, `drilldownPieChart` — widgets `"pieChart"` and `"drilldownPieChart"`, ONE props type |
| `.../Layout/Widgets/StyleBox.e` (new, 48) | `StyleBoxProps r`, `styleBox` — widget `"styleBox"` |
| `.../Layout/Widgets/DrilldownBar.e` (new, 26) | `DrilldownBarProps r`, `drilldownBar` — widget `"drilldownBar"` |
| `.../Layout/Widgets.e` | five more `export`s; the `widgetNames` comment now says treeMap is the unsupported one |
| `client/src/charts.ts` (new, 677) | the four adapters, the legacy argument types, `TUPLE_LOSS`/`tupleIsLossless`, `axisValue`/`ymd`/`cssColor`, `seriesRows`/`pieRows`/`styleBoxCells`, `chartSkeleton` |
| `client/src/legacy.ts` | `HtmlWriter` extended with `runTimeSeries`/`runDrilldownBar`/`runPiechart`/`runPiechartDrilldown`/`runStylebox`; `LegacyFormatTuple` exported |
| `client/src/props.ts` | the TS mirrors of the five new Ermine modules |
| `client/src/index.ts` | five more registry lines; `UNSUPPORTED_WIDGETS` re-exported; the treeMap rationale |
| `client/scripts/generate.sh` | four more `types` entries, five more `WIDGET_PROP_SCHEMAS` lines, and `UNSUPPORTED_WIDGETS` in the generated index |
| `client/src/generated/{axisChart,pieChart,styleBox,drilldownBar}.ts` + `index.ts` | regenerated |
| `client/test/charts.test.ts` (new, 640) | **22 tests**: the tuple property, the four adapters, treeMap, the missing-global case |
| `client/test/{harness,mutate,props,corpus,endtoend}.test.ts` / helpers | the stub records chart calls; the new optional keys; the new prop pins; property (b) extended; the end-to-end doc's chart half |
| `core/src/test/resources/modules/Doc/SalesReport.e` | now also an `axisChart` and a `pieChart` over the same relation |
| `scalacheck-binding/src/main/scala/TestWidgets.scala` | `axisChartSrc`, `pieSrc`, `drilldownPieSrc`, `styleBoxSrc`, `drilldownBarSrc`, a colour column in the field pool, a position relation, `(a-pin4)` |
| `tracker/tools/lsp-smoke.sh` | the client timeout 120 → 240 s (see departures) |
| `tracker/JSON-API-DESIGN.md` | §3.7e continued: "Stage 3 charts as built" |
| `tracker/JSON-STAGE3-PLAN.md` | J3e ticked; handoff-log entry |
| `client/README.md` | "Charts and the style box", the reserved-names section rewritten, five more known gaps |

No production Scala changed. J3a's exporter and J3b's writer needed no change for any of these types; `src/dispatcher.ts` and `src/relation.ts` are untouched, exactly as J3d's extension point 4 promised.

## The prop type declarations, as landed

```
-- Layout/Widgets/Chart.e
data LegendLocation = LegendDefault | LegendAbove | LegendOverlay | LegendRightOverlay
                    | LegendRightNotOverlay | LegendRightTable | LegendHidden
data ChartLegendOptions = ChartLegendOptions { legendLocation : LegendLocation }
data ChartRenderHints   = ChartRenderHints { enableDataLabels : Bool }
data Orientation  = Vertical | Horizontal
data DisplayScale = Linear | Logarithmic
data SortDir      = Asc | Desc
data ScalarType = Scalar { typeName : String, typeNumeric : Bool }
                | Compound { componentTypes : List ScalarType }
data AxisConstraints =
    Scaled { lowerBound : Maybe Double, upperBound : Maybe Double, displayScale : DisplayScale }
  | Unscaled { sortOrders : List SortDir, tickOverrides : List (String, String) }
data ChartAxis = ChartAxis { axisLabel : String, tooltipLabel : String, axisFormat : CellFormat
                           , scalarType : ScalarType, showTicks : Bool
                           , constraints : AxisConstraints }
data ChartVariant = Line | Bar | Step | Scatter | StackedBar | StackedArea
                  | BoxAndWhiskers | Bubble { zLabel : String }
data ChartSeries = ChartSeries { seriesColumns : List String, categoryColumns : List String
                               , valueColumn : String, extraColumns : List String
                               , colorColumn : Maybe String, seriesFormat : CellFormat
                               , extraFormats : List CellFormat, variant : ChartVariant }
data ChartMeta = ChartMeta { chartTitle : String, domainAxis : ChartAxis, rangeAxis : ChartAxis
                           , orientation : Orientation, legendOptions : ChartLegendOptions
                           , renderHints : ChartRenderHints }

-- Layout/Widgets/AxisChart.e
data AxisChartProps r = AxisChartProps { chartMeta : ChartMeta
                                       , chartSeries : List ChartSeries
                                       , chartRows : [..r] }
axisChart : AxisChartProps r -> Node                  -- widget "axisChart"

-- Layout/Widgets/DrilldownBar.e
data DrilldownBarProps r = DrilldownBarProps { barMeta : ChartMeta, barSeries : ChartSeries
                                             , barParentColumn : String
                                             , barChildColumn : String, barRows : [..r] }
drilldownBar : DrilldownBarProps r -> Node            -- widget "drilldownBar"

-- Layout/Widgets/PieChart.e
data PieChartProps r = PieChartProps { pieTitle : String, seriesName : String
                                     , pieLabelColumn : String, pieValueColumn : String
                                     , pieColorColumn : Maybe String
                                     , pieChildColumn : Maybe String
                                     , pieParentColumn : Maybe String
                                     , pieLabelFormat : CellFormat, pieValueFormat : CellFormat
                                     , pieLegend : ChartLegendOptions
                                     , pieHints : ChartRenderHints, pieRows : Inline r }
pieChart, drilldownPieChart : PieChartProps r -> Node  -- widgets "pieChart"/"drilldownPieChart"

-- Layout/Widgets/StyleBox.e
data StyleBoxProps r = StyleBoxProps { xTitle : String, yTitle : String
                                     , aggColumn : String, aggTitle : String
                                     , aggFormat : CellFormat
                                     , xPositionColumn : String, yPositionColumn : String
                                     , rowLabels : List String, columnLabels : List String
                                     , showNumber : Bool
                                     , xBins : List (Double, Double)
                                     , yBins : List (Double, Double)
                                     , styleBoxRows : Inline r }
styleBox : StyleBoxProps r -> Node                    -- widget "styleBox"
```

Every one exports one schema with its row parameter free (`ermine:Layout.Widgets.AxisChart/AxisChartProps r`, …), pinned by `(a-pin3)`.

## Every legacy callback path, and what the adapter does about it

Design note §4.5's table, restricted to what these five widgets can reach.

| POST | Where the JS decides | What this path does |
|---|---|---|
| `relation` (series rows) | `withTimeSeriesData`, `ermine-htmlwriter.js:221-248`. Taken unless `series[i].data` is an `Array` (`:223`) | **avoided.** `charts.ts` always sends an array. `selSeries`/`selCategory`/`selValue`/`selExtra`/`selCategoryCols`/`meta.colors` exist only to build that payload; the first four are replaced by column names in the prop types, `selCategoryCols` is still emitted (cheap, keeps the object self-describing) and `colors` goes out as `null`. |
| `pieChartData` | `withPiechartData`, `:261-295`. Taken unless `args.relation` is an `Array` (`:262`) | **avoided.** The adapter sends the row array. A drilldown pie filters `rec[4] === parentId` IN THE BROWSER (`:268`), so drilling in needs no round trip either — every level's rows are in the one array. |
| `styleBoxData` | `withStyleBoxData`, `:297-319`. **No local branch at all.** | **NOT avoidable.** The 3×3 grid is built entirely from `cellCounts`, which the adapter computes, so the widget renders with zero requests; but clicking a cell always POSTs. The adapter sends `relation: null` and `legend: null`, the POST fails, and `stylebox.js` logs it through its own `callbackError` (`:222-224`). Nothing throws and nothing else on the page is affected — the cell-click popup simply does not work on the JSON path. Fixing it needs a J3c endpoint taking a relation token plus a cell position; it is NOT expressible as "send more data up front", because the popup is a per-security drill-through of the whole relation, not of the 9 aggregates. |
| `tableData` | `HTMLRunner.scala:303-315` | unreachable from writer-generated pages (tables are inline); no chart touches it. |
| `treeMapData` | `HTMLRunner.scala:508-515` | no client caller exists; `runTreeMap` is undefined in the bundle. `treeMap` is registered as unsupported instead. |

A second, smaller "callback" is `sercolors`/`legend`: both are f0 handles that only ever appear inside a POST body, so sending `null` is not a loss on this path.

## The tuple format, case by case

`HTMLWriter.jsLayoutFormat` (~208-227) is what every chart axis, every series name, the pie's two formats and the style box's `aFormat` are read through — `runStylebox` even applies `formatDisplay` to `args.aFormat` itself (`ermine-htmlwriter.js:3583`), so it must be handed the tuple. `client/src/charts.ts::TUPLE_LOSS` is the table in code; this is it in prose. "Impl?" means `formatDisplay`'s styleMap (`js/ermine/utils.js:293-333`) has an entry for the name; a name it does not have falls through to `styleMap.Default`, which means the format is lost ENTIRELY, not partly.

| CellFormat | Tuple | Impl? | What is lost |
|---|---|---|---|
| `Default` | `["Default", null]` | yes | nothing |
| `Constant` | `["Constant", value]` | yes | nothing |
| `DateRange` | `["DateRange", null]` | yes | nothing |
| `Truncate` | `["Truncate", places]` | yes | nothing |
| `Percentage` | `["Percentage", [places, pad]]` | yes | `color`, `negParens` — a red negative percentage draws black and `-0.17` reads `-17%`, not `(17%)` |
| `Currency` | `["Currency", [symbol, places]]` | yes | `color`, `negParens` |
| `Round` | `["Round", places]` (a BARE number, not a pair) | yes | `color`, `negParens` |
| `IntegralRound` | `["IntegralRound", places]` | yes | `color`, `negParens` |
| `Alias` | `["Alias", {from: to}]` | yes | the pair LIST becomes an object: the ORDER is gone and a repeated key keeps the last pair. The RENDERING is unaffected — `src/format.ts` also takes the last match, and the map is built with `Object.create(null)`, so `"constructor"`/`"__proto__"` read nothing on either side. |
| `Pr1` | `["Pr1", <inner tuple>]` | yes | whatever the inner format's row loses; the only recursive case the tuple keeps |
| `Pr2` | `["Pr2", <inner tuple>]` | **no** | everything: the styleMap has no `Pr2`, so it renders as `Default` of the FIRST value — the mirror case silently becomes the ordinary one |
| `Markdown` | `["MarkdownFmt", null]` | **no** | everything, including the base format |
| `Conditional` | `["Conditional", null]` | **no** | everything: the condition and both branches |
| `Color` | `["ColorFormat", null]` | **no** | everything: `bg`, `fg` and the base |
| `Verbatim` | `["Verbatim", null]` | **no** | everything, and the fallback is `Default`, which ESCAPES — the opposite of Verbatim |

`tupleIsLossless(f)` is the VALUE-level question, distinct from the table: a `Percentage` with `color` and `negParens` both false loses nothing even though the encoding has no room for them. `(t-tuple)` uses both — where `tupleIsLossless` holds it compares the tuple's answer from the REAL legacy `formatDisplay` against `src/format.ts` value for value, and where "Impl?" is no it requires the legacy to answer exactly what `Default` answers. So the documented loss is CHECKED to be the loss, not asserted.

The consequence a report author must know: **a chart cannot format as the table beside it does.** That is today's behaviour, reproduced, not a regression.

## Decisions taken in code (the brief did not fix these)

1. **One shared `Layout.Widgets.Chart` module, four widget modules.** `axisChart` and `drilldownBar` send the same `meta` and the same `series` shape, so the vocabulary is declared once and each props module imports it with an explicit `using` list of TYPES only (J3d's extension point 1). The umbrella `Layout/Widgets.e` exports all nine modules, so every FIELD NAME in the five new modules had to be fresh across all of them: `title` was taken (Scorecard), hence `chartTitle`; `range` would collide with common stdlib spellings in a report's scope, hence `domainAxis`/`rangeAxis`.
2. **An axis chart has ONE relation, shared by every series.** Server-side each `ChartSeries` carries its own `Tabular`. Here the relation sits on `AxisChartProps.chartRows` and each series names its columns inside it, because the multi-series case in practice is several value columns of one relation and one relation is one scan. **This is a choice, not a typing limit** (corrected after the review; the first cut of this report claimed the alternative was untypeable, which is wrong): `data ChartSeries r = ChartSeries { …, seriesRows : [..r] }` with `chartSeries : List (ChartSeries r)` IS typeable and strictly more general — the series could then carry different ROW SETS over the same columns, and a deferred token each. What no spelling available here can express is series over relations of different SHAPES; that needs an existential row.
3. **The delivery wrappers, per widget.** `chartRows` and `barRows` are bare `[..r]` (a chart over a large relation may defer; the dispatcher resolves it before the adapter runs, pinned by `(x-deferred)`). `pieRows` and `styleBoxRows` are `Inline r`: a pie with no slices is nothing, and the style box aggregates its rows client-side, so both always travel and neither component has a deferred case to handle.
4. **`structure` is not emitted.** `SeriesStructure.Complex`'s `trees` is an f0 blob with no JSON equivalent, and `runTimeSeries` gates series-level drilldown on `s.structure && s.structure.trees` (`:1727`). Leaving the key off makes `isSeriesLevelDD` false, which is the `Simple` behaviour. Modelled as a gap, not as an empty structure.
5. **Extras follow `RelationRunner.runRelation`'s own split.** That function takes `extraCols` (SCALAR positions) and `extraOps` (LIST positions) and emits `extraCols` first. The axis chart's local path passes `extraCols = List.empty` (`RelationRunner.axisChartToString:326`), so a series' `extraColumns` are LISTS at index 4+; the drilldown bar passes `List(childCol, parentCol)` as `extraCols` (`HTMLWriter:1291`), so index 4 is the child and index 5 the parent, as SCALARS — which is what `cur[4]` and `_.filter(d, [5, ddid])` read. Both reproduced as written.
6. **A colour cell is normalised to `#rrggbb` or null.** `getColorIndex` looks the string up in a map, and `cssColor` server-side prints lower-case hex (`HTMLWriter.getColorHexcode`), so anything that is not `/^#[0-9a-fA-F]{6}$/` becomes `null` rather than a colour the renderer will not find. Property (b) asserts the invariant over the whole corpus, and the corpus generator mints junk colours on purpose.
7. **A series with no `seriesColumns` sends `[""]` as its name.** The legacy always has a `Presentation` there, and the idiom is a `Constant` `seriesFormat` that renames whatever arrives (`formatDisplay(fmtsSeries[i])([this.series.name])`), so an empty name is the honest input to it. `Doc.SalesReport` uses exactly that shape.
8. **`cellCounts` keys the positions as the literal `xPosition`/`yPosition`.** `stylebox.js` reads `val.xPosition` (`:91-96`) while the server names those output columns after the VALUES of `xPositionField`/`yPositionField` — so the widget only works today when the relation's columns happen to be called that. The adapter renames, so any column name works. A deliberate, documented fix.
9. **`xBins`/`yBins` are pairs of NUMBERS, not the server's pre-formatted strings.** Their only consumer is `formatBounds` (`stylebox.js:183`), which calls `.toFixed(3)` — which throws on the strings the server sends today. That path is only reachable after a `styleBoxData` response, i.e. inside the callback this stage cannot serve, so it is dead either way; numbers are the shape that would work.
10. **`treeMap` stays OUT of `defaultRegistry()`** (J3d extension point 7, binding), and is named by a new generated constant `UNSUPPORTED_WIDGETS` so the intent is in code rather than only in prose. `(x-treemap)` pins both halves: not in the registry, no generated schema, and the dispatcher's error box carrying `data-widget="treeMap"`.
11. **`pieChart` and `drilldownPieChart` share ONE props type**, as the legacy does (`genPieChart` with an optional `childParentCol`). Two smart constructors, two registry names, one schema — `(p-registry)` asserts the two map to the same zod object.
12. **The chart renderers are called `(id, args)`, unlike `runTabular`'s single map**, and each chart gets the wrapper DOM its emission site builds (`timeseries`/`dd_barchart`/`piechart`/`dd_piechart`/`stylebox` inside `<css>_wrapper sizeme`), addressed by the id the renderer is handed. Checked for every chart of every corpus document.
13. **The pie's slice LABEL is formatted on the client; everything else in a chart row travels raw** (added by review fix 1). `RelationRunner.runPieChartData` builds position 0 as `lc.format.basicEval(labels) extractNullableString ""` (`RelationRunner.scala:240`), always a String, and nothing in the browser formats it again — `args.labelFmt` reaches only `hcutil.pieLegendOptions`, whose merged options end with the pie's own `labelFormatter` interpolating `this.name` (= `r[0]`) verbatim. So `pieRows` takes a `FormatEnv`, formats the RAW cell (not `axisValue`'s — a `[y,m,d]` triple would be turned back into a `Date` by `formatDisplay`'s own `nelpeHwDates`) and stringifies, with null becoming `""`. Every other chart value stays raw because Highcharts formats it from the tuple.

## Departures from the brief

| Brief | As built | Why |
|---|---|---|
| adapters in `client/src/legacy/` | `client/src/charts.ts` beside `client/src/legacy.ts` | J3d's `legacy.ts` is the file that TYPES the `htmlwriter` global (extension point 5) and holds the table adapters; turning it into a directory would have moved reviewed code for no gain. `HtmlWriter` is extended in place and the chart argument types are `import type`d from `charts.ts`. |
| `drilldownBar` listed beside `pieChart` under §4.1 #7 | its own module and registry name, sharing `Chart.e` with `axisChart` | `runDrilldownBar` IS `runTimeSeries`; the props are a `meta` + one `series` + the parent/child pair |
| `treeMap`: "register it so the dispatcher renders an explicit unsupported widget box" | NOT registered; the dispatcher's own error box is that behaviour, and `UNSUPPORTED_WIDGETS` names it | J3d's extension point 7 is binding and says treeMap must stay out of `defaultRegistry()`; `(d-unknown)` already pins the box's shape |
| — | `tracker/tools/lsp-smoke.sh`'s client timeout 120 s → 240 s | The smoke **timed out twice** at 120 s on this tree (`SP/gate5-lsp.log`, `SP/gate5-lsp2.log`), while the server's own log showed it completing. It is dominated by typechecking every stdlib module at boot. Doubling a HANG guard is legitimate; it is not a performance assertion, and the script's comment says so. **Timing caveat** (corrected after the review): the 108 s / 116 s figures are `time`'s wall clock from my shell, NOT recorded in `SP/gate5-lsp-baseline.log`, which holds only `PASS lsp (577 checks)` — and the reviewer's own clean run took **89 s**. So the boot is load-dependent and J3e's five modules are not the proximate cause; the real fact is that a 129-module boot sits inside noise of any fixed budget. See open issue 10. |
| — | `Doc/SalesReport.e` gained an `axisChart` and a `pieChart` | the end-to-end property should cover a chart through SQLite, not only the table half |

## Properties

### Scala — `TestWidgets`, 6 properties (was 5)

| Id | What | Size / non-vacuity |
|---|---|---|
| (a) | unchanged in shape, extended in reach: `widgetSrc` now generates all EIGHT widgets, so random `AxisChartProps`/`PieChartProps`/`StyleBoxProps`/`DrilldownBarProps` values go through `Write.doc` and must validate against the exported schema | 100 cases; each mutates one key and requires refusal |
| (a-cov) | 200 fixed-seed cases with coverage assertions (was 120) | all **eight** widgets, all fifteen `CellFormat` cases, both deliveries, both wrappers, **all eight `ChartVariant`s**, both `AxisConstraints` arms, flat and drilldown pies, `colorColumn` present and absent, both `showNumber` values, and at least one `mutant-rejected` |
| (a-pin4) | **new.** The wire spelling of an axis chart: a nullary `ChartVariant` is `{"tag":"Line","args":[]}`, `Scaled` with `Nothing` bounds leaves NO key behind, `Just 9.0` carries the value, `Unscaled` carries `sortOrders`/`tickOverrides` | — |
| (a-pin), (a-pin2) | unchanged | — |
| (a-pin3) | extended to the four new prop types: seven `$id`s, each leaving `r` free | — |

Generator additions: a `wfColor` column whose literals are 5-in-6 well-formed `#rrggbb` and 1-in-6 junk (`"red"`, `""`, `"#12345"`), so the colour invariant is exercised on both sides; and a separate `posRelSrc` for the style box whose positions run `0..3` — one past the 3×3 grid on purpose, so `validatePosition`'s drop is exercised.

New optional keys for the mutation check (a `Maybe` field's key is omitted on the wire, so dropping it is not refusable): `lowerBound`, `upperBound`, `colorColumn`, `pieColorColumn`, `pieChildColumn`, `pieParentColumn`, on both the Scala (`TestWidgets.optionalKeys`) and TypeScript (`test/mutate.ts`) sides. Missing them is how `(b-neg)` failed first: it dropped `pieColorColumn` from a valid document and the schema, correctly, accepted it.

### TypeScript — 60 tests (was 36), 22 of them new in `charts.test.ts`

| Id | What |
|---|---|
| `(t-pin)` | one pin per `CellFormat` case of `legacyFormatTuple`'s spelling, the prototype-less `Alias` map, and `TUPLE_LOSS.implemented` against `LEGACY_STYLE_NAMES` |
| `(t-tuple)` | **fast-check, 600 random `(CellFormat, values)` pairs** against the REAL legacy `formatDisplay` loaded out of `~/research/ermine/ermine-writers`: totality and 2-tuple shape; `TUPLE_LOSS` has a row for every tag and agrees with `LEGACY_STYLE_NAMES`; where `tupleIsLossless` the two answers are compared VALUE FOR VALUE (**250 pairs** on the recorded run); where the name is unimplemented the legacy must answer exactly `Default`'s answer (**203**); all 15 cases occurred |
| `(t-mutant)` | the comparison is not vacuous: `Currency`'s tuple argument order swapped renders `"2NaN"` instead of `"$12.35"` |
| `(x-dates)` | `ymd` on both ISO spellings; `axisValue`'s null rule (`null` in a numeric column, `""` elsewhere — `jsonPrepAxis`); a `Long` string becomes a number; the triple round-trips through the legacy `nelpeHwDates` to the right `Date` |
| `(x-color)` | `#rrggbb` or null, nothing else |
| `(x-axis)` | the whole `runTimeSeries` argument object asserted structurally: the `timeseries` div inside `timeseries_wrapper sizeme`, the complete `meta` (both axes, both constraint arms, `colors: null`), `fmtSeries`/`fmtExtra`/`selCategoryCols`/`variant`, **no `structure` key**, and the two positional rows including the `[y,m,d]` category |
| `(x-axis-empty-series-column)`, `(x-axis-bubble)`, `(x-scalartype)` | the unnamed series, the Bubble `zlabel`, compound scalar types, every `LegendLocation` losing exactly its prefix |
| `(x-bar)` | `runDrilldownBar`: child at index 4, parent at 5, `parentCol`/`childCol` both non-null (both needed for `isDD`), the `dd_barchart` skeleton |
| `(x-pie)`, `(x-pie-dd)`, `(x-pie-label)` | `[label, \|value\|, colour]` rows, the absolute value, the legend/hints objects, and the two extra positions a drilldown pie adds — with `runPiechart` and `runPiechartDrilldown` recorded apart. `(x-pie)` uses a non-`Default` `pieLabelFormat` (`Alias`) so an inert prop fails; **`(x-pie-label)`** (review fix 1) drives `Default`, `Constant` and `Truncate` over a `Date` label column with a NULL row and requires a STRING at `row[0]` every time |
| `(x-stylebox)`, `(x-stylebox-args)`, `(x-stylebox-hidden)`, `(x-stylebox-legacy)` | the client-side `AggregateByGroupE`; the literal `xPosition`/`yPosition` keys; an out-of-grid position kept for the renderer to drop; JSON inside a string; `aFormat` as a TUPLE; `relation`/`legend` null; `showNumber`/`hiddenNumber`; and the real legacy `formatDisplay` applied to that tuple the way `runStylebox` applies it |
| `(x-treemap)` | not in the registry, no generated schema, the error box with `data-widget="treeMap"`, and every OTHER reserved name registered |
| `(x-no-htmlwriter)`, `(x-deferred)` | a missing legacy global is an error box, not a throw; a deferred chart relation is resolved before the adapter sees it |
| `(x-rows)`, `(x-axis-fn)` | the row builders directly: every category comes from the relation, colours are `#rrggbb`-or-null, an absent column reads as a null cell rather than throwing, pie values stay finite and non-negative, both constraint arms |
| `(p-charts)`, `(p-chart-types)` | **new prop pins**: the four prop types' keys and optional keys; `pieRows`/`styleBoxRows` having no deferred arm and `chartRows` having both; `ChartMeta`/`ChartAxis`/`ChartSeries` keys; `ScalarType`/`AxisConstraints`/`ChartVariant` arms; and the enum MEMBERS of `LegendLocation`/`Orientation`/`DisplayScale`/`SortDir` driven through `legendLocationOf`/`legacyScalarType`/`legacyAxis`, both directions — a member added in Ermine that the adapter does not handle fails here |
| `(p-registry)` | the eight registry names, the two pie names sharing one schema, `treeMap` having none |

**(b), cross-language, extended.** The corpus generator now mints all eight widgets, and property (b) checks each chart call against the props that produced it:

```
200 documents, 416 widgets, 1039 cells, 129 deferred relations resolved,
15 CellFormat cases, sort directions asc/desc;
603 chart points over 8 variants, 292 pie slices, 197 style-box cells
```

zero validation failures, zero error boxes. The chart invariants asserted for every call: every chart id addresses the skeleton with the class its emission site uses; `meta.type` is `AxisChartData`, `colors` is null, the orientation and legend location are legacy strings, every axis format is a tuple whose NAME is one of the fifteen `legacyFormatTuple` can emit (tightened after the review — the first cut checked only the shape), both constraint arms are well formed; each series has one row per relation row, `data[i][0]` is the value column's `axisValue`, **`data[i][1]` is exactly the relation's category values for that row**, the series-name arity is `max(1, |seriesColumns|)`, the colour is `#rrggbb` or null, the extras are scalars for the drilldown bar and lists for the axis chart, and `structure` is absent; a plain axis chart has `parentCol`/`childCol` null while a drilldown bar has both; **a pie's `row[0]` is a STRING equal to `format.ts` on the label cell** (review fix 1; the corpus generates random `pieLabelFormat`s, so this is not a `Default`-only check), **pie values are absolute** and equal `|wire value|` column by column, and a pie row is 3 wide or 5 when it drills; the style box's `cellCounts` parses, has one entry per distinct position, and each entry's aggregate equals the sum the server would compute. `[...widgetNames]` must be exactly the eight registered names and `[...variants]` exactly the eight `ChartVariant`s — so a widget or a variant that stopped being generated fails rather than silently thinning the property. `(b-neg)` mutates each of the 200 documents once: **200 of 200 refused**, all three kinds.

**(e2e)** now renders `Doc.SalesReport` — scorecard, table, axis chart and pie over one relation through SQLite — and asserts the chart's meta, the `Constant` series format, the points keyed by category, and the pie's slices.

## Gates

Logs under `SP = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/j3e/`.

| # | Gate | Result | Log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources` | success | `SP/gate1-compile.log` |
| 2 | `core/testOnly TestJson TestSchema TestNamedFields TestDoc TestWidgets` | **93/93** (28 + 25 + 14 + 20 + **6**; J3d's tree was 92) | `SP/gate2-suites.log` |
| 3 | `core/testOnly *TestLoopTrace` with `-Dermine.looptrace=<json-wrappers>/tracker/lean/.lake/build/bin/looptrace` | 3/3; **720 solves, 720 segments, 720 agree, skipped=0, hashdiff=0, eqdiff=0, nonpart=0**; controls detect 46/720 and 58/720 | `SP/gate3-looptrace.log` |
| 4 | `corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged | `SP/gate4-corpus.log`, `SP/gate4-verdicts.log` |
| 5 | `repl-smoke.sh` | **PASS**, 9 groups / 86 checks (aliasing 2, ffi 5, ffi-tolerant 9, json 20, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5) | `SP/gate5-repl.log` |
| 5 | `lsp-smoke.sh` | **PASS, 577 checks** with the timeout raised to 240 s; it FAILED (timed out) twice at the old 120 s, `SP/gate5-lsp.log` / `SP/gate5-lsp2.log`. Wall clock is load-dependent — 116 s here, 108 s on the J3d module set, 89 s on the reviewer's machine — and is `time`'s figure, not something the logs record. See the departures row and open issue 10. | `SP/gate5-lsp-final.log`, `SP/gate5-lsp-baseline.log` |
| J3e | `npx tsc -p tsconfig.json --noEmit` (strict, `noUncheckedIndexedAccess`) | clean | — |
| J3e | `client/scripts/check-generated.sh` | exit 0, "src/generated is up to date" | `SP/check-generated.log` |
| J3e | `node --test "dist/test/*.test.js"` with both fixtures | **60/60, 0 skipped** (59 before review fix 1) | — |
| J3e | `client/scripts/check-corpus.sh` with NO argument | exit 0, **60/60** | `SP/check-corpus-fix.log` (pre-fix: `SP/check-corpus.log`, 59/59) |
| — | `sbt 'core/Test/runMain ...WidgetCorpus target/widget-corpus 200'` | 200 documents | `SP/corpus-gen.log` |
| — | `sbt 'core/Test/runMain ...SalesReportDoc target/sales-report.json'` | 3308 chars through SQLite in-memory (was 1421 before the charts) | `SP/salesreport.log` |

`tracker/repl-classpath.txt` was regenerated for the smokes and restored with `git checkout`; `git status` is clean of it. The full `core/test` is the orchestrator's.

## Open issues

1. **The style box's cell-click popup does not work** (the one unavoidable callback, above). The grid does. A J3c endpoint taking `{token, xPosition, yPosition}` would close it.
2. **Series-level drilldown (`SeriesStructure.Complex`) is not modelled**, so an axis chart whose series today carry a `trees` structure loses the drilling. The `trees` value is an f0 blob; `traverseTrail` (`ermine-htmlwriter.js:190-217`) is its only reader.
3. **`Verbatim` on a chart axis is not just lost, it is inverted.** `["Verbatim", null]` falls back to `styleMap.Default`, which runs the value through `string_unhtml` — so a report using `Verbatim` to emit its own markup gets escaped text there. Faithful to the legacy, and worth a lint if anyone ever writes one.
4. **`Bubble`'s z value is read from index 3, the COLOUR slot.** `dataSeriesGroups` builds a point as `[category, value, ...drop(row, 3)]` and `hcutil.series`'s Bubble branch reads `sd[2]`, which is `row[3]` — the colour — while `zAxis.format` is `series[0].fmtExtra[0]`, i.e. the first EXTRA's format. The adapter places the colour at 3 and the extras from 4, exactly as `runRelation` does, and does not try to reconcile the two. A Bubble chart with a `colorColumn` will therefore size its bubbles by a colour string.
5. **`selCategoryCols` pairs the category columns with the DOMAIN's sort orders**, and nothing enforces `|sortOrders| == |categoryColumns|`. The legacy `sortByCategory` compares exactly `constraints.sort.length` components, so a mismatch sorts on too few or reads past the end. A report-authoring constraint the type system cannot state; the corpus generator always matches them.
6. **The style box grid is fixed at 3×3** in `stylebox.js`, so `rowLabels`/`columnLabels` want three entries and `counts[i].unshift(val)` writes past the end for more. Not enforced by the schema (a `List String` of any length validates).
7. **`(t-tuple)` runs on a RANDOM fast-check seed**, like J3d's `(c-legacy)`: a reviewer may see a different slice. Deliberate — that is how J3d found the Alias divergence.
8. **`ermine-schema --zod` inlines every `$def` it reaches into each generated module**, so `Layout_Widgets_Chart_*` appears in both `axisChart.ts` and `drilldownBar.ts`. Harmless (structurally identical, `check-generated.sh` guards them), but `test/props.test.ts` has to pick one module to import the shared types from; it picks `axisChart.ts` and says so.
9. Carried from J3d and still open: no converter from the foreign `Layout.Format` to `CellFormat`; column GROUPINGS are not reproduced; `formatted` is not byte-identical to the server's; the dispatcher resolves deferred relations sequentially; the GUID-NULL NPE in `SqlExecution.nextRecord` and the missing `finally` in `EffectfulProcedure.withDriver`.
10. **The LSP smoke's boot cost is a standing tax, and 240 s is not a plan** (raised from the review's D2). `lsp-smoke.sh` boots a session of **129** stdlib modules and takes 89-116 s depending on load; J3e doubled the hang guard after two timeouts, and every stage that adds modules pushes it further. The next agent that hits the ceiling should NOT double it again: the fix is a subset boot for the smoke (it only needs the fixtures' imports), or a cached/warmed session.
11. **A `Timestamp` column becomes a `[y, m, d]` triple on a chart axis, where the legacy sends the string.** `jsonPrepAxis` matches only `DateExpr`; `TimestampExpr` falls through to `extractNullableString ""`. Deliberate (a timestamp axis then behaves like a date axis, which is the useful reading of `hwAxisDateP`) and now stated beside `DATE_TYPES`, but it IS a divergence. Same for a `Bool` cell, which stays a boolean here and is `"true"`/`"false"` there.
12. **The style box coerces a NULL aggregate cell to 0.** SQL `Sum` over a nullable column ignores NULLs and answers NULL for an all-NULL group, so such a group shows a formatted zero where the server shows the format of a `NullExpr`. Noted in `styleBoxCells`' header.

## What the 2.11 port (P3) must know

1. **Nothing new in production Scala.** The only Scala this stage touched is `scalacheck-binding/src/main/scala/TestWidgets.scala`, already P3's to port.
2. **Dialect.** The additions use `Gen.oneOf(iterable)`, `Gen.frequency`, `Gen.listOfN`, `Gen.zip`, `Gen.const`, `Gen.choose`, `Gen.sequence`, `TestSchema.pickN` and plain `for`-comprehensions — all already used by J3d's generators. `variantSrc` builds a `List[Gen[(String, List[String])]]` and calls `Gen.oneOf(list).flatMap(identity)`; `Gen.oneOf` over an `Iterable` exists in the 2.11 ScalaCheck, and note J3a's finding was about `Gen.pick`, not `oneOf`. No `Either#map`, no `given`/`enum`/`extension`, no Java 11+ API. `Json.jObjectAssocList` (argonaut 6.0+) is still the only third-party call J3d flagged, unchanged.
3. **Five new `.e` files** under `core/src/main/resources/modules/Layout/Widgets/` plus the umbrella's five `export` lines. Pure Ermine, using only features J3d's modules already use: record-style `data`, mixed nullary/record unions, `Maybe`, tuples, `List`, and `[..r]` / `Inline r` relation fields. Copy verbatim.
4. **`Doc/SalesReport.e` grew** an `axisChart` and a `pieChart`; `SalesReportDoc` now writes 3308 chars rather than 1421, and `client/test/endtoend.test.ts` asserts the chart half.
5. **`tracker/tools/lsp-smoke.sh`'s timeout is now 240 s.** The 2.11 branch's copy will want the same change for the same reason — its boot is not faster.
6. **The counts move**: `(a-cov)` is 200 cases (was 120), `TestWidgets` is 6 properties (was 5) so the five-suite total is 93 on Scala 3, and the node suite is 60 tests (was 36).

## Review fixes applied (2026-09-16, after `review-J3e.md`, verdict FIX-THEN-LAND)

| # | What the review found | What changed |
|---|---|---|
| **1 (required)** | **The pie chart's slice LABEL was emitted raw where the legacy sends it FORMATTED.** `RelationRunner.runPieChartData` builds position 0 as `lc.format.basicEval(labels) extractNullableString ""` (`RelationRunner.scala:240`) — always a String. The adapter sent `axisValue(col, cell)`: the raw cell, and a `[y, m, d]` ARRAY for a Date/Timestamp label column. `args.labelFmt` cannot repair it in the browser — `runPiechart` hands it only to `hcutil.pieLegendOptions` (`ermine-htmlwriter.js:2422`), whose merged options end with the pie's own `labelFormatter` (`:1358-1369`, `:1379-1388`) interpolating `this.name` verbatim, and `this.name` is `r[0]` out of `processPieData`. So a non-`Default` `pieLabelFormat` was validated, carried on the wire and silently ignored; a Date label rendered `2026,1,31` in the legend; a NULL label rendered `null` instead of `""`. No test caught it: every pie fixture used `Default`, and `(b)` asserted `row[1]` and `row[2]` but never `row[0]`. | `pieRows(props, env)` now formats the RAW cell (not `axisValue`'s — a triple would be turned back into a `Date` by `formatDisplay`'s own `nelpeHwDates`) with `formatDisplay(props.pieLabelFormat, env)` and stringifies, `null`/`undefined` → `""`. The `FormatEnv` is threaded through `pieArgs` and `pieChartWidget(drilldown, env?)` exactly as `styleBoxWidget(env?)` does, and `defaultRegistry` passes its own. Side benefit: `Default` runs `string_unhtml`, so the label the legend interpolates into HTML is escaped — the same move J3d made for table cells. **Tests**: `(x-pie)` switched to a non-`Default` `pieLabelFormat` (`Alias`); new `(x-pie-label)` drives `Default`, `Constant` and `Truncate` over a Date label column with a NULL row, through both pie renderers, requiring a STRING at `row[0]`; `(b)`'s pie block now asserts `row[0]` is a string equal to `format.ts` on the label cell, over the corpus's RANDOM label formats. **Anti-vacuity**: reverting `pieRows` to the raw label fails `(x-pie)`, `(x-pie-label)` and `(b)` — 3 of 24 in the two files — and restoring gives 60/60 again. |
| O1 | `Timestamp` in `DATE_TYPES` diverges from `jsonPrepAxis`, which matches only `DateExpr` | stated as deliberate beside `DATE_TYPES`, with the reason (`hwAxisDateP`); open issue 11 |
| O2 | a `Bool` cell stays a boolean where the legacy sends `"true"`/`"false"` | same comment block; open issue 11 |
| O3 | `styleBoxCells` would let an `aggColumn` named `xPosition`/`yPosition`/`styleBoxAggFormatted` overwrite that key | guarded with `RESERVED_CELL_KEYS`; the aggregate is simply not written under a reserved name |
| O4 | `assertTuple` promised a known style NAME and checked only the shape | new exported `TUPLE_STYLE_NAMES` (the ten `LEGACY_STYLE_NAMES` plus `MarkdownFmt`, `ColorFormat`, `Conditional`, `Verbatim`, `Pr2`); `assertTuple` now asserts membership and that both lists still hold 15 |
| O5 | decision 2's justification was wrong: a per-series relation IS typeable and more general | restated in decision 2, `AxisChart.e`'s header, the README's known gaps and §3.7e — the real gap is series over relations of different SHAPES, which needs an existential row |
| O6 | the `selCategoryCols` comment claimed the server's spelling; the server actually sends the `SortOrder` because its lambda parameter shadows the `val order` at `HTMLWriter.scala:737` | comment corrected, including why the boolean is the shape that `val` intended and why the key is POST-only |
| O7 | 240 s is not a plan for the LSP boot cost | open issue 10 and a handoff-log line naming the real fix (subset boot or cached session) |
| O8 | a NULL style-box aggregate becomes 0 rather than a `NullExpr` | stated in `styleBoxCells`' header; open issue 12 |