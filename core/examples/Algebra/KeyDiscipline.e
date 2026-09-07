module Algebra.KeyDiscipline where

{- SAYING WHICH KEY YOU MEANT: the four join spellings, and what each one
   catches.

   Ermine's `join` takes the intersection of the two headers as its key and
   says nothing about it. Every bug that follows is the same bug -- the
   intersection was not what the author thought -- and the stdlib offers three
   ways to write the assumption down so the type checker can disagree:

     join            no assertion. A shared column you forgot about silently
                     becomes part of the key; a column you expected to share
                     and do not turns the join into a cartesian product.
     join1  f        `f` is the WHOLE key -- see the note at spelling 4; the
                     documentation says "the intersection is nonempty" but the
                     constraints say more than that.
     joinBy  {k}     the key is EXACTLY `{k}`. Rules out both.
     joinBy' {kh}    the key CONTAINS `{kh}`; the rest is inferred. The middle
                     ground, and the one to reach for when a compound key has
                     a part that varies between call sites.

   All four are the same function at run time. The difference is entirely in
   what the solver is asked to prove, which is the point.

   Tables: readings     (12 columns: stationId, sensorId, readingDate + 9 more)
           calibrations (7 columns:  sensorId, readingDate, calibSource + 4 more)
           sensors      (5 columns:  sensorId + 4 more)

   Helpers used: joinOn1, joinOnExactly, joinOnAtLeast, carry, overwriteWith,
                 semiJoin, groupSum.
   Stdlib exercised: `Relation.join1`, `Relation.joinBy`, `Relation.joinBy'`,
                 `Relation.copyColumn`, `Relation.replaceColumn`,
                 `Relation.rename'`, `Relation.memoRelWithPK`,
                 `Relation.letRWithPK`, `Relation.materializeWithPK`,
                 `Relation.materialize` -- of which only `materialize` had an
                 example use.

   SOLVER SHAPES. `joinBy'` is the only stdlib signature that SPLITS a key
   into a named head and an inferred tail (`r1 <- (kh, kt, t1)`), so `kt` is
   determined by nothing but the intersection of two concrete headers -- the
   solver has to compute a set difference to find it. `memoRelWithPK` and
   `letRWithPK` carry a `Row` witness that must be proved a subset of the
   relation's header (`Has r k`) while the relation itself is passed to a
   FUNCTION, which is the higher-order case of the same constraint.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/KeyDiscipline.e
     >> :import Algebra.KeyDiscipline
     >> valued
     >> keyReport
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Algebra.Helpers

field stationId, sensorId, sampleId, latencyDays : Int
field readingDate, calibSource, sensorName, sensorClass : String
field siteType, siteCountry, unitCode, networkCode, channelName : String
field streamCode, isFlagged, calibQuality, serialCode : String
field rawCount, baseGain, fullGain, gainDrift, scaleToSi : Double
field scaledValue, siValue, sharePct : Double
field loggedDate : String

readings : [ stationId, sensorId, readingDate, sampleId, rawCount
           , networkCode, channelName, streamCode, isFlagged, latencyDays
           , unitCode, scaleToSi ]
readings = relation [
  { stationId = 100, sensorId = 9001, readingDate = "2026-01-20", sampleId = 1, rawCount =  50000.0, networkCode = "NORD", channelName = "hhz",   streamCode = "S1", isFlagged = "no",  latencyDays = 2, unitCode = "nm/s", scaleToSi = 1.0000 },
  { stationId = 100, sensorId = 9002, readingDate = "2026-01-20", sampleId = 2, rawCount =  30000.0, networkCode = "NORD", channelName = "hhz",   streamCode = "S1", isFlagged = "no",  latencyDays = 2, unitCode = "um/s", scaleToSi = 0.9210 },
  { stationId = 100, sensorId = 9003, readingDate = "2026-01-20", sampleId = 3, rawCount =  12000.0, networkCode = "ALPS", channelName = "hhn",   streamCode = "S2", isFlagged = "yes", latencyDays = 3, unitCode = "nm/s", scaleToSi = 1.0000 },
  { stationId = 200, sensorId = 9001, readingDate = "2026-01-20", sampleId = 4, rawCount =  80000.0, networkCode = "NORD", channelName = "hhz",   streamCode = "S3", isFlagged = "no",  latencyDays = 2, unitCode = "nm/s", scaleToSi = 1.0000 },
  { stationId = 200, sensorId = 9004, readingDate = "2026-01-20", sampleId = 5, rawCount =   5000.0, networkCode = "ALPS", channelName = "hhe",   streamCode = "S3", isFlagged = "no",  latencyDays = 1, unitCode = "mm/s", scaleToSi = 1.1740 },
  { stationId = 300, sensorId = 9002, readingDate = "2026-01-20", sampleId = 6, rawCount = 110000.0, networkCode = "NORD", channelName = "hhz",   streamCode = "S4", isFlagged = "no",  latencyDays = 2, unitCode = "um/s", scaleToSi = 0.9210 }
]

calibrations : [ sensorId, readingDate, baseGain, fullGain, gainDrift
               , calibSource, calibQuality ]
calibrations = relation [
  { sensorId = 9001, readingDate = "2026-01-20", baseGain =  99.88, fullGain = 101.02, gainDrift = 1.14, calibSource = "onsite",  calibQuality = "good" },
  { sensorId = 9002, readingDate = "2026-01-20", baseGain = 101.28, fullGain = 101.28, gainDrift = 0.00, calibSource = "factory", calibQuality = "good" },
  { sensorId = 9003, readingDate = "2026-01-20", baseGain =  88.95, fullGain =  90.31, gainDrift = 1.36, calibSource = "field",   calibQuality = "stale" },
  { sensorId = 9004, readingDate = "2026-01-20", baseGain = 104.75, fullGain = 104.75, gainDrift = 0.00, calibSource = "factory", calibQuality = "good" }
]

sensors : [ sensorId, sensorName, sensorClass, siteType
          , siteCountry ]
sensors = relation [
  { sensorId = 9001, sensorName = "Aurora BB-2031", sensorClass = "broadband", siteType = "vault",    siteCountry = "DE" },
  { sensorId = 9002, sensorName = "Basalt BB-4028", sensorClass = "broadband", siteType = "borehole", siteCountry = "US" },
  { sensorId = 9003, sensorName = "Cinder BB-6236", sensorClass = "broadband", siteType = "surface",  siteCountry = "NL" },
  { sensorId = 9004, sensorName = "Delta BB-3129",  sensorClass = "broadband", siteType = "borehole", siteCountry = "GB" }
]

-- ------------------------------------------------------- the four spellings
--
-- Readings and calibrations share TWO columns, `sensorId` and `readingDate`.
-- All four of these compute the same rows; they differ in what they promise.

-- 1. No assertion at all.
joinedPlainly = readings ** calibrations

-- 2. "The key is exactly these two." The strongest claim, and the one that
-- breaks loudly if a column is added to both tables under one name.
joinedExactly = joinOnExactly {sensorId, readingDate} readings calibrations

-- 3. "The key contains `sensorId`; work the rest out." Compiles here and
-- would still compile if the date column were dropped from both sides, which
-- is either the flexibility you want or the assertion you did not get.
joinedAtLeast = joinOnAtLeast {sensorId} readings calibrations

-- 4. `join1` -- AND WHAT ITS DOCUMENTATION DOES NOT SAY.
--
-- The comment on `Relation.join1` calls it "a witness that the intersection is
-- nonempty, to guard against accidental cartesian joins". Its constraints say
-- something much stronger:
--
--     join1 : (ra <- (k, r1), rb <- (k, r2), r <- (k, r1, r2))
--          => Field k a -> rel ra -> rel rb -> rel r
--
-- `r <- (k, r1, r2)` is a partition, so `r1` and `r2` must be DISJOINT -- and
-- `r1`, `r2` are everything the two operands hold apart from `k`. Any second
-- shared column lands in both and the module does not check. So `join1 f` does
-- not mean "`f` is among the key columns"; it means "`f` is the ONLY key
-- column", exactly like `joinBy {f}`. There is no cheaper spelling of the
-- weaker claim: `joinBy' {f}` is it.
--
-- `readings ** calibrations` therefore CANNOT be written with `join1`
-- (measured 2026-09-06: "Row partitions are unsatisfiable at field
-- 'readingDate': the whole contains it but no part does" -- see
-- `shouldfail/alg05_join1_two_shared_columns.e`). Against the sensor
-- dimension, which shares one column, it is fine:
joinedWithWitness = joinOn1 sensorId joinedExactly sensors

valued =
  combine_Op (col_Op rawCount *_Op col_Op fullGain) scaledValue joinedExactly
  |> (r -> combine_Op (col_Op scaledValue *_Op col_Op scaleToSi) siValue r)
  |> joinOn1 sensorId ' sensors


-- ------------------------------------------------ copying and moving columns
--
-- `carry` (`copyColumn`) keeps the original; `overwriteWith` (`rename'`)
-- does not, and requires the destination column to EXIST so it can be
-- dropped; `replaceColumn` swaps a column for the one a lookup table supplies.
withLoggedDate = carry readingDate loggedDate valued

-- `replaceColumn f lookup r` joins on `f` and then DROPS it, so the lookup's
-- payload stands where the key stood. It is `join1` underneath, so the same
-- disjointness rule applies: the lookup may share NOTHING with `r` except `f`.
-- Pointing it at `calibrations # {sensorId, calibSource}` does not check,
-- because `valued` already carries `calibSource`.
serialNumbers : [sensorId, serialCode]
serialNumbers = relation [
  { sensorId = 9001, serialCode = "AUR31" },
  { sensorId = 9002, serialCode = "BAS28" },
  { sensorId = 9003, serialCode = "CIN36" },
  { sensorId = 9004, serialCode = "DEL29" }
]

bySerial = replaceColumn sensorId serialNumbers valued

-- `overwriteWith` (`Relation.rename'`) publishes the drift-corrected gain under
-- the base gain's name, DROPPING the base one. It is a type error unless
-- `baseGain` is already there to drop -- which is the whole difference
-- between it and `alias`, and it is in the constraint set, not in a runtime
-- check.
fullAsBase = overwriteWith fullGain baseGain valued

-- ----------------------------------------------------- materialising with a key
--
-- `letR` / `materialize` name a subexpression so it is computed once.
-- The `WithPK` forms additionally tell the backend which columns are unique,
-- which is what lets it keep an index rather than a bag. The key must be a
-- subset of the header (`Has r k`) and that is all the type says -- Ermine
-- does not and cannot check that the values are actually unique.
calibsOnce   = materialize calibrations
calibsKeyed  = materializeWithPK {sensorId, readingDate} calibrations
calibsMemo   = memoRelWithPK {sensorId, readingDate} calibrations

-- `letRWithPK` is the scoped form: the relation is named for the duration of
-- one function and cannot leak out of it. Note the continuation's type --
-- `Relation a -> Relation b`, NOT `rel a -> rel b` -- so a group function that
-- returns a `Mem` cannot be used here; the body has to stay in `Relation`.
goodCalibsOnly =
  letRWithPK {sensorId, readingDate} calibrations
    (p -> filter_Pred (col_Op calibQuality ==_Pred prim_Op "good") p)

-- --------------------------------------------------------------- the answers

stationTotal = groupSum {stationId} siValue valued
staleValued = semiJoin {sensorId} (asMem (filterEq calibQuality "stale" calibrations)) (asMem valued)
flagged = filterEq isFlagged "yes" valued

-- ---------------------------------------------------------------- the report

keyReport = vflow [
  atomShown "## Readings scaled, with the key written down",
  atomShown "### The scaling",
  tabular Nothing valued,
  atomShown "### The same join, four spellings -- identical rows",
  tabular Nothing joinedPlainly,
  tabular Nothing joinedWithWitness,
  tabular Nothing joinedExactly,
  tabular Nothing joinedAtLeast,
  atomShown "### Logged date carried alongside the reading date",
  tabular Nothing withLoggedDate,
  atomShown "### Sensor id replaced by the serial the lookup supplies",
  tabular Nothing bySerial,
  atomShown "### The corrected gain published under the base gain's name",
  tabular Nothing fullAsBase,
  atomShown "### Total by station",
  tabular Nothing stationTotal,
  atomShown "### Readings scaled from a stale calibration",
  tabular Nothing staleValued,
  atomShown "### Flagged readings",
  tabular Nothing flagged
]
