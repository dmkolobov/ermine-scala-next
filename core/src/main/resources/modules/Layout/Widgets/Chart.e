module Layout.Widgets.Chart where

-- The vocabulary the two AXIS-CHART widgets share: "axisChart" (rendered by the
-- legacy htmlwriter.runTimeSeries) and "drilldownBar" (runDrilldownBar, which IS
-- runTimeSeries, ermine-htmlwriter.js:2646).  Both are handed a `meta` object
-- (HTMLWriter.axisChartDataToMap, ~665-713) and a list of `series`
-- (chartSeriesToMap, ~732-793); this module is the Ermine mirror of the parts of
-- those two objects the JavaScript actually READS.
--
-- What is NOT here, and why (tracker/JSON-API-DESIGN.md section 4.2's "read by
-- JS?" column):
--
--   * `selSeries`, `selCategory`, `selValue`, `selExtra` are f0-serialised op
--     lists that the browser POSTs back to the server to fetch the rows
--     (`withTimeSeriesData`, ermine-htmlwriter.js:221-248).  On this path the
--     rows travel with the document, so the JS takes the `Array.isArray` branch
--     at :223 and never reads them.  They are replaced here by COLUMN NAMES --
--     `seriesColumns`, `categoryColumns`, `valueColumn`, `extraColumns` -- which
--     is what client/src/charts.ts builds the legacy row shapes out of.
--   * `selCategoryTips` / `fmtCategoryTips` / `selValueTips` / `fmtValueTips`:
--     zero hits in the bundle.
--   * `structure` (SeriesStructure.Complex `trees`/`correlation`): SERIES-level
--     drilldown, an f0 blob with no JSON equivalent.  Omitting it makes
--     `isSeriesLevelDD` false, which is the Simple behaviour.
--   * `colors` on the meta: a handle the JS only forwards in the POST payload.
--
-- Every per-value format is a Layout.Widgets.Format.CellFormat.  The chart path
-- reads the LOSSY tuple form (HTMLWriter.jsLayoutFormat), so client/src/legacy.ts
-- `legacyFormatTuple` converts, and its losses are documented case by case in
-- client/src/charts.ts (TUPLE_LOSS).

import Layout.Widgets.Format using type CellFormat; Default
import Layout.Widgets.Table using {type Column; columnName}
import List using {map_List; empty_Bracket; cons_Bracket}

-- | writers.ChartLegendLocation (core/.../writers/ChartData.scala:90-99).  The
-- JS compares the string: 'Above', 'Overlay', 'RightTable', 'RightNotOverlay'
-- each take a branch; anything else is the plain Highcharts legend.
data LegendLocation = LegendDefault | LegendAbove | LegendOverlay
                    | LegendRightOverlay | LegendRightNotOverlay
                    | LegendRightTable | LegendHidden

data ChartLegendOptions = ChartLegendOptions { legendLocation : LegendLocation }

-- | writers.ChartRenderHints: whether Highcharts draws a label per point.
data ChartRenderHints = ChartRenderHints { enableDataLabels : Bool }

-- | Which way the RANGE axis runs.
data Orientation = Vertical | Horizontal

data DisplayScale = Linear | Logarithmic

-- | An axis sort direction.  The legacy sends the SortOrder's name; the JS only
-- uses the LIST's length (categoryOrdering, ermine-htmlwriter.js:1589-1601), so
-- the direction is carried for the server's benefit and the length is what
-- matters to the renderer.
data SortDir = Asc | Desc

-- | The axis's `scalarType`: the JS reads `.name` ('Date' switches the axis to a
-- datetime axis, 'compound' plus a `Pr1`/`Pr2` format projects the category) and
-- `.isNumeric`.
data ScalarType = Scalar { typeName : String, typeNumeric : Bool }
                | Compound { componentTypes : List ScalarType }

-- | `constraints`, the scaled/unscaled split of AxisConstraints.
data AxisConstraints =
    Scaled { lowerBound : Maybe Double
           , upperBound : Maybe Double
           , displayScale : DisplayScale }
  | Unscaled { sortOrders : List SortDir
             , tickOverrides : List (String, String) }

-- | One axis of the meta (HTMLWriter.axisToMap).
data ChartAxis = ChartAxis { axisLabel : String
                           , tooltipLabel : String
                           , axisFormat : CellFormat
                           , scalarType : ScalarType
                           , showTicks : Bool
                           , constraints : AxisConstraints }

-- | writers.ChartVariant.  `Bubble` carries the z-axis label the tooltip shows;
-- its z values come from the first `extraColumns` entry, as they do today.
data ChartVariant = Line | Bar | Step | Scatter | StackedBar | StackedArea
                  | BoxAndWhiskers | Bubble { zLabel : String }

-- | One series, as the WIRE carries it (build it typed with `seriesOf` below).
-- The three op-list handles become column names into the widget's
-- single relation: a row of the legacy `data` array is
--
--   [ [value..], [category..], [series..], cssColor|null, child?, parent? ]
--
-- and client/src/charts.ts builds exactly that from these names.
data ChartSeries = ChartSeries { seriesColumns : List String
                               , categoryColumns : List String
                               , valueColumn : String
                               , extraColumns : List String
                               , colorColumn : Maybe String
                               , seriesFormat : CellFormat
                               , extraFormats : List CellFormat
                               , variant : ChartVariant }

-- | The `meta` object.  `chartTitle`, not `title`: Layout.Widgets re-exports every
-- widget module into one scope and Scorecard already owns `title`.
data ChartMeta = ChartMeta { chartTitle : String
                           , domainAxis : ChartAxis
                           , rangeAxis : ChartAxis
                           , orientation : Orientation
                           , legendOptions : ChartLegendOptions
                           , renderHints : ChartRenderHints }

-- spellings a report reaches for

defaultLegendOptions : ChartLegendOptions
defaultLegendOptions = ChartLegendOptions LegendDefault

defaultRenderHints : ChartRenderHints
defaultRenderHints = ChartRenderHints False

-- | An unscaled category axis with one sort component and no tick overrides.
categoryAxis : String -> CellFormat -> ChartAxis
categoryAxis lbl fmt =
  ChartAxis lbl lbl fmt (Scalar "String" False) True (Unscaled [Asc] [])

-- | A scaled numeric axis with automatic bounds.
valueAxis : String -> CellFormat -> ChartAxis
valueAxis lbl fmt =
  ChartAxis lbl lbl fmt (Scalar "Double" True) True (Scaled Nothing Nothing Linear)

-- * The typed authoring API (WP-37, D1/D4)
--
-- `ChartSeries` above is the WIRE: its columns are names.  A report builds a
-- `Series r` instead, whose columns are `Layout.Widgets.Table.Column r` values
-- (`col srRegion`), so each carries `Has r h`; the row `r` is settled where the
-- series meets the chart's relation (`Layout.Widgets.AxisChart.axisChartOf`,
-- `Layout.Widgets.DrilldownBar.drilldownBarOf`), and a column the relation does
-- not have is a type error there.  The series and category lists are OPEN (any
-- number of columns, a column may appear in more than one), so they are
-- `Column r` lists, not partitioned slots.  Only a column's NAME reaches the
-- wire: its header, format, alignment and a table's sort/row-group marks are
-- ignored here (the chart's formats are `seriesFormat`/`extraFormats`).  A column
-- named at run time is `Layout.Widgets.Table.Unsafe.rawColumn`.

-- | A series valid for relations with row `r`.  `Series#` is the unchecked
-- constructor: build one with `seriesOf` or `simpleSeries`.
data Series (r : rho) = Series# ChartSeries

-- | Every slot of `ChartSeries`, in its order, with columns for names.
seriesOf : List (Column r) -> List (Column r) -> Column r -> List (Column r)
        -> Maybe (Column r) -> CellFormat -> List CellFormat -> ChartVariant -> Series r
seriesOf ss cs v xs c fmt xfs var =
  Series# (ChartSeries (map_List columnName ss) (map_List columnName cs) (columnName v)
                       (map_List columnName xs) (maybeName c) fmt xfs var)

-- | A one-column category, one-column value series with no extras.
simpleSeries : Column r -> Column r -> ChartVariant -> Series r
simpleSeries cat val v = seriesOf [] [cat] val [] Nothing Default [] v

-- | The wire series.
seriesWire : Series r -> ChartSeries
seriesWire (Series# s) = s

private
  maybeName : Maybe (Column r) -> Maybe String
  maybeName Nothing  = Nothing
  maybeName (Just c) = Just (columnName c)

-- | The default meta: a title and the two axes, vertical, legend where the
-- report's theme puts it.
simpleMeta : String -> ChartAxis -> ChartAxis -> ChartMeta
simpleMeta t d r =
  ChartMeta t d r Vertical defaultLegendOptions defaultRenderHints
