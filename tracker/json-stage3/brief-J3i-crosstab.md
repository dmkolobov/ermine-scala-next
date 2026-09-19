# J3i: the crosstab widget, and the Fetch widget shape (source record -> props record)

Branch `json-crosstab`, worktree `~/research/ermine/ermine-scala-wt-json-unify`, off `json-encode`
(the orchestrator names the base commit). Budget 6 h. Read `brief-J-common.md`, `brief-J3g-lift.md`,
`report-J3g.md`, `review-J3g.md`, design note §3.4b (with its 2026-09-18 correction) and §3.4c,
`modules/Layout/Fetch.e`, `modules/Layout/Widgets/Headline.e`, `modules/Layout/Widgets/Table.e`,
`modules/Field.e`, `core/src/test/resources/doc/Fetch*.e`, `client/README.md` "Adding a widget",
`client/src/widgets/headline.ts`, and the (fxl-headline) property in `TestRunner.scala`.

## Why

Two findings by the user after J3g landed:

1. `headlineOf` is the only widget constructor in the `Fetch` shape, and it looks nothing like the
   others: positional arguments instead of a props record, and nothing of it in any registry. The
   shape it should have is TWO records -- the WIRE PROPS (registered, schema-checked, rendered) and
   the SOURCE (what the constructor needs to compute them: fields and a relation; server-side, never
   on the wire) -- and one function from the source to `Fetch Node`.
2. Running totals and ranks are `Relation.Windowed`'s job (window functions in SQL), so J3g's
   headline is a weak reason to scan. The crosstab is the strong one: a table's row type is fixed at
   compile time, so a table whose COLUMNS are the distinct values of a data column cannot come from
   a query. Its shape is data. (It therefore cannot reuse the table renderer either: the wire carries
   a matrix, not a relation.)

## Build

### 1. `Layout.Widgets.Crosstab` (new module, one module per widget)

Wire props (registered name `"crosstab"`; add it to `widgetNames` in `Layout/Widgets.e`):

```
data CrosstabProps = CrosstabProps { crosstabTitle : String
                                   , rowHeader     : String         -- what the row keys are
                                   , colHeader     : String         -- what the column keys are
                                   , rowLabels     : List String    -- sorted, distinct
                                   , colLabels     : List String    -- sorted, distinct
                                   , cells         : List (List (Maybe Double))  -- rowLabels x colLabels; Nothing = no rows
                                   , crosstabFormat : CellFormat }
crosstab : CrosstabProps -> Node
```

Check every field name against the global selectors with `bin/ermine :load` (`columns`, `rows`,
`title`, `count`, `descending`, `format` are known to be taken; rename rather than fight). Confirm
what the generic encoder and the zod exporter do with `Maybe Double` INSIDE a list (the encoder's
Maybe-omission rule is for a named FIELD; an element should encode as `null`); pin the wire
spelling in `TestWidgets` as (a-pin) does for the scorecard. Optional but welcome: `rowTotals`,
`colTotals`, `grandTotal` as `Maybe`-free `List Double`/`Double` fields, since the rows are in hand.

Source record and the scanning constructor:

```
data CrosstabSource h1 h2 h3 rel r =
  CrosstabSource { sourceTitle : String, rowKeyHeader : String, colKeyHeader : String
                 , rowKey  : Field h1 String
                 , colKey  : Field h2 String
                 , measure : Field h3 Double
                 , source  : rel r }
crosstabOf : (Relational rel, r <- (h1, h2, h3, t)) => CrosstabSource h1 h2 h3 rel r -> Fetch Node
```

`crosstabOf` scans `source` (no order needed), sums `measure` per (row key, column key), sorts the
distinct keys, and emits `crosstab` with a `Nothing` cell wherever no row had that pair. Keys are
`String`: a caller with an `Int` or `Date` key projects it first; say so in the module comment.
If a higher-kinded `rel` in a data field does not kind-check, fall back to `source : [..r]` and
explain in the report; if `r <- (h1, h2, h3, t)` needs a different spelling, find it with `:load`
and explain. The format is the caller's (`crosstabFormat` in the source, or `Default` -- your call).

### 2. Headline in the same shape

Refactor `headlineOf` to take a `HeadlineSource h rel r` record (`sourceTitle`, `scope`,
`measure : Field h Double`, `source : rel r`) so both Fetch widgets read alike. Update
`FetchHeadline.e`, `FetchFragments.e`, and (fxl-headline). Keep the pure `headline` and its props
unchanged (the wire does not move).

### 3. Client, the three-edit recipe

`Layout.Widgets.Crosstab:CrosstabProps:crosstab:CrosstabPropsSchema` in `client/scripts/generate.sh`
plus the `WIDGET_PROP_SCHEMAS` line; `npm run generate`; the props interface in `src/props.ts`;
`src/widgets/crosstab.ts` (plain DOM: a `<table>` with the column labels as the header row, the row
labels as the first column, `rowHeader`/`colHeader` as captions, each cell through `format.ts` with
`crosstabFormat`, an em dash for `null`, the same as `scorecard.ts`/`headline.ts` do); one line in
`defaultRegistry()`; `(w-crosstab)` in `client/test/widgets.test.ts` and `(p-crosstab)` in
`props.test.ts`; `check-generated.sh` green.

### 4. Example

`core/src/test/resources/doc/FetchCrosstab.e`: `sales` from `FetchData` as regions x days with the
amount summed, a parameter choosing `amount` or `units` as the measure, composed with `vflowF`
beside a `headlineOf` over the same relation (two Fetch widgets in one layout). Add the crosstab as
a fourth fragment of `FetchFragments.e` if it fits in a line or two; otherwise leave it.

## Properties

- `TestRunner (fxc-1)`: over random literal relations with random row/column keys (draw the keys
  from small alphabets so collisions and gaps both occur) and random measures, the rendered
  crosstab's `rowLabels`/`colLabels` are the sorted distinct keys, every cell equals the sum
  computed in Scala from the generated rows, and a pair with no row is `null`. Anti-vacuity: print
  once, and assert, that at least N cases have a gap AND at least N have a collision (two rows on
  one pair); the empty relation yields two empty label lists and an empty matrix.
- `TestWidgets`: the crosstab in the widget pool, so (a)/(a-cov) generate, mutate and validate it;
  an (a-pin) for its wire spelling including a `null` cell.
- Client: `(w-crosstab)` renders a 2x3 matrix with one null and asserts the header row, the row
  labels, the formatted cells and the em dash.
- (fxl-headline) and (fx1)/(fx5) stay green after the `HeadlineSource` refactor.
- The pr-tier sweep `TestTolerantCheck` 6.2c keeps a catalogue `knownHeadDisagreements` of local
  binding heads; a new stdlib module with a local `let`/`where` head under a row constraint can
  move it (J3g's Headline.e:63:9 did, commit 58c52fbb). Run `sbt -batch 'core/testOnly
  *TestTolerantCheck'` ONCE at the end; if it names a `Crosstab.e`/`Headline.e` location, add it to
  the catalogue with a one-line comment as 58c52fbb did, and re-run that suite once.

## Gates

`scripts/gate.sh run commit` in the worktree; `sbt -batch 'core/testOnly *TestRunner *TestWidgets
*TestDoc *TestJson *TestSchema'`; `TestTolerantCheck` as above; `cd client && npm test && npm run
check-generated` (node_modules is already installed here). No full `core/test`.

## Docs

Design note: §3.4c gains a short "The Fetch widget shape" paragraph (source record -> `...Of` ->
props record; the source is server-side by design and no registry knows it; the crosstab as the
case a query cannot cover). `client/README.md`: crosstab in the files table and the reserved
names; "Adding a widget" gains the two-record shape for a widget whose constructor scans. Plan:
J3i row and handoff entry. `Layout/Widgets.e` header: one sentence on the two shapes.

## Report

`tracker/json-stage3/report-J3i.md`, the shape `brief-J-common.md` asks for. Do not commit.
