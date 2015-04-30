module Layout.Report.KeyedTest where

import Error
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax

-- | It's easy to mess up the phantoms so that you accidentally can't
-- use all options.  So we just test that you can use all options that
-- make sense together.

border1 = border_K ([center_O := whatever,
                     north_O := whatever,
                     south_O := whatever,
                     east_O := whatever,
                     west_O := whatever]_Opt)

prefS1 = prefS_K ([width_O := whatever,
                   height_O := whatever]_Opt)

softRelation_Comm = ([valuePresentation_O := whatever,
                      valueSortStrategy_O := whatever,
                      valueSortPriority_O := whatever]_Opt)

softRelation1 = softRelation_K x y ([hardKeySort_O := whatever,
                                     softRelation_Comm]_Opt)

softRelation2 = softRelation_K x y ([softKeySort_O := whatever,
                                     softRelation_Comm]_Opt)

tabular1 = tabular_K ([tabLegend_O := whatever]_Opt)

scaled1 = scaled_K ([numericOrder_O := whatever,
                     lowerBound_O := 0,
                     upperBound_O := 42]_Opt)

unscaled1 = unscaled_K ([stringOrder_O := whatever]_Opt)

unscaled2 = unscaled_K ([arbitraryOrder_O := whatever]_Opt)

chart1 = chart_K ([chartTitle_O := "hi there",
                   yDirection_O := whatever,
                   xLabel_O := whatever,
                   xFormat_O := whatever,
                   showXTicks_O := whatever,
                   yLabel_O := whatever,
                   yFormat_O := whatever,
                   showYTicks_O := whatever]_Opt)

pieChart1 = pieChart_K ([pieTitle_O := "hi there",
                         pieColors_O := Nil,
                         pieDrilldown_O := whatever]_Opt)

drilldownBarChart1 = drilldownBarChart_K unscaled1 scaled1
                       ([titleB_O := "hi there",
                         yDirectionB_O := whatever,
                         legendOptsB_O := whatever,
                         xLabelB_O := whatever,
                         yLabelB_O := whatever,
                         xTicksB_O := whatever,
                         yTicksB_O := whatever]_Opt)

field x: Int
field y: Int

private
  whatever = error "Couldn't be bothered to write what actually happens here"
