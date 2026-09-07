module Algebra.RateStatistics where

{- FOUR AVERAGES OF THE SAME COLUMN, and why a reporting language needs more
   than one.

   `Relation.Aggregate` holds the aggregates a database can compute
   incrementally -- sum, mean, min, max, stddev, variance. A median cannot be
   computed that way, and neither can a weighted or a harmonic mean without
   carrying a second column, so they live somewhere else entirely:
   `Relation.Process`, whose "aggregates" are opaque PROCESS SYMBOLS the
   backend recognises and evaluates over the whole relation.

   That difference shows in the types. A `Relation.Aggregate` aggregate is an
   `Aggregate r a` applied by `aggregate`; a `Relation.Process` aggregator is
   already a function `rel r -> Mem v`, which is exactly the shape `groupBy`
   wants for its group function. So `groupBy k (medianBy stressMpa)` works and
   needs no adapter -- which is the whole reason `groupMedian` in `Helpers.e`
   is one line.

   Table: runs (13 columns)
            runId, specimenId, labCode, runDate, stressMpa, loadCycles,
            scatterPpm, methodCode, rigType, agingHours, alloyGrade,
            isPreliminary, runSource

   Helpers used: groupMean, groupMedian, groupWeightedMean, groupSum,
            groupTop, alias, joinOnExactly, antiJoin.
   Stdlib exercised: `Relation.Process` -- `medianBy`, `weightedMeanBy`,
            `weightedHarmonicMeanBy` -- which had NO example use at all;
            `Relation.Aggregate.meanBy` / `standardDeviationBy` /
            `varianceBy` / `minBy_A` / `maxBy` for the contrast;
            `Relation.maxRowBy` / `minRowBy`.

   SOLVER SHAPES. Four different group functions with four different
   constraint sets are instantiated against the SAME 13-column row, and the
   four one-column results are then renamed apart and joined back together on
   the key, so the solver sees the same partition solved four ways and then
   has to prove the four results disjoint. `weightedMeanBy` is the only one
   whose group function consumes TWO measure columns, giving `v <- (wt, m, o)`
   -- a three-part partition where two parts are single named fields.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/RateStatistics.e
     >> :import Algebra.RateStatistics
     >> averages
     >> rateReport
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Relation.Process as Proc
import Syntax.Relation
import Algebra.Helpers

field runId, specimenId, agingHours : Int
field labCode, runDate, methodCode, rigType : String
field alloyGrade, isPreliminary, runSource : String
field stressMpa, loadCycles, scatterPpm : Double
field meanStress, medianStress, weightedStress, harmonicScatter : Double
field stressStdDev, totalCycles, stressVar, lowStress, highStress : Double

runs : [ runId, specimenId, labCode, runDate, stressMpa, loadCycles
       , scatterPpm, methodCode, rigType, agingHours, alloyGrade
       , isPreliminary, runSource ]
runs = relation [
  { runId = 1,  specimenId = 9001, labCode = "LAB-A", runDate = "2026-01-20", stressMpa =  99.85, loadCycles = 5000000.0, scatterPpm = 12.0, methodCode = "ISO-6892", rigType = "servo",    agingHours = 60,  alloyGrade = "6061", isPreliminary = "no",  runSource = "witnessed" },
  { runId = 2,  specimenId = 9001, labCode = "LAB-B", runDate = "2026-01-20", stressMpa =  99.90, loadCycles = 1000000.0, scatterPpm = 14.0, methodCode = "ISO-6892", rigType = "servo",    agingHours = 60,  alloyGrade = "6061", isPreliminary = "no",  runSource = "witnessed" },
  { runId = 3,  specimenId = 9001, labCode = "LAB-C", runDate = "2026-01-20", stressMpa = 100.40, loadCycles =  250000.0, scatterPpm = 31.0, methodCode = "ISO-6892", rigType = "resonant", agingHours = 60,  alloyGrade = "6061", isPreliminary = "yes", runSource = "auto" },
  { runId = 4,  specimenId = 9001, labCode = "LAB-D", runDate = "2026-01-20", stressMpa =  97.10, loadCycles =  100000.0, scatterPpm = 55.0, methodCode = "ISO-6892", rigType = "resonant", agingHours = 60,  alloyGrade = "6061", isPreliminary = "yes", runSource = "auto" },
  { runId = 5,  specimenId = 9002, labCode = "LAB-A", runDate = "2026-01-20", stressMpa = 101.20, loadCycles = 3000000.0, scatterPpm =  9.0, methodCode = "ASTM-E8",  rigType = "servo",    agingHours = 24,  alloyGrade = "7075", isPreliminary = "no",  runSource = "witnessed" },
  { runId = 6,  specimenId = 9002, labCode = "LAB-B", runDate = "2026-01-20", stressMpa = 101.35, loadCycles = 2000000.0, scatterPpm = 10.0, methodCode = "ASTM-E8",  rigType = "servo",    agingHours = 24,  alloyGrade = "7075", isPreliminary = "no",  runSource = "witnessed" },
  { runId = 7,  specimenId = 9002, labCode = "LAB-E", runDate = "2026-01-20", stressMpa = 101.30, loadCycles =  500000.0, scatterPpm = 11.0, methodCode = "ASTM-E8",  rigType = "resonant", agingHours = 24,  alloyGrade = "7075", isPreliminary = "no",  runSource = "auto" },
  { runId = 8,  specimenId = 9003, labCode = "LAB-C", runDate = "2026-01-20", stressMpa =  88.60, loadCycles =  750000.0, scatterPpm = 88.0, methodCode = "EN-10002", rigType = "servo",    agingHours = 120, alloyGrade = "2024", isPreliminary = "no",  runSource = "witnessed" },
  { runId = 9,  specimenId = 9003, labCode = "LAB-D", runDate = "2026-01-20", stressMpa =  87.95, loadCycles =  400000.0, scatterPpm = 95.0, methodCode = "EN-10002", rigType = "servo",    agingHours = 120, alloyGrade = "2024", isPreliminary = "yes", runSource = "auto" },
  { runId = 10, specimenId = 9003, labCode = "LAB-E", runDate = "2026-01-20", stressMpa =  90.10, loadCycles =  150000.0, scatterPpm = 74.0, methodCode = "EN-10002", rigType = "resonant", agingHours = 120, alloyGrade = "2024", isPreliminary = "yes", runSource = "auto" },
  { runId = 11, specimenId = 9003, labCode = "LAB-F", runDate = "2026-01-20", stressMpa =  89.20, loadCycles = 1200000.0, scatterPpm = 69.0, methodCode = "EN-10002", rigType = "servo",    agingHours = 120, alloyGrade = "2024", isPreliminary = "no",  runSource = "witnessed" },
  { runId = 12, specimenId = 9004, labCode = "LAB-A", runDate = "2026-01-20", stressMpa = 104.75, loadCycles =  900000.0, scatterPpm = 21.0, methodCode = "ISO-6892", rigType = "servo",    agingHours = 36,  alloyGrade = "6061", isPreliminary = "no",  runSource = "witnessed" }
]

-- ------------------------------------------- four averages, four mechanisms

-- 1. Arithmetic mean: `Relation.Aggregate`, incremental, ignores size.
meanBySpecimen =
  alias stressMpa meanStress (groupMean {specimenId} stressMpa runs)

-- 2. Median: `Relation.Process`. Robust against the two preliminary outliers
-- on specimen 9001, which is exactly why a test house asks for it.
medianBySpecimen =
  alias stressMpa medianStress (groupMedian {specimenId} stressMpa runs)

-- 3. Cycle-weighted mean: `Relation.Process` again, but the group function
-- consumes two columns. The five-million-cycle run should count for more
-- than the hundred-thousand-cycle one, and here it does.
weightedBySpecimen =
  alias stressMpa weightedStress (groupWeightedMean {specimenId} loadCycles stressMpa runs)

-- 4. Weighted HARMONIC mean, which is the right average for a rate or a
-- scatter -- averaging parts per million arithmetically overweights the wide ones.
harmonicScatters =
  alias scatterPpm harmonicScatter
    (groupBy {specimenId} (weightedHarmonicMeanBy_Proc loadCycles scatterPpm) runs)

-- All four side by side. Each is keyed on `specimenId` and carries exactly
-- one measure, so `joinOnExactly` can assert that the key really is the key.
averages =
  joinOnExactly {specimenId} meanBySpecimen medianBySpecimen
  |> joinOnExactly {specimenId} weightedBySpecimen
  |> joinOnExactly {specimenId} harmonicScatters

-- -------------------------------------------- the spread of the spread
--
-- `Relation.Aggregate`'s dispersion aggregates, for the columns where an
-- incremental answer is the right one.
dispersion =
  alias stressMpa stressStdDev (groupBy {specimenId} (standardDeviationBy stressMpa) runs)

cyclesBySpecimen =
  alias loadCycles totalCycles (groupSum {specimenId} loadCycles runs)

stressVariance =
  alias stressMpa stressVar (groupBy {specimenId} (varianceBy stressMpa) runs)

-- `minBy_A` and `maxBy` are `Relation.Aggregate`'s extremes: they give back the
-- VALUE, one column, not the row it came from. `maxRowBy` below is the other
-- one. Both spellings matter, and mixing them up is the usual reason a report
-- shows the right number next to the wrong laboratory.
stressRange =
  joinOnExactly {specimenId}
    (alias stressMpa lowStress  (groupBy {specimenId} (minBy_A stressMpa) runs))
    (alias stressMpa highStress (groupBy {specimenId} (maxBy stressMpa) runs))

-- ------------------------------------------------------- the extreme runs
--
-- `maxRowBy` and `minRowBy` keep the WHOLE row of the extreme, not just the
-- value -- which is what a report needs, because the question is always
-- "and which laboratory was that?".
highestStress = maxRowBy stressMpa (asMem runs)
lowestStress  = minRowBy stressMpa (asMem runs)

-- and the same per specimen, which needs `groupTop` rather than `maxRowBy`
bestPerSpecimen = groupTop {specimenId} {stressMpa} 1 runs

-- --------------------------------------------------------- quality filters
--
-- Final results only; and the RUNS (not specimens -- the anti-join filters
-- the fact table, so the answer is one row per run) on specimens for which
-- nobody reported a final result. Empty in this data: every specimen here has
-- at least one final run, which is what the report caption should say.
finalRuns = filterEq isPreliminary "no" runs
runsOnSpecimensWithNoFinalRun =
  antiJoin {specimenId} (asMem finalRuns) (asMem runs)

finalMedians = alias stressMpa medianStress (groupMedian {specimenId} stressMpa finalRuns)

-- ---------------------------------------------------------------- the report

rateReport = vflow [
  atomShown "## Interlaboratory runs: four averages of one column",
  atomShown "### Mean, median, cycle-weighted mean and weighted harmonic scatter",
  tabular Nothing averages,
  atomShown "### Standard deviation, variance and total cycles",
  tabular Nothing (joinOnExactly {specimenId} dispersion
                     (joinOnExactly {specimenId} stressVariance cyclesBySpecimen)),
  atomShown "### Low and high result per specimen (values, not rows)",
  tabular Nothing stressRange,
  atomShown "### The highest result overall, whole row",
  tabular Nothing highestStress,
  atomShown "### The highest result per specimen",
  tabular Nothing bestPerSpecimen,
  atomShown "### Medians over final runs only",
  tabular Nothing finalMedians,
  atomShown "### Runs on specimens with no final result (empty here, by construction)",
  tabular Nothing runsOnSpecimensWithNoFinalRun
]
