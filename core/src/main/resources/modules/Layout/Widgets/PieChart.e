module Layout.Widgets.PieChart where

-- The pie chart: registry names "pieChart" and "drilldownPieChart", rendered by
-- the legacy htmlwriter.runPiechart / runPiechartDrilldown (the latter IS the
-- former, ermine-htmlwriter.js:2632) through client/src/charts.ts.
-- HTMLWriter.genPieChart (~1146-1186) is the emission site.
--
-- In LOCAL mode the legacy sends `relation` as a JSON array of rows
--
--   [ label, |value|, cssColor|null, childValue?, parentValue? ]
--
-- (RelationRunner.runPieChartData), and `withPiechartData` takes the
-- `Array.isArray` branch at :262 -- no callback.  The adapter builds exactly those
-- rows from `pieRows`, so the pie is the one chart whose whole data path is
-- reproduced.  `labelCol`, `dataCol` and `colors` are the REMOTE branch's f0
-- handles and are not modelled.
--
-- The value is |value|: `processPieData` (:250-258) sorts by -y and a negative
-- slice would draw as a hole, so HTMLWriter takes the absolute value server-side
-- and the adapter does the same.  The SIGN is therefore not recoverable from the
-- chart, exactly as today.

import Json using type Inline
import Layout.Widgets.Chart using type ChartLegendOptions; type ChartRenderHints
import Layout.Widgets.Format using type CellFormat
import Layout.Doc using widget; type Node

data PieChartProps r = PieChartProps { pieTitle : String
                                     , seriesName : String
                                     , pieLabelColumn : String
                                     , pieValueColumn : String
                                     , pieColorColumn : Maybe String  -- "#RRGGBB" cells
                                     , pieChildColumn : Maybe String
                                     , pieParentColumn : Maybe String
                                     , pieLabelFormat : CellFormat
                                     , pieValueFormat : CellFormat
                                     , pieLegend : ChartLegendOptions
                                     , pieHints : ChartRenderHints
                                     , pieRows : Inline r }

-- | registry name "pieChart".
pieChart : PieChartProps r -> Node
pieChart p = widget "pieChart" p

-- | registry name "drilldownPieChart".  The same props; the child/parent columns
-- are what make the legacy renderer draw its breadcrumb trail, so a drilldown pie
-- without them is just a pie.
drilldownPieChart : PieChartProps r -> Node
drilldownPieChart p = widget "drilldownPieChart" p
