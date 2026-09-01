module Ai.IncidentSeverity where

{- Service incidents bucketed by severity band, with a severity hierarchy
   (critical / major / minor) as the drilldown and a legend
   that fixes column order explicitly.

   Fact:       incidents       (incidentId, serviceId, severityId, downMins, recurrence)
   Dimensions: serviceRegistry (serviceId -> system, region, isCustomerFacing)
               severityDim     (severityId -> severityCode, bandId, parentBandId)

     >> :load core/examples/ai/Common.e
     >> :load core/examples/ai/IncidentSeverity.e
     >> render severityReport
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Ai.Common

field incidentId, serviceId, severityId : Int
field bandId, parentBandId : Int
field system, region, isCustomerFacing, severityCode, severityBand : String
field displayName, impactLabel : String
field downMins, recurrence, lostMinutes : Double
field value : Nullable Double

incidents = relation [
  { incidentId = 1, serviceId = 1, severityId = 1, downMins = 142.0, recurrence = 1.5 },
  { incidentId = 2, serviceId = 2, severityId = 2, downMins =  74.0, recurrence = 2.0 },
  { incidentId = 3, serviceId = 3, severityId = 3, downMins =  38.0, recurrence = 4.0 },
  { incidentId = 4, serviceId = 4, severityId = 4, downMins =  12.0, recurrence = 9.0 },
  { incidentId = 5, serviceId = 5, severityId = 2, downMins =  95.0, recurrence = 1.0 }
]

serviceRegistry = relation [
  { serviceId = 1, system = "Checkout API",  region = "EU", isCustomerFacing = "yes" },
  { serviceId = 2, system = "Batch ETL",     region = "US", isCustomerFacing = "no" },
  { serviceId = 3, system = "Index Builder", region = "AU", isCustomerFacing = "no" },
  { serviceId = 4, system = "Build Runners", region = "US", isCustomerFacing = "no" },
  { serviceId = 5, system = "Media CDN",     region = "DE", isCustomerFacing = "yes" }
]

severityDim = relation [
  { severityId = 1, severityCode = "S1", severityBand = "Critical" },
  { severityId = 2, severityCode = "S2", severityBand = "Critical" },
  { severityId = 3, severityCode = "S3", severityBand = "Major" },
  { severityId = 4, severityCode = "S4", severityBand = "Minor" }
]

feed : [ incidentId, serviceId, severityId, downMins, recurrence
       , system, region, isCustomerFacing, severityCode, severityBand ]
feed = incidents ** serviceRegistry ** severityDim

-- Expected minutes lost is downtime times the expected recurrences per year.
withEM = combine_Op (col_Op downMins *_Op col_Op recurrence) lostMinutes feed

-- Customer-facing systems are shown with the region they serve, because the
-- user impact depends on where the outage lands; internal ones show severity.
labelled =
  withColumn (if_Op (col_Op isCustomerFacing ==_Pred prim_Op "yes")
                    (col_Op system ++_Op prim_Op " [" ++_Op col_Op region ++_Op prim_Op " edge]")
                    (col_Op system ++_Op prim_Op " (" ++_Op col_Op severityCode ++_Op prim_Op ")"))
             displayName
             feed

renamed = rename severityBand impactLabel labelled

-- A legend that pins column order: system first, then severity, then minutes.
feedLegend : Legend_Lg (| system, severityCode, downMins |)
feedLegend = [ (system,       "Service")  ^ 0
             , (severityCode, "Severity") ^ 1
             , (downMins,     "Minutes")  ^ 2 ]_Sorted_Lg

feedTable = tabular (Just feedLegend) (feed # { system, severityCode, downMins })

-- Severity hierarchy for the drilldown.
bandTree : [ bandId, parentBandId, severityCode ]
bandTree = relation [
  { bandId = 1,  parentBandId = 0, severityCode = "Total Incidents" },
  { bandId = 10, parentBandId = 1, severityCode = "Critical" },
  { bandId = 11, parentBandId = 10, severityCode = "S1" },
  { bandId = 12, parentBandId = 10, severityCode = "S2" },
  { bandId = 20, parentBandId = 1, severityCode = "Major" },
  { bandId = 21, parentBandId = 20, severityCode = "S3" },
  { bandId = 30, parentBandId = 1, severityCode = "Minor" },
  { bandId = 31, parentBandId = 30, severityCode = "S4" }
]

sevBandTree = treeTable severityCode parentBandId bandId bandTree

downtimeChart =
  chart_K ([chartTitle_O := "Minutes Down by Severity", yDirection_O := Horizontal]_Opt)
          defaultUnscaled defaultScaled
          [bar severityBand severityCode downMins feed]

stackedByBand =
  chart_K ([chartTitle_O := "Minutes Down by Band"]_Opt)
          defaultUnscaled defaultScaled
          [stackedBar severityBand severityCode downMins feed]

severityReport = vflow [
  atomShown "## Incident Severity",
  valueGrid [ ("Incidents", atomShown "5")
            , ("Services", atomShown "5")
            , ("Bands", atomShown "Critical / Major / Minor") ],
  downtimeChart,
  stackedByBand,
  collapsible False "Severity hierarchy" sevBandTree,
  atomShown "### Incidents",
  feedTable,
  tabular Nothing renamed
]
