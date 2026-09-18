module Layout.Widgets where

-- The widget registry of the JSON report client (tracker/JSON-API-DESIGN.md
-- section 4; tracker/json-stage3/brief-J3d-client.md).  Every widget is a `data`
-- type of prop fields plus a smart constructor that wraps it in a Layout.Doc.Node:
--
--   tabular p   ==>   {"tag":"Widget","name":"table","props":{..}}
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
import List using empty_Bracket; cons_Bracket

-- | The registry names Stage 3 reserves.  Every one of them is built except
-- "treeMap", which has no JS renderer at all (`runTreeMap` is undefined in the
-- bundle and the Local branch of HTMLWriter.treeMap is `sys.error("todo")`): it
-- is deliberately left OUT of the client registry, so a document asking for one
-- gets the dispatcher's error box naming it.
widgetNames : List String
widgetNames = ["table", "drilldownTable", "axisChart", "pieChart",
               "drilldownPieChart", "styleBox", "drilldownBar", "treeMap",
               "scorecard", "headline"]
