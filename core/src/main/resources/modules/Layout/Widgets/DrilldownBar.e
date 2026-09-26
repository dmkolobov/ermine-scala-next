module Layout.Widgets.DrilldownBar where

-- The drilldown bar chart: registry name "drilldownBar", rendered by the legacy
-- htmlwriter.runDrilldownBar, which is an ALIAS of runTimeSeries
-- (ermine-htmlwriter.js:2646).  HTMLWriter.drilldownBarChartPC (~1279-1313) sends
-- `meta`, a ONE-element `series` list whose `data` is always inline (the comment
-- at :1286 says drilldown bars have no partial fetch), and the parent/child
-- column pair that makes runTimeSeries take its drilldown branch
-- (`isDD = !isnull(parentCol) && !isnull(childCol)`, :1728).
--
-- The legacy row for a drilldown bar carries two EXTRA positions after the colour:
-- index 4 is the child value (the drilldown id the breadcrumb pushes) and index 5
-- the parent value (what `_.filter(d, [5, ddid])` restricts on, :1921).
-- client/src/charts.ts appends them in that order.

import Layout.Widgets.Chart using {type ChartMeta; type ChartSeries; type Series; seriesWire}
import Field using fieldName
import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}

data DrilldownBarProps r = DrilldownBarProps { barMeta : ChartMeta
                                             , barSeries : ChartSeries
                                             , barParentColumn : String
                                             , barChildColumn : String
                                             , barRows : [..r] }

-- | The registry name, tied to the props type.
drilldownBarName : WidgetName (DrilldownBarProps r)
drilldownBarName = WidgetName "drilldownBar"

drilldownBar : DrilldownBarProps r -> Node
drilldownBar p = widget drilldownBarName p

-- * The typed authoring API (WP-37, D1/D4)
--
-- `DrilldownBarProps` is the WIRE (column names, D3).  A report builds it with
-- `drilldownBarOf` from a `DrilldownBarSource`: the series is a typed
-- `Layout.Widgets.Chart.Series r`, and parent and child are FIELDS, two DISTINCT
-- columns of the relation (the partition in `drilldownBarOf`).

-- | What `drilldownBarOf` lowers.  Server-side only.  Parent and child carry the
-- same value type: a parent cell names another row's child cell.
data DrilldownBarSource h1 h2 a r =
  DrilldownBarSource { barSourceMeta : ChartMeta
                     , barSourceSeries : Series r
                     , barParent : Field h1 a
                     , barChild : Field h2 a
                     , barSourceRows : [..r] }

drilldownBarOf : (r <- (h1, h2, t)) => DrilldownBarSource h1 h2 a r -> DrilldownBarProps r
drilldownBarOf s =
  DrilldownBarProps (barSourceMeta s) (seriesWire (barSourceSeries s))
                    (fieldName (barParent s)) (fieldName (barChild s)) (barSourceRows s)
