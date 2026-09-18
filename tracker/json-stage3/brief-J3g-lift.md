# J3g: widgets and layouts in `Fetch`; `Fetch Node` as THE report type (Change A)

Branch `json-unify`, worktree `~/research/ermine/ermine-scala-wt-json-unify`, off `json-encode`
babac791. Budget 6 h. Read `brief-J-common.md`, design note §3.4b, `modules/Layout/Fetch.e`,
`json/Runner.scala` (`render`, `build`, `renderFetch`, `interpret`, `evalStep`), the four
`core/src/test/resources/doc/Fetch*.e` examples, `TestRunner.scala` section (fx), and
`client/README.md` "Adding a widget". J3f's decisions (design note §3.4b table) stand: `Fetch` is a
separate CPS type, NOT a `Node` constructor, and there is NO `Monad` instance.

## Why

Today a scan must be hoisted above its layout (`scanRelation r (rows -> done (vflow [..]))`) and
no widget's smart constructor can scan, because every layout combinator takes `Node` and every
widget returns `Node`. The user wants to write a report as one `Fetch Node`, cut pieces of it out
into functions of type `... -> Fetch Node` (server-side fragments), and turn a fragment into a
client-rendered widget only when its DOM needs a new renderer. `Fetch` is not an arbitrary effect
(one operation: scan a plan in an order), so nothing stops widgets from living in it.

## Build

### 1. Lifts in `modules/Layout/Fetch.e` (plain functions, no instance)

- `map_Fetch : (a -> b) -> Fetch a -> Fetch b`
- `bind_Fetch : Fetch a -> (a -> Fetch b) -> Fetch b`
- `sequence_Fetch : List (Fetch a) -> Fetch (List a)` (left to right; the scans happen in list
  order, which the interpreter property below pins)
- lifted layouts over `Fetch Node`, in `Layout.Fetch` (it imports `Layout.Doc`; `Doc` must not
  import `Fetch`): `vflowF : List (Fetch Node) -> Fetch Node`, `hflowF`, `gridF : List (List
  (Fetch Node)) -> Fetch Node`, `tabbedF : List (String, Fetch Node) -> Fetch Node`.
  Names are yours if these clash (check with `bin/ermine :load`; recall that a top-level name may
  not shadow a global field selector), but keep the `_Fetch` / `F` pattern consistent.
- Rewrite the header comment of `Fetch.e`: the "a scan cannot sit inside a vflow: hoist it"
  paragraph is no longer true.

### 2. `Fetch Node` is the report type; `Params -> Node` is sugar (`json/Runner.scala`)

- A report is `Params -> Fetch Node`. A report typed `Params -> Node` is still accepted and is
  treated as `done` of its value. `resultKind` may stay as the classifier, but `render` must be
  ONE path: drop the `fetching` flag on `Report` and the `build`+`write` branch.
- Keep the ordering guarantee of the pure path and extend it to fetching reports: the FIRST
  evaluation step (decode, apply the report, force to `Done`/`Scan`) runs under `evalLock`
  BEFORE `cfg.run.run` opens a connection. Only if that step is a `Scan` does the connection open
  and `interpret` continue inside it. A report whose evaluation fails therefore opens no
  connection, pure or fetching; update the doc comment of `renderFetch` ("has opened a
  connection for nothing") and design note §3.4b's "Cost" line accordingly.
- Error texts for existing failure cases stay as they are (the (b3) refusal text, the "scan n
  failed" 500, the "cannot be encoded" 500); list in the report any message you change.

### 3. A widget whose constructor scans: `Layout.Widgets.Headline`

New module `modules/Layout/Widgets/Headline.e` (one module per widget), exported from
`Layout/Widgets.e`, registry name `"headline"`, added to `widgetNames`:

```
data HeadlineProps = HeadlineProps { title : String, scope : String
                                   , rowCount : Int, total : Double, largest : Double
                                   , headlineFormat : CellFormat }
headline : HeadlineProps -> Node                                 -- pure, for a caller with the numbers
headlineOf : String -> String -> Field r Double -> rel r -> Fetch Node   -- scans `rel`, counts, sums,
                                                                          -- takes the max of the field
```

(`Relational rel =>`; spell the field argument the way the stdlib does, e.g. `sumBy`'s. If a
field selector name clashes, rename the prop, not the widget.) `headlineOf` is the demonstration
that a widget definition can incorporate `Fetch`: it is the thing `FetchHeadline.e` builds by
hand today with the ad hoc `widget "headline"`.

Client side, the three-edit recipe of `client/README.md`: `Layout.Widgets.Headline:HeadlineProps`
in `client/scripts/generate.sh` (+ the `WIDGET_PROP_SCHEMAS` line), `npm run generate`, the props
interface in `src/props.ts`, `src/widgets/headline.ts` (plain DOM: a title, the scope, and three
formatted figures; format the total and the largest with `headlineFormat` through `format.ts`),
one line in `defaultRegistry()`. `check-generated.sh` must pass.

### 4. Examples: the decomposition story

- `core/src/test/resources/doc/FetchHeadline.e`: use `headlineOf` and `vflowF`; the ad hoc
  `widget "headline"` and `widget "text"` go (a "text" widget is not in the registry).
- New `core/src/test/resources/doc/FetchFragments.e`: ONE report assembled from at least three
  fragments of type `... -> Fetch Node` (e.g. the headline over a region, the running-total table
  of `FetchRunning`, the top-N pie of `FetchTopN`), composed with `vflowF`/`tabbedF`/`sequence_Fetch`,
  each fragment scanning on its own. Its point is that the fragments are ordinary functions and
  the report is their composition; say so in its header comment.
- `FetchTopN.e`'s `widget "metTargets"` may stay (it is a pin that an unregistered name goes on
  the wire) or become a headline; your call, state it.

## Properties (`TestRunner.scala`, section (fx); `TestWidgets.scala` for the headline)

Random over declarations and values, per `brief-J-common.md`; generated Ermine source loaded as
a module.

- (fxl-order) a random tree of `sequence_Fetch`/`vflowF`/`bind_Fetch` over N leaf scans of random
  literal relations renders, and the scans run in left-to-right order: observe the order through
  the rows the continuations receive (e.g. each leaf tags its rows with its index into a table)
  and through the runner's log or a counting `Scanner`. State how the property cannot pass
  vacuously (N ≥ 2 in most cases; print the distribution once).
- (fxl-laws) `map_Fetch f (done a)` renders the same document as `done (f a)`; `bind_Fetch (done a) k`
  the same as `k a`; `bind_Fetch m done` the same as `m`; all as byte-equal responses over random
  fetching reports.
- (fxl-sugar) a random pure report `Params -> Node` (reuse `TestWidgets`' document generator)
  and the same body wrapped in `done` as `Params -> Fetch Node` render byte-identical responses,
  including the deferred arm (the tokens differ; compare after resolving them or after masking).
- (fxl-conn) a report whose evaluation fails (pure AND fetching) opens NO connection; a fetching
  report that scans opens exactly one. Extend (fx-conn).
- (fxl-headline) `headlineOf` over a random literal relation: `rowCount`, `total`, `largest` equal
  the values computed in Scala from the generated rows; the client component renders them
  (`client/test/widgets.test.ts` in jsdom, as the scorecard is tested).
- The existing (fx1)-(fx4), (fx-conn), (fx-err) and (b3) stay green; (fx1) changes with
  `FetchHeadline.e` -- update it, do not delete it.

## Gates

`scripts/gate.sh run commit` in your worktree (compile, corpus, lsp; content-keyed; never re-run
the same content), plus your suites: `sbt -batch 'core/testOnly *TestRunner *TestWidgets
*TestDoc *TestJson *TestSchema'`, and `cd client && npm ci && npm test && npm run check-generated`.
Record every number with the log path. No full `core/test`.

## Docs

Design note: a short §3.4c "Fetch as the report type" with a decisions table (lifts, first step
outside the connection, headline widget, what stays sugar). Plan: J3g row and a handoff-log
entry. `client/README.md`: the headline in the widget table; "Adding a widget" gains one sentence
on a constructor that returns `Fetch Node`. `Fetch.e` header rewritten (above).

## Report

`tracker/json-stage3/report-J3g.md`, the shape `brief-J-common.md` asks for. Do not commit.
