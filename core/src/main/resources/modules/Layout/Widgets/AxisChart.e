module Layout.Widgets.AxisChart where

-- The axis chart: registry name "axisChart", rendered by the legacy
-- htmlwriter.runTimeSeries (ermine-htmlwriter.js:1716) through
-- client/src/charts.ts.  The props are what HTMLWriter.axisChart (~1099-1121 ->
-- axisChartToMap 795-805) sends today, minus everything the JS only posts back.
--
-- ONE RELATION FOR THE WHOLE CHART.  Server-side each ChartSeries carries its own
-- Tabular.  Here the series share `chartRows` and each one names its columns
-- inside it, because the multi-series case in practice is several value columns
-- of ONE relation and one relation is one scan.
--
-- That is a CHOICE, not a limit of the type system.  A per-series relation IS
-- typeable -- `data ChartSeries r = ChartSeries { .., seriesRows : [..r] }` with
-- `chartSeries : List (ChartSeries r)` -- and is strictly more general: the series
-- would then carry different ROW SETS over the same columns, and a deferred token
-- each.  What NEITHER spelling can express is series over relations of different
-- SHAPES, which would need an existential row.  See the departures table in
-- tracker/json-stage3/report-J3e.md.
--
-- `chartRows` is a BARE relation: the request's `data.default` decides inline or
-- deferred, and the dispatcher resolves a deferred one before the adapter runs.

import Layout.Widgets.Chart using {type ChartMeta; type ChartSeries; type Series; seriesWire}
import List using {map_List; empty_Bracket; cons_Bracket}
import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}

data AxisChartProps r = AxisChartProps { chartMeta : ChartMeta
                                       , chartSeries : List ChartSeries
                                       , chartRows : [..r] }

-- | The registry name, tied to the props type.
axisChartName : WidgetName (AxisChartProps r)
axisChartName = WidgetName "axisChart"

axisChart : AxisChartProps r -> Node
axisChart p = widget axisChartName p

-- | The typed constructor (WP-37): the series' columns are checked against the
-- relation's row here (`Layout.Widgets.Chart.Series`), and lowered to names.
axisChartOf : ChartMeta -> List (Series r) -> [..r] -> AxisChartProps r
axisChartOf m ss rs = AxisChartProps m (map_List seriesWire ss) rs

-- | One series over one relation.
simpleAxisChart : ChartMeta -> Series r -> [..r] -> AxisChartProps r
simpleAxisChart m s rs = axisChartOf m [s] rs
