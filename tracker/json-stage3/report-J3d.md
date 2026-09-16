# J3d as built: widget prop types, the TypeScript client, the table adapters, one new widget

(Report text written by the implementer agent, saved to this path by the orchestrator: the agent's harness blocked writing `.md` files.)


Branch `json-client`, worktree `~/research/ermine/ermine-scala-wt-json-client`, off 6f0e3d8b (json-encode f8a789d1 [J3a] merged with json-doc bf832e46 [J3b]). Uncommitted. 2026-09-16, ~5 h of the 6 h budget, plus the four review fixes
(`review-J3d.md`, FIX-THEN-LAND) — see "Review fixes applied" at the end.

## Files built

| File | What |
|---|---|
| `core/src/main/resources/modules/Layout/Widgets/Format.e` (new, 84 lines) | `RGB`, `Threshold`, `CellCondition`, `CellFormat` (all fifteen legacy cases) + six spellings (`plain`, `percent`, `dollars`, `roundTo`, `truncateTo`, `constantly`) |
| `.../Layout/Widgets/Table.e` (new, 57) | `ColumnAlign`, `ColumnKind`, `ColumnSort`, `TableColumn`, `TableProps r`, `tabular`, `simpleTable`, `textColumn`, `numberColumn` |
| `.../Layout/Widgets/Drilldown.e` (new, 33) | `DrilldownTableProps r`, `drilldownTable`, `simpleDrilldownTable` |
| `.../Layout/Widgets/Scorecard.e` (new, 30) | `ScorecardProps r`, `scorecard`, `simpleScorecard` — the NEW widget |
| `.../Layout/Widgets.e` (new, 34) | the umbrella: `export`s the four, plus `widgetNames` (the nine reserved registry names) |
| `client/` (new, 30 tracked files) | the npm package: `package.json` + `package-lock.json` (zod 3.23.8, typescript 5.6.3, jsdom 25.0.1, fast-check 3.23.1 pinned), `tsconfig.json` (strict + `noUncheckedIndexedAccess`), `README.md`, `scripts/{generate,check-generated,check-corpus}.sh`, `src/{props,relation,document,format,dispatcher,legacy,index}.ts`, `src/widgets/scorecard.ts`, `src/generated/` (5 generated zod modules + index), `test/` (6 test files + 3 helpers) |
| `core/src/test/resources/modules/Doc/SalesReport.e` (new, 46) | the end-to-end report: one relation, one `scorecard`, one `table` |
| `scalacheck-binding/src/main/scala/TestWidgets.scala` (new, ~470) | property (a) + coverage + three pins (**5 properties**), and the `WidgetCorpus` / `SalesReportDoc` runMains |
| `.gitignore` | `client/node_modules/`, `client/dist/` |
| `tracker/JSON-API-DESIGN.md` | new §3.7e "Stage 3 client as built" |
| `tracker/JSON-STAGE3-PLAN.md` | J3d ticked; handoff-log entry |

No production Scala changed: `Encode`, `Schema`, `Zod`, `Validate`, `Doc`, `Write`, `PlanCache` are exactly as J3a and J3b left them. J3a's row-polymorphic root rule and `bin/ermine-schema --zod` needed no change to export these prop types.

## The prop type declarations, as landed

```
-- Layout/Widgets/Format.e
data RGB = RGB { red : Int, green : Int, blue : Int }
data Threshold = TNum Double | TStr String | TBool Bool
data CellCondition = Gt { gt : Threshold } | Lt { lt : Threshold } | Eq { eq : Threshold }
                   | Gte { gte : Threshold } | Lte { lte : Threshold }
                   | And { and : (CellCondition, CellCondition) }
data CellFormat =
    Default | Verbatim
  | Markdown { base : CellFormat }
  | Constant { value : String }
  | Percentage { color : Bool, negParens : Bool, places : Int, pad : Bool }
  | Currency { color : Bool, negParens : Bool, symbol : String, places : Int }
  | Pr1 { base : CellFormat } | Pr2 { base : CellFormat }
  | DateRange
  | Round { color : Bool, negParens : Bool, places : Int }
  | IntegralRound { color : Bool, negParens : Bool, places : Int }
  | Truncate { places : Int }
  | Conditional { condition : CellCondition, whenTrue : CellFormat, whenFalse : CellFormat }
  | Color { bg : RGB, fg : RGB, base : CellFormat }
  | Alias { aliases : List (String, String) }

-- Layout/Widgets/Table.e
data ColumnAlign = AlignLeft | AlignRight
data ColumnKind  = NumberColumn | DateColumn | OtherColumn
data ColumnSort  = ColumnSort { sortColumn : Int, descending : Bool }
data TableColumn = TableColumn { column : String, header : String, cellFormat : CellFormat
                               , align : ColumnAlign, kind : ColumnKind }
data TableProps r = TableProps { columns : List TableColumn, rowGroup : Maybe Int
                               , sorts : List ColumnSort, paginate : Bool, scroll : Bool
                               , rows : [..r] }
tabular : TableProps r -> Node                    -- widget "table"

-- Layout/Widgets/Drilldown.e
data DrilldownTableProps r = DrilldownTableProps { ddColumns : List TableColumn
                                                 , parentColumn : String, childColumn : String
                                                 , labelColumn : String, ddSorts : List ColumnSort
                                                 , ddPaginate : Bool, ddScroll : Bool
                                                 , ddRows : [..r] }
drilldownTable : DrilldownTableProps r -> Node    -- widget "drilldownTable"

-- Layout/Widgets/Scorecard.e   (the NEW widget)
data ScorecardProps r = ScorecardProps { title : String, cardLabel : String, cardValue : String
                                       , cardDelta : Maybe String, cardFormat : CellFormat
                                       , cards : Inline r }
scorecard : ScorecardProps r -> Node              -- widget "scorecard"
```

`bin/ermine-schema -i Layout.Widgets.Table TableProps` gives `"$id": "ermine:Layout.Widgets.Table/TableProps r"`, `$ref` into `#/$defs/Layout.Widgets.Table.TableProps__` (TS `Layout_Widgets_Table_TableProps__`) — the row parameter free, one schema for every relation the widget is used with (pinned by `(a-pin3)`).

## Decisions taken in code (the plan did not fix these)

1. **ONE MODULE PER WIDGET, not one `Layout/Widgets.e`.** Ermine field selectors are MODULE-global: a second `data` type with a `columns` field in the same module is *"field selector columns is already a field selector of another data type"*. Since J3e adds five more widgets that all want `columns`/`rows`/`series`, the brief's single module is a dead end. Each widget's props live in `Layout/Widgets/<Widget>.e` and `Layout/Widgets.e` re-exports them with `export`. A widget module imports another only with an explicit `using` list of TYPES (`import Layout.Widgets.Table using type TableColumn; type ColumnSort`), so the imported selectors never come into scope to be shadowed. The drilldown's fields are therefore prefixed (`ddColumns`, `ddRows`, `ddSorts`, `ddPaginate`, `ddScroll`) and the scorecard's are its own (`cardLabel`, `cardValue`, `cardDelta`, `cardFormat`, `cards`).
2. **`table` is a keyword, so the smart constructor is `tabular`.** The registry name on the wire is still `"table"`. (J3a warned about `table` as a FIELD name; it is equally unusable as a definition name.)
3. **`CellFormat`'s `tag` maps to the legacy `"type"` by lower-casing the first letter.** The generic walker fixes the discriminator as `"tag"` with the constructor NAME, so `Default -> "default"`, `IntegralRound -> "integralRound"`. Three fields could not keep the legacy spelling: `whenTrue`/`whenFalse` for Conditional's `then`/`else` (Ermine keywords), and `aliases` is a list of pairs because the walker has no map encoding. `client/src/legacy.ts::legacyFormat` is the one function that maps back; `(w-legacy-format)` pins it.
4. **`Currency` carries `places`, which the legacy object form does not.** The server reads it from `CurrencyObj.settings(symbol, Locale.US)`; the client has no such table and must format the cell itself. The two genuinely lossy spots (`round`/`integralRound` drop `color`) are kept lossy, so what reaches `runTabular` stays comparable with what the server sends today.
5. **`Threshold` is a positional three-arm union, not `Json`.** A `Json`-typed field exports as `{}` — any document — so no mutation inside a condition threshold could ever be refused. `{"tag":"TNum","args":[1.0]}` is mutation-detectable, which property (d) needs.
6. **`TableProps.rows` / `DrilldownTableProps.ddRows` are bare `[..r]`; `ScorecardProps.cards` is `Inline r`.** A table may defer (the request decides); a scorecard with no numbers is nothing, so its schema has the inline arm only and the component has no deferred case. Note `Inline`/`Deferred` take a ROW, so they cannot be applied to a field already declared `[..r]` — the wrapper choice is made in the DECLARATION, not at the use site.
6a. **`runTabular`'s `sorts` is `[index, "asc" | "desc"]`, a STRING, and the adapter does the
   translation.** DataTables builds the NAME of the comparator it calls out of that second
   element (`oSort[sDataType + "-" + aaSort[k][1]]`, datatables.js:4019), and the server sends
   the same strings (`Tabular.ordering : IndexedSeq[(Label, SortOrder)]`, printed by
   `PruJS.scala:59` as `x.toString.toLowerCase`). The Ermine type keeps the boolean
   `ColumnSort.descending` — the translation belongs beside `alignmentOf`/`columnTypeOf`, not
   in the wire type. (Added by review fix 1; the first cut sent the boolean, which would have
   thrown a TypeError on the first draw of any sorted table.)
7. **The dispatcher resolves relations STRUCTURALLY, and `isWireRelation` is deliberately
   narrow.** `resolveRelations` deep-walks the validated props and replaces anything shaped like a relation arm with the inline object its token fetches, so J3e's charts resolve for free with no dispatcher change. Because that test is structural, it requires the WHOLE arm — `kind`, plus `columns` holding real column descriptors, plus `rows`+`rowCount` or `token`+`expires` — not just `kind` and `columns`: `TableColumn` already declares a field named `kind`, so the weaker test left a one-field-name margin between a chart descriptor and a relation. Pinned by `(p-relation-guard)`.
8. **`src/props.ts` is hand-written and pinned, not inferred.** `ermine-schema --zod` must emit a recursive schema as `z.ZodTypeAny` (for `z.lazy`), and `z.infer` of that is `any`. The generated zod stays the runtime authority; `test/props.test.ts` compares the hand-written declarations against it field by field and tag by tag, both directions.
9. **A NULL cell displays as the legacy `-`, outside the port.** Server-side a format applied to a `NullExpr` stays a `NullExpr` and `HTMLWriter.jsPrimExprTabular` prints `-`; the JS `formatDisplay` has no null case, so `Round` on a null would read `0.0`. The rule lives in `legacy.ts::tabularCell` (and the scorecard), not in `format.ts`, so the port stays bug-compatible with the legacy function. `Constant` is the exception — it ignores its input.
10. **`Highcharts.numberFormat` is transcribed into `src/format.ts` and injected into the legacy side as its Highcharts stub.** highcharts is not a dependency here, so the agreement property covers DISPATCH and argument plumbing of every lossless case rather than Highcharts' own number formatting; the transcription is pinned separately in `(c-pin)`. Said plainly because it bounds what (c) proves.
11. **The drilldown tree is built on the client** from `parentColumn`/`childColumn` (depth-first from the roots; a root is a row whose parent value matches no row's child value). A cycle does not loop: its rows are emitted at the end at depth 0 (pinned).
12. **The error box, not an exception.** Unknown widget name, props the schema refuses, an unresolvable deferred token, and a renderer that throws all render `div.ermine-widget-error[data-widget]` and add an entry to `RenderResult.errors`.
13. **`settings` is `z.record(z.unknown())` and the envelope is `.strict()`** — a document carrying the reserved `errors` key (Streamed, not in v1) is refused here rather than silently ignored.

## Departures from the brief

| Brief | As built | Why |
|---|---|---|
| `modules/Layout/Widgets.e` holds the prop types | four modules under `modules/Layout/Widgets/`, re-exported by `Layout/Widgets.e` | field selectors are module-global (decision 1) |
| `table : TableProps r -> Node` | `tabular : TableProps r -> Node`, registry name still `"table"` | `table` is an Ermine keyword |
| prop types for "the seven live widgets" | `table`, `drilldownTable`, new `scorecard`; the five chart names reserved in `Layout.Widgets.widgetNames` and the README | the brief's own build list is exactly these three; charts are J3e |
| report module under `core/src/test/resources/doc/` | `core/src/test/resources/modules/Doc/SalesReport.e` | only `modules/` on the classpath is on the module search path |
| through `bin/ermine-serve` if J3c has landed | `sbt 'core/Test/runMain com.clarifi.reporting.SalesReportDoc <file>'` with `Scanners.SQLite(SMEnv.dummySmenv)` + `Runners.SQLite("jdbc:sqlite::memory:")` + `Guard.db` | J3c has not started |
| `tag` spelled so the JSON is directly `formatDisplay`'s object form | `tag` + constructor name, with the documented lower-first-letter mapping and three renamed fields | the walker fixes `"tag"` and the constructor name; `then`/`else` are keywords; no map encoding (decision 3) |
| `format.ts` ports `formatDisplay` "to the object form" | the form it dispatches on is `CellFormat` (Ermine), not the legacy `{type: …}` object; `legacy.ts` converts to the legacy object for the cell's `format` key | the legacy `{type}` object is only ever READ for `format.type === 'markdown'` (tables.js's sort key); nothing formats from it |
| property (a) uses random literal relations | every generated relation has 1..6 rows (never 0) | `mkRelation# (toList# [])` carries no header and `Doc.fromRuntime` refuses it without a hint (J3b `(d-pin)`); empty relations are covered by the client's `(d-empty)` |

## Properties (random declarations and values)

### Scala — `TestWidgets`, 5 properties

| Id | What | Size / non-vacuity |
|---|---|---|
| (a) | random `TableProps`/`DrilldownTableProps`/`ScorecardProps` values, as generated Ermine source over random literal relations, inside random `vflow`/`hflow`/`grid`/`tabbed` trees, with a random `WriteConfig` (delivery default + threshold), through `Write.doc`, must validate against `Schema.exportNamed` for their prop type AND the root against `Layout.Doc.Node`'s schema | 100 cases; each case also MUTATES one key of the props (drop / retype / add) and requires the schema to refuse it |
| (a-cov) | (a) over 120 fixed-seed cases with coverage assertions | all three widgets, **all fifteen** `CellFormat` constructors, both `kind-inline` and `kind-deferred`, both relation forms (`wrap-bare`, `wrap-Inline`), and at least one `mutant-rejected` |
| (a-pin) | byte-for-byte wire spelling of a scorecard document (envelope, `tag`/`name`/`props`, the `Round` object, sorted `columns`, `rowCount`) | — |
| (a-pin2) | a nullary `CellFormat` constructor goes out `{"tag":"Default","args":[]}`, not a bare string | — |
| (a-pin3) | each prop type exports ONE schema whose `$id` leaves the row parameter free | — |

The mutation check was not vacuous in the writing: it caught that a `Maybe` field's key is OPTIONAL on the wire, so dropping `rowGroup`/`cardDelta` is not a refusable mutation (they are retyped or added to instead).

### TypeScript — 33 tests

| File | Tests | What |
|---|---|---|
| `format.test.ts` | 5 | **(c)**: `(c-total)` the port answers for every random `CellFormat` (fast-check, 500 runs) and the generated zod's tag list equals the port's switch; **`(c-legacy)`** 4000 random (format, values) pairs, of which **~2500 are lossless in the tuple form** and are compared against the REAL legacy `formatDisplay` loaded out of `~/research/ermine/ermine-writers`, all ten styleMap cases covered; `(c-mutant)` a deliberately wrong Truncate is caught; `(c-pin)` the transcribed helpers; `(c-extra)` the five cases and two flags the tuple form cannot carry, plus the Alias pins |
| `props.test.ts` | 7 | every generated schema's keys, optional keys, union arms and enum values against `src/props.ts` and `src/relation.ts` |
| `dispatcher.test.ts` | 12 | the envelope; the four layout containers (tab switching included); **(d)**: 400 single mutations of a valid document, every one refused with a path and an error box, all three mutation kinds; unknown widget, invalid props, throwing renderer, unresolvable token; deferred resolution and `httpFetchData`; an EMPTY relation |
| `widgets.test.ts` | 6 | the `runTabular` argument object cell by cell; the legacy object and tuple encodings; the drilldown tree and a cycle; the scorecard's DOM; the skeleton |
| `corpus.test.ts` | 2 | **(b)** and its negative half |
| `endtoend.test.ts` | 1 | `Doc.SalesReport` through SQLite, rendered in jsdom |

**(b), cross-language.** `WidgetCorpus` writes **200 documents** from the same generator (a) uses, each with a `NNN.tokens.json` sidecar standing for `GET /data/<token>`. The client parses, dispatches and renders every one in jsdom against a stub `htmlwriter` that records `runTabular` calls:

```
200 documents, 425 widgets, 2666 cells, 176 deferred relations resolved, 15 CellFormat cases
```

zero validation failures, zero error boxes; every call's args satisfy the legacy interface (`id` ends `_tabular` and addresses a real `table.tabular` inside a `div.tabular_wrapper`; `colAlignments`/`colType` are the legacy vocabularies and as long as `cols`; `sorts` are `[number, "asc" | "desc"]` and BOTH directions occur; drilldown `ix` dense, `indent >= 0`); `cells.length = rows × displayed columns`; `raw` equals the wire cell of that column (or `null` for a column the relation lacks); `formatted` equals `tabularCell` on it. **That last one is a consistency check, not an independent check of the port**: it re-calls the function that produced the value, so what it pins is the format-to-COLUMN alignment (each cell got its own column's `CellFormat`, in order), not the port's arithmetic. An independent check is impossible here — the server's `formatted` is not on the wire — and the port's arithmetic is what `(c-legacy)` is for. `(b-neg)` mutates each of the 200 documents once: **200 of 200 refused**, all three kinds exercised.

**A real divergence the properties found.** `(c-legacy)` failed on one `check-corpus.sh` run with `{"tag":"Alias","aliases":[["",""],["","a"]]}` on `[""]`: the legacy builds a plain OBJECT from the pairs, so a REPEATED key takes the LAST pair's value, while the port's list walk took the first. Fixed (`format.ts` keeps the last match) and pinned, together with the empty-alias fallback and the two keys where the port is deliberately NOT bug-compatible — the legacy's `aliases[fst]` answers `Object.prototype`'s member for `"constructor"`/`"__proto__"`, the list walk does not. Five consecutive random runs green after the fix.

## Gates

Logs under `SP = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/j3d/`.

| # | Gate | Result | Log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources` | success, no warnings | `SP/gate1-compile-final.log` |
| 2 | `core/testOnly TestJson TestSchema TestNamedFields TestDoc TestWidgets` | **92/92** (28 + 25 + 14 + 20 + **5**; the four-suite base on this tree is 87) | `SP/gate2-suites-final.log` |
| 3 | `core/testOnly *TestLoopTrace` with `-Dermine.looptrace=<json-wrappers>/tracker/lean/.lake/build/bin/looptrace` | 3/3; **720 solves, 720 segments, 720 agree, skipped=0, hashdiff=0, eqdiff=0**; controls detect 46/720 and 58/720 | `SP/gate3-looptrace2.log` (without the binary the replay is SKIPPED: `SP/gate3-looptrace.log`) |
| 4 | `corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged | `SP/gate4-corpus.log`, `SP/gate4-verdicts.log` |
| 5 | `repl-smoke.sh` | **PASS**, 9 groups / 86 checks (aliasing 2, ffi 5, ffi-tolerant 9, json 20, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5) | `SP/gate5-repl.log` |
| 5 | `lsp-smoke.sh` | **PASS, 577 checks** | `SP/gate5-lsp.log` |
| J3d | `npx tsc -p tsconfig.json --noEmit` (strict) | clean | `SP/tsc.log` |
| J3d | `client/scripts/check-generated.sh` | exit 0, "src/generated is up to date" | `SP/check-generated.log` |
| J3d | `npm run build && node --test "dist/test/*.test.js"` from a CLEAN checkout, no fixtures, no environment (the README's own line) | exit 0, **33 passed / 3 skipped** (the three fixture-backed tests name the command that would produce them) | `SP/fix-nofixtures.log` |
| J3d | the same with the fixtures present | **36/36** | `SP/fix-nodetest.log` |
| J3d | `client/scripts/check-corpus.sh` with NO argument (sbt writes both fixtures into `<repo>/target`, then npm ci + tsc + the suite) | exit 0, **36/36** | `SP/fix-checkcorpus.log` |
| — | `sbt 'core/Test/runMain ...WidgetCorpus <dir> 200'` | 200 documents written | `SP/corpus-gen.log` |
| — | `sbt 'core/Test/runMain ...SalesReportDoc <file>'` | 1421 chars through SQLite in-memory | `SP/salesreport1.log` |

`tracker/repl-classpath.txt` was regenerated for the smokes and restored with `git checkout`; `git status` is clean of it. The full `core/test` is the orchestrator's.

## Open issues

1. **No converter from the foreign `Layout.Format` to `CellFormat`.** Out of scope by the brief, and it cannot be written in Ermine: `Format` is a Scala ADT with no exposed eliminator. It needs a Scala-side fold (roughly `HTMLWriter.jsFormat` re-targeted at a `Runtime`), which would let existing `Presentation`-based reports move over unchanged.
2. **Empty relations never reach the Scala property** (`mkRelation# (toList# [])` has no header; `Doc.fromRuntime` refuses it). The client's `(d-empty)` covers the wire object by hand. Closing this properly wants a literal-relation-with-header spelling reachable from generated Ermine source.
3. **Column GROUPINGS are not reproduced.** `tableSkeleton` emits one header row and `args.legend` is `null`; the legacy `Legend` is an f0-serialised blob the JSON path has no equivalent for. Nothing in the local-relation path of `runTabular` reads it, but a report that today shows grouped headers would lose them.
3a. **Five of the fifteen `CellFormat` arms have example-grade evidence, not property-grade.**
   `Verbatim`, `Markdown`, `Pr2`, `Conditional` and `Color` have no counterpart in the legacy
   JS `formatDisplay` (its tuple form collapses them to `Default`), so `(c-legacy)` cannot
   reach them; they follow a READING of `HTMLWriter.htmlEval` and are covered only by
   `(c-extra)`'s pins. Inherent, but worth saying.
3b. **`formatted` is not byte-identical to what the server sends today.** A Date or Timestamp
   cell arrives as its wire string rather than through `HTMLRunner.tabularDateFmt`'s
   `MMM-dd-yyyy`, and `htmlEval`'s fallback branch replaces every space with `&nbsp;` while
   the port does not. Both are cosmetic and arguably improvements; the cell's `format` key IS
   byte-identical. Stated in `legacy.ts`'s header, the README and §3.7e.
4. **`Markdown` does not render markdown** — the port formats with `base` and passes the result through. The cell's `format.type` is still `"markdown"`, which is what the legacy sort key needs.
5. **`(c-legacy)` runs on a RANDOM fast-check seed**, so it explores a different slice each run — that is how the Alias divergence was found. A reviewer may see a new counterexample; the gate is not bit-reproducible. Fixing the seed would trade the search for CI determinism.
6. **`Highcharts.numberFormat` is shared between port and legacy stub** in `(c-legacy)` (decision 10), so that property does not cross-check number formatting itself.
7. **`legacyFormatTuple` for `Pr2`/`Conditional`/`ColorFormat`/`Verbatim`/`MarkdownFmt`** faithfully reproduces `jsLayoutFormat`, which means those tuples name styles the legacy `formatDisplay` has no case for and silently fall back to `Default`. J3e's chart adapters inherit that: a chart with a `Conditional` format will not format as the table does.
8. **No `x-ermine: {module, type, hash}` drift guard** (§3.5). `check-generated.sh` plays that role in-repo, but a client shipped separately from the server has nothing to check against; J3c should consider putting a schema hash in the envelope.
9. **The dispatcher awaits relation resolution per widget, sequentially** — a document with many deferred relations makes one round trip after another. A batching `fetchData` (or resolving all tokens up front) is the fix; not needed at the sizes seen.
10. Carried from J3b, both reachable from anything the client renders: a NULL in a `GUID` column NPEs in `SqlExecution.nextRecord`, and `EffectfulProcedure.withDriver` lacks a `finally` around teardown.

## Extension points J3e (charts) must use

1. **One module per widget.** `Layout/Widgets/AxisChart.e`, `PieChart.e`, `StyleBox.e`, … each with its own field selectors, each `export`ed from `Layout/Widgets.e`. Do NOT add a second `data` type with a `columns`/`rows`/`series` field to an existing module — it will not compile. Import another widget's module only with an explicit `using` list of TYPES, so its selectors never come into scope.
2. **Reuse `Layout.Widgets.Format.CellFormat`** for anything per-value: `aFormat`, axis formats and series formats are all the same legacy `Format`. `import Layout.Widgets.Format using type CellFormat` (add `Default` etc. to the `using` list only where a default value is spelled).
3. **`client/scripts/generate.sh`**: add one line to the `types` array (`"Layout.Widgets.AxisChart:AxisChartProps:axisChart:AxisChartPropsSchema"`) and one line to the `WIDGET_PROP_SCHEMAS` literal in the same script, then `npm run generate`. `check-generated.sh` then guards it.
4. **`src/dispatcher.ts` needs no change.** Implement `Widget<P>` = `{ render(ctx: WidgetContext, props: P): void | Promise<void> }` and add a line to `defaultRegistry()` in `src/index.ts`. The dispatcher validates props with the generated schema, deep-resolves every relation anywhere inside them, gives you `ctx.target` (an empty `div.ermine-widget[data-widget]` already in the tree), `ctx.document`, `ctx.uid()` and `ctx.path`, and turns anything you throw into an error box.
4a. **A prop record must not reproduce a relation arm.** The dispatcher finds relations
   STRUCTURALLY, so `isWireRelation` (`src/relation.ts`) decides what is a relation by shape.
   It is deliberately narrow — `kind` of `"inline"`/`"deferred"`, `columns` of real column
   descriptors (`{name, type ∈ the ten column types, nullable}`), and `rows`+`rowCount` or
   `token`+`expires` — so an ordinary chart descriptor cannot trip it even though
   `TableColumn` already has a field called `kind`. Do NOT declare a props record that carries
   all of those together: it would be swapped out and handed to your widget as a relation (or,
   spelled `"deferred"`, would send a `GET /data/<your object's token>` and render an error
   box), and neither failure points at the prop type. If you ever need that shape, give the
   dispatcher an explicit relation path rather than widening the test. `(p-relation-guard)`
   pins the boundary in both directions.
5. **`src/legacy.ts` is where the `htmlwriter` global is typed.** Extend `HtmlWriter` with `runTimeSeries`, `runPiechart`, `runPiechartDrilldown`, `runDrilldownBar`, `runStylebox` — note `runStylebox` applies `formatDisplay` to `args.aFormat` ITSELF (`ermine-htmlwriter.js:3583`), so hand it the TUPLE from `legacyFormatTuple`, not a formatted value. `legacyFormat` (object form) and `legacyFormatTuple` (tuple form) are both exported; `LEGACY_STYLE_NAMES` says which tuples the legacy actually implements. Note the vocabulary
   rule the table adapters follow: anything DataTables or Highcharts reads as a NAME must be
   the legacy's string, not a richer client-side value — `sorts` is `[index, "asc"|"desc"]`,
   `colAlignments` is `"left"`/`"right"`, `colType` is `"number"`/`"date"`/`"other"`. The
   Ermine types keep the typed constructors; `alignmentOf`, `columnTypeOf` and `sortPairs`
   translate.
6. **`src/format.ts::formatDisplay(fmt, env)`** is curried exactly like the legacy, so build the formatter once per series or axis and apply per point. `defaultFormatEnv(document)` gives the DOM-backed `string_unhtml`; `hwDates` turns a YMD triple into the Date the chart path expects.
7. **`treeMap`** is reserved in `Layout.Widgets.widgetNames` but should stay OUT of `defaultRegistry()`: the dispatcher's error box naming it is the intended "unsupported" behaviour, and `(d-unknown)` pins that shape.
8. **Testing.** Add your prop generators to `TestWidgets.widgetSrc` (the source-generating `Gen[WidgetSrc]`s are `tableSrc`/`drilldownSrc`/`scorecardSrc`; each yields decls, an expression, the registry name and coverage tags); the corpus, `check-corpus.sh` and property (b) pick them up with no further change — `(b)`'s widget-name assertion is the one line to extend. `test/harness.ts` has the jsdom setup, the recording stub and the `cellFormatArb` fast-check arbitrary.

## Review fixes applied (2026-09-16, after `review-J3d.md`, verdict FIX-THEN-LAND)

| # | What the review found | What changed |
|---|---|---|
| 1 | `runTabular`'s `sorts` carried a **boolean** where the legacy sends `"asc"`/`"desc"`. DataTables builds its comparator's NAME out of that element (`oSort[sDataType + "-" + aaSort[k][1]]`, datatables.js:4019), so `true` resolves to `oSort["ermine-htmlwriter-true"]` — undefined — and throws a TypeError on the first draw of ANY table with a non-empty `sorts`, `Doc.SalesReport` included. A real runtime break in the one thing the adapter exists for. | `RunTabularArgs.sorts` is now `[number, SortDirection][]` with `SortDirection = "asc" \| "desc"`, and `sortPairs` maps `descending`. `ColumnSort.descending : Bool` is unchanged in Ermine — the translation sits beside `alignmentOf`/`columnTypeOf`. Assertions corrected in `corpus.test.ts` (which had asserted the wrong contract), `widgets.test.ts` and `endtoend.test.ts`; new pin `(w-sorts)` drives both directions through the table AND the drilldown; `(b)` now asserts both directions occur across the corpus **and nothing else does** (`sort directions asc/desc` in its diagnostic). |
| 2 | `props.test.ts` pinned field names and the `CellFormat`/`DocNode` arms, but never the enum VALUES of `ColumnAlign`/`ColumnKind` nor the arms of `Threshold`/`CellCondition` — so a case added in Ermine would pass `check-generated.sh`, `tsc` and that file, then make `alignmentOf` answer `"left"`, `columnTypeOf` answer `undefined` and every `Conditional` take `whenFalse`. | `(p-table)` now pins both enums against the generated zod and drives every member through `alignmentOf`/`columnTypeOf`; the new `(p-condition)` pins the `CellCondition` and `Threshold` arms and their field names, and drives one value of EVERY condition arm through `evalCondition` (asserting it answers a boolean, i.e. does not fall off the switch) and through the generated schema. Both directions, for all four types. |
| 3 | `npm test` was red from a clean checkout: the fixture defaults resolved to `client/target/...` while the README and `check-corpus.sh` use `<repo>/target/...`. The README's own command line gave 30 pass / 3 fail. | Defaults now resolve to `<repo>/target/widget-corpus` and `<repo>/target/sales-report.json` — the paths `check-corpus.sh` writes — so `npm test` after that script needs no environment. A MISSING fixture now SKIPS with the command that would produce it instead of failing, so the README's line is green from a clean checkout at **33 passed / 3 skipped**. README rewritten to say all of that; the gate rows below distinguish the three runs. |
| 4 | `isWireRelation` accepted any `{kind: "inline"\|"deferred", columns: []}`, and `TableColumn` already has a field named `kind` — a J3e chart descriptor was one field name away from being swallowed by `resolveRelations`. | Tightened (the review's preferred option): the whole arm is required — `columns` must hold real column descriptors, and inline needs `rows`+`rowCount`, deferred `token`+`expires`. New pin `(p-relation-guard)`, nine cases. Documented anyway, in the README's "Adding a widget", §3.7e and extension point 4a. |

Optional items also taken: **O1** the drilldown-row comment no longer claims `jsTreeEntry`
emits `ix` (tables.js mints it; the comment said the wrong thing and J3e and the porter would
have read it as the legacy contract); **O2/O5** `legacy.ts`'s header, the README, §3.7e and
open issues 3a/3b now say that `formatted` is NOT byte-comparable with the server's (dates
and `&nbsp;`) and that `(b)`'s `formatted` assertion is a consistency check, not an
independent one; **O4** the dead assertion in `(d-mutation)` replaced with the intended one;
**O6** `legacyFormat`'s alias map is built with `Object.create(null)` so a `__proto__` key is
stored rather than swallowed by the prototype setter (pinned in `(w-legacy-format)`);
**O7** §3.7e now says that HTML escaping moved from the Scala writer to `format.ts` —
the §3.4 trust boundary is unchanged, its enforcement point is not.

Not taken: **O3** (`TestWidgets.mutate` does not descend into arrays, so the Scala
anti-vacuity mutation never reaches inside `columns[]`) — the TypeScript `mutateOnce` does
walk arrays, so the zod side is covered, and J3a's `(r-c)` covers `Validate` generically;
left as a note for whoever touches that generator. **O8** is a porting note for P3: the only
new third-party API in `TestWidgets.scala` that no landed stage already uses is
`Json.jObjectAssocList` (argonaut 6.0+).

Counts after the fixes: Scala **92/92**, TypeScript **36/36** with fixtures (33 + 3 skipped
without), `check-corpus.sh` with no argument exit 0.
