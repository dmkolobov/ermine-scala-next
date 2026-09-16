# J3e: chart and stylebox adapters on the client scaffolding

Branch `json-charts`, worktree `~/research/ermine/ermine-scala-wt-json-charts`, off
`json-encode` AFTER J3d has landed. Budget 5 h. Read `brief-J-common.md`, `brief-J3d-client.md`
and `report-J3d.md` first; J3d's extension points are binding.

## Build

Ermine prop types in `modules/Layout/Widgets.e` and adapters in `client/src/legacy/` for the
remaining live renderers of design note §4.1: `axisChart` (`runTimeSeries`, series §4.2,
meta §4.3), `pieChart` / `drilldownPieChart` (`runPiechart`), `drilldownBar`
(`runDrilldownBar`), `styleBox` (`runStylebox`), and `treeMap`, which has no JS renderer
(`runTreeMap` is undefined in the bundle): register it so the dispatcher renders an explicit
"unsupported widget" box, and say so.

- Model only the props the JS actually READS (§4.2's "read by JS?" column); the selector
  op-list handles (`selSeries`, `selCategory`, `selValue`, `selExtra`) are server-side f0
  blobs: replace them with column names in the prop types and have the adapter build the
  legacy row shapes from the inline relation (pie: `[label, |value|, cssColor|null, child?,
  parent?]`; axis series `data` rows; stylebox `relation`, `cellCounts` -- note the legacy
  JSON-inside-a-string at `js/ermine/stylebox.js:87`). Where a legacy renderer would POST a
  callback for its data (`relation`, `pieChartData`, `styleBoxData`, §4.5), the adapter must
  supply inline data instead or resolve a deferred relation through J3d's `resolveRelation`;
  list every callback path that cannot be avoided and what the adapter does about it.
- Formats: `CellFormat` via `format.ts`; the lossy tuple form (`jsLayoutFormat`) that chart
  axes read is produced from `CellFormat` by an adapter function whose lossiness is
  documented case by case.
- Dates for axes as the legacy `[y, m, d]` triples, built client-side from the ISO cell.

## Properties

The J3d properties (a), (b), (d), (e) extended to every new prop type (random values ->
documents -> schema-valid -> dispatcher in jsdom with a stub `htmlwriter` recording the
calls -> each call's args satisfy the legacy interface and the invariants you state per
widget, e.g. every series row's category is one of the relation's values; pie values are
absolute; colours are `#RRGGBB` or null). Plus fast-check on the tuple-format adapter.

## Also

Update `client/README.md`, the design note's §3.7e, tick J3e in the plan.
