module Date where

import Function
import Primitive
import Native
import Ord
import List as L
import Maybe as M
import String as S

-- builtin data "java.util.Date" Date
-- builtin data "java.sql.Timestamp" Timestamp

-- Despite the fact that Ermine uses java.util.Date as the backing type
-- for its `Date` type, an Ermine Date is morally a year-month-day triple,
-- the same as the DATE type in SQL.
-- A `Timestamp` is a Date+Time, corresponding to a SQL TIMESTAMP value
-- (or DATETIME2 in MS-SQL). Timestamps are assumed to be in UTC for the
-- purposes of treating a Date+Time as an actual moment in time.
--
-- ONE TIMEZONE, AND IT IS UTC (stage F3, ticket A3), for everything that READS
-- or FORMATS a date: `parseDate`, `unsafeFormatDate`, `formatMonthYear`,
-- `formatYear`, `formatMonth`, `formatDay`, `getYear`, `getMonth`, `getDate`,
-- and everything built on them (`quarter`, `formatQuarter`, `formatExcelDate`,
-- and `DateRange`'s period labels) all work in `YMDTriple.ymdPivotTimeZone` --
-- the same zone the SQL emitters bind a date parameter in. So a date literal is
-- ONE day everywhere and a report labels its periods the same on every machine.
--
-- DATE ARITHMETIC IS NOT YET IN THAT ZONE, and F3 did not fix it.
-- `incrementDate` / `decrementDate` / `incrementTimestamp` go through
-- `com.clarifi.reporting.TimeUnit.increment`, which builds a
-- `Calendar.getInstance` -- the JVM's DEFAULT zone -- and adds there. Adding
-- whole days is offset-invariant EXCEPT across a daylight-saving transition,
-- where the local day is 23 or 25 hours long and the answer lands on the wrong
-- UTC day. Measured on this repository:
--
--     incrementDate 1 days @2011/3/13     UTC: "3/14/11"   MDT: "3/13/11"
--
-- (13 March 2011 is the US spring-forward.) Same family as A3, same fix --
-- `Calendar.getInstance(ymdPivotTimeZone)` in `Op.scala` -- and it is a
-- BEHAVIOUR change to a shipped function, so it belongs in a stage of its own.
--
-- Until 2026-09-08 the three ACCESSORS below did not: `getYear`, `getMonth` and
-- `getDate` were bound to `java.util.Date`'s deprecated methods, which read the
-- instant in the JVM's DEFAULT timezone, so `@2011/1/1` was simultaneously
-- "1/1/11" (formatted, UTC) and 31 December 2010 (accessed, in MDT) and every
-- `DateRange` period label was machine-dependent. They are bound to
-- `PrimExprs.get{Year,Month,Date}` now, which read the same UTC calendar. Their
-- CONVENTIONS are unchanged: `getYear` is the year minus 1900, `getMonth` is
-- 0-based (January is 0), `getDate` is the 1-based day of the month.

parseDate : String -> Maybe Date
parseDate = fromMaybe# . parseDate#

foreign
-- Construct a date given a year, month, and day.
-- e.g. `yyyymmdd 1970 1 1` -> January 1, 1970
  function "com.clarifi.reporting.util.YMDTriple" "apply" yyyymmdd : Int -> Int -> Int -> Date

  function "com.clarifi.reporting.PrimExprs" "parseDate" parseDate# : String -> Maybe# Date
  function "com.clarifi.reporting.PrimExprs" "formatDate" unsafeFormatDate : Date -> String
  function "com.clarifi.reporting.PrimExprs" "formatMonthYear" formatMonthYear : Date -> String
  function "com.clarifi.reporting.PrimExprs" "formatYear" formatYear : Date -> String
  function "com.clarifi.reporting.PrimExprs" "formatMonth" formatMonth : Date -> String
  function "com.clarifi.reporting.PrimExprs" "formatDay" formatDay : Date -> String

  method "getTime" getTime       : Date -> Long

-- The accessors read the instant in UTC, the zone the formatters above use; see
-- the module header. `getYear` is the year minus 1900, `getMonth` is 0-based,
-- `getDate` is the 1-based day of the month -- the conventions of the
-- `java.util.Date` methods these replaced.
  function "com.clarifi.reporting.PrimExprs" "getDate" getDate   : Date -> Int
  function "com.clarifi.reporting.PrimExprs" "getMonth" getMonth : Date -> Int
  function "com.clarifi.reporting.PrimExprs" "getYear" getYear   : Date -> Int

  method "before" before : Date -> Date -> Bool

foreign
  constructor timestampFromLong : Long -> Timestamp

formatExcelDate d =
  spaced_S ' [
    toString . getJust_M "unknown month" ' at_L (getMonth d) shortMonthNames,
    toString ' getDate d
  ]_L

monthNames : List String
monthNames =
  ["January", "February", "March", "April", "May", "June",
   "July", "August", "September", "October", "November", "December"]_L

shortMonthNames : List String
shortMonthNames =
  ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]_L

quarterNames : List String
quarterNames = ["Q1", "Q2", "Q3", "Q4"]_L

-- | The calendar quarter a date falls in, 1 through 4: January is 1.
--
-- Stage F3, ticket A4: this used to read `getMonth d / 4 + 1`, which is wrong
-- twice over -- a quarter is THREE months, not four, and `formatQuarter` then
-- indexed a 0-based list with the 1-based answer, so "Q1" was unreachable and
-- January printed "Q2". The divisor is 3 now and `formatQuarter` subtracts the
-- one; `quarter` itself keeps its 1-based meaning, which is the one its name and
-- `quarterNames` have.
quarter : Date -> Int
quarter d = getMonth d / 3 + 1

formatQuarter : Date -> String
formatQuarter d = orElse_M "Unknown" (at_L (quarter d - 1) quarterNames)

-- | `incrementDate 5 days d`
incrementDate : Int -> TimeUnit -> Date -> Date
incrementDate n u d = incrementDate# u d n

decrementDate : Int -> TimeUnit -> Date -> Date
decrementDate n = incrementDate (-n)

-- date arithmetic
foreign
  data "com.clarifi.reporting.TimeUnit" TimeUnit
  function "com.clarifi.reporting.TimeUnits" "Millisecond" milliseconds : TimeUnit
  function "com.clarifi.reporting.TimeUnits" "Second" seconds : TimeUnit
  function "com.clarifi.reporting.TimeUnits" "Day" days : TimeUnit
  function "com.clarifi.reporting.TimeUnits" "Week" weeks : TimeUnit
  function "com.clarifi.reporting.TimeUnits" "Month" months : TimeUnit
  function "com.clarifi.reporting.TimeUnits" "Year" years : TimeUnit

private foreign
  method "increment" incrementDate# : TimeUnit -> Date -> Int -> Date
  method "incrementTimestamp" incrementTimestamp# : TimeUnit -> Timestamp -> Int -> Timestamp
