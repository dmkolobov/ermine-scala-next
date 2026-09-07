module Time.SensorSeries where

{- A SENSOR SERIES WITH GAPS, filled forward across a dense calendar, with a
   rolling z-score flagging the outliers.

   Fact:      readings  (16 fields: readingId, sensorId, sensorName, site,
                         region, assetType, unitOfMeasure, quality, firmware,
                         technician, alarmState, readingDate, calibrationDate,
                         reading (NULLABLE), batteryPct, latitudeBand)
   Calendar:  days      (calDate, dayName, isBusinessDay)

   The four sensors do NOT report on the same days. `sensorId` is an `Int`, and
   sensor 102 reports on 1, 2, 7 and 10 June -- a FOUR-day hole (3, 4, 5, 6) in
   the middle of the window; sensor 104 reports on 3, 6 and 8 June and then stops
   entirely. Under the stdlib's own `lookupLatest`, which groups by the date
   alone, sensor 104 would vanish from every day after the 8th because some OTHER
   sensor reported later.
   `fillForward` (built on `Helpers.nearestBy`) groups by the key as well, so
   `S-104`'s last reading is carried forward -- which is what "last known value"
   means and is the entire point of the report.

   SHAPES EXERCISED
     * `fillForward` -- the (key x day) spine and a per-key as-of over it. The
       widest residual chain in this directory: a 16-column observation relation
       crossed with a 3-column calendar.
     * `movingMean` / `movingStdDev` -- framed window aggregates partitioned by
       sensor and ordered by the calendar date.
     * `orZero` on the nullable reading, then `safeDiv` for the z-score --
       a rolling standard deviation is zero on a flat run, and a report that
       divides by it without a guard prints NaN.
     * `band3` on the z-score.
     * `Vector` and `Math` at the value level, and the limit that goes with
       them (see `sortedSpread` below).

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/SensorSeries.e
     >> sensorReport

   NOTE ON `render`. `render` is not a defined term anywhere in Ermine -- not in
   the stdlib, not in the REPL. A report can only be RENDERED through
   `Layout.harness`, which needs a `Scanner` and a `Runner`, and every
   constructor of both is a database connection. So from `bin/ermine` you
   EVALUATE the report (and any relation in the module), which prints its
   resolved header -- the column set the report will show. See
   `tracker/loopmodel/E3-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Math as M
import Vector as V
import List.Util as LU
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field readingId, sensorId, batteryPct : Int
field sensorName, site, region, assetType, unitOfMeasure : String
field quality, firmware, technician, alarmState, latitudeBand : String
field readingDate, calibrationDate, calDate : Date
field reading : Nullable Double
field dayName, isBusinessDay : String
field readingVal, rollingMean, rollingSd, devFromMean, zScore, rmsRatio : Double
field outlierBand : String

-- ------------------------------------------------------------- the fact table

-- Sixteen columns. `reading` is null on the two readings whose `quality` is
-- "Suspect": the logger recorded that it took a sample and that the sample was
-- not usable, which is different from not sampling at all.
readings : [ readingId, sensorId, sensorName, site, region, assetType
           , unitOfMeasure, quality, firmware, technician, alarmState
           , readingDate, calibrationDate, reading, batteryPct, latitudeBand ]
readings = relation [
  { readingId = 1, sensorId = 101, sensorName = "Feeder A phase current",
    site = "Ravensbourne", region = "South", assetType = "Feeder",
    unitOfMeasure = "A", quality = "Good", firmware = "3.4.1",
    technician = "r.mensah", alarmState = "Clear", readingDate = @2011/6/1,
    calibrationDate = @2011/1/14, reading = Some 412.5, batteryPct = 97,
    latitudeBand = "Temperate" },
  { readingId = 2, sensorId = 101, sensorName = "Feeder A phase current",
    site = "Ravensbourne", region = "South", assetType = "Feeder",
    unitOfMeasure = "A", quality = "Good", firmware = "3.4.1",
    technician = "r.mensah", alarmState = "Clear", readingDate = @2011/6/3,
    calibrationDate = @2011/1/14, reading = Some 418.9, batteryPct = 96,
    latitudeBand = "Temperate" },
  { readingId = 3, sensorId = 101, sensorName = "Feeder A phase current",
    site = "Ravensbourne", region = "South", assetType = "Feeder",
    unitOfMeasure = "A", quality = "Good", firmware = "3.4.1",
    technician = "r.mensah", alarmState = "Clear", readingDate = @2011/6/6,
    calibrationDate = @2011/1/14, reading = Some 940.2, batteryPct = 95,
    latitudeBand = "Temperate" },
  { readingId = 4, sensorId = 101, sensorName = "Feeder A phase current",
    site = "Ravensbourne", region = "South", assetType = "Feeder",
    unitOfMeasure = "A", quality = "Good", firmware = "3.4.2",
    technician = "r.mensah", alarmState = "Clear", readingDate = @2011/6/9,
    calibrationDate = @2011/1/14, reading = Some 421.0, batteryPct = 94,
    latitudeBand = "Temperate" },
  { readingId = 5, sensorId = 102, sensorName = "Transformer T2 oil temp",
    site = "Ravensbourne", region = "South", assetType = "Transformer",
    unitOfMeasure = "degC", quality = "Good", firmware = "2.9.0",
    technician = "l.varga", alarmState = "Clear", readingDate = @2011/6/1,
    calibrationDate = @2010/11/2, reading = Some 63.4, batteryPct = 88,
    latitudeBand = "Temperate" },
  { readingId = 6, sensorId = 102, sensorName = "Transformer T2 oil temp",
    site = "Ravensbourne", region = "South", assetType = "Transformer",
    unitOfMeasure = "degC", quality = "Suspect", firmware = "2.9.0",
    technician = "l.varga", alarmState = "Clear", readingDate = @2011/6/2,
    calibrationDate = @2010/11/2, reading = Null Double, batteryPct = 88,
    latitudeBand = "Temperate" },
  { readingId = 7, sensorId = 102, sensorName = "Transformer T2 oil temp",
    site = "Ravensbourne", region = "South", assetType = "Transformer",
    unitOfMeasure = "degC", quality = "Good", firmware = "2.9.0",
    technician = "l.varga", alarmState = "Warning", readingDate = @2011/6/7,
    calibrationDate = @2010/11/2, reading = Some 71.8, batteryPct = 86,
    latitudeBand = "Temperate" },
  { readingId = 8, sensorId = 102, sensorName = "Transformer T2 oil temp",
    site = "Ravensbourne", region = "South", assetType = "Transformer",
    unitOfMeasure = "degC", quality = "Good", firmware = "2.9.0",
    technician = "l.varga", alarmState = "Alarm", readingDate = @2011/6/10,
    calibrationDate = @2010/11/2, reading = Some 92.6, batteryPct = 85,
    latitudeBand = "Temperate" },
  { readingId = 9, sensorId = 103, sensorName = "Substation busbar voltage",
    site = "Kilnhurst", region = "North", assetType = "Busbar",
    unitOfMeasure = "kV", quality = "Good", firmware = "4.0.7",
    technician = "d.okonkwo", alarmState = "Clear", readingDate = @2011/6/2,
    calibrationDate = @2011/3/21, reading = Some 33.1, batteryPct = 99,
    latitudeBand = "Temperate" },
  { readingId = 10, sensorId = 103, sensorName = "Substation busbar voltage",
    site = "Kilnhurst", region = "North", assetType = "Busbar",
    unitOfMeasure = "kV", quality = "Good", firmware = "4.0.7",
    technician = "d.okonkwo", alarmState = "Clear", readingDate = @2011/6/5,
    calibrationDate = @2011/3/21, reading = Some 33.4, batteryPct = 99,
    latitudeBand = "Temperate" },
  { readingId = 11, sensorId = 103, sensorName = "Substation busbar voltage",
    site = "Kilnhurst", region = "North", assetType = "Busbar",
    unitOfMeasure = "kV", quality = "Good", firmware = "4.0.7",
    technician = "d.okonkwo", alarmState = "Clear", readingDate = @2011/6/8,
    calibrationDate = @2011/3/21, reading = Some 32.9, batteryPct = 98,
    latitudeBand = "Temperate" },
  { readingId = 12, sensorId = 103, sensorName = "Substation busbar voltage",
    site = "Kilnhurst", region = "North", assetType = "Busbar",
    unitOfMeasure = "kV", quality = "Good", firmware = "4.0.7",
    technician = "d.okonkwo", alarmState = "Clear", readingDate = @2011/6/11,
    calibrationDate = @2011/3/21, reading = Some 33.2, batteryPct = 98,
    latitudeBand = "Temperate" },
  { readingId = 13, sensorId = 104, sensorName = "Wind farm nacelle vibration",
    site = "Carrickmore", region = "West", assetType = "Turbine",
    unitOfMeasure = "mm/s", quality = "Good", firmware = "1.2.9",
    technician = "b.ferreira", alarmState = "Clear", readingDate = @2011/6/3,
    calibrationDate = @2011/5/6, reading = Some 2.4, batteryPct = 74,
    latitudeBand = "Maritime" },
  { readingId = 14, sensorId = 104, sensorName = "Wind farm nacelle vibration",
    site = "Carrickmore", region = "West", assetType = "Turbine",
    unitOfMeasure = "mm/s", quality = "Good", firmware = "1.2.9",
    technician = "b.ferreira", alarmState = "Clear", readingDate = @2011/6/6,
    calibrationDate = @2011/5/6, reading = Some 2.6, batteryPct = 71,
    latitudeBand = "Maritime" },
  { readingId = 15, sensorId = 104, sensorName = "Wind farm nacelle vibration",
    site = "Carrickmore", region = "West", assetType = "Turbine",
    unitOfMeasure = "mm/s", quality = "Suspect", firmware = "1.2.9",
    technician = "b.ferreira", alarmState = "Warning", readingDate = @2011/6/8,
    calibrationDate = @2011/5/6, reading = Null Double, batteryPct = 68,
    latitudeBand = "Maritime" }
]

-- ---------------------------------------------------------- the day calendar

-- A DENSE spine: eleven consecutive days, whether or not anything reported.
-- (Named `dayGrid`, not `days`: `Date.days` is the `TimeUnit`, and Ermine
-- refuses a top-level definition that would shadow a global one.)
dayGrid : [ calDate, dayName, isBusinessDay ]
dayGrid = relation [
  { calDate = @2011/6/1,  dayName = "Wed", isBusinessDay = "Y" },
  { calDate = @2011/6/2,  dayName = "Thu", isBusinessDay = "Y" },
  { calDate = @2011/6/3,  dayName = "Fri", isBusinessDay = "Y" },
  { calDate = @2011/6/4,  dayName = "Sat", isBusinessDay = "N" },
  { calDate = @2011/6/5,  dayName = "Sun", isBusinessDay = "N" },
  { calDate = @2011/6/6,  dayName = "Mon", isBusinessDay = "Y" },
  { calDate = @2011/6/7,  dayName = "Tue", isBusinessDay = "Y" },
  { calDate = @2011/6/8,  dayName = "Wed", isBusinessDay = "Y" },
  { calDate = @2011/6/9,  dayName = "Thu", isBusinessDay = "Y" },
  { calDate = @2011/6/10, dayName = "Fri", isBusinessDay = "Y" },
  { calDate = @2011/6/11, dayName = "Sat", isBusinessDay = "N" }
]

-- ================================================================ the pipeline

-- STEP 1. THE GRID. Every sensor gets a row on every day from its first
-- reading onwards, carrying its last known reading. 16 columns in, 19 out --
-- and the row count goes from 15 observations to one per (sensor, day).
filled = fillForward {sensorId} readingDate readings calDate dayGrid

-- STEP 2. A non-null numeric column to do arithmetic on. The two suspect
-- readings are nulls; `orZero` says explicitly that a suspect reading counts as
-- zero for the rolling statistics, which is a decision and not a default.
valued = combine_Op (orZero reading) readingVal filled

-- STEP 3. Rolling mean and standard deviation over a four-row trailing window,
-- PARTITIONED BY SENSOR and ordered by the calendar date.
rolled =
     valued
  |> combine_Op (movingMean {sensorId} calDate readingVal 3) rollingMean
  |> combine_Op (movingStdDev {sensorId} calDate readingVal 3) rollingSd

-- STEP 4. The z-score, guarded. A sensor that has repeated the same carried
-- value for four days has a rolling standard deviation of exactly zero, and
-- `deviation / 0` is where an unguarded report prints NaN or dies.
sensorScored =
     rolled
  |> combine_Op (col_Op readingVal -_Op col_Op rollingMean) devFromMean
  |> combine_Op (safeDiv devFromMean rollingSd) zScore
  |> combine_Op (band3 zScore (0.0 - 1.5) "Low" 1.5 "Normal" "High")
                outlierBand

-- The outliers alone.
outliers = filterNEq outlierBand "Normal" sensorScored

-- ------------------------------------------------------------ data quality

suspect  = missing reading readings          -- readings that were taken and are unusable
usable   = present reading readings          -- the rest

-- Days on which a given sensor had no reading of its own: the grid minus the
-- observations. This is what `fillForward` filled in.
gapDays = difference (sensorScored # {sensorId, calDate})
                     (rename readingDate calDate (readings # {sensorId, readingDate}))

-- ---------------------------------------- what Vector and Math can and cannot do

{- `Vector` is a Scala `Vector` reachable from Ermine VALUES; `Math` likewise
   works on `Double`s. Neither can be applied to a COLUMN: there is no way to
   lift an Ermine function into an `Op`, so a statistic that is not among
   `Relation.Aggregate`'s eight and `Relation.Op`'s arithmetic cannot become a
   column of a relation at all.

   What they CAN do is compute over a list the program already holds. The
   thresholds below are an ordinary Ermine value, sorted with `Vector.sort`,
   reduced with `Vector.foldl`, and the median taken with `List.Util.median`;
   the result is a `Double` and `prim_Op` puts it into a query as a literal.
   That is the whole of the interoperation, and it is worth knowing before
   planning a report around a statistic Ermine does not have. Recorded in
   E3-EXAMPLES.md. -}

alarmThresholds : List Double
alarmThresholds = [ 92.6, 33.4, 2.6, 940.2, 71.8 ]

sortedThresholds : Vector_V Double
sortedThresholds = sort_V numOrd (vector_V alarmThresholds)

-- The spread of the thresholds: max minus min, via a Vector fold.
sortedSpread : Double
sortedSpread = at_V (length_V sortedThresholds - 1) sortedThresholds
             - at_V 0 sortedThresholds

-- The median of the same list -- `List.Util.median`, which no example used.
thresholdMedian : Maybe Double
thresholdMedian = median_LU alarmThresholds

-- Root-mean-square of the thresholds, folded by hand because there is no
-- aggregate for it: `Vector.foldl` plus `Math.sqrt`.
thresholdRms : Double
thresholdRms =
  sqrt_M (foldl_V (acc x -> acc + x * x) 0.0 sortedThresholds
          / toDouble (length_V sortedThresholds))

-- and injected into a query as a constant column.
-- (a DIFFERENT quantity from `devFromMean` above, and therefore a different
-- column: one field name, one meaning, is the rule this module follows.)
withRms = combine_Op (col_Op readingVal /_Op prim_Op thresholdRms) rmsRatio valued

-- ------------------------------------------------------------------- report

sensorReport = vflow [
  atomShown "## Sensor series, 1-11 June 2011",
  atomShown "### Raw observations (15 rows, four sensors, irregular days)",
  tabular Nothing (readings # {readingId, sensorId, sensorName, readingDate,
                               reading, quality, alarmState}),
  atomShown "### Filled forward onto the day grid, with rolling statistics",
  tabular Nothing (sensorScored # {sensorId, calDate, readingDate, readingVal,
                             rollingMean, rollingSd, zScore, outlierBand}),
  atomShown "### Outliers",
  tabular Nothing (outliers # {sensorId, sensorName, calDate, readingVal,
                               zScore, outlierBand}),
  atomShown "### Suspect readings (recorded, unusable)",
  tabular Nothing (suspect # {readingId, sensorId, readingDate, quality}),
  atomShown "### Days that had to be filled",
  tabular Nothing gapDays
]
