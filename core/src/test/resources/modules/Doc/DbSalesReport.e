module Doc.DbSalesReport where

-- THE DB-BACKED TWIN of Doc.SalesReport (DB-PLAN D7, tracker/db/REPORTS.md):
-- the same report with `sales` bound to `table sales_report` -- a base table
-- in ErmineSales (a mart snapshot, tracker/db/SCHEMA-SALES.md §2) or in the
-- loader's SQLite twin -- instead of the three literal rows.  At tier xs the
-- table holds exactly those rows, so the document equals SalesReport's
-- (TestDbReports); from tier s it is derived per region group.  The original's notes follow unchanged.
--
-- The end-to-end fixture: a report that uses the legacy-backed "table",
-- "axisChart" and "pieChart" widgets and the new "scorecard" widget over ONE
-- relation (J3d built the first two, J3e added the charts).
--
--   sbt -batch 'core/Test/runMain com.clarifi.reporting.SalesReportDoc <file>'
--
-- writes it through json/Write.scala on a SQLite in-memory connection, and
-- client/test/endtoend.test.ts renders THAT FILE in jsdom with a stub
-- htmlwriter.  When J3c lands, the same module is what `bin/ermine-serve`
-- answers `POST /report/Doc.SalesReport` with.
--
-- It lives under modules/ rather than the brief's core/src/test/resources/doc/
-- because that is the directory the module loader searches on the classpath.

import Native.List
import Native.Relation
import List
import Json using type Inline; Inline
import Layout.Doc using vflow; type Node
import Layout.Widgets.Format
import Layout.Widgets.Table
import Layout.Widgets.Scorecard
import Layout.Widgets.Chart
import Layout.Widgets.AxisChart
import Layout.Widgets.PieChart

field srRegion : String
field srSales : Double
field srDelta : Double

table sales_report : [srRegion, srSales, srDelta]

sales : [srRegion, srSales, srDelta]
sales = sales_report

report : Node
report =
  vflow
    [ scorecard (ScorecardProps "Sales by region" "srRegion" "srSales" (Just "srDelta")
                                (Round False False 1) (Inline sales))
    , tabular (TableProps
        [ TableColumn "srRegion" "Region" Default AlignLeft OtherColumn
        , TableColumn "srSales" "Sales" (Currency False False "$" 2) AlignRight NumberColumn
        , TableColumn "srDelta" "Change" (Percentage False True 1 False) AlignRight NumberColumn
        ]
        Nothing [ColumnSort 1 True] True True sales)
    , axisChart (AxisChartProps
        (ChartMeta "Sales by region"
          (ChartAxis "Region" "Region" Default (Scalar "String" False) True (Unscaled [Asc] []))
          (ChartAxis "Sales" "Sales" (Round False False 1) (Scalar "Double" True) True
                     (Scaled (Just 0.0) Nothing Linear))
          Vertical (ChartLegendOptions LegendAbove) (ChartRenderHints False))
        [ChartSeries [] ["srRegion"] "srSales" [] Nothing (Constant "Sales") [] Bar]
        sales)
    , pieChart (PieChartProps "Share of sales" "Sales" "srRegion" "srSales"
                              Nothing Nothing Nothing
                              Default (Round False False 1)
                              (ChartLegendOptions LegendRightTable) (ChartRenderHints True)
                              (Inline sales))
    ]
