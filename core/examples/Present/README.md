# `core/examples/Present` — layout, charts, writers, validation and the report combinators

Nine self-contained Ermine reports, a shared library of **34 row-polymorphic
presentation helpers** (`Helpers.e`), machine-checked proofs about those
signatures (`Signatures.e`), a measurement module about what a parameterised
report costs the row solver (`ProjectionCost.e`), and seven negative modules
under `shouldfail/`.

They exist because this is the half of Ermine that makes a **document**, and it
was nearly undocumented by example. Before this directory `core/examples` had
three chart uses (`ChartsExample.e`, `GridExample.e`, `PieChartLegendExample.e`),
all over three-column toy relations, and **no example at all** of:

`Layout.Writer` · `Layout.Writer.Profiled` · `Layout.harness` ·
`Layout.Report.Fulcrum.Dynamic` · `Layout.Report.Fulcrum.Legendary` ·
`Layout.Report.StyleGrid` · `Layout.Report.Relation` · `Layout.Report.Atomic`
(beyond one `val`) · `Layout.Report.SelectorMode` · `Layout.Validation` ·
`Layout.Column` / `Column.Unsafe` · `Layout.Magnitude`'s `Area`/`Volume` ·
`Layout.Color` beyond a chart palette · `Layout.Font` · `Layout.BorderOptions` ·
`Layout.SortStrategy` · `Layout.SortPriority` · `Syntax.Selector` ·
`DrilldownList` · `styleBox` · `treemapChart` · `Layout.Scan` ·
`Layout.PresRow` · the whole selector API.

(`Layout.Report.Atomic` and `Layout.Report.Direction` are reached through
`Layout`'s own re-exports, so grepping for their import finds nothing.)

Load the library first — every report imports it:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2" \
      bin/ermine core/examples/Present/Helpers.e \
                 $(ls core/examples/Present/*.e | grep -v 'Helpers\.e')

or, from the REPL, `:load core/examples/Present/Helpers.e`, then the report you
want, then evaluate it by name.

## **`render` does not exist**, and here is what does

`render` is not a term in the stdlib, not a REPL command and not a builtin. A
`Report` is run by a **`Layout.Writer`**, and `Layout/Writer.e` declares the type
`foreign` with **no constructor**: every concrete writer — HTML (remote and
local), JavaFX, JSON (fancy and dense), JsonDebug, CSV, PDF — lives in the
separate `ermine-writers` project, which is not on this build's classpath.

**The missing piece is the writer, and only the writer.** A `Scanner` and a
`Runner` are *not* the obstacle: `Runners.sqlite : String -> Runner DB` takes a
JDBC URL, `jdbc:sqlite::memory:` is one, and the driver is already on
`target/ermine-classpath` — which is how `tracker/tools/sql-render.sh` runs this
group's queries today, against an empty database, because every relation here is
a literal and compiles to a table-value constructor needing no schema. Putting
the CSV or JSON writer's jar and its `modules/` resource root on the classpath
would turn `written` from a type-check into a rendering.

So from `bin/ermine` you can:

* **evaluate a report**, which prints `Report <function>` — it type-checked, and
  its constituent relations resolved;
* **evaluate the relations it draws**, which prints their resolved headers — the
  column set the document will show. That is a real check on the row solver;
* **dump a relation to SQL** with `Scanners.dumpQuery`, which needs no database
  at all. `Present/WriterOutputs.e` does this for five relations in two
  dialects, and `tracker/tools/sql-render.sh` executes the result against
  SQLite. This is the nearest thing to `render` this repository has.

`Present/WriterOutputs.e` documents the writer pipeline in full — the type of
every writer constructor, the four `harness` variants, and the four-line entry
point that every writer in `ermine-writers` shares.

### One REPL trap, if you drive the REPL from a script

`Console.other` decides a typed line is unfinished if it **contains the
substring** `case`, `let` or `where` — not the keyword, the substring — and at
end of input `readLine` returns `null`, which is not `""`, so the "blank line
ends it" escape never fires. **The loop therefore does not terminate**: it
appends five characters per iteration and re-scans the whole string each time.

    printf 'staircase\n' | bin/ermine     # never returns; ~110 `|> ` prompts/s
    printf 'staircas\n'  | bin/ermine     # exits 0, no prompts

Genuine offenders include `showcase`, `staircase`, `complete`, `delete`,
`palette` and `elsewhere`. (`latest` and `casing` are **not** — neither contains
any of the three substrings.) The report in `SortShowcase.e` is called
`sortingReport` for exactly this reason; it was `sortShowcase` until it hung a
session. Interactive sessions are fine — you just press return.

### The one-session recipe, and three names it cannot reach

The command at the top loads all twelve modules into one session and every
report can then be evaluated by name. Three helper bindings are defined in two
modules each and are therefore ambiguous, so evaluating them unqualified answers
`undefined term`: **`shown`** (`ValidationReport`, `SortShowcase`),
**`inRegion`** (`DrilldownExplorer`, `WriterOutputs`) and **`byCategory`**
(`SalesDashboard`, `StyleGridHeatmap`). No report is affected. Field names repeat
freely across modules, which is why a *field-level* session has to be per
module.

## The reports

| file | subject | fact row | what it exercises |
|---|---|---|---|
| `SalesDashboard.e` | a dashboard page, **nine** chart objects | 21 cols | one `chartOf` signature instantiated **five** ways (`bar`, `line`, `stackedBar`, `scatter`, `step`), plus `chartOfAll` for a two-series comparison, a raw `chart_K` for the transformer stack, `bar'` with a `Layout.PresRow` of tooltip-only columns, and `pieOf`; a soft-schema grid whose columns are the data's own quarters, and the SAME grid again through `Layout.Scan`; three KPI tiles **computed** with `scanRelation` rather than typed in |
| `VarianceStyling.e` | budget against actual, conditionally formatted | 18 cols | `Layout.Format`'s `conditional`/`colored`/`alias`/`constant`/`roundParens`; two- and three-band colour rules; a legend built from a row plus a naming function; `Layout.Font` stacks; `Layout.BorderOptions` through `borderSize'`; scale-in-the-relation vs format-in-the-legend; tiles **computed** with `scanRelation` |
| `FulcrumPanel.e` | quarterly grid, two ways | **30 cols** | `Fulcrum.Dynamic` (columns from the data) against `Fulcrum.Legendary` (columns in the source); `pivotColumn`'s rank-2 argument; `MythicalFulcrum` and `(><)`; a `RUnion2` chain four deep |
| `ValidationReport.e` | data quality | 17 cols | `Layout.Validation` on the report's own parameters, with errors accumulated; three relational checks (`outOfRange`, `missingKey`, `unreconciled`) whose failures are themselves reports |
| `DrilldownExplorer.e` | a three-level org tree with controls | 17 cols | `DrilldownList` with three (parent, child) pairs; **every** selector widget; all six `Layout.Report.SelectorMode` constructors written out and matched on; `Syntax.Selector`'s applicative composing four selectors; `drilldownPieChart` and `drilldownBarChart` |
| `WriterOutputs.e` | params → report → document | 15 cols | `written` / `writtenProfiled`; all four `harness` forms; `Layout.Writer`'s functor/ap/monad; `dumpQuery` in two dialects — the only output this build can actually produce |
| `SortShowcase.e` | one table, four orderings | 16 cols | the four different things called a sort — `Relation.Sort`, `SortPriority`, `SortStrategy`, `Ord (Record (\| … \|))` — side by side, plus a hidden sort column, the `Layout.Column` API and `Layout.Column.Unsafe`'s `column#`, the seam to the writer |
| `AtomicAndRelation.e` | the two report models | 18 cols | `Atomic` value reports against relational ones, `scanRelation`/`scan`/`runScan` as the bridge, `formatDate`'s writer callback, and `Layout.Report.Relation`'s "Other" bucketing |
| `StyleGridHeatmap.e` | a risk heat map | 16 cols | `styleBox` — the only combinator that lays out by POSITION; `StyleGrid`; `Layout.Color` in full; `Layout.Magnitude` in all three units plus `Area`/`Volume`; `treemapChart` |
| `ProjectionCost.e` | what a parameterised report costs the solver | — | the measured ladder: N reads of one unannotated record parameter cost **3 / 30 / 207 / 1,230 / 6,783** draws for N = 2…6 (`(5^N − 3·3^N + 2·2^N)/2`, exact) — the group's costliest solve, 34 % of the budget — and **seven exhausts the 20,000-draw budget**; the same reads under one written partition cost **nothing** |
| `Signatures.e` | the proofs | — | `xFull`/`xDeduped`/`xAsWritten` for four helpers plus a full 14-constraint/11-existential `xFull` for `unreconciled`, `xSimple` for two, and the finding that **three** helpers' inferred signatures cannot be written down |

## `Helpers.e` — the library, and the rule it obeys

Thirty-four helpers with explicit signatures and doc comments, grouped as
legends, presentations, sorting, magnitudes, charts, grids, drilldowns,
validation, writers and layout. Every one names only the columns it touches and
carries the rest as a row variable; the partition constraints in the signatures
are what says so.

**The rule**, inherited from `Ai/Common.e` and `Time/Helpers.e`: a
row-polymorphic helper is only useful if its *call sites* check. The Ai README's
cliff — bundling `if`'s `RUnion3` on top of `combine`'s `RUnion2` — does **not**
reproduce at the row-solver defaults adopted at `fe024a7`.
`Layout.Report.Fulcrum.Legendary`'s `snoc_Brace`, which carries an `RUnion2` per
pivot column, is chained four deep in `FulcrumPanel.e` and the whole module
checks in half a second. Numbers in `tracker/loopmodel/E4-EXAMPLES.md`.

**And the harder rule, which `ProjectionCost.e` measures**: write the PARAMETER
row down. `Record.(!)` is a partition, not a lookup, so reading N fields out of
one unannotated record costs FIVE times as much per extra field, exactly
`(5^N − 3·3^N + 2·2^N)/2` draws (**3 / 30 / 207 / 1,230 / 6,783** for two to six,
35,910 at seven) — and seven reads of a bare parameter record exhaust the adopted
draw budget, with no relation, no join and no presentation anywhere near it. One
line of signature takes 1,230 draws to 0.

**And the counter-rule**, which `Signatures.e` proves: write the signature by
hand anyway. `unreconciled`'s inferred constraint set is **eleven existentials
and fourteen constraints**; written by hand it is **one partition**. `chartOf`'s
inferred type knows nothing about rows at all — it would let a caller pass a
series selector for one relation and a value selector for another. The
hand-written signature is where the meaning lives.

## `shouldfail/`

Seven negatives, each with its verbatim diagnostic in its own header:

| module | mistake |
|---|---|
| `fmt01_currency_on_string.e` | a currency format on a `String` column |
| `leg01_legend_column_missing.e` | a legend naming a column the relation has not got |
| `leg02_column_twice.e` | one column on both sides of `withFormats`'s partition |
| `box01_position_in_legend.e` | `styleBox`'s cell-coordinate column also in its legend |
| `box02_treemap_same_measure.e` | a treemap coloured and sized by the same column |
| `chart01_series_not_in_relation.e` | a chart series column dropped by a projection |
| `proj01_seven_reads.e` | seven reads of one unannotated record parameter — the only module in `core/examples` rejected by the **draw budget** rather than by a type error |
