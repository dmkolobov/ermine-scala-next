# Brief: E4 — `core/examples/Present/`: layout, charts, writers, validation and the report combinators

Read `tracker/loopmodel/briefs/brief-E-common.md` FIRST; it carries the conventions, rules, wiring policy and
gates. This file says only what E4 covers. Stage name `E4`; group `core/examples/Present/`, module prefix
`Present.`, helper library `Present/Helpers.e`, report `tracker/loopmodel/E4-EXAMPLES.md`.

WHAT IS UNDER-EXAMPLED HERE. The `Layout.*` family is where a report becomes a document, and most of it has no
example: `Layout.Chart` (bar/line/pie/stacked/time-series/scatter, whichever exist) beyond three uses,
`Layout.Writer` / `Layout.Writer.Profiled` (writing a report out — HTML/CSV/whatever the writers produce; the
production shape is params→report with interactivity in JS widgets, `tracker/JSON-API-DESIGN.md`),
`Layout.StyleGrid`, `Layout.Report.Fulcrum.Dynamic` / `Fulcrum.Legendary` (the wide-table fulcrum reports),
`Layout.Report.Atomic` / `Report.Relation` / `Report.Direction` / `Report.SelectorMode`, `Layout.Validation`,
`Layout.Column` / `Column.Unsafe`, `Layout.Magnitude`, `Layout.Color` / `Font` / `BorderOptions`,
`Layout.SortStrategy` / `SortPriority` (two uses), `Layout.Presentation` / `PresRow` (six), `Layout.Scan`,
`DrilldownList`, `Syntax.Selector`, `Layout.Legend` beyond pinning column order.

READ, beyond the common list: every `Layout/*.e` and `Layout/Report/**.e` module's public signatures; `Layout.e`
itself; `core/examples/ChartsExample.e`, `GridExample.e`, `LayoutTesting.e`, `PieChartLegendExample.e`,
`Ai/IncidentSeverity.e` (legend pinning), `Ai/FiscalCalendar.e` (columns grouped by a tree); `tracker/JSON-API-DESIGN.md`
and `tracker/ROW-CONSTRAINT-STATE.md`'s "production shape" notes (params → report; interactivity lives in
widgets); `tracker/tools/repl-smoke.sh` for how `render` is driven.

## What to build (eight to ten modules plus `Helpers.e`; realistic reports over tables of 15–40 fields)

* `Helpers.e`: generic PRESENTATION helpers with explicit signatures — `withFormats` (apply number/date/currency
  formats to a generic set of measure columns), `withMagnitudes` (`Layout.Magnitude` scaling of a generic
  measure row), `styledBy` (a `StyleGrid`/`Color` rule driven by a generic threshold column), `sortedBy` (a
  generic `SortStrategy` over a key row with priorities), `validated` (`Layout.Validation` checks over a generic
  row: non-null keys, ranges, totals reconciling), `legendFor` (a `Legend` built from a generic category row),
  `chartOf` (a `Layout.Chart` built from a generic key/measure pair), `drilldownOf` (`DrilldownList` over a
  generic parent/child pair), `written` (`Layout.Writer` output of a generic report); two with `xFull`/`xSimple`
  pairs.
* Reports: a dashboard page composing several charts and a keyed grid from one wide fact table; a styled
  variance report (conditional colours and fonts by threshold, borders, magnitudes in thousands/millions); a
  fulcrum report (`Fulcrum.Dynamic`/`Legendary`) over a 30-column table with a pinned legend; a validation
  report that renders the failures of `Layout.Validation` checks as a report of its own; a drilldown-list
  report with three levels and selectors (`Syntax.Selector`, `SelectorMode`); a report written out through
  `Layout.Writer` in each format the writer supports, captured to files under scratch; a sort-strategy
  showcase (the same grid under four strategies); an atomic/relation report pair showing the two report
  models side by side; plus the `Present/shouldfail/` negative (a format applied to a non-numeric column; a
  legend over a missing category) with the expected diagnostics.

The point for users: this is the half of the language that makes a document, and it is nearly undocumented by
example. The point for the corpus: presentation combinators are row-polymorphic too (formats over "the measure
columns, whatever they are"); measure what their call sites cost the solver (G3).
