module Time.ReadingHistory where

{- A READING HISTORY ACROSS TWO NETWORK CALENDARS, and the six different
   "as of" questions the stdlib can answer -- all of them, side by side, which
   is what `core/examples` did not contain before.

   Fact:     readingLog (17 fields: readingId, station, network, region, terrain,
                       unitLabel, loggerCode, dataQuality, sensorBand,
                       stationStatus, readDate, dailyMean, dayStart,
                       dailyMax, dailyMin, calibFactor, sampleCount)
   Calendar: sessions (network, sessionDate, sessionType)

   April 2011 is the right month for this. THE TWO NETWORKS DISAGREE about
   which days exist: 22 April (Good Friday) and 25 April (Easter Monday) are
   maintenance days on both, but 29 April -- the royal wedding -- is a UK bank
   holiday and an ordinary NOAA polling day. So a UKMO line and a NOAA line in a
   report are on different date axes and a naive join loses rows on both sides.

   ALL EIGHT DATE-KEYED COMBINATORS `Relation.e` SHIPS, plus the per-key one it
   does not. Seven of the eight had no example anywhere in `core/examples` before
   this directory (`nearestDateWithin` had two, both in `incomplete/`).

     `asOf`           `lookupLatest1`      -- the latest rows at or before a date,
                      GLOBALLY. Wrong for a multi-station history, and the report
                      shows exactly how it goes wrong.
     `asOfEach`       `lookupLatest`       -- against a whole RELATION of as-of
                      dates at once.
     `asOfWithin`     `lookupLatestWithin1`-- with a staleness window. Read its
                      doc comment in `Helpers.e` first: it is a BINARY GATE on
                      `asOf`'s answer, not a per-row filter.
     `asOfEachWithin` `lookupLatestWithin` -- the relation-of-dates form of the
                      window, which unlike the previous one really does return
                      one date's worth per requested date.
     `nearest`        `nearestDate`        -- map each sparse date to the nearest
                      fine one at or before it. DATES TO DATES; see (4).
     `nearestWithin`  `nearestDateWithin`  -- the same with a window.
     `lookback`       `lookbackJoin`       -- a JOIN rather than a lookup: both
                      sides' columns, and the RIGHT date in the result.
     `latestPerKey`   `lookupLatest'`      -- the recursive one: guarantees a row
                      per key by walking back a day at a time.
     `nearestBy`      `Time.Helpers`       -- the PER-KEY version the stdlib does
                      NOT have. What the report actually wants.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/ReadingHistory.e
     >> readingReport

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
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field readingId, sampleCount : Int
field station, network, region, terrain, unitLabel : String
field loggerCode, dataQuality, sensorBand, stationStatus, sessionType : String
field readDate, sessionDate, asOfDate : Date
field dailyMean, dayStart, dailyMax, dailyMin, calibFactor : Double
field baseMean, meanIndex, smoothedMean, stalenessDays, refLevel : Double
field refStation : String
field staleDays : Int

-- ------------------------------------------------------------- the fact table

-- Seventeen columns. Four stations on two networks; note that the UKMO sites
-- have no row on 29 April and the NOAA ones do.
readingLog : [ readingId, station, network, region, terrain, unitLabel
             , loggerCode, dataQuality, sensorBand, stationStatus, readDate
             , dailyMean, dayStart, dailyMax, dailyMin, calibFactor, sampleCount ]
readingLog = relation [
  { readingId = 1, station = "ESK.UK", network = "UKMO", region = "Scotland",
    terrain = "Moorland", unitLabel = "nT", loggerCode = "AWS",
    dataQuality = "Verified", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/18, dailyMean = 17655.0, dayStart = 17520.0,
    dailyMax = 17710.0, dailyMin = 17485.0, calibFactor = 1.0, sampleCount = 86400 },
  { readingId = 2, station = "ESK.UK", network = "UKMO", region = "Scotland",
    terrain = "Moorland", unitLabel = "nT", loggerCode = "AWS",
    dataQuality = "Verified", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/20, dailyMean = 17810.0, dayStart = 17690.0,
    dailyMax = 17865.0, dailyMin = 17630.0, calibFactor = 1.0, sampleCount = 86400 },
  { readingId = 3, station = "ESK.UK", network = "UKMO", region = "Scotland",
    terrain = "Moorland", unitLabel = "nT", loggerCode = "AWS",
    dataQuality = "Verified", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/26, dailyMean = 17740.0, dayStart = 17805.0,
    dailyMax = 17820.0, dailyMin = 17675.0, calibFactor = 1.0, sampleCount = 86112 },
  { readingId = 4, station = "LER.UK", network = "UKMO", region = "Shetland",
    terrain = "Coastal Cliff", unitLabel = "hPa", loggerCode = "AWS",
    dataQuality = "Verified", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/18, dailyMean = 1004.2, dayStart = 1003.5,
    dailyMax = 1006.0, dailyMin = 1002.8, calibFactor = 1.0, sampleCount = 1440 },
  { readingId = 5, station = "LER.UK", network = "UKMO", region = "Shetland",
    terrain = "Coastal Cliff", unitLabel = "hPa", loggerCode = "AWS",
    dataQuality = "Estimated", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/21, dailyMean = 1008.9, dayStart = 1005.0,
    dailyMax = 1009.5, dailyMin = 1004.6, calibFactor = 1.0, sampleCount = 1437 },
  { readingId = 6, station = "BOU", network = "NOAA", region = "Colorado",
    terrain = "Foothills", unitLabel = "ppb", loggerCode = "MET",
    dataQuality = "Verified", sensorBand = "Reference", stationStatus = "Active",
    readDate = @2011/4/18, dailyMean = 33.18, dayStart = 32.72,
    dailyMax = 33.24, dailyMin = 32.69, calibFactor = 1.0, sampleCount = 288 },
  { readingId = 7, station = "BOU", network = "NOAA", region = "Colorado",
    terrain = "Foothills", unitLabel = "ppb", loggerCode = "MET",
    dataQuality = "Verified", sensorBand = "Reference", stationStatus = "Active",
    readDate = @2011/4/21, dailyMean = 35.07, dayStart = 34.41,
    dailyMax = 35.18, dailyMin = 34.36, calibFactor = 1.0, sampleCount = 288 },
  { readingId = 8, station = "BOU", network = "NOAA", region = "Colorado",
    terrain = "Foothills", unitLabel = "ppb", loggerCode = "MET",
    dataQuality = "Verified", sensorBand = "Reference", stationStatus = "Active",
    readDate = @2011/4/29, dailyMean = 35.01, dayStart = 34.99,
    dailyMax = 35.12, dailyMin = 34.85, calibFactor = 1.0, sampleCount = 287 },
  { readingId = 9, station = "FRD", network = "NOAA", region = "Virginia",
    terrain = "Piedmont", unitLabel = "ug/m3", loggerCode = "MET",
    dataQuality = "Verified", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/18, dailyMean = 19.68, dayStart = 19.80,
    dailyMax = 19.84, dailyMin = 19.61, calibFactor = 1.0, sampleCount = 1440 },
  { readingId = 10, station = "FRD", network = "NOAA", region = "Virginia",
    terrain = "Piedmont", unitLabel = "ug/m3", loggerCode = "MET",
    dataQuality = "Verified", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/21, dailyMean = 20.32, dayStart = 19.95,
    dailyMax = 20.41, dailyMin = 19.92, calibFactor = 1.0, sampleCount = 1440 },
  { readingId = 11, station = "FRD", network = "NOAA", region = "Virginia",
    terrain = "Piedmont", unitLabel = "ug/m3", loggerCode = "MET",
    dataQuality = "Stale", sensorBand = "Primary", stationStatus = "Active",
    readDate = @2011/4/26, dailyMean = 20.15, dayStart = 20.28,
    dailyMax = 20.33, dailyMin = 20.09, calibFactor = 1.0, sampleCount = 1392 }
]

-- -------------------------------------------------------- two network calendars

-- The polling sessions of both networks. 22 and 25 April are down on both;
-- 29 April is a UK bank holiday and an ordinary NOAA polling day.
sessions : [ network, sessionDate, sessionType ]
sessions = relation [
  { network = "UKMO", sessionDate = @2011/4/18, sessionType = "Regular" },
  { network = "UKMO", sessionDate = @2011/4/19, sessionType = "Regular" },
  { network = "UKMO", sessionDate = @2011/4/20, sessionType = "Regular" },
  { network = "UKMO", sessionDate = @2011/4/21, sessionType = "Regular" },
  { network = "UKMO", sessionDate = @2011/4/26, sessionType = "Regular" },
  { network = "UKMO", sessionDate = @2011/4/27, sessionType = "Regular" },
  { network = "UKMO", sessionDate = @2011/4/28, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/18, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/19, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/20, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/21, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/26, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/27, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/28, sessionType = "Regular" },
  { network = "NOAA", sessionDate = @2011/4/29, sessionType = "Regular" }
]

-- ============================================================ the six lookups

-- (1) `asOf` -- GLOBAL. The rows on the latest read date at or before 22 April
-- (Good Friday): that is 21 April, and only LER.UK, BOU and FRD reported. ESK.UK
-- DISAPPEARS, although its 20 April mean is perfectly good. This is the
-- behaviour of `Relation.lookupLatest1`, and the reason `nearestBy` exists.
valueOn22Global : [ readingId, station, network, region, terrain, unitLabel
                  , loggerCode, dataQuality, sensorBand, stationStatus
                  , readDate, dailyMean, dayStart, dailyMax, dailyMin
                  , calibFactor, sampleCount ]
valueOn22Global = asOf readDate @2011/4/22 readingLog

-- (2) `asOfWithin` -- the same date with a staleness window, and THE ANSWER IS
-- NOT WHAT A READER EXPECTS. `nearestDateWithin`'s body is
--
--     groupBy {ffine} (maxRowBy fsparse)
--       ([| fsparse <= ffine, ffine <= upperBound fsparse |] (join ...))
--
-- and with ONE as-of date there is ONE group, so `maxRowBy` collapses whatever
-- survived the window to the rows on a SINGLE read date. The window can
-- therefore only ever admit the globally latest date or nothing:
--
--   within 3 -- 21 April is inside the window, so the answer is the three
--               21 April rows: EXACTLY `valueOn22Global`. The window does NOT
--               rescue ESK.UK, whose own last reading is 20 April, because the
--               grouping is by date alone and 21 April wins globally. This is
--               finding (1) again, and it is why `nearestBy` exists.
--   within 1 -- 21 April is STILL inside the window (the filter is
--               `histDate <= asOf <= histDate + n`, so n = 1 admits 21 April),
--               and the answer is again those same three rows. A reader who
--               reads "within one day" as "at most one day stale" gets what they
--               expect here only by accident.
--   within 0 -- nothing is admitted and the result is EMPTY, which is the only
--               way to say "a reading dated today or not at all". MEASURED: with
--               n = 0 the filter collapses to `histDate = asOfDate`, and
--               `filterEq readDate @2011/4/22 readingLog` dumped to SQL returns
--               0 rows -- no station was polled on Good Friday.
--
-- Three calls, two distinct answers, and one of them is the global lookup's.
valueOn22Within3 = asOfWithin 3 readDate @2011/4/22 readingLog
valueOn22Within1 = asOfWithin 1 readDate @2011/4/22 readingLog
valueOn22Within0 = asOfWithin 0 readDate @2011/4/22 readingLog

-- (2b) `asOfEachWithin` -- the RELATION-of-dates form of the window. Here the
-- grouping is per requested date, so this one really does return several dates'
-- worth: one date's rows for each as-of date whose window admits anything.
readingsEachWithin = asOfEachWithin 3 readDate checkDates readingLog

-- (3) `asOfEach` -- several as-of dates at once, supplied as a relation of the
-- date column. One pass, three answers.
checkDates : [ readDate ]
checkDates = relation [ { readDate = @2011/4/19 },
                        { readDate = @2011/4/22 },
                        { readDate = @2011/4/27 } ]

readingsEach = asOfEach readDate checkDates readingLog

-- (4) `nearest` -- `nearestDate` proper, and the first surprise a reader gets:
-- its type is
--     Field rsparse Date -> Relation rsparse -> Field rfine Date -> Relation rfine
-- and a `Field r a` has the SINGLETON row of that field, so BOTH relations are
-- forced to one column. `nearestDate` maps DATES TO DATES. It does not carry
-- either table along; you project both date columns out, map one to the other,
-- and JOIN THE RESULT BACK yourself. Passing the wide relations straight in gives
--     failed to unify type (|readDate|) with type (|terrain, dataQuality, ...|)
--     failed to unify type (|sessionDate|) with type (|sessionDate, sessionType|)
-- which are confusing messages for what is really an arity mistake. `nearestBy`
-- below takes whole relations, which is half of why it exists.
ukSessions : [ network, sessionDate, sessionType ]
ukSessions = filterEq network "UKMO" sessions

readDates : [ readDate ]
readDates = readingLog # {readDate}

nearestUk : [ readDate, sessionDate ]
nearestUk = nearest readDate readDates sessionDate (ukSessions # {sessionDate})

-- and joined back onto the facts by hand, which is the step `nearestBy` folds in.
nearestUkJoined = join readingLog nearestUk

-- (5) `nearestBy` -- PER STATION AND NETWORK. The spine is built by joining the
-- session calendar to the distinct (station, network) pairs, which because the
-- join is natural on `network` pairs each network's sessions with its OWN
-- stations and never with the other's. Then each (station, session) cell takes
-- that station's own latest reading.
spine = join sessions (readingLog # {station, network})

perStation = nearestBy {station, network} readDate readingLog sessionDate spine

-- The same thing said in one call: `fillForward` builds that spine itself.
carried = fillForward {station, network} readDate readingLog sessionDate sessions

-- (6) `latestPerKey` -- the recursive lookback. Walks back from 26 April a day
-- at a time until every station has a row or 18 April is reached. Quadratic in
-- the window, so the window is short.
stations : [ station ]
stations = readingLog # {station}

latestByStation = latestPerKey readDate readingLog @2011/4/18 @2011/4/26 stations

-- ---------------------------------------------------------- derived columns

-- How stale is each carried reading? The gap between the session date and the
-- read date that supplied it -- the column a data-quality panel prints.
staleness = combine_Op (dayCount readDate sessionDate) staleDays perStation

-- A reading index: each mean relative to the station's 18 April base, times 100.
base : [ station, baseMean ]
base = asOf readDate @2011/4/18 readingLog # {station, dailyMean}
    |> rename dailyMean baseMean

meanIndexed =
  combine_Op (indexOf dailyMean baseMean *_Op prim_Op 100.0) meanIndex
             (join readingLog base)

-- A three-session moving average of the carried mean, per station.
meanSmoothed =
  combine_Op (movingMean {station} sessionDate dailyMean 2) smoothedMean perStation

-- (7) `lookback` -- `Relation.lookbackJoin`, the eighth combinator and the only
-- one that is a JOIN. Read its body (`Relation.e:206`) before using it: for each
-- RIGHT date it finds the nearest LEFT date at or before it within the window,
-- RE-DATES the left rows onto the right date, and joins. So the left side is the
-- SPARSE one and the right side supplies the dates that survive.
--
-- The natural use is a weekly reference cell against a daily reading history:
-- every mean gains the most recent reference level, carried forward up to five
-- days. The two relations share `readDate` and nothing else, which is what
-- `r3 <- (k, s, t)` in `lookback`'s signature requires -- a shared NON-date
-- column would make the result row a non-disjoint union and the call would not
-- check. (That is worth knowing about `incomplete/Signatures.valueAsOfSimple`
-- too, which carries the same three constraints over a run log and a reference
-- history that DO share a station column.)
refLevels : [ refStation, readDate, refLevel ]
refLevels = relation [
  { refStation = "NPL-REF", readDate = @2011/4/14, refLevel = 6022.26 },
  { refStation = "NPL-REF", readDate = @2011/4/21, refLevel = 6018.30 },
  { refStation = "NPL-REF", readDate = @2011/4/28, refLevel = 6069.90 }
]

lookbackJoined = lookback 5 readDate refLevels readingLog

-- -------------------------------------------------------------- exceptions

-- Sessions on which a station had NO reading of its own -- the cells `nearestBy`
-- had to CARRY. Take the (station, session) grid and subtract the (station, read
-- date) pairs that actually exist, renaming the read date onto the session
-- column so the difference lines up. This is the same manoeuvre
-- `Time.SensorSeries.gapDays` makes, and it is what the previous version of this
-- definition claimed to do and did not: it computed "every cell whose session is
-- not 18 April", which is a different set and a bigger one.
--
-- MEASURED by dumping the same expression with `spine` in place of `perStation`
-- (the two have the same (station, session) set, because every station's first
-- reading is 18 April = the first session, so no cell is missing from the front):
-- 19 rows, and they are exactly
--   ESK.UK (read 18, 20, 26)       misses UKMO 19, 21, 27, 28          -- 4
--   LER.UK (read 18, 21)           misses UKMO 19, 20, 26, 27, 28      -- 5
--   BOU    (read 18, 21, 29)       misses NOAA 19, 20, 26, 27, 28      -- 5
--   FRD    (read 18, 21, 26)       misses NOAA 19, 20, 27, 28, 29      -- 5
-- -- 19 April is a gap for all four, and 29 April appears only for FRD, because
-- the UKMO network has no session that day and BOU reported on it.
carriedCells = difference (perStation # {station, sessionDate})
                          (rename readDate sessionDate (readingLog # {station, readDate}))

-- One logger row is flagged `Stale` in the feed itself -- a different kind of
-- staleness from the one `staleness` above measures, and a report shows both.
staleFlags = filterEq dataQuality "Stale" readingLog

-- ------------------------------------------------------------------- report

readingReport = vflow [
  atomShown "## Reading history over two network calendars, April 2011",
  atomShown "### The network calendars (29 April is NOAA-only)",
  tabular Nothing sessions,
  atomShown "### (1) asOf 22 April, GLOBAL -- ESK.UK is missing and should not be",
  tabular Nothing (valueOn22Global # {station, network, readDate, dailyMean}),
  atomShown "### (2) asOfWithin 3, 1 and 0 days -- the first two are the GLOBAL answer, the third is empty",
  tabular Nothing (valueOn22Within3 # {station, readDate, dailyMean}),
  tabular Nothing (valueOn22Within1 # {station, readDate, dailyMean}),
  tabular Nothing (valueOn22Within0 # {station, readDate, dailyMean}),
  atomShown "### (2b) asOfEachWithin -- the relation-of-dates form, one date's worth per request",
  tabular Nothing (readingsEachWithin # {station, readDate, dailyMean}),
  atomShown "### (3) asOfEach, three as-of dates at once",
  tabular Nothing (readingsEach # {station, readDate, dailyMean}),
  atomShown "### (4) nearest, over the UKMO calendar -- dates only, then joined back",
  tabular Nothing nearestUk,
  tabular Nothing (nearestUkJoined # {station, readDate, sessionDate, dailyMean}),
  atomShown "### (5) nearestBy, per station and network -- with staleness",
  tabular Nothing (staleness # {station, network, sessionDate, readDate,
                                dailyMean, staleDays}),
  atomShown "### (6) latestPerKey, recursive lookback to 18 April",
  tabular Nothing (latestByStation # {station, readDate, dailyMean}),
  atomShown "### Reading index against the 18 April base",
  tabular Nothing (meanIndexed # {station, readDate, dailyMean, baseMean, meanIndex}),
  atomShown "### Three-session moving average of the carried mean",
  tabular Nothing (meanSmoothed # {station, sessionDate, dailyMean, smoothedMean}),
  atomShown "### (7) lookback -- lookbackJoin: the weekly reference carried onto every reading",
  tabular Nothing (lookbackJoined # {station, readDate, dailyMean, refStation, refLevel}),
  atomShown "### Cells nearestBy had to carry, and the feed's own stale flag",
  tabular Nothing carriedCells,
  tabular Nothing (staleFlags # {readingId, station, readDate, dataQuality})
]
