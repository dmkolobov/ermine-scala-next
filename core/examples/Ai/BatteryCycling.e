module Ai.BatteryCycling where

{- A time-series report over a small battery test bench.

   Fact:       cycleLog  (cellId, testDate, capacityAh, energyWh)
   Dimensions: cell      (cellId -> cellName, chemistry, manufactureDate)
               reference (cellId -> referenceCell)

   Shows: a date-axis chart per cell, capacity retention as a derived column, a
   computed `displayName` that folds the chemistry into the label, and a
   rename so the rendered column header differs from the source column.

     >> :load core/examples/ai/BatteryCycling.e
     >> render cyclingReport
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Ai.Common

field cellId : Int
field cellName, chemistry, referenceCell, displayName : String
field testDate, manufactureDate : Date
field capacityAh, energyWh, retention, dischargeAh : Double
field value : Nullable Double
field label : String
field startDate : Date

cycleLog = relation [
  { cellId = 1, testDate = @2011/1/31, capacityAh = 2.00, energyWh = 6.40 },
  { cellId = 1, testDate = @2011/2/28, capacityAh = 1.98, energyWh = 6.34 },
  { cellId = 1, testDate = @2011/3/31, capacityAh = 1.96, energyWh = 6.27 },
  { cellId = 2, testDate = @2011/1/31, capacityAh = 2.00, energyWh = 7.40 },
  { cellId = 2, testDate = @2011/2/28, capacityAh = 1.97, energyWh = 7.29 },
  { cellId = 2, testDate = @2011/3/31, capacityAh = 1.93, energyWh = 7.14 }
]

cell = relation [
  { cellId = 1, cellName = "Cell A7", chemistry = "LFP",
    manufactureDate = @2009/6/30 },
  { cellId = 2, cellName = "Cell B3", chemistry = "NMC",
    manufactureDate = @2010/1/29 }
]

reference = relation [
  { cellId = 1, referenceCell = "C1 control" },
  { cellId = 2, referenceCell = "C2 control" }
]

-- The star join, annotated.
cycles : [ cellId, testDate, capacityAh, energyWh, cellName, chemistry
         , manufactureDate, referenceCell ]
cycles = cycleLog ** cell ** reference

-- Retention against the 2.0 Ah rated capacity: 100 / 2.0 is 50 per amp-hour.
withHealth = combine_Op (prim_Op 50.0 *_Op col_Op capacityAh) retention cycles

-- `displayName` distinguishes the two chemistries, so the series legend reads
-- differently for a nickel-rich cell than for an iron-phosphate one.
labelled =
  combine_Op
    (if_Op (col_Op chemistry ==_Pred prim_Op "NMC")
           (col_Op cellName ++_Op prim_Op " (NMC vs " ++_Op col_Op referenceCell ++_Op prim_Op ")")
           (col_Op cellName ++_Op prim_Op " vs " ++_Op col_Op referenceCell))
    displayName
    cycles

-- Rename so the chart's series column is `label` and its x-axis is `startDate`,
-- which is what the charting combinators expect.
chartFeed =
    labelled
 |> rename displayName label
 |> rename testDate startDate

capacityChart =
  timeSeriesChart (Just "Discharge Capacity") (Just (val "Month")) (Just (val "Ah"))
                  line label startDate capacityAh chartFeed

energyChart =
  timeSeriesChart (Just "Discharge Energy") (Just (val "Month")) (Just (val "Wh"))
                  bar label startDate energyWh chartFeed

-- A rename that actually changes the rendered header: `capacityAh` becomes
-- `dischargeAh`, which is what the test report calls it.
detailTable = tabular Nothing (rename capacityAh dischargeAh labelled)

cyclingReport = vflow [
  atomShown "## Battery Cycling",
  capacityChart,
  energyChart,
  atomShown "### Underlying data",
  tabular Nothing labelled
]
