module Ai.GridTelemetry where

{- Electricity-grid telemetry, where the date-range tree goes all the way down
   to DAYS and the readings are heterogeneous: a feeder reports load in MW, a
   transformer reports temperature in Celsius, and a meter reports a status
   string. The unit is therefore part of the display label, not a column the
   reader can interpret on its own.

   Fact:       readings (assetId, dateRangeId, metricKind, reading)
   Dimensions: asset    (assetId -> assetName, assetType, substationId)
               calendar (dateRangeId -> parentDateRangeId, periodKind,
                                        periodShort, fiscalYear)
   Hierarchy:  substation tree over gridNodeId / parentGridNodeId

     >> :load core/examples/ai/Common.e
     >> :load core/examples/ai/GridTelemetry.e
     >> render telemetryReport
-}

import Prelude
import Layout
import Layout.Legend as Lg
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Ai.Common

field assetId, substationId : Int
field dateRangeId, parentDateRangeId : Int
field gridNodeId, parentGridNodeId : Int
field assetName, assetType, metricKind, substationName : String
field periodKind, periodShort, fiscalYear, periodName : String
field displayName, feederLabel : String
field reading : Double
field value : Nullable Double

-- A day-level calendar: one month subdivided into days.
calendar : [ dateRangeId, parentDateRangeId, periodKind, periodShort, fiscalYear ]
calendar = relation [
  { dateRangeId = 2011,     parentDateRangeId = 0,      periodKind = "Year",    periodShort = "FY",  fiscalYear = "2011" },
  { dateRangeId = 20111,    parentDateRangeId = 2011,   periodKind = "Quarter", periodShort = "Q1",  fiscalYear = "2011" },
  { dateRangeId = 201101,   parentDateRangeId = 20111,  periodKind = "Month",   periodShort = "Jan", fiscalYear = "2011" },
  { dateRangeId = 20110101, parentDateRangeId = 201101, periodKind = "Day",     periodShort = "1",   fiscalYear = "2011" },
  { dateRangeId = 20110102, parentDateRangeId = 201101, periodKind = "Day",     periodShort = "2",   fiscalYear = "2011" },
  { dateRangeId = 20110103, parentDateRangeId = 201101, periodKind = "Day",     periodShort = "3",   fiscalYear = "2011" },
  { dateRangeId = 20110104, parentDateRangeId = 201101, periodKind = "Day",     periodShort = "4",   fiscalYear = "2011" }
]

readings : [ assetId, dateRangeId, metricKind, reading ]
readings = relation [
  { assetId = 1, dateRangeId = 20110101, metricKind = "load",        reading =  42.7 },
  { assetId = 1, dateRangeId = 20110102, metricKind = "load",        reading =  45.1 },
  { assetId = 1, dateRangeId = 20110103, metricKind = "load",        reading =  39.8 },
  { assetId = 2, dateRangeId = 20110101, metricKind = "temperature", reading =  63.0 },
  { assetId = 2, dateRangeId = 20110102, metricKind = "temperature", reading =  71.5 },
  { assetId = 3, dateRangeId = 20110103, metricKind = "status",      reading =   1.0 },
  { assetId = 3, dateRangeId = 20110104, metricKind = "status",      reading =   0.0 }
]

assetDim = relation [
  { assetId = 1, assetName = "Feeder 11A",      assetType = "feeder",      substationId = 10 },
  { assetId = 2, assetName = "Transformer T3",  assetType = "transformer", substationId = 10 },
  { assetId = 3, assetName = "Meter M-4471",    assetType = "meter",       substationId = 20 }
]

substationDim = relation [
  { substationId = 10, substationName = "Eastfield" },
  { substationId = 20, substationName = "Kirkhill" }
]

-- Star join, with the day rows of the calendar as the time dimension.
telemetry : [ assetId, dateRangeId, metricKind, reading, assetName, assetType
            , substationId, substationName, parentDateRangeId, periodKind
            , periodShort, fiscalYear ]
telemetry = readings ** assetDim ** substationDim
                     ** nodesOfKind periodKind "Day" calendar

-- Three-way label: the unit belongs to the metric, so it goes in the label.
labelled =
  withColumn (if_Op (col_Op metricKind ==_Pred prim_Op "load")
                    (col_Op assetName ++_Op prim_Op " (MW)")
                    (if_Op (col_Op metricKind ==_Pred prim_Op "temperature")
                           (col_Op assetName ++_Op prim_Op " (deg C)")
                           (col_Op assetName ++_Op prim_Op " (status)")))
             displayName
             telemetry

renamed = rename assetName feederLabel labelled

labelledCalendar =
  withColumn (if_Op (col_Op periodKind ==_Pred prim_Op "Year")
                    (prim_Op "FY" ++_Op col_Op fiscalYear)
                    (col_Op periodShort ++_Op prim_Op " " ++_Op col_Op fiscalYear))
             periodName
             calendar

calendarTree = treeTable periodShort parentDateRangeId dateRangeId calendar

-- The substation hierarchy.
substationTree : [ gridNodeId, parentGridNodeId, substationName ]
substationTree = relation [
  { gridNodeId = 1,  parentGridNodeId = 0, substationName = "Network" },
  { gridNodeId = 10, parentGridNodeId = 1, substationName = "Eastfield" },
  { gridNodeId = 20, parentGridNodeId = 1, substationName = "Kirkhill" }
]

networkTree = treeTable substationName parentGridNodeId gridNodeId substationTree

loadChart =
  chart_K ([chartTitle_O := "Daily readings"]_Opt)
          defaultUnscaled defaultScaled
          [line assetName periodShort reading telemetry]

telemetryReport = vflow [
  atomShown "## Grid Telemetry",
  atomShown "### Calendar, down to days",
  calendarTree,
  tabular Nothing labelledCalendar,
  atomShown "### Substations",
  networkTree,
  atomShown "### Readings (heterogeneous metrics)",
  loadChart,
  tabular Nothing renamed
]
