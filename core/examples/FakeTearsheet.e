module FakeTearsheet where

import Prelude
import Layout
import Layout.Color as Color
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Report
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Syntax
import Layout.Report.Keyed.Options as O
import Layout.SortPriority
import Ord using lt; eq
import DateRange as DR
import Primitive using primOrd
import Relation
import Relation.Aggregate as Ag
import Relation.Op as Op
import Syntax.Relation
import Relation.RTree
import Double
import Nullable
import List.Stream as Inf
import List.Util using sortBy
import Syntax.List
import Syntax.Do
import Math
import Map as Map
import Parse
import Maybe
import Syntax.Maybe
import Control.Ap
import Control.Traversable
import Control.Monad.Cont
import Record as Rec
import Validation as V
import Layout.Validation using withValidation
import Type.Remember using asTypeOf

field label : String
field value, port, bench, active : Double
field allocEff, selectEff, interEff, totalEff : Double
field avgWt, ret, contrib : Double
field startDate, endDate : Date

lg = legend_Lg
bold s = "__" ++_String s ++_String "__"
hAtom s = style "atom" $ atomShown s

fakeTearsheetHeader portfolioNamesDropdown portfolioNamesSource =
  header "Portfolio Information" $
  grid [
      headerRow "Portfolio Name" portfolioNamesDropdown                      "Date Range" "One Year to end Of Last Quarter",
      headerRow "Portfolio Id"   (hAtom "-")                             "Currency" "Hong Kong Dollar (HKD)",
      headerRow "Benchmark"      (hAtom "123456 - Panjab")               "Grouping" "CICS Sector",
      headerRow "Risk Model"     (hAtom "Global Fundamental Short Term") "Exclude Cash" "No"
  ]
  where headerRow a b c d = [ prefW [pixelsM 150] $ hAtom (bold a), prefW [pixelsM 400] b, prefW [pixelsM 150] $ hAtom (bold c), hAtom d ]

poLegend = Just $
  legend_Lg (truncate_Pres 22 label) "" ++_Lg
  legend_Lg port "Port" ++_Lg
  legend_Lg bench "Bench" ++_Lg
  legend_Lg active "Active"

fakePORelation = relation [
  { label = "Total Return",	          port = 21.19,   bench = 23.48,  active = neg 2.30 },
  { label = "Realized Risk",            port = 30.21,   bench = 18.39,  active = 19.07 },
  { label = "Latest Predicted Risk",    port = 23.03,   bench = 14.56,  active = 16.40 },
  { label = "-Factor Risk",             port = 19.84,   bench = 13.86,  active = 10.58 },
  { label = "-Stock Specific Risk",     port = 11.71,   bench = 4.47,   active = 12.53 },
  { label = "Portfolio Value($mm)",     port = 1.29,    bench = 0.0,    active = 0.0 },
  { label = "\\# of Securities",        port = 18.0,    bench = 37.0,   active = 0.0 },
  { label = "Annualized Total Return",  port = 21.12,   bench = 23.41,  active = neg 2.29 },
  { label = "% of Cash",                port = 0.00,    bench = 0.54,   active = neg 0.54 }
]

-- todo: put prc line chart here
fakePOData = relation [
  { endDate = @2011/1/1,   value = 0.11 }
, { endDate = @2011/2/5,   value = 0.13 }
, { endDate = @2011/8/23,  value = 0.19 }
, { endDate = @2011/9/23,  value = 0.10 }
, { endDate = @2011/10/23, value = 0.29 }
, { endDate = @2011/11/23, value = 0.29 }
]

fakePOBenchData = relation [
  { endDate = @2011/1/1,   value = 0.21 }
, { endDate = @2011/2/5,   value = 0.23 }
, { endDate = @2011/8/23,  value = -0.01 }
, { endDate = @2011/9/23,  value = 0.05 }
, { endDate = @2011/10/23, value = 0.29 }
, { endDate = @2011/11/23, value = 0.19 }
]

--http://www.december.com/html/spec/color3.html
slategray1 = getJust $ sRGBread_Color "#C6E2FF"

poChart hasBench =
  chart_K ([yLabel_O := Atomic unit_Fmt "Return (%)", yFormat_O := percentage_Fmt]_Opt)
          defaultScaled defaultScaled $
          [coloredSeries line [({}, blue_Color)] (prim_Op "Portfolio Contribution") endDate value fakePOData]
          ++ if hasBench
               [coloredSeries line [({}, slategray1)] (prim_Op "Benchmark Contribution") endDate value fakePOBenchData]
               []

pcLegend = Just $
  legend_Lg (truncate_Pres 22 label) "" ++_Lg
  legend_Lg port "Port" ++_Lg
  legend_Lg bench "Bench"

fakePCRelation = relation [
  { label = "Market Capitalization",    port = 609097.97,   bench = 160053.20 },
  { label = "P/E",                      port = 16.89,       bench = 14.70 },
  { label = "P/BV",    	              port = 1.44,        bench = 5.57 },
  { label = "P/Sales",    	          port = 2.32,        bench = 2.54 },
  { label = "Div Yield",    	          port = 2.23,        bench = 1.60 },
  { label = "Return on Equity %",    	  port = 7.47,        bench = 40.13 },
  { label = "Total Debt/Equity",    	  port = 564.56,      bench = 348.90 },
  { label = "Forward P/E",    	      port = 10.89,       bench = 13.11 },
  { label = "EPS 3 Yr CAGR %",    	  port = 11.28,       bench = 23.30 }
]

sectorWeightLegend = Just $
  legend_Lg (truncate_Pres 22 label) "" ++_Lg
  legend_Lg port "Port" ++_Lg
  legend_Lg bench "Bench" ++_Lg
  legend_Lg active "Active"

fakeSectorWeightRelation = relation [
  { label = fakeLinkLabel "Financials",	              port = 21.19,   bench = 23.48,  active = neg 2.30 },
  { label = fakeLinkLabel "Industrials",              port = 30.21,   bench = 18.39,  active = 19.07 },
  { label = fakeLinkLabel "Information Technology",   port = 23.03,   bench = 14.56,  active = 16.40 },
  { label = fakeLinkLabel "Consumer Discretionary",   port = 19.84,   bench = 13.86,  active = 10.58 },
  { label = fakeLinkLabel "Healthcare",               port = 11.71,   bench = 4.47,   active = 12.53 },
  { label = fakeLinkLabel "Consumer Staples",         port = 1.29,    bench = 0.0,    active = 0.0 },
  { label = fakeLinkLabel "Telecommunication Services",   port = 18.0,    bench = 37.0,   active = 0.0 },
  { label = fakeLinkLabel "Utilities",                port = 18.0,    bench = 37.0,   active = 0.0 },
  { label = fakeLinkLabel "Materials",                port = 21.12,   bench = 23.41,  active = neg 2.29 },
  { label = fakeLinkLabel "Cash",                     port = 0.00,    bench = 0.54,   active = neg 0.54 }
]

-- todo: put swc pie chart here
fakePieChart = (pieChart_K [pieTitle_O := "", pieColors_O := [({label = "Cash"}, green_Color)]]_Opt) label value (relation [
   { label = "Information Technology",  value = 45.0},
   { label = "Financials",              value = 30.0},
   { label = "Consumer Staples",        value = 15.0},
   { label = "Other",                   value = 10.0}
 ])

saLegend = Just $
  legend_Lg (truncate_Pres 22 label) "" ++_Lg
  legend_Lg allocEff  "Alloc Eff" ++_Lg
  legend_Lg selectEff "Selec Eff" ++_Lg
  legend_Lg interEff  "Inter Eff" ++_Lg
  legend_Lg totalEff  "Total Eff"

fakeSARelation = relation [
  { label = fakeLinkLabel "Financials",           allocEff = 2.91,  selectEff = neg 1.52,  interEff = neg 6.51, totalEff = neg 5.12 },
  { label = fakeLinkLabel "Industrials",          allocEff = 0.20,  selectEff = 3.84,   interEff = neg 0.21, totalEff = 3.82 },
  { label = fakeLinkLabel "Information Technology", allocEff = neg 3.16, selectEff = neg 9.52,  interEff = 7.44,  totalEff = neg 5.25 },
  { label = fakeLinkLabel "Consumer Discretionaries", allocEff = 0.78,  selectEff = 2.64,   interEff = neg 2.62, totalEff = 0.80 },
  { label = fakeLinkLabel "Healthcare",           allocEff = 2.64,  selectEff = neg 19.76, interEff = 19.58, totalEff = 2.46 },
  { label = fakeLinkLabel "Consumer Staples",     allocEff = 0.08,  selectEff = 0.03,   interEff = neg 0.03, totalEff = 0.07 },
  { label = fakeLinkLabel "Utilities",            allocEff = neg 0.01, selectEff = 0.00,   interEff = 0.00,  totalEff = neg 0.01 },
  { label = fakeLinkLabel "Telecommunication Services",  allocEff = neg 2.42, selectEff = neg 1.04,  interEff = 1.04,  totalEff = neg 2.43 },
  { label = fakeLinkLabel "Materials",            allocEff = 3.21,  selectEff = 0.00,   interEff = 0.00,  totalEff = 3.21 },
  { label = fakeLinkLabel "Cash",                 allocEff = 0.14,  selectEff = 0.00,   interEff = 0.00,  totalEff = 0.14 },
  { label = fakeLinkLabel "Total",                allocEff = 4.35,  selectEff = neg 25.34, interEff = 18.69, totalEff = neg 2.30 }
]

securityWeightLegend = Just $
  legend_Lg (truncate_Pres 22 label) "Top 10" ++_Lg
  legend_Lg port "Port" ++_Lg
  legend_Lg bench "Bench" ++_Lg
  legend_Lg active "Active"

fakeSecurityWeightRelation = relation [
  { label = fakeLinkLabel "The Goldman Sachs Group of Death",	    port = 71.92,   bench = 0.00,  active = 71.92 },
  { label = fakeLinkLabel "General Electric Company of Destiny",	    port = 13.68,   bench = 0.00,  active = 13.68 },
  { label = fakeLinkLabel "Gluskin Sheff + Association and Friends",	    port = 8.95,    bench = 0.00,  active =	8.95 },
  { label = fakeLinkLabel "JPMorgan Chase & Co. Something Something",	    port = 2.44,    bench = 0.00,  active = 2.44 },
  { label = fakeLinkLabel "Gefran SpA (BIT:GE)",	        port = 2.28,    bench = 0.00,  active = 2.28 },
  { label = fakeLinkLabel "Google Inc. (NasdaqGS blah blah blah",	    port = 0.45,    bench = 0.00,  active = 0.45 },
  { label = fakeLinkLabel "Volkswagen AG (DB:VOW)",	        port = 0.10,    bench = 0.00,  active = 0.10 },
  { label = fakeLinkLabel "Granville Pacific Capitalwerwerwer", 	port = 0.05,    bench = 0.00,  active = 0.05 },
  { label = fakeLinkLabel "Johnson & Johnson (NYhrtujytutyu",	    port = 0.04,    bench = 0.00,  active = 0.04 },
  -- TODO: this é breaks things when we don't set -Dfile.encoding=UTF-8...
  { label = fakeLinkLabel "Nestlé S.A. (SWX:NESN)",	        port = 0.04,    bench = 0.00,  active = 0.04 },
         --{ label = fakeLinkLabel "Nestle S.A. (SWX:NESN)",	        port = 0.04,    bench = 0.00,  active = 0.04 },
  { label = fakeLinkLabel "Total",	                        port = 99.95,   bench = 0.00,  active = 99.95 }
]

securityContributionTopLegend = Just $
  legend_Lg (truncate_Pres 22 label) "Top 5" ++_Lg
  legend_Lg avgWt "Avg Wgt" ++_Lg
  legend_Lg ret "Return" ++_Lg
  legend_Lg contrib "Contr"

fakeSecurityContributionTopRelation = relation [
  { label = fakeLinkLabel "The Goldman Sachs Grwererwer",	    avgWt = 71.92,   ret = 21.67,  contrib = 15.55 },
  { label = fakeLinkLabel "General Electric Compaerergergt",	    avgWt = 13.68,   ret = 53.80,  contrib = 6.38 },
  { label = fakeLinkLabel "JPMorgan Chase & Co. ewgtrewgerrh ewr",	    avgWt = 2.41,    ret = 37.96,  contrib = 0.83 },
  { label = fakeLinkLabel "Google Inc. (NasdaqGSwerwetjrtjrt",	    avgWt = 0.41,    ret = 45.90,  contrib = 0.17 },
  { label = fakeLinkLabel "Volkswagen AG (DB:VOW)",	        avgWt = 0.10,    ret = 35.80,  contrib = 0.03 }
]

securityContributionBottomLegend = Just $
  legend_Lg (truncate_Pres 22 label) "Bottom5" ++_Lg
  legend_Lg avgWt "AvgWgt" ++_Lg
  legend_Lg ret "Return" ++_Lg
  legend_Lg contrib "Contr"

fakeSecurityContributionBottomRelation = relation [
  { label = fakeLinkLabel "Gefran SpA (BIT:GE)",	        avgWt = 2.67,    ret = neg 19.55,  contrib = neg 2.28 },
  { label = fakeLinkLabel "Gluskin Sheff + Associaegtwaerhhh",	    avgWt = 9.71,    ret = neg 3.06,   contrib = neg 8.95 },
  { label = fakeLinkLabel "Granville Pacific Capitaleerwerwer", 	avgWt = 0.07,    ret = neg 69.99,  contrib = neg 0.005 },
  { label = fakeLinkLabel "Electricite de France Swer98678df",	    avgWt = 0.02,    ret = neg 23.83,  contrib = 0.0 },
  { label = fakeLinkLabel "Medivir AB (OM:MVIR B)",	        avgWt = 0.001,   ret = neg 14.29,  contrib = 0.0 }
]

fakeLinkLabel s = "[" ++_String s ++_String "](http//www.google.com)"

littleSquareWidth = 349
littleSquare1 name r = prefA [pixelsA littleSquareWidth 193] $ header name r
littleSquare2 name r = prefA [pixelsA littleSquareWidth 231] $ header name r
littleSquare3 name r = prefA [pixelsA littleSquareWidth 231] $ header name r

fakeTearsheetBody =
  noTableScrolling . noTablePagination ' vflow [
    grid [
      [
        littleSquare1 "Portfolio Overview"  $ tabular poLegend fakePORelation,
        littleSquare1 "Portfolio Return Chart" $ poChart True,
        littleSquare1 "Portfolio Characteristics" $ tabular pcLegend fakePCRelation
      ],
      [
        littleSquare2 "Sector Weight" $ tabular sectorWeightLegend fakeSectorWeightRelation,
        littleSquare2 "Sector Weight Chart" $ fakePieChart,
        littleSquare2 "Sector Attribution" $ tabular saLegend fakeSARelation
      ],
      [
        littleSquare3 "Security Weight" $ tabular securityWeightLegend fakeSecurityWeightRelation,
        littleSquare3 "Security Contribution Chart" $ atomShown "todo!",
        littleSquare3 "Security Contribution" $ vflow [
          tabular securityContributionTopLegend fakeSecurityContributionTopRelation,
          tabular securityContributionBottomLegend fakeSecurityContributionBottomRelation
        ]
      ]
    ]
  ]

portfolioNames = ["****Kitty Rocking 2010", "Portfolio 1", "Portfolio 2", "Portfolio 3"]

fakeTearsheet = fakeTearsheetBody
showFakeTearsheet = html' fakeTearsheet
--testPie = html $ littleSquare2 "Sector Weight Chart" fakePieChart
