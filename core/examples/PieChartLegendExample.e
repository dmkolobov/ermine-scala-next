module PieChartLegendExample where

import Prelude
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Syntax.List

field city : String
pie : Report f z
pie = pieChart_K
  ([pieLegendOpts_O := chartLegendRight, pieTitle_O := "Most Snow"]_Opt)
  city
  Count $ relation [
    {city = "Oswego",   Count = 10},
    {city = "New York", Count = 6},
    {city = "Boston",   Count = 4} ]
