# Review of J3e (chart and style-box prop types, the client adapters, treeMap as unsupported)

Independent review of the uncommitted diff on `json-charts` against `5b0cc4ee` (J3d), plus the
untracked files. Reviewer did not write the stage. Read in order: `brief-J-common.md`,
`JSON-STAGE3-PLAN.md`, `brief-J3e-charts.md`, `report-J3d.md`, `report-J3e.md`,
`brief-review.md`. Legacy read-only at `~/research/ermine/ermine-writers`.

Logs from this review: `SP2 = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/rev-j3e/`.
The implementer's are `SP = .../scratchpad/j3e/`.

## Verdict summary

The stage is accurate work. I checked every adapter argument against its emission site in
`HTMLWriter.scala` / `RelationRunner.scala` and against what the bundle actually reads, and
found **one real divergence**: the pie chart's slice label. Everything else I checked matched,
including the parts that are easy to get wrong (series row positions, the drilldown bar's
scalar child/parent at 4 and 5, `cellCounts` as JSON-in-a-string with literal `xPosition`
keys, `aFormat` as a tuple, the skeleton class names and id suffixes, the legend-location
spellings, and the fifteen-row `TUPLE_LOSS` table against `styleMap`).

## Re-run here (not cited)

| Gate | Result | Log |
|---|---|---|
| `sbt -batch core/compile core/copyResources` | success, exit 0 | `SP2/compile.log` |
| `core/testOnly TestWidgets TestDoc TestJson TestSchema TestNamedFields` | **93/93**, exit 0 | `SP2/suites.log` |
| `npx tsc -p tsconfig.json --noEmit` (strict, `noUncheckedIndexedAccess`) | clean | `SP2/ts.log` |
| `client/scripts/check-generated.sh` | exit 0, "src/generated is up to date" | — |
| `node --test "dist/test/*.test.js"` **x3** | **59/59, 0 skipped** each time — `(t-tuple)`'s random fast-check seed did not flake | `SP2/ts.log` |
| `tracker/tools/lsp-smoke.sh` (disputed figure, see D2) | **PASS, 577 checks, 89 s wall** | `SP2/lsp-rerun.log` |
| mutation: drop `variantSrc`'s Bubble arm | `(a-cov)` **Falsified**; reverted, 6/6 green again | `SP2/mutant-scala.log`, `SP2/restore-check.log` |
| mutation: `cssColor` stops normalising | **7 of 59 node tests fail**, including `(b)` (`002: pie colour "bucmgl"`); reverted, 59/59 | — |

Cited, not re-run (the diff cannot plausibly affect them, or I do not dispute them):
`SP/gate3-looptrace.log` (3/3, 720 solves / 720 segments / 720 agree, skipped=0, hashdiff=0,
eqdiff=0, nonpart=0), `SP/gate4-corpus.log` + `SP/gate4-verdicts.log` (**89 LOADED / 79
REJECTED / 0 UNKNOWN over 168**, verified by reading the verdict tail), `SP/gate5-repl.log`
(PASS, 9 groups / 86 checks), `SP/check-corpus.log` (exit 0, 59/59).

`check-corpus.sh` I deliberately did NOT re-run: with the fixtures already written its only
additional step is `npm ci`, which wipes `client/node_modules` and would leave the worktree
broken if the install could not be satisfied. Its substance — `tsc` plus the whole node suite
against `<repo>/target/widget-corpus` and `<repo>/target/sales-report.json` — is what I ran
three times.

Backup/restore of the two mutated files verified by md5 (`SP2/*.bak`); `tracker/repl-classpath.txt`
was regenerated for my LSP run and restored byte-identically (`git status` clean).

## Correctness, line by line

Verified against the legacy, with the line numbers I read:

* **Series rows.** `RelationRunner.runRelation:71-79` emits
  `[[value…],[category…],[series…], colour] ++ extraCols(SCALARS) ++ extraOps(LISTS)`.
  `seriesRows` (charts.ts:344-372) reproduces exactly that, scalars before lists.
  `axisChartToString:325-327` passes `extraCols = List.empty`, so an axis chart's extras are
  lists at 4+; `drilldownBarChartPC` (HTMLWriter.scala:1291) passes `List(childCol, parentCol)`
  as `extraCols`, so index 4 is the child and 5 the parent as scalars — which is what
  `cur[4]` (:1932) and `_.filter(d, [5, ddid])` (:1921) read. Both reproduced.
  `unfmtRow` (:1897) rewrites only indices 0-2 via `$.extend`, so 4 and 5 survive. Correct.
* **Nulls and dates.** `jsonPrepAxis` (RelationRunner.scala:50-58): numeric NULL → `null`,
  anything else → `""`; `DateExpr` → the `[y,m,d]` triple. `axisValue` (charts.ts:144-158)
  matches, and `NUMERIC_TYPES` = {Byte, Double, Int, Long, Short} is `PrimT.isNumeric`'s set
  over the ten wire column types. The `Long`-as-decimal-string → number conversion is right
  (`PrimNumAsJson` sends a number).
* **meta.** `axisChartDataToMap` / `axisToMap` (HTMLWriter.scala:665-712) against
  `legacyMeta`/`legacyAxis` (charts.ts:290-330): `type`, `domain`/`range`, `title`,
  `orientation` lower-cased, `legendOptions.location` = `ChartLegendLocation.toString`
  (ChartData.scala:93-101 — all seven names match `legendLocationOf`'s prefix strip and all
  seven are keys of the JS `specialOpts`), `renderHints`, `colors` null, `scalarType`
  scalar/compound, and both constraint arms including the fact that the Scaled arm carries no
  `sort` key. Correct.
* **`structure` absent.** `isSeriesLevelDD` (:1727) needs `s.structure && s.structure.trees`,
  so omitting the key gives the Simple behaviour. Correct, and `(x-axis)`/`(b)` assert absence.
* **Pie.** `genPieChart` (HTMLWriter.scala:1146-1186) sends `title`, `seriesName`,
  `legendOptions`, `renderHints`, `dataFmt`, `labelFmt` and, in Local mode, `relation`;
  `parentCol`/`childCol` only for the drilldown constructor (as `p`, `c` in that order). The
  adapter sends the same set plus explicit `null`s for a flat pie, which `isnull` treats
  identically. Row shape `[label, |value|, colour, child?, parent?]` matches
  `runPieChartData` (RelationRunner.scala:238-243) — **except position 0**, see fix 1.
  `processPieData` reads `r[3]` as the drilldown id and `withPiechartData` filters
  `parentId === rec[4]` (:268), so child at 3 / parent at 4 is right.
* **Style box.** `HTMLWriter.styleBox:1188-1271` against `styleBoxWidget`: every one of the
  sixteen keys is present and spelled as the server spells it, the skeleton
  `div.stylebox_wrapper.sizeme > div.stylebox#<uid>_stylebox` is byte-for-byte the emission
  site's, `cellCounts` is `JSON.stringify` of records carrying `styleBoxAggFormatted` and the
  aggregate under `[aField]`, and `aFormat` is the tuple that `runStylebox` (:3582-3583) then
  curries. `stylebox.js:91-96` reads only `val.xPosition`, `val.yPosition`, `val[aField]` and
  `val.styleBoxAggFormatted`, so the rename in decision 8 is safe.
* **Callback claims.** Verified from the bundle: `withTimeSeriesData:221-224` takes the local
  branch on `Array.isArray(currentSeries.data)`; `withPiechartData:261-270` on
  `Array.isArray(rel)`, and the drilldown filter is in the browser;
  `withStyleBoxData:297-319` has **no** local branch and always `$.post`s — so
  "`styleBoxData` is unavoidable" is correct, and `getData` is only reached from
  `alertRowCell`, i.e. a cell click, with the failure landing in `stylebox.js:222-224`'s own
  `callbackError`. The report's table is accurate.
* **`TUPLE_LOSS`.** `legacyFormatTuple` (legacy.ts:184-206) is `jsLayoutFormat`
  (HTMLWriter.scala:208-227) case for case, including `Percentage → [places, pad]`,
  `Currency → [symbol, places]`, `Round` as a bare number, and the `MarkdownFmt`/`ColorFormat`
  renames. `styleMap` (utils.js:293-333) has exactly ten entries — Default, Percentage,
  Currency, DateRange, Round, IntegralRound, Truncate, Pr1, Alias, Constant — which is
  precisely `TUPLE_LOSS`'s `implemented: true` set and `LEGACY_STYLE_NAMES`. The five
  `implemented: false` rows are the five with no entry. The table is right.
  `(t-tuple)` genuinely CHECKS it rather than asserting it: it runs the real legacy
  `formatDisplay` loaded out of `ermine-writers`, compares value-for-value where
  `tupleIsLossless` and requires an exact `Default` answer where the name is unimplemented,
  with in-test floors (`lossless > 100`, `fellBack > 50`, all 15 tags seen) that stop it
  passing vacuously. `(t-mutant)` shows the comparison bites.
* **`isWireRelation` hazard: clear.** No record in `Chart.e`, `AxisChart.e`, `PieChart.e`,
  `StyleBox.e` or `DrilldownBar.e` declares a field named `kind` or `columns` (the nearest are
  `columnLabels`, `categoryColumns`, `componentTypes`), so J3d extension point 4a is honoured.
* **Security.** `charts.ts` contains no `innerHTML`/`insertAdjacentHTML`/`document.write`; all
  DOM is `createElement` + `className`/`id`. The only `innerHTML` in `src/` is J3d's
  `string_unhtml` port and the dispatcher's two `= ""` clears.
* **Scope and dialect.** Nothing outside the stage's files changed;
  no `core/examples/` additions; `tracker/repl-classpath.txt` unmodified. The Scala diff
  (`TestWidgets.scala` only — no production Scala) is clean of `given`/`using`/`enum`/
  `extension`/`export`/`derives`/`Either#map`/`LazyList`/`CollectionConverters`/Java 9+ APIs/
  top-level defs/`as` renames. One pre-existing `Int + String` deprecation warning at :622.

## Properties

Generators are random over declarations AND values (generated Ermine source, random literal
relations, random formats, random variants), not hand-picked. `(a)` mutates one key per case
and requires refusal; the six new optional keys were correctly added to both
`TestWidgets.optionalKeys` and `test/mutate.ts` (a `Maybe` field's key is absent on the wire,
so dropping it is not refusable). `(a-cov)`'s 200 fixed cases assert eight widgets, fifteen
`CellFormat` cases, eight variants, both constraint arms, both pie shapes, colour column
present/absent, both `showNumber` values and at least one refused mutant. `(b)` re-derives
every legacy row from the wire props — value, every category component, series-name arity,
colour, scalar vs list extras, row width, `structure` absent, pie width and `|value|`,
`cellCounts` group count and sums — and pins `[...widgetNames]` to exactly the eight
registered names so a widget that stops being generated fails rather than thinning it.

I confirmed non-vacuity two ways (above): deleting the Bubble arm from `variantSrc` falsifies
`(a-cov)`, and breaking `cssColor` fails `(b)` plus five pins. Both reverted and re-verified.

## The judgement calls the brief asked for

**D1 — `treeMap` not registered. The implementer is right; keep it.** J3d's extension point 7
is binding and says treeMap must stay out of `defaultRegistry()`. The J3e brief's wording
("register it so the dispatcher renders an unsupported box") is self-defeating: registering a
name means supplying a renderer for it, and the dispatcher only draws its error box for names
it does NOT have. The existing behaviour is already the intended one — `div.ermine-widget-error`
with `data-widget="treeMap"` plus a `RenderResult.errors` entry — and `UNSUPPORTED_WIDGETS`
plus `(x-treemap)` put the intent in code and in a test rather than only in prose. No change.

**D2 — `lsp-smoke.sh` 120 → 240 s. Accept the change; ticket the cost.** The necessity is
evidenced: `SP/gate5-lsp.log` and `SP/gate5-lsp2.log` both read `FAIL lsp (timed out)` at 120 s
on this tree. Doubling a hang guard in a shared tool is legitimate — the budget exists to stop
a wedged server, not to police performance, and the comment in the script says so.
Two caveats the orchestrator should know. (i) The report's "108 s on the J3d module set, 116 s
with J3e's five more" is not evidenced by the log it cites: `SP/gate5-lsp-baseline.log` records
only `PASS lsp (577 checks)` with no timing. My own clean run of the smoke on the J3e tree took
**89 s** (`SP2/lsp-rerun.log`), so the 120 s failures were load-dependent, and J3e's five
modules are not the proximate cause. (ii) The real fact is that the smoke boots a session of
129 modules and sits within noise of any fixed budget, and every remaining stage adds modules.
Raising the number again next stage is not a plan. Recommend an open issue (optional O7).

**D3 — `charts.ts` beside `legacy.ts` rather than `client/src/legacy/`.** Right call.
`legacy.ts` is the file that types the `htmlwriter` global (J3d extension point 5) and holds
the table adapters; turning it into a directory would have moved reviewed code for no gain,
and the chart argument types are `import type`d across cleanly.

**D4 — `xBins`/`yBins` as numbers.** Right, and for the stated reason: their only consumer is
`formatBounds` (`stylebox.js:183-185`), which calls `.toFixed(3)` — the server's pre-formatted
strings throw there today. The path is unreachable on this stage's rendering anyway (it is
inside the `styleBoxData` popup), so numbers are the shape that would work if the popup is ever
served. Documented in the module header, the README and §3.7e.

**D5 — decision 8, `cellCounts` renaming, is a genuine fix of a legacy defect.** Confirmed from
both sides: `HTMLWriter.styleBox:1213-1218` names the group attributes after the VALUES of
`xPositionField`/`yPositionField`, while `stylebox.js:91-96` reads the literal `val.xPosition` /
`val.yPosition` — so today the widget only produces a non-empty grid when the relation's
columns happen to be called `xPosition`/`yPosition`; otherwise `validatePosition(undefined)` is
false for every cell and the grid renders empty. The rename is safe because those four key
names are all the renderer reads, and `xPositionField`/`yPositionField` are still sent for the
POST. Keep, and it is correctly called out as deliberate.

**D6 — decision 2, one relation per axis chart.** The restriction is acceptable and well
documented, but the *justification* in the report is wrong; see O5.

## REQUIRED fixes

### 1. The pie chart's slice label is sent raw where the legacy sends it FORMATTED

**Where.** `client/src/charts.ts:495` (`const label = reader(rel, props.pieLabelColumn);`) and
`client/src/charts.ts:504` (`label(row),` — position 0 of every pie row).

**What the legacy does.** `RelationRunner.runPieChartData` builds position 0 as
`lc.format.basicEval(labels) extractNullableString ""` (`RelationRunner.scala:240`) — the label
column's `Format` applied server-side (`Legend.scala:619`, `Format.basicEval`), always a
String, with a NULL flattened to `""`. The adapter instead emits `axisValue(col, cell)`: the
raw wire cell, and for a `Date`/`Timestamp` column the `[y, m, d]` ARRAY.

**Why `labelFmt` cannot repair it in the browser.** `runPiechart` passes `args.labelFmt` to
exactly one place, `hcutil.pieLegendOptions(args.legendOptions, args.labelFmt, datafmt)`
(`ermine-htmlwriter.js:2422`). That function returns
`endoMConcat([hcutil.legend(legendOptions, [fmtSeries]), pieLegendTable | pieLegendRegular])`
(`:1404-1405`); `varyOpts` is `old => _.merge({}, old, new)` (`utils.js:73-75`), so the pie's
own builder is applied LAST and its `labelFormatter` (`:1358-1369`, `:1379-1388`) wins — and
that formatter interpolates `this.name` verbatim, `this.name` being `r[0]` straight out of
`processPieData` (`:250-258`). The tooltip formats the name with a hard-coded
`['Default', null]` (`:2415-2421`), which for a non-string simply returns the value. So
whatever the adapter puts at position 0 is what reaches the DOM.

**Failure scenario.** (a) Any pie whose `pieLabelFormat` is not `Default` — `Constant`,
`Alias`, `Truncate`, `Currency`, `Percentage`, … — renders unformatted labels in the legend,
the tooltip and the drilldown breadcrumb, where today's server-rendered page shows the
formatted ones. The prop is accepted, validated, carried on the wire and then silently ignored.
(b) A pie over a `Date` or `Timestamp` label column renders `2026,1,31` in the legend (the
array stringified) and a `Date` object's `toString` in the tooltip, where the server shows the
formatted date. (c) A NULL label renders `null` rather than `""`.
No test catches it: every pie fixture in `charts.test.ts`, `endtoend.test.ts` and the
generated corpus uses `Default`, and `(b)`'s pie block asserts `row[1]` and `row[2]` but never
`row[0]` (`client/test/corpus.test.ts`, the `pieChart`/`drilldownPieChart` branch).

**Fix.** Format the label on the client, the way `styleBoxCells` already formats its aggregate.
In `pieRows`, take a `FormatEnv`, read the label column's RAW cell (not `axisValue` — a
`[y,m,d]` triple would be turned into a `Date` by `formatDisplay`'s own `nelpeHwDates`), and
emit `String(formatDisplay(props.pieLabelFormat, env)([raw]) ?? "")`, with `null`/`undefined`
coerced to `""` to match `extractNullableString ""`. Thread the env through `pieArgs` and
`pieChartWidget(drilldown, env?)` exactly as `styleBoxWidget(env?)` does (`defaultRegistry`
already has one), and pass `defaultFormatEnv(ctx.document)` when it is absent.
Then: give `(x-pie)` a non-`Default` `pieLabelFormat` and a Date label column, and add
`row[0]` to `(b)`'s pie assertions so the hole does not reopen. Note the side benefit: the
port's `Default` runs `string_unhtml`, so the label that the legend interpolates into HTML
becomes escaped, which is the same move J3d made for table cells.

## Optional suggestions

* **O1. `Timestamp` columns become `[y, m, d]`; the legacy sends a string.**
  `charts.ts:132` puts `Timestamp` in `DATE_TYPES`, but `jsonPrepAxis` matches only
  `DateExpr` (`RelationRunner.scala:53`) — a `TimestampExpr` falls through to
  `extractNullableString ""`. Arguably an improvement (a timestamp axis then behaves like a
  date axis), but the header comment claims fidelity to the legacy conversion, so it should
  either say this is deliberate or restrict the set to `Date`.
* **O2. A non-string, non-null cell of a `Bool` column.** The legacy sends `"true"`/`"false"`
  (the `extractNullableString` fall-through); `axisValue` returns a JS boolean. Cosmetic in
  every reader I found, but worth a line beside `NUMERIC_TYPES`.
* **O3. `styleBoxCells` key collision.** `charts.ts:588` does `cell[props.aggColumn] = g.sum`
  after setting `xPosition`/`yPosition`/`styleBoxAggFormatted`. An `aggColumn` literally named
  one of those three silently overwrites it, and the renderer then drops the cell
  (`validatePosition` on a sum) or prints the raw number. One `if` or a comment would close it.
* **O4. `assertTuple` promises more than it checks.** `client/test/corpus.test.ts`: the
  doc-comment says the tuple's name must be one `TUPLE_LOSS` knows, but the body only asserts
  `Array.isArray && length === 2`, a string head, and the constant
  `Object.values(TUPLE_LOSS).length === 15`. The NAME is never checked. Tighten it to
  membership in the fifteen tuple names (`LEGACY_STYLE_NAMES` plus `MarkdownFmt`,
  `ColorFormat`, `Conditional`, `Verbatim`, `Pr2`), or soften the comment.
* **O5. Decision 2's justification is wrong, though the decision is fine.** The report says one
  shared relation is "strictly no weaker than the typeable alternative". It is not:
  `data ChartSeries r = ChartSeries { …, seriesRows : [..r] }` with
  `chartSeries : List (ChartSeries r)` is typeable and strictly more general (same columns,
  different row sets, and a deferred token per series). What the client cannot express either
  way is series over relations of DIFFERENT shapes. Please restate the gap that way in the
  README's known-gaps entry and in §3.7e, so the next stage does not inherit a wrong reason.
* **O6. `selCategoryCols`' second element.** `charts.ts:378-382` pairs each category column
  with a BOOLEAN and cites `chartSeriesToMap` ~758-762; the server actually pairs it with the
  `SortOrder` value, because the lambda parameter in
  `s.selCategory.zip(domOrder).list.flatMap { case (op, order) => … }` (HTMLWriter.scala:756-760)
  shadows the `val order = domOrder map {Asc => false; Desc => true}` at `:734`, leaving that
  `val` dead. The key is POST-only so nothing breaks, but the comment should not claim the
  spelling is the server's.
* **O7. Ticket the LSP boot cost** rather than leaving 240 s as the answer (D2). A handoff-log
  line or an open issue saying "the LSP smoke boots 129 modules and now runs 90-116 s; the next
  module additions will need either a subset boot for the smoke or a cached session" would keep
  the next agent from simply doubling it again.
* **O8. NULL aggregates in the style box.** SQL `Sum` over a nullable Double ignores NULLs and
  yields NULL for an all-NULL group; `charts.ts:573-577` coerces a NULL cell to `0`, so such a
  group shows a formatted zero where the server shows the format of a `NullExpr`. Tiny, and
  arguably nicer, but it is a divergence in the one number the widget exists to show.

## Nothing else to flag

The `using` lists are types-only except `Default` in `Chart.e:32`, which is a CONSTRUCTOR, not
a field selector, and is exactly what J3d's extension point 2 sanctions for spelling a default
value. Field names are fresh across the nine-module umbrella — demonstrated, not assumed, by
the five modules loading together in `bin/ermine-schema` (my `check-generated.sh` run), by
`TestWidgets` importing all nine with `all` in one scope and evaluating generated source
(93/93), and by the LSP smoke's 577 checks. The docs (README, §3.7e, the plan row and handoff
entry) are accurate and short.

---

**FIX-THEN-LAND** — one required fix (pie-chart label formatting, above), which is local to
`client/src/charts.ts`'s `pieRows`/`pieArgs`/`pieChartWidget` plus two test additions; the
eight optional items are suggestions only.
