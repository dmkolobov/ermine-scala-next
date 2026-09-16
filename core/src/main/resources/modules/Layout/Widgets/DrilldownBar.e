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

import Layout.Widgets.Chart using type ChartMeta; type ChartSeries
import Layout.Doc using widget; type Node

data DrilldownBarProps r = DrilldownBarProps { barMeta : ChartMeta
                                             , barSeries : ChartSeries
                                             , barParentColumn : String
                                             , barChildColumn : String
                                             , barRows : [..r] }

drilldownBar : DrilldownBarProps r -> Node
drilldownBar p = widget "drilldownBar" p
