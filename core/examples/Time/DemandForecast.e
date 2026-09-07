module Time.DemandForecast where

{- ELECTRICITY DEMAND AGAINST FORECAST, as a TIME-SERIES CHART with moving
   statistics. Before this directory `timeSeriesChart` had two callers in
   `core/examples` -- `Ai/BatteryCycling.e` and `ChartsExample.e` (which calls
   it twice) -- and neither put a WINDOW FUNCTION on the series it plots, which
   is what this one is for.

   Fact: observations (16 fields: obsId, regionCode, regionName, gridZone,
                       meterClass, tariff, weatherStation, modelVersion,
                       forecastVintage, dayType, readingDate, demandMw,
                       forecastMw, temperatureC, windMs, humidityPct)
   Calendar: seasons (seasonStart, seasonEnd, seasonName, tariffPeriod)

   SHAPES EXERCISED
     * `movingAgg` -- the GENERIC framed-window helper, instantiated four
       different ways in one pipeline (mean, min, max, standard deviation) over
       the same partition and frame. This is the one call site in the group that
       passes an `Aggregate` as a value rather than naming a specialisation.
     * `runningSum` -- cumulative energy over the window.
     * `pctChange` for the relative forecast error, and `safeDiv` for the load
       factor against the rolling maximum, which is zero on a partition's first
       row and would otherwise be a division by zero.
     * `bucketBy` -- season attribution by date range.
     * `timeSeriesChart` (the deprecated one-series form) AND `chart_K` with
       four series on one axis, which is what a forecast-versus-actual plot is.
     * A `rename` chain to put the chart's series and category columns under the
       names the combinators want, as `Ai/BatteryCycling.e` does.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/DemandForecast.e
     >> demandReport

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
import Layout.Legend as Lg
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field obsId, humidityPct : Int
field regionCode, regionName, gridZone, meterClass, tariff : String
field weatherStation, modelVersion, forecastVintage, dayType : String
field readingDate, seasonStart, seasonEnd, startDate : Date
field demandMw, forecastMw, temperatureC, windMs : Double
field rollingMean, rollingMin, rollingMax, rollingSd : Double
field cumulativeMwh, absError, relError, loadFactor : Double
field seasonName, tariffPeriod, label : String
field errorBand : String

-- ------------------------------------------------------------- the fact table

-- Sixteen columns, two regions, twelve days each.
observations : [ obsId, regionCode, regionName, gridZone, meterClass, tariff
               , weatherStation, modelVersion, forecastVintage, dayType
               , readingDate, demandMw, forecastMw, temperatureC, windMs
               , humidityPct ]
observations = relation [
  { obsId = 1, regionCode = "NW", regionName = "North West", gridZone = "Z4",
    meterClass = "HH", tariff = "Economy 7", weatherStation = "Ringway",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/1/10, demandMw = 4120.5, forecastMw = 4080.0,
    temperatureC = 3.2, windMs = 5.1, humidityPct = 84 },
  { obsId = 2, regionCode = "NW", regionName = "North West", gridZone = "Z4",
    meterClass = "HH", tariff = "Economy 7", weatherStation = "Ringway",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/1/11, demandMw = 4205.9, forecastMw = 4150.0,
    temperatureC = 2.4, windMs = 6.8, humidityPct = 88 },
  { obsId = 3, regionCode = "NW", regionName = "North West", gridZone = "Z4",
    meterClass = "HH", tariff = "Economy 7", weatherStation = "Ringway",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/1/12, demandMw = 4388.2, forecastMw = 4210.0,
    temperatureC = 0.8, windMs = 3.2, humidityPct = 91 },
  { obsId = 4, regionCode = "NW", regionName = "North West", gridZone = "Z4",
    meterClass = "HH", tariff = "Economy 7", weatherStation = "Ringway",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekend",
    readingDate = @2011/1/15, demandMw = 3610.4, forecastMw = 3720.0,
    temperatureC = 4.9, windMs = 9.4, humidityPct = 76 },
  { obsId = 5, regionCode = "NW", regionName = "North West", gridZone = "Z4",
    meterClass = "HH", tariff = "Economy 7", weatherStation = "Ringway",
    modelVersion = "v3.2", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/4/12, demandMw = 3402.7, forecastMw = 3450.0,
    temperatureC = 14.1, windMs = 4.0, humidityPct = 62 },
  { obsId = 6, regionCode = "NW", regionName = "North West", gridZone = "Z4",
    meterClass = "HH", tariff = "Economy 7", weatherStation = "Ringway",
    modelVersion = "v3.2", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/7/19, demandMw = 3188.0, forecastMw = 3240.0,
    temperatureC = 21.6, windMs = 2.7, humidityPct = 55 },
  { obsId = 7, regionCode = "NW", regionName = "North West", gridZone = "Z4",
    meterClass = "HH", tariff = "Economy 7", weatherStation = "Ringway",
    modelVersion = "v3.2", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/10/18, demandMw = 3874.3, forecastMw = 3810.0,
    temperatureC = 11.3, windMs = 7.2, humidityPct = 79 },
  { obsId = 8, regionCode = "SE", regionName = "South East", gridZone = "Z9",
    meterClass = "HH", tariff = "Standard", weatherStation = "Heathrow",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/1/10, demandMw = 6890.1, forecastMw = 6800.0,
    temperatureC = 5.0, windMs = 4.4, humidityPct = 80 },
  { obsId = 9, regionCode = "SE", regionName = "South East", gridZone = "Z9",
    meterClass = "HH", tariff = "Standard", weatherStation = "Heathrow",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/1/11, demandMw = 7012.8, forecastMw = 6910.0,
    temperatureC = 4.1, windMs = 5.9, humidityPct = 83 },
  { obsId = 10, regionCode = "SE", regionName = "South East", gridZone = "Z9",
    meterClass = "HH", tariff = "Standard", weatherStation = "Heathrow",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/1/12, demandMw = 7340.6, forecastMw = 7005.0,
    temperatureC = 2.2, windMs = 3.0, humidityPct = 89 },
  { obsId = 11, regionCode = "SE", regionName = "South East", gridZone = "Z9",
    meterClass = "HH", tariff = "Standard", weatherStation = "Heathrow",
    modelVersion = "v3.1", forecastVintage = "D-1", dayType = "Weekend",
    readingDate = @2011/1/15, demandMw = 6120.9, forecastMw = 6300.0,
    temperatureC = 6.7, windMs = 8.1, humidityPct = 72 },
  { obsId = 12, regionCode = "SE", regionName = "South East", gridZone = "Z9",
    meterClass = "HH", tariff = "Standard", weatherStation = "Heathrow",
    modelVersion = "v3.2", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/4/12, demandMw = 5980.2, forecastMw = 6050.0,
    temperatureC = 16.4, windMs = 3.6, humidityPct = 58 },
  { obsId = 13, regionCode = "SE", regionName = "South East", gridZone = "Z9",
    meterClass = "HH", tariff = "Standard", weatherStation = "Heathrow",
    modelVersion = "v3.2", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/7/19, demandMw = 6402.5, forecastMw = 6180.0,
    temperatureC = 26.8, windMs = 2.1, humidityPct = 51 },
  { obsId = 14, regionCode = "SE", regionName = "South East", gridZone = "Z9",
    meterClass = "HH", tariff = "Standard", weatherStation = "Heathrow",
    modelVersion = "v3.2", forecastVintage = "D-1", dayType = "Weekday",
    readingDate = @2011/10/18, demandMw = 6544.0, forecastMw = 6490.0,
    temperatureC = 13.0, windMs = 6.5, humidityPct = 75 }
]

-- ----------------------------------------------------------- season calendar

seasons : [ seasonStart, seasonEnd, seasonName, tariffPeriod ]
seasons = relation [
  { seasonStart = @2011/1/1,  seasonEnd = @2011/3/20,  seasonName = "Winter",
    tariffPeriod = "Peak" },
  { seasonStart = @2011/3/21, seasonEnd = @2011/6/20,  seasonName = "Spring",
    tariffPeriod = "Shoulder" },
  { seasonStart = @2011/6/21, seasonEnd = @2011/9/22,  seasonName = "Summer",
    tariffPeriod = "Off-peak" },
  { seasonStart = @2011/9/23, seasonEnd = @2011/12/31, seasonName = "Autumn",
    tariffPeriod = "Shoulder" }
]

-- ================================================================ the pipeline

-- STEP 1. Season attribution.
seasoned = bucketBy seasonStart seasonEnd readingDate seasons observations

-- STEP 2. FOUR INSTANTIATIONS OF ONE GENERIC HELPER. `movingAgg` takes the
-- `Aggregate` as a value, so mean / min / max / standard deviation over the
-- same partition and the same trailing three-row frame are four calls that
-- differ only in the aggregate passed.
demandSmoothed =
     seasoned
  |> combine_Op (movingAgg (mean_Agg   (col_Op demandMw)) {regionCode} readingDate 2)
                rollingMean
  |> combine_Op (movingAgg (min_Agg    (col_Op demandMw)) {regionCode} readingDate 2)
                rollingMin
  |> combine_Op (movingAgg (max_Agg    (col_Op demandMw)) {regionCode} readingDate 2)
                rollingMax
  |> combine_Op (movingAgg (stddev_Agg (col_Op demandMw)) {regionCode} readingDate 2)
                rollingSd

-- STEP 3. Cumulative demand over the window, per region.
cumulated = combine_Op (runningSum {regionCode} readingDate demandMw)
                       cumulativeMwh demandSmoothed

-- STEP 4. Forecast error, absolute and relative, and a band on the relative one.
forecastScored =
     cumulated
  |> combine_Op (col_Op demandMw -_Op col_Op forecastMw) absError
  |> combine_Op (pctChange demandMw forecastMw) relError
  |> combine_Op (safeDiv demandMw rollingMax) loadFactor
  |> combine_Op (band3 relError (0.0 - 0.02) "Over-forecast" 0.02 "Within 2%"
                       "Under-forecast")
                errorBand

-- ==================================================================== charts

-- The chart combinators want the series column and the category column under
-- particular names, so rename onto them -- the same manoeuvre `BatteryCycling`
-- makes.
chartFeed =
     forecastScored
  |> rename regionName label
  |> rename readingDate startDate

-- The deprecated one-series form, kept because it is what most of the corpus
-- uses and a reader will meet it.
demandChart =
  timeSeriesChart (Just "Demand by region") (Just (val "Date")) (Just (val "MW"))
                  line label startDate demandMw chartFeed

errorChart =
  timeSeriesChart (Just "Forecast error") (Just (val "Date")) (Just (val "MW"))
                  bar label startDate absError chartFeed

-- FOUR SERIES ON ONE AXIS: actual, forecast, and the rolling envelope. This is
-- what a forecast-versus-actual plot actually looks like, and `chart_K` is the
-- combinator for it.
envelopeChart =
  chart_K ([chartTitle_O := "North West: actual, forecast and rolling envelope"]_Opt)
          defaultScaled defaultScaled
          [ line (prim_Op "Actual")       startDate demandMw    nwFeed
          , line (prim_Op "Forecast")     startDate forecastMw  nwFeed
          , line (prim_Op "Rolling mean") startDate rollingMean nwFeed
          , line (prim_Op "Rolling max")  startDate rollingMax  nwFeed ]
  where nwFeed = filterEq regionCode "NW" chartFeed

-- ----------------------------------------------------------------- roll-ups

bySeason : [ seasonName, regionCode, demandMw ]
bySeason = aggregateByGroup_Agg (sum_Agg (col_Op demandMw))
                                {seasonName, regionCode} demandMw seasoned

worstDays = filterNEq errorBand "Within 2%" forecastScored

-- ------------------------------------------------------------------- report

demandReport = vflow [
  atomShown "## Electricity demand against forecast, 2011",
  demandChart,
  errorChart,
  envelopeChart,
  atomShown "### Rolling envelope and forecast error",
  tabular Nothing (forecastScored # {obsId, regionCode, readingDate, seasonName,
                             demandMw, forecastMw, rollingMean, rollingMin,
                             rollingMax, rollingSd, loadFactor, absError,
                             relError, errorBand}),
  atomShown "### Days outside the 2% band",
  tabular Nothing (worstDays # {regionCode, readingDate, demandMw, forecastMw,
                                relError, errorBand}),
  atomShown "### Demand by season and region",
  tabular Nothing bySeason,
  atomShown "### Cumulative demand",
  tabular Nothing (cumulated # {regionCode, readingDate, demandMw, cumulativeMwh})
]
