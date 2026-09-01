module Ai.TelescopeTime where

{- A classic star schema: one fact table of observing slots, three dimension
   tables, and a grouping hierarchy laid over the result.

   Fact:       obsSlots   (targetId, slotId, obsHours, overheadRatio)
   Dimensions: skyTargets (targetId -> name, catalogueId, targetKind, programmeId)
               setups     (targetId -> bandCode)
               programme  (programmeId -> programmeName, parentProgrammeId)

   The leaves of the drilldown are HETEROGENEOUS: a bright star, a nearby
   galaxy and a solar-system body all appear side by side, so `displayName`
   is computed with a conditional Op rather than taken from any one column.

   From the REPL:
     >> :load core/examples/ai/TelescopeTime.e
     >> render allocationReport
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Ai.Common

field targetId, programmeId, slotId : Int
field parentProgrammeId : Int
field targetName, catalogueId, targetKind, programmeName : String
field bandCode, displayName, longLabel : String
field obsHours, overheadRatio, chargedHours : Double
field value : Nullable Double

-- ---------------------------------------------------------------- fact table

obsSlots = relation [
  { targetId = 1, slotId = 101, obsHours = 6.5,  overheadRatio = 1.12 },
  { targetId = 2, slotId = 102, obsHours = 4.0,  overheadRatio = 1.08 },
  { targetId = 3, slotId = 103, obsHours = 9.25, overheadRatio = 1.21 },
  { targetId = 4, slotId = 104, obsHours = 7.5,  overheadRatio = 1.15 },
  { targetId = 5, slotId = 105, obsHours = 1.0,  overheadRatio = 1.30 }
]

-- ----------------------------------------------------------- dimension tables

skyTargets = relation [
  { targetId = 1, targetName = "Barnard's Star",
    catalogueId = "GJ 699",   targetKind = "Star",   programmeId = 10 },
  { targetId = 2, targetName = "Betelgeuse",
    catalogueId = "HD 39801", targetKind = "Star",   programmeId = 10 },
  { targetId = 3, targetName = "Andromeda Galaxy",
    catalogueId = "M31",      targetKind = "Galaxy", programmeId = 20 },
  { targetId = 4, targetName = "Whirlpool Galaxy",
    catalogueId = "M51",      targetKind = "Galaxy", programmeId = 20 },
  { targetId = 5, targetName = "Neptune",
    catalogueId = "899",      targetKind = "Planet", programmeId = 30 }
]

programme = relation [
  { programmeId = 10, programmeName = "Stellar Physics" },
  { programmeId = 20, programmeName = "Nearby Galaxies" },
  { programmeId = 30, programmeName = "Solar System" }
]

setups = relation [
  { targetId = 1, bandCode = "K" },
  { targetId = 2, bandCode = "K" },
  { targetId = 3, bandCode = "R" },
  { targetId = 4, bandCode = "R" },
  { targetId = 5, bandCode = "J" }
]

-- ------------------------------------------------------- the star-schema join

-- Annotating the fully-joined shape keeps inference off the slow path;
-- see tracker/TICKET-row-constraint-decision.md for why that matters.
enriched : [ targetId, slotId, obsHours, overheadRatio, targetName, catalogueId
           , targetKind, programmeId, programmeName, bandCode ]
enriched = obsSlots ** skyTargets ** setups ** programme

-- ------------------------------------------------- computed display columns

-- Charged time is observed hours times the overhead ratio, as a derived column.
withHours = combine_Op (col_Op obsHours *_Op col_Op overheadRatio) chargedHours enriched

-- `displayName` is where the heterogeneity is handled: stars are shown by
-- catalogue id, galaxies by their full name, and anything else by kind and
-- band. Nested conditionals are the point -- each `if_Op` is a row constraint.
labelled =
  combine_Op
    (if_Op (col_Op targetKind ==_Pred prim_Op "Star")
           (col_Op catalogueId)
           (if_Op (col_Op targetKind ==_Pred prim_Op "Galaxy")
                  (col_Op targetName)
                  (col_Op targetKind ++_Op prim_Op " (" ++_Op col_Op bandCode ++_Op prim_Op ")")))
    displayName
    enriched

-- A rename, so the report column reads differently from the source column.
relabelled = rename targetName longLabel labelled

-- ------------------------------------------------------- grouping hierarchy

-- Total -> programme -> target. Leaf rows are the heterogeneous items.
hierarchy = relation [
  { programmeId = 1,  parentProgrammeId = 0,  programmeName = "Total Allocation", value = Some 100.0 },
  { programmeId = 10, parentProgrammeId = 1,  programmeName = "Stellar Physics",  value = Some  40.0 },
  { programmeId = 11, parentProgrammeId = 10, programmeName = "GJ 699",           value = Some  15.0 },
  { programmeId = 12, parentProgrammeId = 10, programmeName = "HD 39801",         value = Some  25.0 },
  { programmeId = 20, parentProgrammeId = 1,  programmeName = "Nearby Galaxies",  value = Some  50.0 },
  { programmeId = 21, parentProgrammeId = 20, programmeName = "Andromeda Galaxy", value = Some  30.0 },
  { programmeId = 22, parentProgrammeId = 20, programmeName = "Whirlpool Galaxy", value = Some  20.0 },
  { programmeId = 30, parentProgrammeId = 1,  programmeName = "Solar System",     value = Some  10.0 }
]

-- --------------------------------------------------------------- the widgets

slotTable = tabular Nothing relabelled

targetsTree = treeTable programmeName parentProgrammeId programmeId hierarchy

allocationPie =
  pieChart_K
    ([pieTitle_O := "Share of Allocated Time by Programme",
      pieDrilldown_O := (parentProgrammeId, programmeId)]_Opt)
    programmeName value hierarchy

summaryGrid = grid [
  [atomShown "Slots",        atomShown "5"],
  [atomShown "Programmes",   atomShown "3"],
  [atomShown "Target kinds", atomShown "Star / Galaxy / Planet"]
]

allocationReport = vflow [
  atomShown "## Telescope Time Allocation",
  summaryGrid,
  atomShown "### Share of time",
  allocationPie,
  targetsTree,
  atomShown "### Detail",
  slotTable
]
