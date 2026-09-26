module Regions where

import Json using type Inline; Inline
import Layout.Doc using vflow; tabbed; type Node
import Layout.Widgets.Format
import Layout.Widgets.Table
import Layout.Widgets.Scorecard
import Layout.Widgets.Chart
import Layout.Widgets.PieChart
import List using empty_Bracket; cons_Bracket
import Native.List
import Native.Relation

field rRegion : String
field rSales  : Double
field rDelta  : Double

-- the request sends "sortBy": "BySales"
data Order = ByName | BySales

data Params = Params { heading : String, sortBy : Order }

sales : [rRegion, rSales, rDelta]
sales = mkRelation# (toList#
  [ { rRegion = "EMEA", rSales = 120.5,  rDelta = 0.125 }
  , { rRegion = "APAC", rSales = 98.25,  rDelta = -0.04 }
  , { rRegion = "AMER", rSales = 310.75, rDelta = 0.5 }
  ])

-- The sort is a MARK on the column the parameter picks; `simpleTable` turns it
-- into that column's index on the wire.
sortedBy : Order -> Order -> Column r -> Column r
sortedBy ByName  ByName  c = sortDesc c
sortedBy BySales BySales c = sortDesc c
sortedBy _       _       c = c

report : Params -> Node
report p =
  tabbed
    [ ("Summary",
        scorecard (scorecardOf (ScorecardSource (heading p) rRegion rSales (Just rDelta)
                                                (Round False False 1) (Inline sales))))
    , ("Detail",
        tabular (simpleTable
          [ sortedBy (sortBy p) ByName (withHeader "Region" (col rRegion))
          , sortedBy (sortBy p) BySales (withHeader "Sales" (numCol rSales (Currency False False "$" 2)))
          , withHeader "Change" (numCol rDelta (Percentage False True 1 False)) ]
          sales))
    , ("Share",
        pieChart (pieChartOf (PieSource "Share of sales" "Sales" rRegion rSales
                                        Nothing Nothing Nothing
                                        Default (Round False False 1)
                                        (ChartLegendOptions LegendRightTable) (ChartRenderHints True)
                                        (Inline sales))))
    ]
