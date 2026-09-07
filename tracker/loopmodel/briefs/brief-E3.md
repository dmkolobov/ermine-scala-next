# Brief: E3 — `core/examples/Time/`: dates, calendars, time series, money and nullable arithmetic

Read `tracker/loopmodel/briefs/brief-E-common.md` FIRST; it carries the conventions, rules, wiring policy and
gates. This file says only what E3 covers. Stage name `E3`; group `core/examples/Time/`, module prefix `Time.`,
helper library `Time/Helpers.e`, report `tracker/loopmodel/E3-EXAMPLES.md`.

WHAT IS UNDER-EXAMPLED HERE. `Date` is imported by six examples and `DateRange` by two, both only through the
Ai date-range trees; `Relation.e`'s date-keyed helpers — `lookupLatest`, `lookupLatest1`, `lookupLatestWithin`,
`lookupLatest'`, `nearestDate`, `nearestDateWithin` — have no example; `Currency`, `Math`, `Double`/`Long`/`Int`
arithmetic modules, `Nullable` (null-aware arithmetic and aggregation), `Random`, `Vector` and `Ring` have zero
uses; `Relation.Aggregate` appears in eight examples but only with `sum`/`count`; `Relation.Sort` in two.
`Layout.Chart` time-series charts appear once (`BatteryCycling.e`).

READ, beyond the common list: `Date.e`, `DateRange.e`, `Currency.e`, `Math.e`, `Nullable.e`, `Num.e`,
`Double.e`, `Long.e`, `Ring.e`, `Random.e`, `Vector.e`, `Relation/Aggregate.e` (every aggregate), `Relation/Sort.e`,
`Relation/Windowed.e` (only for framed aggregates over dates — E1 owns rank/ntile/pivot; do not duplicate),
`Layout/Chart.e`; `core/examples/Ai/BatteryCycling.e`, `Ai/FiscalCalendar.e`, `Ai/RevenueByPeriod.e`,
`Ai/GridTelemetry.e` (the date-range trees), `incomplete/RunCalibration.e` (`valueAsOf` — a date lookup whose
residual signature is in `incomplete/Signatures.e`).

## What to build (eight to ten modules plus `Helpers.e`, all realistic reports; fact tables of 15–40 fields)

* `Helpers.e`: `asOf` (a generic `lookupLatest` over a generic key row and a date column: the price/rate/status
  "as of" pattern), `asOfWithin` (with a staleness window), `nearest` (a generic `nearestDate`), `fxConvert`
  (a `Currency` conversion using an as-of rate table, generic over the amount columns), `bucketBy` (a generic
  calendar bucketing: day/week/month/quarter/fiscal period from a `DateRange` tree), `fillForward` (carry the
  last known value across a calendar — a framed window or a scan over dates), `pctChange`/`yoy` (period-over-
  period change against a generic key, nullable-aware), `safeDiv`/`nullSum` (nullable arithmetic helpers),
  `ageBucket`, a `Random`-seeded synthetic series generator if `Random` is usable in a report (say if not);
  two with `xFull`/`xSimple` pairs.
* Reports: a multi-currency P&L with as-of FX rates and a fiscal calendar; a subscription-revenue waterfall
  (starts, churns, expansions per period, month-over-month and year-over-year); an interest-accrual ledger
  (day-count conventions, `Math`, nullable rates); a sensor series with gaps filled forward and outliers
  flagged (`Vector`/`Math` statistics if expressible); an employee tenure and age-band report (dates, buckets);
  a reading history with nearest-date joins across two network calendars; a cohort retention triangle (signup
  month × months since signup — a date-keyed pivot-like layout done with `Layout.Report.Keyed`, not `Pivot`);
  a time-series chart report (`Layout.Chart`) with moving statistics; plus the `Time/shouldfail/` negative (an
  as-of lookup whose key row is not a subset of the fact row; a nullable sum where a non-nullable is expected)
  with the expected diagnostics.

The point for the certification corpus: `lookupLatest`'s `r <- (h, t)` family at call sites over wide rows,
chained through `fxConvert` and `bucketBy`, should produce residual chains and `concrete` steps the census never
sees; measure it (G3) and say what moved. The point for users: the "as of" pattern is what every dated report
needs and the corpus does not show it once.
