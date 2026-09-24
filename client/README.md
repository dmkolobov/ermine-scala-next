# ermine-report-client

The TypeScript client for Ermine JSON report documents: one zod schema per widget,
generated from the Ermine prop types; a dispatcher that walks the document and
renders it; adapters onto the renderers that already exist in `ermine-writers`; and
three widgets (`scorecard`, `headline`, `crosstab`) that are native TypeScript, as the
proof that adding one is cheap.

Stages J3d (`brief-J3d-client.md`: the dispatcher, the tables, the scorecard) and
J3e (`brief-J3e-charts.md`: the charts and the style box) of the JSON Stage 2/3
programme; J3g (`brief-J3g-lift.md`) added the headline, the widget whose Ermine
constructor scans, and J3i (`brief-J3i-crosstab.md`) the crosstab, the widget a
query cannot produce at all.

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

**One prerequisite that is not optional**: the suite needs a sibling `../ermine-writers`
checkout, or `ERMINE_WRITERS` pointing at one. `(c-legacy)` compares this port against the
real `formatDisplay` and **hard-fails** without it (`test/format.test.ts:67-70` calls
`assert.fail`, not `t.skip`, unlike the four chart tests beside it, which do skip). That
is long-standing, not new.

With that checkout present, the command above is green. Eight of the tests skip, each
naming what would make it run: three need FIXTURES the Scala side writes — property (b)'s
200-document corpus, its negative half, and the end-to-end document — and five need the
browser bundle, which `npm run bundle` builds. That was **90 tests, 82 passed, 8 skipped** before WP-10 S1 added `test/page.test.ts` (100 tests: 97 passed, 3 skipped after S1; **112 tests: 109 passed, 3 skipped after WP-10 S2**; **114 tests: 111 passed, 3 skipped after WP-10 S3**; **115 tests: 112 passed, 3 skipped after WP-11**, with the bundle built, MEASURED 2026-09-23)
(MEASURED 2026-09-21 on node v24.20.0; the count this paragraph carried before WP-9 was
33/3 and was stale by 29 passing tests). `npm run test:bundle` builds the bundle first and
gives 87 passed, 3 skipped; writing the fixtures as well runs all 90:

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
  htmlwriter: (window as any).ermine_htmlwriter, // the legacy bundle, for table widgets
  fetchData: httpFetchData("/report", (url) => fetch(url)),
});
result.errors.forEach((e) => console.warn(e.widget, e.path, e.message));
```

The legacy global is **`window.ermine_htmlwriter`** — not `window.htmlwriter`, which this
README and `src/index.ts` both said until WP-9 — and it is assigned **only inside a
`DOMContentLoaded` listener** (`ermine-writers/writers/js/htmlwriter.js:10-13`). A page
that reads it at script-evaluation time gets `undefined`, and a `table` or a chart then
shows the "this widget needs the legacy renderers" error box rather than anything that
looks like a timing problem, so **wait for the event before calling `render`**.
`window.ermine_htmlwriter_conf` is set at module top level and is a red herring for a
readiness probe. Nothing in this package reads a global: `render` takes the writer
through `env.htmlwriter` and the host decides where it came from.

`render` never throws on a widget's behalf. An unknown widget name, props the
schema refuses, a deferred token that will not resolve and a renderer that throws
all leave an error box (`div.ermine-widget-error`, `data-widget=<name>`) in the tree
and an entry in `result.errors`.

## The browser bundle

```sh
npm run bundle          # tsc, then webpack -> dist/browser/
npm run bundle:watch    # tsc --watch AND webpack --watch together, writing to disk
npm run test:bundle     # build the bundle, then the whole suite including test/bundle.test.ts
```

`bundle:watch` is `node scripts/bundle-watch.js`: one full `tsc` build first (a type error
aborts there), then both watchers, with Ctrl-C stopping the pair. It has to drive both
because **webpack watches `dist/src/`, not the sources** — a bare `webpack --watch` rebuilds
nothing when you edit a `.ts` file, and fails outright from a clean checkout with
`Module not found: Can't resolve './dist/src/index.js'`. That is the cost of the tsc-first
decision below, and it is paid once, in that script, rather than by everyone who forgets.

**With the preview panel open** (extension 0.1.13, WP-10 S3) the extension watches
`dist/browser/*.js`: one build (four files, two of them `.js`) is ONE reload of the page,
about 250 ms after its last write, with a *"the client bundle changed; reloading"* banner
in between; deleting the bundle FILES shows the panel's *not built* page and the next build
brings the page back. Deleting the FOLDER (`rm -rf dist/browser`) probably does NOT: the vendored
typings say a deleted watched path makes the watcher *"suspend and not report any events until the
path is created again"* and that a folder delete may fold into one event for the folder
(`editor/vscode/node_modules/@types/vscode/index.d.ts:13977-13979`, `:13996-14001`); the page stays
up until the next build or the next explicit preview command re-checks. Playtest E8 records which. The page's `fetchData` REJECTS (the preview only ever asks for inline
relations, and the page's CSP has no `connect-src`), so a document with a deferred relation
draws that widget's own error box and fetches nothing — `(pg-fetch-deferred-box)`.

**The writers in the panel** (extension 0.1.14, WP-11): the page loads the writers bundle
FIRST (`htmlwriter.js` from `ermine.preview.writersPath`, default the sibling
`../ermine-writers/writers/html/src/main/resources/web`), then this package's two entries,
with `common.css`, `htmlwriter.css` and `htmlwriter_classic.css`. `src/host/page.ts` was NOT
changed: it already posts `ready` from a `DOMContentLoaded` listener registered by the host
script (so after the writers' own listener, registered by the earlier script) and reads
`window.ermine_htmlwriter` at RENDER time. `(pg-writers-global)` pins both with the REAL
client in a JSDOM: a stub writers listener registered first has run before `ready`, `table`
reaches `runTabular` of the global, and without the global `table` is its own error box under
the extension's writers banner (the reducer's `error` kind, so the document is dimmed).
Whether the real bundle does this in a webview is the playtest's (E9).

**`gate_client`** (`scripts/gates.sh`, nightly tier since WP-10 S3) runs `npm test` here and
prints one `SUMMARY <n> tests, <p> pass, <f> fail, <s> skipped` line. Without
`node_modules` it is UNAVAILABLE (exit 3), not FAIL; a skip is counted, a failure fails it.

Two entries, no loaders (WP-9):

| Output | Global it defines | What it is |
|---|---|---|
| `dist/browser/ermine-client.js` (+ `.map`) | `window.ErmineClient` | this package's whole public surface — `parseDocument`, `render`, `defaultRegistry`, everything `src/index.ts` exports |
| `dist/browser/ermine-host.js` (+ `.map`) | `window.ErmineHost` | since WP-10 S2 the panel PAGE (`src/host/page.ts`): it calls `acquireVsCodeApi()` once, posts `ready`, folds each snapshot envelope and draws through `window.ErmineClient`; it re-exports the presentation reducer (`applyMessage`, `presentation`, `initialHostState`, ...). A SECOND entry because a webview page under `script-src ${cspSource}` with no nonce may carry no inline `<script>` at all |

**`devtool` is `'source-map'`, and that is load-bearing.** `mode: 'development'`
defaults to `devtool: 'eval'`, which wraps every module in an `eval("…")` call; a VS Code
webview CSP without `'unsafe-eval'` blocks all of them and the bundle silently never
initialises. `test/bundle.test.ts` `(b-no-eval)` asserts the static half of that — no
`eval(` and no `new Function` in either output — and `(b-sourcemap)` asserts the map is a
separate file rather than an inline `data:` URI. Nothing here has run in a browser or a
webview.

**Webpack's input is the `tsc` output**, `dist/src/*.js`, not the TypeScript sources, so
`bundle` is `npm run build && webpack` and the dependency closure is `webpack` +
`webpack-cli` and nothing else — which is what a closed-network machine has to carry.
Source-map frames are therefore `.js` (tsconfig has `sourceMap: false`); switching to
`ts-loader` for `.ts` frames is four commented lines in `webpack.config.js` plus one
devDependency.

**`mode` is `development` only.** Nothing is minified. Whether a `production` build is
ever wanted is not decided and is not WP-9's: the panel loads the bundle from the
developer's own workspace, so bytes buy nothing, and minified frames would make WP-10's
error boxes harder to read.

**The output is not committed.** `client/dist/` is gitignored, so a fresh clone has no
bundle and `test/bundle.test.ts` skips, naming `npm run bundle`. Whether the built bundle
should be committed instead is open, and belongs to WP-17 (closed-environment packaging).

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
| `src/widgets/crosstab.ts` | the `crosstab` widget, plain DOM: a `<table>` of row labels x column labels with totals. Its props carry a MATRIX, not a relation -- `crosstabOf` scanned one server-side and the column set IS the data (J3i) -- so it does not go through the table adapter. A `null` cell is a pair no row had and shows as an em dash. |
| `src/index.ts` | the public surface and `defaultRegistry()`. |
| `src/host/` | the preview panel's PRESENTATION reducer — `applyMessage`, `presentation`, `initialHostState` — bundled as `ermine-host.js`. It decides what the panel SHOWS and nothing else: every decision (is this answer current, should we re-render, did the wedge clear) stays in the extension's `preview-core.js`, so the two reducers cannot disagree. `page.ts` (WP-10) is the webview page built on it: the snapshot fold, `pageStep` (delivery only: snapshot envelopes, a rising `seq`, re-render only when the document changed) and `boot`, the DOM. |

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

**The principle (Q25, decided by the user 2026-09-23: *"I'm pretty sure I want
typed widget schemas in the typescript rather than matching runtime ermine values
fallibly"*): a widget's props are validated by the zod GENERATED from its
`Layout.Widgets.*` module, or the widget does not exist.** There is no
hand-written schema path: `Widget` has no `schema` field, the dispatcher looks the
name up in the generated `WIDGET_PROP_SCHEMAS` only, and a registered name without
an entry there draws an error box. `test/widgets.test.ts` `(w-generated-only)` pins
that the registry's names are exactly the generated ones and that no renderer
carries a schema of its own. A report that hands a widget a bare runtime value --
`rawWidget` over a report-local record, a bare string, a bare relation -- gets an
error box, by design.

Three edits, plus the generate step.

1. **Ermine.** A new module under `core/src/main/resources/modules/Layout/Widgets/`
   — one module PER WIDGET, because Ermine field selectors are module-global and
   two `data` types in one module may not both declare `columns`. Declare the props
   and a smart constructor:

   ```
   module Layout.Widgets.Sparkline where

   import Json using type Inline
   import Layout.Widgets.Format using type CellFormat
   import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}

   data SparklineProps r = SparklineProps { sparkTitle : String
                                          , sparkValue : String
                                          , sparkPoints : Inline r }

   sparklineName : WidgetName (SparklineProps r)   -- the registry name, tied to the props type
   sparklineName = WidgetName "sparkline"

   sparkline : SparklineProps r -> Node
   sparkline p = widget sparklineName p
   ```

   `WidgetName p` is a phantom type: `widget sparklineName x` type-checks only when `x`
   is a `SparklineProps`, so the string and the type cannot drift apart in Ermine. The
   untyped `rawWidget "name" x` remains for tests and for a name the registry does not
   know yet; the client validates either the same way -- against the GENERATED
   schema of that name, so a `rawWidget` whose value does not have the typed shape
   is an error box.

   Then `export Layout.Widgets.Sparkline` from `Layout/Widgets.e` (unless a field
   name is one another widget module already owns: `Layout.Widgets.Heading` is
   not re-exported for that reason -- through the umbrella its `title` would
   silently shadow Scorecard's -- and is imported by name) and add its name to
   `widgetNames` there. A relation field
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

**A widget whose constructor scans** is two records and a function between them
(stages J3g, J3i). The props above are the wire half; beside them the Ermine module
declares a SOURCE record -- the fields and the relation the constructor needs -- and

```
crosstabOf : (Relational rel, r <- (h1, h2, h3, t))
          => CrosstabSource h1 h2 h3 rel r -> Fetch Node
```

reads the rows while the report is being built and returns the props wrapped in a
`Node`. Nothing changes on this side: the source record is server-side by design, no
registry or schema knows it, and what reaches the client is still the props the scan
produced. It is what a widget whose SHAPE is in the data needs -- `crosstab`'s columns
are the distinct values of a data column, which no query can name in advance.

One naming rule follows from the Ermine side: field selectors are global and
`Layout/Widgets.e` re-exports every widget module into one scope, so a field name two
widget modules both want has to be prefixed (`headlineTitle` because the scorecard owns
`title`, `crosstabRowLabels` because the style box owns `rowLabels`). The generated zod
and `src/props.ts` carry whatever Ermine settled on.

The dispatcher needs nothing: it looks the schema up by name, validates, resolves
every relation anywhere in the props, and calls `render`.

### Names Stage 3 reserves

`table`, `drilldownTable`, `scorecard`, `headline`, `crosstab`, `axisChart`,
`pieChart`, `drilldownPieChart`, `styleBox` and `drilldownBar` are all built and
registered.
`treeMap` is **registered as unsupported**: it is the one reserved name with no
renderer behind it at all — `runTreeMap` is undefined in the `ermine-writers`
bundle and the Local branch of `HTMLWriter.treeMap` is `sys.error("todo")` — so it
is deliberately left out of `defaultRegistry()` and a document asking for one gets
the dispatcher's error box naming it. `UNSUPPORTED_WIDGETS` says so in code;
`test/charts.test.ts` `(x-treemap)` pins it.

`heading` and `text` are registered too, and since Q25 (2026-09-23) they are typed
like the rest: `Layout.Widgets.Heading` (`HeadingProps {title, sortColumn, matched,
total}`, constructor `heading`) and `Layout.Widgets.Text` (`TextProps {body}`,
constructor `plainText`), each with a `generate.sh` entry and generated zod
(`src/generated/heading.ts`, `text.ts`). Q24 (d) had first registered them with
hand-written schemas through a `Widget.schema` override; Q25 deleted that override
and the `(w-own-schema)` allowance with it. The client's `text` is PLAIN text:
the Ermine-side `Layout.Report.text` (a legacy Report builder, not a registry name)
means markdown, which is why the typed constructor is `plainText` and its field is
`body`.

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
