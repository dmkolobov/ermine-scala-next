module Layout.Widgets where

-- The widget registry of the JSON report client (tracker/JSON-API-DESIGN.md
-- section 4; tracker/json-stage3/brief-J3d-client.md).  Every widget is a `data`
-- type of prop fields plus a smart constructor that wraps it in a Layout.Doc.Node:
--
--   tabular p   ==>   {"tag":"Widget","name":"table","props":{..}}
--
-- The registry NAME is a value beside the props, `tableName : WidgetName (TableProps r)`,
-- and `widget tableName p` is the only way a smart constructor spells it: the
-- phantom parameter ties the string to the props type, so a name applied to the
-- wrong props is a type error here rather than an error box in the browser
-- (`Layout.Doc.WidgetName`; `rawWidget` is the untyped escape hatch).
--
-- The props go out through the GENERIC walker (Json.toJson), so the record-style
-- declarations ARE the wire, and
--
--   bin/ermine-schema --zod -i Layout.Widgets.Table TableProps
--
-- is the zod the TypeScript dispatcher validates them with (the row parameter is
-- left abstract: one schema per widget, whatever relation it is used with).
--
-- ONE MODULE PER WIDGET.  Ermine field selectors are module-global -- two data
-- types in one module may not both declare `columns` -- so each widget's props
-- live in their own module under Layout/Widgets/ and this module re-exports them.
-- J3e's chart widgets should each get a module here too.
--
-- TWO SHAPES.  A widget whose props the caller already holds is one record and
-- one smart constructor (`tabular`, `scorecard`, ...).  A widget that has to
-- READ ROWS to work its props out is two records and a function between them:
-- the wire props, plus a SOURCE record of the fields and the relation the
-- constructor scans, plus `...Of : ...Source -> Fetch Node`
-- (`Layout.Widgets.Headline`, `Layout.Widgets.Crosstab`; design note 3.4c).
-- The source is server-side by design: no registry, no schema, nothing of it on
-- the wire.  Because this module re-exports everything, a field name two widget
-- modules both want has to be prefixed (`headlineTitle`, `crosstabRowLabels`).

export Layout.Widgets.Format
export Layout.Widgets.Table
export Layout.Widgets.Drilldown
export Layout.Widgets.Scorecard
export Layout.Widgets.Chart
export Layout.Widgets.AxisChart
export Layout.Widgets.PieChart
export Layout.Widgets.StyleBox
export Layout.Widgets.DrilldownBar
export Layout.Widgets.Headline
export Layout.Widgets.Crosstab
export Layout.Widgets.Text
-- Layout.Widgets.Heading (Q25, 2026-09-23) is a typed widget module too, with
-- generated zod, but it is NOT re-exported here: its `title`, `sortColumn` and
-- `total` are the names core/src/test/resources/doc/Sales.e has always put on
-- the wire, and Scorecard, Table's ColumnSort and Headline own those field
-- names already.  MEASURED by the Q25 review: exporting it gives no clash
-- error -- the umbrella loads and `title` SILENTLY resolves to HeadingProps,
-- breaking every importer's Scorecard/Table code.  Import it by name.
import List using empty_Bracket; cons_Bracket

-- | The registry names Stage 3 reserves.  Every one of them is built except
-- "treeMap", which has no JS renderer at all (`runTreeMap` is undefined in the
-- bundle and the Local branch of HTMLWriter.treeMap is `sys.error("todo")`): it
-- is deliberately left OUT of the client registry, so a document asking for one
-- gets the dispatcher's error box naming it.
widgetNames : List String
widgetNames = ["table", "drilldownTable", "axisChart", "pieChart",
               "drilldownPieChart", "styleBox", "drilldownBar", "treeMap",
               "scorecard", "headline", "crosstab", "heading", "text"]
