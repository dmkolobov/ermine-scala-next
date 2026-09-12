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
  method "getDate" getDate       : Date -> Int
  method "getMonth" getMonth     : Date -> Int
  method "getYear" getYear       : Date -> Int
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

quarter : Date -> Int
quarter d = getMonth d / 4 + 1

formatQuarter : Date -> String
formatQuarter d = orElse_M "Unknown" (at_L (quarter d) quarterNames)

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
