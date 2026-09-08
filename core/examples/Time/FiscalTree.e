module Time.FiscalTree where

{- A FISCAL CALENDAR AS A TREE OF DATE RANGES, and what `DateRange.e` can and
   cannot do with it.

   Fact:     serviceOrders (18 fields: orderId, customerRef, serviceClass,
                            siteCode, serviceRegion, engineer, priority, slaBand,
                            contractType, billingCode, orderStatus, orderDate,
                            promisedDate, completedDate, labourHours, partsCost,
                            travelKm, creditNote (NULLABLE))
   Calendar: periodTree    (dateRangeId, parentDateRangeId, periodKind,
                            periodStart, periodEnd, periodShort, fiscalYear) --
                            a TREE: FY2011 -> four quarters -> twelve months,
                            each node carrying its own (start, end) pair
   Rates:    tariffs       (serviceClass, effectiveFrom, hourlyRate)

   WHY THIS MODULE EXISTS. The other seven reports here answer "there is no month
   accessor in `Relation.Op`" by carrying a FLAT calendar relation and joining
   facts to it with `Helpers.bucketBy`. The obvious question is whether the
   stdlib's `DateRange` module is the right tool instead, and the answer is worth
   writing down, because it is *no*, for two reasons this module measures rather
   than asserts. See "WHAT `DateRange` IS FOR" below.

   The calendar here is a TREE in the sense `Ai/FiscalCalendar.e` and
   `Ai/RevenueByPeriod.e` use -- parent/child id columns, drilled down with
   `drilldownTable` -- and each node ALSO carries its half-open range, so the same
   relation serves both as a hierarchy to navigate and as a set of ranges to
   bucket against. That combination is what neither directory had.

   SHAPES EXERCISED
     * `bucketBy` against the LEAF nodes of a tree, then a roll-up that walks the
       parent edge to the quarter and the year.
     * `nearestBy` with the FINE relation drawn from a tree -- the tariff in force
       at each period's start, per service class. A tree-shaped input under the
       as-of helpers, which neither this directory nor `Ai/` had.
     * `drilldownTable` on the same relation the ranges came from.
     * `DateRange`'s value-level formatters and parser, and the two defects they
       expose in `Date.e` (below).
     * `Ring`, `Num`, `Long`, `Int` and `Nullable` at the value level -- the five
       arithmetic modules the rest of the directory never touches, and the reason
       it does not.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/FiscalTree.e
     >> fiscalReport

   NOTE ON `render`. `render` is not a defined term anywhere in Ermine -- not in
   the stdlib, not in the REPL. See `tracker/loopmodel/E3-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import DateRange as DR
import Date as Dt
import Ring as Rg
import Nullable as Nu
import Num as Nm
import Long as Lg
import Int as It
import Ord as Od
import Relation.Op as Op
import Relation.Op.Type using type Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field orderId, travelKm, dateRangeId, parentDateRangeId : Int
field customerRef, serviceClass, siteCode, serviceRegion, engineer : String
field priority, slaBand, contractType, billingCode, orderStatus : String
field orderDate, promisedDate, completedDate, periodStart, periodEnd : Date
field effectiveFrom : Date
field labourHours, partsCost, hourlyRate, labourValue, orderValue : Double
field creditNote : Nullable Double
field periodKind, periodShort, fiscalYear, quarterShort : String
field parentStart, parentEnd : Date
field periodValue, quarterValue : Double

-- ------------------------------------------------------------- the fact table

-- Eighteen columns. `creditNote` is null on the orders that were never disputed,
-- which is not the same as a credit note of zero.
serviceOrders : [ orderId, customerRef, serviceClass, siteCode, serviceRegion
                , engineer, priority, slaBand, contractType, billingCode
                , orderStatus, orderDate, promisedDate, completedDate
                , labourHours, partsCost, travelKm, creditNote ]
serviceOrders = relation [
  { orderId = 8001, customerRef = "NW-0431", serviceClass = "Emergency",
    siteCode = "RVB-01", serviceRegion = "South", engineer = "r.mensah",
    priority = "P1", slaBand = "4 hour", contractType = "Managed",
    billingCode = "T&M", orderStatus = "Closed", orderDate = @2010/10/14,
    promisedDate = @2010/10/14, completedDate = @2010/10/14,
    labourHours = 6.5, partsCost = 1240.0, travelKm = 84,
    creditNote = Null Double },
  { orderId = 8002, customerRef = "CT-1180", serviceClass = "Planned",
    siteCode = "KLN-07", serviceRegion = "North", engineer = "l.varga",
    priority = "P4", slaBand = "5 day", contractType = "Managed",
    billingCode = "Fixed", orderStatus = "Closed", orderDate = @2010/11/23,
    promisedDate = @2010/11/30, completedDate = @2010/11/29,
    labourHours = 14.0, partsCost = 380.0, travelKm = 212,
    creditNote = Null Double },
  { orderId = 8003, customerRef = "FB-0902", serviceClass = "Emergency",
    siteCode = "CRM-02", serviceRegion = "West", engineer = "b.ferreira",
    priority = "P1", slaBand = "4 hour", contractType = "Break-fix",
    billingCode = "T&M", orderStatus = "Closed", orderDate = @2011/1/8,
    promisedDate = @2011/1/8, completedDate = @2011/1/9,
    labourHours = 9.25, partsCost = 2870.0, travelKm = 341,
    creditNote = Some 450.0 },
  { orderId = 8004, customerRef = "NW-0431", serviceClass = "Planned",
    siteCode = "RVB-01", serviceRegion = "South", engineer = "r.mensah",
    priority = "P3", slaBand = "2 day", contractType = "Managed",
    billingCode = "Fixed", orderStatus = "Closed", orderDate = @2011/2/17,
    promisedDate = @2011/2/19, completedDate = @2011/2/18,
    labourHours = 5.0, partsCost = 0.0, travelKm = 76,
    creditNote = Null Double },
  { orderId = 8005, customerRef = "LB-2204", serviceClass = "Upgrade",
    siteCode = "LON-11", serviceRegion = "South", engineer = "d.okonkwo",
    priority = "P2", slaBand = "1 day", contractType = "Project",
    billingCode = "Capital", orderStatus = "Closed", orderDate = @2011/3/29,
    promisedDate = @2011/4/1, completedDate = @2011/4/4,
    labourHours = 31.5, partsCost = 18400.0, travelKm = 55,
    creditNote = Some 1200.0 },
  { orderId = 8006, customerRef = "WG-7781", serviceClass = "Planned",
    siteCode = "KLN-07", serviceRegion = "North", engineer = "l.varga",
    priority = "P4", slaBand = "5 day", contractType = "Managed",
    billingCode = "Fixed", orderStatus = "Closed", orderDate = @2011/5/11,
    promisedDate = @2011/5/18, completedDate = @2011/5/17,
    labourHours = 11.75, partsCost = 640.0, travelKm = 198,
    creditNote = Null Double },
  { orderId = 8007, customerRef = "FB-0902", serviceClass = "Emergency",
    siteCode = "CRM-02", serviceRegion = "West", engineer = "b.ferreira",
    priority = "P1", slaBand = "4 hour", contractType = "Break-fix",
    billingCode = "T&M", orderStatus = "Closed", orderDate = @2011/6/2,
    promisedDate = @2011/6/2, completedDate = @2011/6/2,
    labourHours = 3.5, partsCost = 910.0, travelKm = 327,
    creditNote = Null Double },
  { orderId = 8008, customerRef = "LB-2204", serviceClass = "Upgrade",
    siteCode = "LON-11", serviceRegion = "South", engineer = "d.okonkwo",
    priority = "P2", slaBand = "1 day", contractType = "Project",
    billingCode = "Capital", orderStatus = "Closed", orderDate = @2011/7/19,
    promisedDate = @2011/7/22, completedDate = @2011/7/21,
    labourHours = 22.0, partsCost = 9350.0, travelKm = 61,
    creditNote = Null Double },
  { orderId = 8009, customerRef = "CT-1180", serviceClass = "Planned",
    siteCode = "KLN-07", serviceRegion = "North", engineer = "l.varga",
    priority = "P3", slaBand = "2 day", contractType = "Managed",
    billingCode = "Fixed", orderStatus = "Closed", orderDate = @2011/8/30,
    promisedDate = @2011/9/1, completedDate = @2011/9/1,
    labourHours = 7.25, partsCost = 155.0, travelKm = 204,
    creditNote = Some 90.0 },
  { orderId = 8010, customerRef = "TR-3310", serviceClass = "Emergency",
    siteCode = "AMS-04", serviceRegion = "East", engineer = "b.ferreira",
    priority = "P1", slaBand = "4 hour", contractType = "Break-fix",
    billingCode = "T&M", orderStatus = "Open", orderDate = @2011/9/26,
    promisedDate = @2011/9/26, completedDate = @2011/9/27,
    labourHours = 12.0, partsCost = 4180.0, travelKm = 402,
    creditNote = Null Double }
]

-- =================================================== the calendar AS A TREE

-- Seventeen nodes: one fiscal year (October to September), four quarters, twelve
-- months. `dateRangeId` / `parentDateRangeId` are the same pair of columns
-- `Ai/FiscalCalendar.e` uses, so the same `drilldownTable` navigates it -- and
-- every node ALSO carries its own range, so `Helpers.bucketBy` can filter
-- against the leaves. One relation, two jobs.
periodTree : [ dateRangeId, parentDateRangeId, periodKind, periodStart
             , periodEnd, periodShort, fiscalYear ]
periodTree = relation [
  { dateRangeId = 2011, parentDateRangeId = 0, periodKind = "Year",
    periodStart = @2010/10/1, periodEnd = @2011/9/30, periodShort = "FY11",
    fiscalYear = "FY2011" },

  { dateRangeId = 20111, parentDateRangeId = 2011, periodKind = "Quarter",
    periodStart = @2010/10/1, periodEnd = @2010/12/31, periodShort = "Q1",
    fiscalYear = "FY2011" },
  { dateRangeId = 201110, parentDateRangeId = 20111, periodKind = "Month",
    periodStart = @2010/10/1, periodEnd = @2010/10/31, periodShort = "Oct",
    fiscalYear = "FY2011" },
  { dateRangeId = 201111, parentDateRangeId = 20111, periodKind = "Month",
    periodStart = @2010/11/1, periodEnd = @2010/11/30, periodShort = "Nov",
    fiscalYear = "FY2011" },
  { dateRangeId = 201112, parentDateRangeId = 20111, periodKind = "Month",
    periodStart = @2010/12/1, periodEnd = @2010/12/31, periodShort = "Dec",
    fiscalYear = "FY2011" },

  { dateRangeId = 20112, parentDateRangeId = 2011, periodKind = "Quarter",
    periodStart = @2011/1/1, periodEnd = @2011/3/31, periodShort = "Q2",
    fiscalYear = "FY2011" },
  { dateRangeId = 201101, parentDateRangeId = 20112, periodKind = "Month",
    periodStart = @2011/1/1, periodEnd = @2011/1/31, periodShort = "Jan",
    fiscalYear = "FY2011" },
  { dateRangeId = 201102, parentDateRangeId = 20112, periodKind = "Month",
    periodStart = @2011/2/1, periodEnd = @2011/2/28, periodShort = "Feb",
    fiscalYear = "FY2011" },
  { dateRangeId = 201103, parentDateRangeId = 20112, periodKind = "Month",
    periodStart = @2011/3/1, periodEnd = @2011/3/31, periodShort = "Mar",
    fiscalYear = "FY2011" },

  { dateRangeId = 20113, parentDateRangeId = 2011, periodKind = "Quarter",
    periodStart = @2011/4/1, periodEnd = @2011/6/30, periodShort = "Q3",
    fiscalYear = "FY2011" },
  { dateRangeId = 201104, parentDateRangeId = 20113, periodKind = "Month",
    periodStart = @2011/4/1, periodEnd = @2011/4/30, periodShort = "Apr",
    fiscalYear = "FY2011" },
  { dateRangeId = 201105, parentDateRangeId = 20113, periodKind = "Month",
    periodStart = @2011/5/1, periodEnd = @2011/5/31, periodShort = "May",
    fiscalYear = "FY2011" },
  { dateRangeId = 201106, parentDateRangeId = 20113, periodKind = "Month",
    periodStart = @2011/6/1, periodEnd = @2011/6/30, periodShort = "Jun",
    fiscalYear = "FY2011" },

  { dateRangeId = 20114, parentDateRangeId = 2011, periodKind = "Quarter",
    periodStart = @2011/7/1, periodEnd = @2011/9/30, periodShort = "Q4",
    fiscalYear = "FY2011" },
  { dateRangeId = 201107, parentDateRangeId = 20114, periodKind = "Month",
    periodStart = @2011/7/1, periodEnd = @2011/7/31, periodShort = "Jul",
    fiscalYear = "FY2011" },
  { dateRangeId = 201108, parentDateRangeId = 20114, periodKind = "Month",
    periodStart = @2011/8/1, periodEnd = @2011/8/31, periodShort = "Aug",
    fiscalYear = "FY2011" },
  { dateRangeId = 201109, parentDateRangeId = 20114, periodKind = "Month",
    periodStart = @2011/9/1, periodEnd = @2011/9/30, periodShort = "Sep",
    fiscalYear = "FY2011" }
]

monthNodes  = filterEq periodKind "Month"   periodTree
quarterNodes = filterEq periodKind "Quarter" periodTree

-- ------------------------------------------------------------------ tariffs

-- The chargeable hourly rate per service class, revised twice in the year.
tariffs : [ serviceClass, effectiveFrom, hourlyRate ]
tariffs = relation [
  { serviceClass = "Emergency", effectiveFrom = @2010/10/1, hourlyRate = 185.0 },
  { serviceClass = "Emergency", effectiveFrom = @2011/4/1,  hourlyRate = 198.0 },
  { serviceClass = "Planned",   effectiveFrom = @2010/10/1, hourlyRate = 92.0 },
  { serviceClass = "Planned",   effectiveFrom = @2011/4/1,  hourlyRate = 97.5 },
  { serviceClass = "Upgrade",   effectiveFrom = @2011/1/1,  hourlyRate = 140.0 }
]

-- ================================================================ the pipeline

-- STEP 1. Bucket the orders into the tree's LEAVES by range. 18 columns in, 25
-- out; every order lands in exactly one month because the twelve leaf ranges
-- tile the fiscal year without overlapping. MEASURED: dumped to SQL through
-- `tracker/tools/sql-render.sh`, `inMonth # {orderId, orderDate, periodShort}`
-- returns 10 rows for 10 orders -- no duplicates on a boundary day, and nothing
-- lost.
inMonth = bucketBy periodStart periodEnd orderDate monthNodes serviceOrders

-- STEP 2. Walk the parent edge to the quarter. The quarter's own columns are
-- renamed on the way in, so the join is on the id alone and the result carries
-- both levels' ranges.
quarterOf : [ dateRangeId, quarterShort, parentStart, parentEnd ]
quarterOf = quarterNodes # {dateRangeId, periodShort, periodStart, periodEnd}
         |> rename periodShort quarterShort
         |> rename periodStart parentStart
         |> rename periodEnd parentEnd

inQuarter = join (rename parentDateRangeId dateRangeId (inMonth -# {dateRangeId}))
                 quarterOf

-- STEP 3. THE TARIFF IN FORCE AT EACH PERIOD START, per service class -- a
-- per-key as-of whose FINE relation is drawn from the tree. The spine is the
-- twelve leaf nodes crossed with the three service classes; each cell takes that
-- class's latest tariff at or before the month's start date.
classSpine = join (monthNodes # {dateRangeId, periodShort, periodStart})
                  (serviceOrders # {serviceClass})

tariffByPeriod = nearestBy {serviceClass} effectiveFrom tariffs periodStart classSpine

-- STEP 4. Value the labour at the tariff in force in the order's own month, and
-- add the parts.
orderValued =
     join inMonth (tariffByPeriod # {serviceClass, dateRangeId, hourlyRate})
  |> combine_Op (col_Op labourHours *_Op col_Op hourlyRate) labourValue
  |> combine_Op (col_Op labourValue +_Op col_Op partsCost) orderValue

-- ---------------------------------------------------------------- roll-ups

byFiscalPeriod : [ periodShort, dateRangeId, periodValue ]
byFiscalPeriod = aggregateByGroup_Agg (sum_Agg (col_Op orderValue))
                                {periodShort, dateRangeId} periodValue orderValued

byQuarter : [ quarterShort, quarterValue ]
byQuarter = aggregateByGroup_Agg (sum_Agg (col_Op orderValue))
                                 {quarterShort} quarterValue
                                 (join orderValued quarterOf)

-- The tree itself, navigable.
calendarTree = drilldownTable Nothing periodShort parentDateRangeId dateRangeId periodTree

-- Nullable projections on the credit notes.
disputed   = present creditNote serviceOrders
undisputed = missing creditNote serviceOrders

{- ==========================================================================
   WHAT `DateRange` IS FOR, AND THE TWO DEFECTS IT EXPOSES

   `DateRange.e` is not a relational module at all. It is seven VALUE-level
   functions over a `(Date, Date)` pair -- `ord`, `unsafeFormatDateRange`,
   `formatExcelPeriod`, `formatPeriod`, `formatPeriodOr`, `parseDateRange`,
   `ltStringDateRange` -- so by the same limit `SensorSeries.e` records for
   `Math` and `Vector`, none of them can produce a COLUMN. That is why the
   calendars in this directory are relations of `periodStart`/`periodEnd` and not
   `DateRange` values: a range that lives in an Ermine pair cannot be joined
   against a fact table.

   What it CAN do is label a range the program already holds, and that is what
   `periodLabel*` below does with the tree's own nodes. But two things go wrong,
   and both are `Date.e`'s doing rather than `DateRange`'s.

   BOTH DEFECTS ARE FIXED as of stage F3 (2026-09-08, tickets A3 and A4); what
   follows is the record of what they were, because the two bindings at the foot
   of this section were written to expose them and now pin the fix instead.

   DEFECT 1 -- `Date`'s accessors read the instant in the JVM'S DEFAULT TIMEZONE
   while its formatters did not, so a date literal was two different days at once.
   Measured on this repository for the single literal `@2011/1/1`:

                                    system TZ (MDT)     -Duser.timezone=UTC   AFTER F3
       unsafeFormatDate             "1/1/11"            "1/1/11"              unchanged
       formatMonthYear              "Jan 2011"          "Jan 2011"            unchanged
       getYear                      110  (= 2010)       111  (= 2011)         111
       getMonth                     11   (December)     0    (January)        0
       getDate                      31                  1                     1
       formatExcelDate              "Dec 31"            "Jan 1"               "Jan 1"
       quarter                      3                   1                     1
       formatQuarter                "Q4"                "Q2"                  "Q1"
       formatPeriodOr "custom"
         (1 Jan, 31 Jan)            "Jan 2011"          "custom"              "custom"
         (1 Jan,  1 Apr)            "custom"            "Q2 2011"             "Q2 2011"
       formatExcelPeriod
         (1 Jan, 31 Jan)            "Dec 31 to Jan 30"  "Jan 1 to Jan 31"     "Jan 1 to Jan 31"

   `formatDate`/`formatMonthYear` go through a formatter fixed at UTC;
   `getYear`/`getMonth`/`getDate` WERE `java.util.Date` methods and used the
   default zone. `Date.quarter`, `Date.formatQuarter`, `Date.formatExcelDate`,
   `DateRange.formatPeriod` and `DateRange.formatExcelPeriod` are all built on the
   accessors, so **a period label computed with `DateRange` was not reproducible
   across machines**. F3 bound the three accessors to `PrimExprs.get{Year,Month,
   Date}`, which read the same UTC calendar the formatters use, so the whole
   module is now one timezone; the last column above is the answer on ANY machine.
   The advice the defect motivated is still the better practice and is what this
   directory does: a report that must be the same everywhere labels its periods
   from a calendar COLUMN, because that survives a database round trip as well.

   DEFECT 2 -- `Date.formatQuarter` was wrong on its own terms, in two ways, and
   the two did not cancel.

       quarter d = getMonth d / 4 + 1                     -- Date.e, before F3
       formatQuarter d = orElse "Unknown" (at (quarter d) quarterNames)
       quarterNames = ["Q1", "Q2", "Q3", "Q4"]

   `getMonth` is 0-based and `List.at` is 0-based, but `quarter` returns a
   1-based number, so the lookup was off by one and **"Q1" was unreachable**. And
   the divisor was 4, not 3, so the "quarters" were four months long: months 0-3
   -> 1 -> "Q2", months 4-7 -> 2 -> "Q3", months 8-11 -> 3 -> "Q4". Under UTC,
   1 January reported "Q2". Recorded in `tracker/loopmodel/E3-EXAMPLES.md`; fixed
   in F3 as `getMonth d / 3 + 1` with `at (quarter d - 1)`, so `quarter` keeps its
   1-based meaning and January is "Q1".
   ========================================================================== -}

-- The tree's own ranges, as `(Date, Date)` pairs, labelled with `DateRange`.
fyRange, q2Range, janRange : (Date, Date)
fyRange  = (@2010/10/1, @2011/9/30)
q2Range  = (@2011/1/1,  @2011/4/1)
janRange = (@2011/1/1,  @2011/1/31)

periodLabelFy  = formatPeriodOr_DR "custom" fyRange
periodLabelQ2  = formatPeriodOr_DR "custom" q2Range
periodLabelJan = formatPeriodOr_DR "custom" janRange

-- The two formatters, which agree with the literal on every machine since F3.
rangeText  = unsafeFormatDateRange_DR janRange     -- "1/1/11 - 1/31/11"
excelText  = formatExcelPeriod_DR janRange         -- "Jan 1 to Jan 31" (was zone-dependent)

-- The parser, and the string ordering built on it.
parsedRange = parseDateRange_DR "1/1/2011-1/31/2011"
janBeforeFeb = ltStringDateRange_DR "1/1/2011-1/31/2011" "2/1/2011-2/28/2011"
janBeforeQ2  = lt_Od ord_DR janRange q2Range

-- The two `Date` accessors that exposed defect 1, and the quarter that exposed
-- defect 2, kept as values so a reader can evaluate them and see for themselves.
-- Since stage F3 they read the same on every machine: 0, 111, 1 and "Q1".
janMonthNumber   = getMonth_Dt @2011/1/1
janYearNumber    = getYear_Dt @2011/1/1
janQuarterNumber = quarter_Dt @2011/1/1
janQuarterLabel  = formatQuarter_Dt @2011/1/1
aprQuarterLabel  = formatQuarter_Dt @2011/4/1
julQuarterLabel  = formatQuarter_Dt @2011/7/1
octQuarterLabel  = formatQuarter_Dt @2010/10/1

{- ==========================================================================
   THE FIVE ARITHMETIC MODULES, AND WHY NO REPORT HERE IMPORTS THEM

   `Ring`, `Num`, `Long`, `Int` and `Nullable` are all VALUE-level, so none of
   them can appear in a `combine`; every arithmetic column in this directory is
   `Relation.Op`'s. `Double.e` is worth naming separately: it is an EMPTY module,
   two lines long, containing only `module Double where`. There is nothing in it
   to use.

   What is left for them is scalar work the report holds outside the relation --
   thresholds, conversion factors, checks -- which is what follows.
   ========================================================================== -}

-- `Ring`: the four operations plus `fromInt`, `zero` and `one`, at both
-- instances. A ring is how a generic numeric algorithm would be written if
-- Ermine had one to write; nothing in `core/examples` did.
budgetPerQuarter : Double
budgetPerQuarter = add_Rg doubleRing_Rg 42000.0 8000.0

engineersOnCall : Int
engineersOnCall = times_Rg intRing_Rg 3 4

noValue : Double
noValue = zero_Rg doubleRing_Rg

unitCharge : Int
unitCharge = one_Rg intRing_Rg

creditSign : Double
creditSign = negate_Rg doubleRing_Rg 1.0

netDays : Int
netDays = subtract_Rg intRing_Rg 30 7

quartersInYear : Double
quartersInYear = fromInt_Rg doubleRing_Rg 4

-- `Num`: the conversions `Relation.Op.fromNumericOp` does per row, done here per
-- value.
travelKmAsDouble : Double
travelKmAsDouble = toDouble_Nm 402

roundedHours : Int
roundedHours = toInt_Nm 12.75

absoluteCredit : Double
absoluteCredit = abs_Nm (0.0 - 450.0)

-- `Long`: `Date.getTime` is the only source of a `Long` in this directory, and
-- `Long.e`'s three functions are the only things to do with one.
fyStartMillis, fyEndMillis : Long
fyStartMillis = getTime_Dt @2010/10/1
fyEndMillis   = getTime_Dt @2011/9/30

fyLengthMillis : Long
fyLengthMillis = abs_Lg (fyStartMillis - fyEndMillis)

fyLater : Long
fyLater = max_Lg fyStartMillis fyEndMillis

fyEarlier : Long
fyEarlier = min_Lg fyStartMillis fyEndMillis

-- `Int`: bit and radix functions. `hexString` on a `dateRangeId` is a compact
-- key for a URL or a cache; `signum` is the sign test the relational algebra
-- has no operator for.
periodKeyHex : String
periodKeyHex = hexString_It 201104

periodKeyBase36 : String
periodKeyBase36 = radixString_It 201104 36

overOrUnder : Int
overOrUnder = signum_It (0 - 1)

-- `Nullable` ITSELF -- the module, not `Relation.Op.coalesce`. These four are how
-- a nullable is handled once it has LEFT the relation and is an ordinary Ermine
-- value; inside a relation `orZero`/`orElseNum`/`missing`/`present` are the
-- tools, and this directory uses those everywhere else.
sampleCredit : Nullable Double
sampleCredit = Some 450.0

creditAsMaybe : Maybe Double
creditAsMaybe = toMaybe_Nu sampleCredit

creditOrZero : Double
creditOrZero = getOrElse_Nu 0.0 sampleCredit

creditDoubled : Nullable Double
creditDoubled = map_Nu Double (x -> x * 2.0) sampleCredit

creditFromMaybe : Nullable Double
creditFromMaybe = fromMaybe_Nu Double Nothing

-- ------------------------------------------------------------------- report

fiscalReport = vflow [
  atomShown "## Service orders on a fiscal calendar held as a TREE OF DATE RANGES",
  atomShown "### The tree (FY2011 -> four quarters -> twelve months)",
  calendarTree,
  tabular Nothing periodTree,
  atomShown "### Orders bucketed into the leaf ranges",
  tabular Nothing (inMonth # {orderId, orderDate, periodShort, periodStart,
                              periodEnd, serviceClass, labourHours}),
  atomShown "### The same, walked up the parent edge to the quarter",
  tabular Nothing (inQuarter # {orderId, orderDate, quarterShort, parentStart,
                                parentEnd}),
  atomShown "### The tariff in force at each period start, per service class",
  tabular Nothing (tariffByPeriod # {periodShort, periodStart, serviceClass,
                                     effectiveFrom, hourlyRate}),
  atomShown "### Orders valued at the tariff in force in their own month",
  tabular Nothing (orderValued # {orderId, periodShort, serviceClass, labourHours,
                             hourlyRate, labourValue, partsCost, orderValue}),
  atomShown "### By period and by quarter",
  tabular Nothing byFiscalPeriod,
  tabular Nothing byQuarter,
  atomShown "### Orders with a credit note, and without",
  tabular Nothing (disputed # {orderId, customerRef, creditNote}),
  tabular Nothing (undisputed # {orderId, customerRef})
]
