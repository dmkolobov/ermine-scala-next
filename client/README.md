# ermine-report-client

The TypeScript client for Ermine JSON report documents: one zod schema per widget,
generated from the Ermine prop types; a dispatcher that walks the document and
renders it; adapters onto the renderers that already exist in `ermine-writers`; and
two widgets (`scorecard`, `headline`) that are native TypeScript, as the proof that
adding one is cheap.

Stages J3d (`brief-J3d-client.md`: the dispatcher, the tables, the scorecard) and
J3e (`brief-J3e-charts.md`: the charts and the style box) of the JSON Stage 2/3
programme; J3g (`brief-J3g-lift.md`) added the headline, the widget whose Ermine
constructor scans.

## The shape of a response

```
{"version": 1, "settings": {...}, "root": <Layout.Doc.Node>}
```

A `Node` is `Widget | VFlow | HFlow | Grid | Tabbed`; a `Widget` carries a `name`
(the registry key) and `props` (whatever that widget's Ermine `data` type encodes
to). A relation inside props is either

```
{"kind": "inline",   "columns": [...], "rows": [[...]], "rowCount": n}
{"kind": "deferred", "columns": [...], "token": "...", "expires": "..."}
```

and the client resolves a deferred one with `GET <base>/data/<token>`. Columns are
sorted by name and every row array follows that order; a `Long`, `Date`,
`Timestamp` or `GUID` cell is a STRING, `Int`/`Short`/`Byte`/`Double` a number,
`Bool` a boolean, a null cell `null`.

## Install, generate, test

```sh
cd client
npm ci                     # node_modules is gitignored; package-lock.json is not
npm run generate           # src/generated/ from bin/ermine-schema --zod
npm run check-generated    # CI: regenerate into a temp dir and diff
npm run typecheck          # tsc --noEmit, strict
npm run build && node --test "dist/test/*.test.js"
```

That command is green from a clean checkout. Three of the tests need FIXTURES that the
Scala side writes — property (b)'s 200-document corpus, its negative half, and the
end-to-end document — and they SKIP, naming the command that would produce them, when the
fixtures are absent: **33 passed, 3 skipped**. Write the fixtures and all 36 run:

```sh
scripts/check-corpus.sh    # writes both fixtures with sbt, then npm ci + tsc + the suite
```

Fixture locations, all resolved relative to the REPOSITORY root (what `check-corpus.sh`
writes), and each overridable:

| Variable | What | Default |
|---|---|---|
| `ERMINE_CORPUS` | the 200-document corpus of property (b) | `<repo>/target/widget-corpus` |
| `ERMINE_REPORT_DOC` | the end-to-end document | `<repo>/target/sales-report.json` |
| `ERMINE_WRITERS` | the `ermine-writers` checkout, for the legacy `formatDisplay` | the nearest sibling directory of that name |

```sh
client/scripts/check-corpus.sh              # writes the corpus, npm ci, tsc, node --test
client/scripts/check-corpus.sh /tmp/corpus  # reuse an existing corpus
```

The fixtures come from the Scala side:

```sh
sbt -batch 'core/Test/runMain com.clarifi.reporting.WidgetCorpus <dir> 200'
sbt -batch 'core/Test/runMain com.clarifi.reporting.SalesReportDoc <file>'
```

## Using it

```ts
import { parseDocument, render, defaultRegistry, httpFetchData } from "ermine-report-client";

const doc = parseDocument(await (await fetch("/report/Doc.SalesReport", { method: "POST" })).json());
const result = await render(document.getElementById("report")!, doc, defaultRegistry(), {
  document,
  htmlwriter: (window as any).htmlwriter,       // the legacy bundle, for table widgets
  fetchData: httpFetchData("/report", (url) => fetch(url)),
});
result.errors.forEach((e) => console.warn(e.widget, e.path, e.message));
```

`render` never throws on a widget's behalf. An unknown widget name, props the
schema refuses, a deferred token that will not resolve and a renderer that throws
all leave an error box (`div.ermine-widget-error`, `data-widget=<name>`) in the tree
and an entry in `result.errors`.

## The files

| File | What |
|---|---|
| `src/generated/` | zod, written by `scripts/generate.sh` from `bin/ermine-schema --zod`. Never edited. `index.ts` also holds `WIDGET_PROP_SCHEMAS`, the registry name -> schema map. |
| `src/props.ts` | the TypeScript types mirroring the Ermine declarations. Hand-written, because `z.infer` of a recursive generated schema is `any`; `test/props.test.ts` pins them against the generated zod. |
| `src/relation.ts` | the relation wire types, `resolveRelation`, `resolveRelations` (a deep walk, so a widget added later resolves for free) and `httpFetchData`. |
| `src/document.ts` | the envelope schema and `parseDocument` / `safeParseDocument`. |
| `src/format.ts` | the port of `formatDisplay`, total over `CellFormat`. |
| `src/dispatcher.ts` | `render`, the layout containers, the registry lookup, validation, the error box. |
| `src/legacy.ts` | the `htmlwriter` interface, the `table` and `drilldownTable` adapters, and the two legacy format encodings. |
| `src/charts.ts` | the `axisChart`, `pieChart`, `drilldownPieChart`, `drilldownBar` and `styleBox` adapters, the chart-side legacy argument types, `TUPLE_LOSS`, and the date/colour conversions. |
| `src/widgets/scorecard.ts` | the `scorecard` widget, plain DOM: cards from an `Inline` relation. |
| `src/widgets/headline.ts` | the `headline` widget, plain DOM: a title, a scope and three figures. Its props carry NO relation -- the Ermine constructor `headlineOf` scanned one server-side (J3g). |
| `src/index.ts` | the public surface and `defaultRegistry()`. |

## Formatting a cell

`src/format.ts` is a port of `formatDisplay` (`ermine-writers`,
`writers/js/ermine/utils.js` ~291-352) to the OBJECT form of a format. The legacy
function takes a TUPLE (`["Percentage", [places, pad]]`) that drops the colour and
negative-parenthesis flags and collapses `Markdown`, `Conditional`, `ColorFormat`,
`Verbatim` and `Pr2` to a style its table does not have. The object form —
`Layout.Widgets.Format.CellFormat` — keeps all fifteen cases, and on the JSON path
the client is the only thing that can format a cell at all: today `formatted` is
computed in Scala and shipped, and that code is not on the wire.

The ten cases the legacy implements are reproduced exactly, oddities included, and
`test/format.test.ts` checks that against the real legacy function loaded out of the
`ermine-writers` checkout. `Highcharts.numberFormat` is transcribed into
`src/format.ts` and injected into the legacy side as a stub, so the agreement
property covers dispatch and argument plumbing rather than Highcharts' own number
formatting; that transcription is pinned separately.

HTML escaping moved with the formatting. Today the Scala writer's `htmlEval` decides what
is escaped and what is raw; on this path `format.ts` does — `Default` and `Truncate` run the
cell through `string_unhtml` (a detached `<span>`'s `innerHTML`/`textContent`, exactly what
the legacy does), `Verbatim` is the deliberate raw passthrough, and `Color`/`signSpan` mint
spans. The trust boundary is unchanged (the same DB content, the same escape hatch); its
ENFORCEMENT POINT is now the client.

One adapter rule sits on top of the port: a NULL cell displays as `-`
(`HTMLWriter.jsPrimExprTabular`'s null), because server-side a format applied to a
`NullExpr` stays a `NullExpr`, while the JS `formatDisplay` has no null case and
`Round` on a null would read `0.0`. `Constant` is the exception — it ignores its
input.

## Adding a widget

Three edits, plus the generate step.

1. **Ermine.** A new module under `core/src/main/resources/modules/Layout/Widgets/`
   — one module PER WIDGET, because Ermine field selectors are module-global and
   two `data` types in one module may not both declare `columns`. Declare the props
   and a smart constructor:

   ```
   module Layout.Widgets.Sparkline where

   import Json using type Inline
   import Layout.Widgets.Format using type CellFormat
   import Layout.Doc using widget; type Node

   data SparklineProps r = SparklineProps { sparkTitle : String
                                          , sparkValue : String
                                          , sparkPoints : Inline r }

   sparkline : SparklineProps r -> Node
   sparkline p = widget "sparkline" p
   ```

   Then `export Layout.Widgets.Sparkline` from `Layout/Widgets.e`. A relation field
   is `[..r]` when the request may defer it, `Inline r` when the widget cannot work
   without the rows. The row parameter stays FREE: one schema per widget, whatever
   relation it is used with.

   **One shape to avoid.** The dispatcher finds relations STRUCTURALLY: it walks the
   validated props and swaps out anything that looks like a relation arm on the wire.
   `isWireRelation` therefore requires the WHOLE arm — `kind` plus `columns` of real
   column descriptors plus `rows`+`rowCount`, or plus `token`+`expires` — so an
   ordinary props record cannot be mistaken for one (`TableColumn` already has a field
   called `kind`). Do not declare a props record that reproduces a whole relation arm;
   if you ever need to, give the dispatcher an explicit relation path instead of
   widening the test. `(p-relation-guard)` pins the boundary.

2. **Generate.** Add `"Layout.Widgets.Sparkline:SparklineProps:sparkline:SparklinePropsSchema"`
   to the `types` array in `scripts/generate.sh`, add the registry line to
   `WIDGET_PROP_SCHEMAS` in the same script, and run `npm run generate`.

3. **TypeScript.** Mirror the props in `src/props.ts`, write the component
   (`src/widgets/sparkline.ts`) as a `Widget<SparklineProps>`, and add one line to
   `defaultRegistry()` in `src/index.ts`.

A smart constructor may also return `Layout.Fetch.Fetch Node` instead of `Node` and
read the rows it needs while the report is being built (`headlineOf`, stage J3g);
nothing changes on this side, because what reaches the client is still the props
that scan produced.

The dispatcher needs nothing: it looks the schema up by name, validates, resolves
every relation anywhere in the props, and calls `render`.

### Names Stage 3 reserves

`table`, `drilldownTable`, `scorecard`, `headline`, `axisChart`, `pieChart`,
`drilldownPieChart`, `styleBox` and `drilldownBar` are all built and registered.
`treeMap` is **registered as unsupported**: it is the one reserved name with no
renderer behind it at all — `runTreeMap` is undefined in the `ermine-writers`
bundle and the Local branch of `HTMLWriter.treeMap` is `sys.error("todo")` — so it
is deliberately left out of `defaultRegistry()` and a document asking for one gets
the dispatcher's error box naming it. `UNSUPPORTED_WIDGETS` says so in code;
`test/charts.test.ts` `(x-treemap)` pins it.

## Charts and the style box

`src/charts.ts` rebuilds, on the client, the argument objects
`htmlwriter.runTimeSeries`, `runPiechart` / `runPiechartDrilldown`,
`runDrilldownBar` and `runStylebox` are called with today. Three things about
that path are worth knowing before reading it.

**The op-list handles are gone.** `selSeries`, `selCategory`, `selValue`,
`selExtra` and the meta's `colors` are f0 blobs the browser POSTs back to the
server to *fetch* rows. The Ermine prop types replace them with COLUMN NAMES, and
the adapter builds the legacy row shapes from the inline relation:

```
axis series data   [ [value..], [category..], [series..], "#rrggbb"|null, extra… ]
pie relation       [ label, |value|, "#rrggbb"|null, child?, parent? ]
style box          cellCounts, a JSON STRING of [{xPosition, yPosition, <aField>, styleBoxAggFormatted}]
```

Because the data is an array, `withTimeSeriesData` and `withPiechartData` take
their local branches and never post.

**One callback cannot be avoided.** `withStyleBoxData` has no local branch, so
clicking a style-box cell always POSTs `styleBoxData`. The grid itself is built
from `cellCounts`, which the adapter computes, so the widget renders with no
request; `relation` and `legend` go out as `null` and the click-through popup does
not work on this path. Nothing throws — the legacy logs through its own error
callback.

**Chart formats are the LOSSY tuple.** Axes, series, the pie's two formats and
the style box's `aFormat` all read `HTMLWriter.jsLayoutFormat`'s `[name, arg]`
pair, not the object form a table cell carries. `legacyFormatTuple` produces it
and `charts.ts::TUPLE_LOSS` documents the loss per `CellFormat` case: five cases
(`Verbatim`, `Markdown`, `Pr2`, `Conditional`, `Color`) become a name the legacy
`formatDisplay` has no entry for and fall back to `Default` there, and
`Percentage`/`Currency`/`Round`/`IntegralRound` lose their `color` and `negParens`
flags. A chart therefore cannot format as the table beside it does; that is the
legacy's behaviour, reproduced, not a regression. `runStylebox` applies
`formatDisplay` to `aFormat` itself, so it is handed the tuple, never a value.

**Dates.** The chart path wants the legacy `[y, m, d]` triple, and it is built
client-side from the ISO cell, keyed on the relation column's declared type
(`Date`/`Timestamp`), never on the shape of the string.

**One value in a chart row is FORMATTED, not raw: the pie's slice label.**
`RelationRunner.runPieChartData` builds position 0 as
`lc.format.basicEval(labels) extractNullableString ""`, always a String, and
nothing in the browser formats it again — `args.labelFmt` reaches only
`hcutil.pieLegendOptions`, whose merged options end with the pie's own
`labelFormatter` interpolating `this.name` (which is `r[0]`) verbatim. So
`pieRows` applies `pieLabelFormat` with `format.ts` and stringifies, with a null
label becoming `""`. Everything else in a chart row is the raw wire value,
because Highcharts formats it from the tuple.

## Known gaps

- `formatted` is NOT byte-identical to what the server sends today, and is not meant to
  be: a Date or Timestamp cell arrives as its `yyyy-MM-dd` wire string rather than through
  `HTMLRunner.tabularDateFmt`'s `MMM-dd-yyyy`, and `htmlEval`'s fallback branch replaces
  every space with `&nbsp;` while the port (following the JS `formatDisplay`) does not.
  The cell's `format` key IS byte-identical.
- Column GROUPINGS (the legacy `Legend`'s nested header rows) are not reproduced:
  `tableSkeleton` emits one header row, and `args.legend` is `null`. Nothing in the
  local-relation path of `runTabular` reads it.
- `Markdown` formats with its base and passes the result through; rendering markdown
  needs an engine, which is the host page's business.
- There is no converter from the foreign `Layout.Format` to `CellFormat`: the former
  is a Scala ADT with no Ermine eliminator, so it would need a Scala-side fold.
- **The style box's cell-click popup does not work** (`styleBoxData` has no local
  branch, above). The grid does.
- **An axis chart has ONE relation for all its series.** Server-side each
  `ChartSeries` carries its own `Tabular`; here the series share `chartRows` and
  each names its columns inside it. That is a choice, not a typing limit — a
  per-series `seriesRows : [..r]` with `chartSeries : List (ChartSeries r)` is
  typeable and strictly more general (different row SETS over the same columns,
  and a deferred token per series). What no spelling here can express is series
  over relations of different SHAPES, which would need an existential row.
- **Series-level drilldown is not modelled.** `SeriesStructure.Complex`'s `trees`
  is an f0 blob with no JSON equivalent, so `structure` is not emitted and
  `isSeriesLevelDD` is always false — the Simple behaviour.
- **The style box grid is fixed at 3x3** (`gridSize = 3`, `js/ermine/stylebox.js`),
  so `rowLabels`/`columnLabels` want three entries and a position outside `0..2` is
  dropped by the renderer.
