module Present.SalesDashboard where

{- A SALES DASHBOARD: one wide fact table, EIGHT charts, three KPI tiles and two
   grids built two different ways, laid out as a page.

   Fact: orders (21 fields: orderId, orderDate, regionName, countryName,
                 channelName, repName, skuCode, skuName, categoryName,
                 subCategory, unitsSold, unitPrice, grossRevenue, discountAmt,
                 netRevenue, costOfGoods, grossMargin, marginPct, quarterName,
                 targetRevenue, repScore)

   WHY THIS FILE EXISTS. `core/examples` had three chart uses before this
   directory -- `ChartsExample.e`, `GridExample.e` and `PieChartLegendExample.e`
   -- all over three-column toy relations, and no example at all of a PAGE: a
   dashboard is not a chart, it is a layout of charts, tiles and grids over ONE
   fact table, and the interesting typing question is what each panel is allowed
   to read from that table. The answer is the existential in `chartOf`'s
   constraint, `r <- (sr, xr, yr, o)`: series, category, value, and `o` for
   "the other seventeen columns, which this panel does not look at".

   SHAPES EXERCISED
     * `chartOf` instantiated FIVE ways from one signature -- `bar`, `line`,
       `stackedBar`, `scatter` and `step` -- each solving the same partition
       against a different triple of columns of the same 21-column row; plus
       `chartOfAll` for a two-series comparison, a raw `chart_K` for the
       transformer stack, and `pieOf`. Eight chart objects in all.
     * `Layout.PresRow` and the EXTRA-DATA series mode: `bar'` carries a
       `PresRow` of columns that are not plotted but travel with each point
       (the tooltip). Its `cons_Bracket` is an `RUnion2`, so the extra row is
       checked against the relation.
     * `Layout.Scan`'s `groupBy1` / `mapV` / `column` / `columns` / `keys`: the
       SAME quarterly grid as `keyedGrid` builds, one layer down and by a
       different route -- scan the relation, split it on the key, turn each
       group into a column. Worth having both: `keyValueTabular` decides the
       schema from a `SoftRelation`, `Layout.Scan` from the scanned rows.
     * `Layout.Chart`'s two axis kinds side by side: `unscaled` for the discrete
       category axis, `scaled` (with an explicit lower bound and a logarithmic
       option) for the value axis.
     * `coloredSeries` and `categoryTickLabels`, the two `ChartSeries`
       transformers, stacked on one series.
     * `pieOf` with `Layout.Legend` pinning through `pieLegendOpts_O`.
     * `keyedGrid` / `softGrid`: a grid whose COLUMN SET is the distinct values
       of `quarterName`, not a static list -- `Layout.Report.SoftRelation`'s
       three-part partition `r <- (k, v, i)`.
     * `withFormats`: one currency format applied to a generic measure row.
     * `Layout.Magnitude` in both its senses -- `sizedTo` for a panel's box, and
       `spread` for a weighted horizontal split.
     * `dashboard` / `panel` / `kpi`: the page.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/SalesDashboard.e
     >> salesDashboard
     >> revenueByRegion
     >> byRegionQuarter        -- the numbers the tiles are computed from

   NOTE ON `render`. There is no `render` in this repository; a `Report` needs a
   `Layout.Writer`, and every concrete writer lives in the separate
   `ermine-writers` project. Evaluate the report (it prints `Report <function>`)
   and evaluate the relations it draws (they print their resolved headers -- the
   column set the document will show). See `tracker/loopmodel/E4-EXAMPLES.md`
   gate G4, and `Present/WriterOutputs.e` for what a writer would do with this.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Color
import Layout.Magnitude
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Layout.Scan as Sc
import Layout.PresRow as PR
import Relation.Op as Op
import Relation.Aggregate as Agg
import Relation.Sort as Sort
import Syntax.Relation
import Syntax.List
import Present.Helpers

field orderId, unitsSold : Int
field orderDate : Date
field regionName, countryName, channelName, repName : String
field skuCode, skuName, categoryName, subCategory, quarterName : String
field unitPrice, grossRevenue, discountAmt, netRevenue : Double
field costOfGoods, grossMargin, marginPct, targetRevenue : Double
field repScore : Nullable Int

field revenueK, targetK, attainment, orderCount, avgOrder : Double
field categoryRevenue, quarterRevenue : Double

-- ------------------------------------------------------------- the fact table

-- Twenty-one columns, fifteen order lines, three regions, three quarters of
-- 2011. `repScore` is nullable on purpose: one rep has no survey score, and the
-- scatter chart below has to cope.
orders : [ orderId, orderDate, regionName, countryName, channelName, repName
         , skuCode, skuName, categoryName, subCategory, unitsSold, unitPrice
         , grossRevenue, discountAmt, netRevenue, costOfGoods, grossMargin
         , marginPct, quarterName, targetRevenue, repScore ]
orders = relation [
  { orderId = 1001, orderDate = @2011/1/17, regionName = "AMER", countryName = "United States",
    channelName = "Direct", repName = "r.alvarez", skuCode = "SKU-1180", skuName = "Trailhead Pack",
    categoryName = "Outdoor", subCategory = "Backpacks", unitsSold = 420, unitPrice = 89.0,
    grossRevenue = 37380.0, discountAmt = 1869.0, netRevenue = 35511.0, costOfGoods = 20559.0,
    grossMargin = 14952.0, marginPct = 0.4211, quarterName = "Q1", targetRevenue = 60000.0,
    repScore = Some 62 },
  { orderId = 1002, orderDate = @2011/1/29, regionName = "AMER", countryName = "Canada",
    channelName = "Partner", repName = "d.chen", skuCode = "SKU-1180", skuName = "Trailhead Pack",
    categoryName = "Outdoor", subCategory = "Backpacks", unitsSold = 180, unitPrice = 89.0,
    grossRevenue = 16020.0, discountAmt = 1922.4, netRevenue = 14097.6, costOfGoods = 8811.0,
    grossMargin = 5286.6, marginPct = 0.3750, quarterName = "Q1", targetRevenue = 60000.0,
    repScore = Some 48 },
  { orderId = 1003, orderDate = @2011/2/8, regionName = "EMEA", countryName = "Germany",
    channelName = "Direct", repName = "k.baumann", skuCode = "SKU-2245", skuName = "Alpine Shell",
    categoryName = "Outdoor", subCategory = "Outerwear", unitsSold = 260, unitPrice = 214.0,
    grossRevenue = 55640.0, discountAmt = 0.0, netRevenue = 55640.0, costOfGoods = 30602.0,
    grossMargin = 25038.0, marginPct = 0.4500, quarterName = "Q1", targetRevenue = 72000.0,
    repScore = Some 71 },
  { orderId = 1004, orderDate = @2011/2/22, regionName = "EMEA", countryName = "France",
    channelName = "Online", repName = "k.baumann", skuCode = "SKU-2245", skuName = "Alpine Shell",
    categoryName = "Outdoor", subCategory = "Outerwear", unitsSold = 140, unitPrice = 214.0,
    grossRevenue = 29960.0, discountAmt = 2396.8, netRevenue = 27563.2, costOfGoods = 16478.0,
    grossMargin = 11085.2, marginPct = 0.4022, quarterName = "Q1", targetRevenue = 72000.0,
    repScore = Some 71 },
  { orderId = 1005, orderDate = @2011/3/3, regionName = "APAC", countryName = "Japan",
    channelName = "Partner", repName = "y.tanaka", skuCode = "SKU-3310", skuName = "Delta Tent",
    categoryName = "Outdoor", subCategory = "Shelter", unitsSold = 95, unitPrice = 449.0,
    grossRevenue = 42655.0, discountAmt = 6398.2, netRevenue = 36256.8, costOfGoods = 23460.3,
    grossMargin = 12796.5, marginPct = 0.3529, quarterName = "Q1", targetRevenue = 85000.0,
    repScore = Null Int },
  { orderId = 1006, orderDate = @2011/3/28, regionName = "APAC", countryName = "Australia",
    channelName = "Online", repName = "y.tanaka", skuCode = "SKU-3310", skuName = "Delta Tent",
    categoryName = "Outdoor", subCategory = "Shelter", unitsSold = 120, unitPrice = 449.0,
    grossRevenue = 53880.0, discountAmt = 2694.0, netRevenue = 51186.0, costOfGoods = 29634.0,
    grossMargin = 21552.0, marginPct = 0.4211, quarterName = "Q1", targetRevenue = 85000.0,
    repScore = Null Int },
  { orderId = 1007, orderDate = @2011/4/11, regionName = "AMER", countryName = "United States",
    channelName = "Online", repName = "r.alvarez", skuCode = "SKU-4402", skuName = "Cinder Stove",
    categoryName = "Gear", subCategory = "Cooking", unitsSold = 610, unitPrice = 64.0,
    grossRevenue = 39040.0, discountAmt = 3904.0, netRevenue = 35136.0, costOfGoods = 18739.2,
    grossMargin = 16396.8, marginPct = 0.4667, quarterName = "Q2", targetRevenue = 95000.0,
    repScore = Some 62 },
  { orderId = 1008, orderDate = @2011/4/26, regionName = "EMEA", countryName = "United Kingdom",
    channelName = "Direct", repName = "s.okonkwo", skuCode = "SKU-4402", skuName = "Cinder Stove",
    categoryName = "Gear", subCategory = "Cooking", unitsSold = 330, unitPrice = 64.0,
    grossRevenue = 21120.0, discountAmt = 0.0, netRevenue = 21120.0, costOfGoods = 10137.6,
    grossMargin = 10982.4, marginPct = 0.5200, quarterName = "Q2", targetRevenue = 80000.0,
    repScore = Some 55 },
  { orderId = 1009, orderDate = @2011/5/9, regionName = "AMER", countryName = "United States",
    channelName = "Partner", repName = "d.chen", skuCode = "SKU-5517", skuName = "Quartz Lamp",
    categoryName = "Gear", subCategory = "Lighting", unitsSold = 880, unitPrice = 32.0,
    grossRevenue = 28160.0, discountAmt = 5632.0, netRevenue = 22528.0, costOfGoods = 13516.8,
    grossMargin = 9011.2, marginPct = 0.4000, quarterName = "Q2", targetRevenue = 95000.0,
    repScore = Some 48 },
  { orderId = 1010, orderDate = @2011/5/30, regionName = "APAC", countryName = "Singapore",
    channelName = "Direct", repName = "y.tanaka", skuCode = "SKU-5517", skuName = "Quartz Lamp",
    categoryName = "Gear", subCategory = "Lighting", unitsSold = 240, unitPrice = 32.0,
    grossRevenue = 7680.0, discountAmt = 384.0, netRevenue = 7296.0, costOfGoods = 3686.4,
    grossMargin = 3609.6, marginPct = 0.4947, quarterName = "Q2", targetRevenue = 20000.0,
    repScore = Null Int },
  { orderId = 1011, orderDate = @2011/6/14, regionName = "EMEA", countryName = "Germany",
    channelName = "Online", repName = "k.baumann", skuCode = "SKU-6628", skuName = "Basalt Boot",
    categoryName = "Footwear", subCategory = "Hiking", unitsSold = 355, unitPrice = 168.0,
    grossRevenue = 59640.0, discountAmt = 1789.2, netRevenue = 57850.8, costOfGoods = 36976.8,
    grossMargin = 20874.0, marginPct = 0.3608, quarterName = "Q2", targetRevenue = 80000.0,
    repScore = Some 71 },
  { orderId = 1012, orderDate = @2011/6/27, regionName = "AMER", countryName = "Canada",
    channelName = "Direct", repName = "r.alvarez", skuCode = "SKU-6628", skuName = "Basalt Boot",
    categoryName = "Footwear", subCategory = "Hiking", unitsSold = 205, unitPrice = 168.0,
    grossRevenue = 34440.0, discountAmt = 0.0, netRevenue = 34440.0, costOfGoods = 21352.8,
    grossMargin = 13087.2, marginPct = 0.3800, quarterName = "Q2", targetRevenue = 95000.0,
    repScore = Some 62 },
  { orderId = 1013, orderDate = @2011/7/12, regionName = "APAC", countryName = "Japan",
    channelName = "Online", repName = "y.tanaka", skuCode = "SKU-7734", skuName = "Vantage Poles",
    categoryName = "Gear", subCategory = "Hiking", unitsSold = 470, unitPrice = 41.0,
    grossRevenue = 19270.0, discountAmt = 1348.9, netRevenue = 17921.1, costOfGoods = 9249.6,
    grossMargin = 8671.5, marginPct = 0.4839, quarterName = "Q3", targetRevenue = 25000.0,
    repScore = Null Int },
  { orderId = 1014, orderDate = @2011/8/2, regionName = "EMEA", countryName = "France",
    channelName = "Partner", repName = "s.okonkwo", skuCode = "SKU-7734", skuName = "Vantage Poles",
    categoryName = "Gear", subCategory = "Hiking", unitsSold = 150, unitPrice = 41.0,
    grossRevenue = 6150.0, discountAmt = 1107.0, netRevenue = 5043.0, costOfGoods = 2952.0,
    grossMargin = 2091.0, marginPct = 0.4146, quarterName = "Q3", targetRevenue = 15000.0,
    repScore = Some 55 },
  { orderId = 1015, orderDate = @2011/9/19, regionName = "AMER", countryName = "United States",
    channelName = "Direct", repName = "d.chen", skuCode = "SKU-2245", skuName = "Alpine Shell",
    categoryName = "Outdoor", subCategory = "Outerwear", unitsSold = 290, unitPrice = 214.0,
    grossRevenue = 62060.0, discountAmt = 1241.2, netRevenue = 60818.8, costOfGoods = 34133.0,
    grossMargin = 26685.8, marginPct = 0.4388, quarterName = "Q3", targetRevenue = 70000.0,
    repScore = Some 48 }]

-- ================================================================ the numbers

-- Revenue by region and quarter, in thousands. `scaledBy` divides the measure
-- and keeps the row it reads; the legend's `Format` decides the places. That
-- division of labour -- relation scales, legend formats -- is the reason
-- `Layout.Magnitude` is NOT involved: a magnitude is a box on a page.
byRegionQuarter : [ regionName, quarterName, revenueK ]
byRegionQuarter =
  aggregateByGroup_Agg (sum_Agg (col_Op netRevenue)) {regionName, quarterName}
                       netRevenue orders
    |> combine_Op (scaledBy 1000.0 netRevenue) revenueK
    |> except {netRevenue}

byCategory : [ categoryName, categoryRevenue ]
byCategory =
  aggregateByGroup_Agg (sum_Agg (col_Op netRevenue)) {categoryName}
                       categoryRevenue orders

byChannelQuarter : [ channelName, quarterName, revenueK ]
byChannelQuarter =
  aggregateByGroup_Agg (sum_Agg (col_Op netRevenue)) {channelName, quarterName}
                       netRevenue orders
    |> combine_Op (scaledBy 1000.0 netRevenue) revenueK
    |> except {netRevenue}

-- Attainment against target: the target is a column of the fact table, so it
-- has to be aggregated by MAX (it repeats per order line) rather than summed.
attainmentByRegion : [ regionName, quarterName, revenueK, targetK, attainment ]
attainmentByRegion =
     (aggregateByGroup_Agg (sum_Agg (col_Op netRevenue)) {regionName, quarterName}
                           netRevenue orders
        |> combine_Op (scaledBy 1000.0 netRevenue) revenueK
        |> except {netRevenue})
  ** (aggregateByGroup_Agg (max_Agg (col_Op targetRevenue)) {regionName, quarterName}
                           targetRevenue orders
        |> combine_Op (scaledBy 1000.0 targetRevenue) targetK
        |> except {targetRevenue})
  |> combine_Op (asOp_Op revenueK /_Op asOp_Op targetK) attainment

-- The scatter chart's points: margin percentage against units, one point per
-- order, coloured by category.
marginVsUnits : [ categoryName, unitsSold, marginPct ]
marginVsUnits = orders # {categoryName, unitsSold, marginPct}

-- ================================================================= the charts

-- ONE helper, FIVE modes. `chartOf`'s signature is written once in `Helpers.e`;
-- each call below instantiates its existential `o` against a different set of
-- carried columns.
revenueByRegion =
  chartOf "Net revenue by region ($000)"
          (unscaled Ascending_Sort) defaultScaled
          bar quarterName regionName revenueK byRegionQuarter

revenueTrend =
  chartOf "Net revenue by channel ($000)"
          (unscaled Ascending_Sort) defaultScaled
          line quarterName channelName revenueK byChannelQuarter

channelMix =
  chartOf "Channel mix by quarter ($000)"
          (unscaled Ascending_Sort) defaultScaled
          stackedBar channelName quarterName revenueK byChannelQuarter

marginScatter =
  chartOf "Margin against volume"
          (scaled Ascending_Sort (Just 0) Nothing Linear) defaultScaled
          scatter categoryName unitsSold marginPct marginVsUnits

attainmentSteps =
  chartOf "Attainment against target"
          (unscaled Ascending_Sort) (scaled Ascending_Sort (Just 0.0) (Just 2.0) Linear)
          step quarterName regionName attainment attainmentByRegion

-- TWO SERIES ON ONE PAIR OF AXES: revenue as bars, target as a line. `chartOfAll`
-- takes the series list ready-made, which is what keeps the two modes
-- independent -- they need only agree on the two AXIS types, not on how they are
-- drawn. Both read the same relation here; they need not.
revenueVsTarget =
  chartOfAll "Revenue against target by region ($000)"
             (unscaled Ascending_Sort) defaultScaled
             [ bar  quarterName regionName revenueK attainmentByRegion
             , line quarterName regionName targetK  attainmentByRegion ]

-- Two `ChartSeries` transformers stacked on one series: fixed colours per
-- region, and a friendlier tick label for one category value. Both are
-- row-typed -- `coloredSeries` takes `List ({..sr}, Color)` over the SERIES
-- row, `categoryTickLabels` takes pairs over the CATEGORY row -- so the compiler
-- checks that a colour is keyed by something the series actually selects.
brandedRevenue =
  chart_K ([chartTitle_O := "Net revenue by region, branded ($000)"]_Opt)
          (unscaled Ascending_Sort) defaultScaled
          [ categoryTickLabels [({regionName = "AMER"}, {regionName = "Americas"})]
              (coloredSeries bar [ ({quarterName = "Q1"}, rgb 31 119 180)
                                 , ({quarterName = "Q2"}, rgb 255 127 14)
                                 , ({quarterName = "Q3"}, rgb 44 160 44) ])
              quarterName regionName revenueK byRegionQuarter ]

-- EXTRA DATA PER POINT. `bar'` is `bar` at the `ExtraMode` signature: it takes a
-- `PresRow` of columns that are NOT plotted but travel with each point, which is
-- what a writer puts in the tooltip. `[...]_PR` is `Layout.PresRow`'s bracket
-- syntax and its `cons_Bracket` carries an `RUnion2`, so the extra row is
-- checked against the relation like everything else.
tooltipExtras = [ round_Pres 2 targetK ]_PR

revenueWithTooltip =
  chart_K ([chartTitle_O := "Net revenue by region, target in the tooltip"]_Opt)
          (unscaled Ascending_Sort) defaultScaled
          [ bar' quarterName regionName revenueK tooltipExtras attainmentByRegion ]

-- The pie, with the legend pinned to the right of the plot rather than under it.
categoryPie =
  pieChart_K ([ pieTitle_O := "Net revenue by category"
              , pieLegendOpts_O := chartLegendRight ]_Opt)
             categoryName (currency_Pres "USD" categoryRevenue) byCategory

-- ================================================================== the grid

-- The soft-schema grid: ONE COLUMN PER QUARTER, and the quarters are whatever
-- the data has. `keyedGrid`'s three-part partition `r <- (k, v, i)` splits this
-- relation into the key column (`quarterName`), the value column (`revenueK`)
-- and the identifier columns (`regionName`), and every column must land in
-- exactly one part -- which is why the relation is projected first.
quarterGrid =
  keyedGrid (softGrid quarterName (round_Pres 1 revenueK))
            (legendFor {regionName})
            (byRegionQuarter # {regionName, quarterName, revenueK})

-- THE SAME GRID, ONE LAYER DOWN. `Layout.Scan` reaches the same shape by a
-- different route: scan the relation, `groupBy1` it on the key column, turn each
-- group into a `Layout.Column` with `mapV column`, and lay the columns out
-- against the row key with `columns … keys`. `keyValueTabular` above decides its
-- schema from a `SoftRelation`; this decides it from the scanned rows. Neither
-- knows the quarters until the data arrives.
quarterScanGrid =
  columns_Sc (groupBy1_Sc quarterName
                (byRegionQuarter # { regionName, quarterName, revenueK })
                |> mapV_Sc column_Sc)
    ' keys_Sc { regionName }

-- The flat form of the same numbers, with the key columns labelled and one
-- currency format over the whole measure row. `withFormats`'s partition
-- `r <- (k, m)` is what checks that the two halves cover the grid exactly.
attainmentLegend : Legend_Lg (| regionName, quarterName, revenueK, targetK, attainment |)
attainmentLegend =
  withFormats ([ (regionName,  "Region")  ^ 0
               , (quarterName, "Quarter") ^ 1 ]_Sorted_Lg)
              (round_Fmt 1)
              {revenueK, targetK, attainment}

attainmentTable =
  tabular_K ([tabLegend_O := groupedAs "Fiscal 2011" attainmentLegend]_Opt)
            attainmentByRegion

-- ================================================================== the page

-- Three tiles across the top, then a 2 x 2 of charts, then the two grids. The
-- weighted split gives the branded chart twice the width of the pie.
-- THE TILES ARE COMPUTED, not typed in. `scanRelation` executes the relation
-- and hands its rows over as ordinary values, so the three headline numbers are
-- derived from the same fifteen rows the grids and charts below draw and cannot
-- drift away from them. (An earlier draft stated them by hand and every one was
-- wrong; that is the whole argument for this shape.)
--
-- The count is accumulated as a `Double` rather than converted from a `length`,
-- because `Op` arithmetic and `Prelude` arithmetic are both homogeneous in
-- their numeric type and there is no implicit widening.
kpiRow = scanRelation (orders # { orderId, netRevenue }) (rows ->
  let total = sum' (map (r -> r ! netRevenue) rows)
      n     = foldl (a _ -> a + 1.0) 0.0 rows
  in hspan [ kpi "Orders"        (wholeNumber (length rows))
           , kpi "Net revenue"   (currency "USD" total)
           , kpi "Average order" (currency "USD" (total / n)) ])

salesDashboard = vflow [
  h2 "Sales dashboard -- fiscal 2011 to date",
  kpiRow,
  vstrut,
  dashboard [ [ panel "By region"   revenueByRegion
              , panel "By channel"  revenueTrend ]
            , [ panel "Channel mix" channelMix
              , panel "Margin"      marginScatter ] ],
  spread [ (2.0, panel "Branded" brandedRevenue)
         , (1.0, panel "Category mix" categoryPie) ],
  panel "Revenue against target" revenueVsTarget,
  panel "Revenue, target in the tooltip" revenueWithTooltip,
  panel "Attainment" (sizedTo [pixelsM 640] [pixelsM 240] attainmentSteps),
  h3 "Revenue by region and quarter ($000)",
  quarterGrid,
  h3 "The same grid through Layout.Scan rather than keyValueTabular",
  quarterScanGrid,
  h3 "The same numbers, flat",
  attainmentTable
]
