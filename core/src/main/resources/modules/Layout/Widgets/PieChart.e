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
import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}
import Field using fieldName

-- The props below are the WIRE (column names, D3).  A report builds them with
-- `pieChartOf` from a `PieSource`, whose column slots are FIELDS: the partition
-- in `pieChartOf` proves every slot is a column of the relation and no two slots
-- are the same column (WP-37, D4).

data PieChartProps r = PieChartProps { pieTitle : String
                                     , seriesName : String
                                     , pieLabelColumn : String
                                     , pieValueColumn : String
                                     , pieColorColumn : Maybe String  -- "#RRGGBB" cells; typed: pieColor
                                     , pieChildColumn : Maybe String
                                     , pieParentColumn : Maybe String
                                     , pieLabelFormat : CellFormat
                                     , pieValueFormat : CellFormat
                                     , pieLegend : ChartLegendOptions
                                     , pieHints : ChartRenderHints
                                     , pieRows : Inline r }

-- | registry name "pieChart".
-- | The registry name, tied to the props type.
pieChartName : WidgetName (PieChartProps r)
pieChartName = WidgetName "pieChart"

pieChart : PieChartProps r -> Node
pieChart p = widget pieChartName p

-- | registry name "drilldownPieChart".  The same props; the child/parent columns
-- are what make the legacy renderer draw its breadcrumb trail, so a drilldown pie
-- without them is just a pie.
-- | The registry name, tied to the props type.
drilldownPieChartName : WidgetName (PieChartProps r)
drilldownPieChartName = WidgetName "drilldownPieChart"

drilldownPieChart : PieChartProps r -> Node
drilldownPieChart p = widget drilldownPieChartName p

-- * The typed authoring API (WP-37, D4)

-- | What `pieChartOf` lowers: the props, with a FIELD in each column slot.
-- Server-side only.  An absent optional slot (`Nothing`) leaves its row
-- variable free, which the partition allows (it is the empty row).
data PieSource h1 h2 h3 h4 h5 a b c r =
  PieSource { pieSourceTitle : String
            , pieSourceSeriesName : String
            , pieLabel : Field h1 a
            , pieValue : Field h2 b
            , pieColor : Maybe (Field h3 String)  -- "#RRGGBB" cells
            , pieChild : Maybe (Field h4 c)
            , pieParent : Maybe (Field h5 c)
            , pieSourceLabelFormat : CellFormat
            , pieSourceValueFormat : CellFormat
            , pieSourceLegend : ChartLegendOptions
            , pieSourceHints : ChartRenderHints
            , pieSourceRows : Inline r }

-- | The wire props: each field becomes its name.  The five slots are five
-- DISTINCT columns of the relation, or a type error.  Hand the result to
-- `pieChart` or `drilldownPieChart`.
pieChartOf : (r <- (h1, h2, h3, h4, h5, t)) => PieSource h1 h2 h3 h4 h5 a b c r -> PieChartProps r
pieChartOf s =
  PieChartProps (pieSourceTitle s) (pieSourceSeriesName s)
                (fieldName (pieLabel s)) (fieldName (pieValue s))
                (pieSlotName (pieColor s)) (pieSlotName (pieChild s)) (pieSlotName (pieParent s))
                (pieSourceLabelFormat s) (pieSourceValueFormat s)
                (pieSourceLegend s) (pieSourceHints s) (pieSourceRows s)

private
  pieSlotName : Maybe (Field h a) -> Maybe String
  pieSlotName Nothing  = Nothing
  pieSlotName (Just f) = Just (fieldName f)
