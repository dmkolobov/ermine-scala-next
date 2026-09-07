module Time.SubscriptionWaterfall where

{- A SUBSCRIPTION-REVENUE WATERFALL: new business, expansion, contraction and
   churn per month, the net movement, the cumulative book, and both
   month-over-month and YEAR-over-year growth -- the last of which needs a
   sixteen-month history and an arithmetic period index, not a date column.

   Fact:  events (19 fields: eventId, eventDate, accountId, accountName,
                  segment, industry, region, country, plan, planTier, seats,
                  mrrDelta, eventType, salesRep, channel, contractMonths,
                  discountPct, invoiceRef, signupDate)

   SHAPES EXERCISED
     * `monthsSince` -- a period index DERIVED from the date by `dateDiff`,
       rather than carried in the data. `Relation.Op` has no year/month
       accessor, so this is the only way to get one.
     * `shiftBy` -- the shifted self-join, twice over the same relation with
       different lags (1 and 12) and different renamed measures, then both
       joined back. Two `withFieldCopy` mints in one expression.
     * `pctChange` at two lags.
     * `runningSum` and `movingSum` -- unbounded and 3-period trailing windows
       over the period index.
     * A grouped `Mem` roll-up materialised back to a `Relation`.
     * `band3` on a Double, at the call site of a 20-column relation.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/SubscriptionWaterfall.e
     >> waterfallReport

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
import Relation.Row as Rw
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field eventId, accountId, seats, contractMonths, monthIx : Int
field eventDate, signupDate : Date
field accountName, segment, industry, region, country : String
field plan, planTier, eventType, salesRep, channel, invoiceRef : String
field mrrDelta, discountPct : Double
field netMrr, priorMrr, priorYearMrr, momPct, yoyPct : Double
field cumulativeMrr, trailing3 : Double
field growthBand, monthLabel : String

-- ------------------------------------------------------------- the fact table

-- Nineteen columns, sixteen events, January 2011 through April 2012 -- long
-- enough that the four most recent months have a same-month-last-year
-- counterpart, which is what a year-over-year column needs.
events : [ eventId, eventDate, accountId, accountName, segment, industry
         , region, country, plan, planTier, seats, mrrDelta, eventType
         , salesRep, channel, contractMonths, discountPct, invoiceRef, signupDate ]
events = relation [
  { eventId = 1, eventDate = @2011/1/12, accountId = 100, accountName = "Northwind Traders",
    segment = "Enterprise", industry = "Retail", region = "AMER", country = "US",
    plan = "Platform", planTier = "Tier 3", seats = 240, mrrDelta = 18400.0,
    eventType = "New", salesRep = "j.okafor", channel = "Direct",
    contractMonths = 36, discountPct = 0.12, invoiceRef = "INV-11001",
    signupDate = @2011/1/12 },
  { eventId = 2, eventDate = @2011/2/8, accountId = 101, accountName = "Contoso GmbH",
    segment = "Enterprise", industry = "Manufacturing", region = "EMEA", country = "DE",
    plan = "Platform", planTier = "Tier 2", seats = 130, mrrDelta = 9750.0,
    eventType = "New", salesRep = "m.lindqvist", channel = "Partner",
    contractMonths = 24, discountPct = 0.05, invoiceRef = "INV-11014",
    signupDate = @2011/2/8 },
  { eventId = 3, eventDate = @2011/3/22, accountId = 100, accountName = "Northwind Traders",
    segment = "Enterprise", industry = "Retail", region = "AMER", country = "US",
    plan = "Platform", planTier = "Tier 3", seats = 60, mrrDelta = 4600.0,
    eventType = "Expansion", salesRep = "j.okafor", channel = "Direct",
    contractMonths = 33, discountPct = 0.12, invoiceRef = "INV-11052",
    signupDate = @2011/1/12 },
  { eventId = 4, eventDate = @2011/4/5, accountId = 102, accountName = "Fabrikam Ltd",
    segment = "SMB", industry = "Services", region = "EMEA", country = "GB",
    plan = "Team", planTier = "Tier 1", seats = 25, mrrDelta = 1875.0,
    eventType = "New", salesRep = "a.petrova", channel = "Self-serve",
    contractMonths = 12, discountPct = 0.0, invoiceRef = "INV-11071",
    signupDate = @2011/4/5 },
  { eventId = 5, eventDate = @2011/5/19, accountId = 101, accountName = "Contoso GmbH",
    segment = "Enterprise", industry = "Manufacturing", region = "EMEA", country = "DE",
    plan = "Platform", planTier = "Tier 2", seats = -20, mrrDelta = -1500.0,
    eventType = "Contraction", salesRep = "m.lindqvist", channel = "Partner",
    contractMonths = 21, discountPct = 0.05, invoiceRef = "INV-11098",
    signupDate = @2011/2/8 },
  { eventId = 6, eventDate = @2011/6/30, accountId = 103, accountName = "Tailspin Toys",
    segment = "SMB", industry = "Retail", region = "AMER", country = "CA",
    plan = "Team", planTier = "Tier 1", seats = 40, mrrDelta = 3000.0,
    eventType = "New", salesRep = "s.ahmed", channel = "Self-serve",
    contractMonths = 12, discountPct = 0.08, invoiceRef = "INV-11130",
    signupDate = @2011/6/30 },
  { eventId = 7, eventDate = @2011/7/14, accountId = 104, accountName = "Litware Bank",
    segment = "Enterprise", industry = "Financial", region = "EMEA", country = "CH",
    plan = "Platform", planTier = "Tier 3", seats = 310, mrrDelta = 24800.0,
    eventType = "New", salesRep = "a.petrova", channel = "Direct",
    contractMonths = 36, discountPct = 0.15, invoiceRef = "INV-11162",
    signupDate = @2011/7/14 },
  { eventId = 8, eventDate = @2011/8/2, accountId = 102, accountName = "Fabrikam Ltd",
    segment = "SMB", industry = "Services", region = "EMEA", country = "GB",
    plan = "Team", planTier = "Tier 1", seats = -25, mrrDelta = -1875.0,
    eventType = "Churn", salesRep = "a.petrova", channel = "Self-serve",
    contractMonths = 0, discountPct = 0.0, invoiceRef = "INV-11180",
    signupDate = @2011/4/5 },
  { eventId = 9, eventDate = @2011/9/27, accountId = 105, accountName = "Adatum Media",
    segment = "Mid-market", industry = "Media", region = "AMER", country = "US",
    plan = "Business", planTier = "Tier 2", seats = 90, mrrDelta = 6300.0,
    eventType = "New", salesRep = "j.okafor", channel = "Partner",
    contractMonths = 24, discountPct = 0.1, invoiceRef = "INV-11220",
    signupDate = @2011/9/27 },
  { eventId = 10, eventDate = @2011/10/11, accountId = 104, accountName = "Litware Bank",
    segment = "Enterprise", industry = "Financial", region = "EMEA", country = "CH",
    plan = "Platform", planTier = "Tier 3", seats = 55, mrrDelta = 4400.0,
    eventType = "Expansion", salesRep = "a.petrova", channel = "Direct",
    contractMonths = 33, discountPct = 0.15, invoiceRef = "INV-11251",
    signupDate = @2011/7/14 },
  { eventId = 11, eventDate = @2011/11/8, accountId = 106, accountName = "Wingtip Devices",
    segment = "Mid-market", industry = "Manufacturing", region = "APAC", country = "JP",
    plan = "Business", planTier = "Tier 2", seats = 120, mrrDelta = 8400.0,
    eventType = "New", salesRep = "s.ahmed", channel = "Partner",
    contractMonths = 24, discountPct = 0.07, invoiceRef = "INV-11288",
    signupDate = @2011/11/8 },
  { eventId = 12, eventDate = @2011/12/20, accountId = 103, accountName = "Tailspin Toys",
    segment = "SMB", industry = "Retail", region = "AMER", country = "CA",
    plan = "Team", planTier = "Tier 1", seats = -40, mrrDelta = -3000.0,
    eventType = "Churn", salesRep = "s.ahmed", channel = "Self-serve",
    contractMonths = 0, discountPct = 0.08, invoiceRef = "INV-11319",
    signupDate = @2011/6/30 },
  { eventId = 13, eventDate = @2012/1/16, accountId = 107, accountName = "Proseware Health",
    segment = "Enterprise", industry = "Healthcare", region = "AMER", country = "US",
    plan = "Platform", planTier = "Tier 3", seats = 280, mrrDelta = 22400.0,
    eventType = "New", salesRep = "j.okafor", channel = "Direct",
    contractMonths = 36, discountPct = 0.13, invoiceRef = "INV-12008",
    signupDate = @2012/1/16 },
  { eventId = 14, eventDate = @2012/2/9, accountId = 105, accountName = "Adatum Media",
    segment = "Mid-market", industry = "Media", region = "AMER", country = "US",
    plan = "Business", planTier = "Tier 2", seats = 35, mrrDelta = 2450.0,
    eventType = "Expansion", salesRep = "j.okafor", channel = "Partner",
    contractMonths = 19, discountPct = 0.1, invoiceRef = "INV-12041",
    signupDate = @2011/9/27 },
  { eventId = 15, eventDate = @2012/3/28, accountId = 106, accountName = "Wingtip Devices",
    segment = "Mid-market", industry = "Manufacturing", region = "APAC", country = "JP",
    plan = "Business", planTier = "Tier 2", seats = -30, mrrDelta = -2100.0,
    eventType = "Contraction", salesRep = "s.ahmed", channel = "Partner",
    contractMonths = 16, discountPct = 0.07, invoiceRef = "INV-12079",
    signupDate = @2011/11/8 },
  { eventId = 16, eventDate = @2012/4/24, accountId = 108, accountName = "Trey Logistics",
    segment = "Enterprise", industry = "Transport", region = "EMEA", country = "NL",
    plan = "Platform", planTier = "Tier 2", seats = 165, mrrDelta = 12375.0,
    eventType = "New", salesRep = "m.lindqvist", channel = "Direct",
    contractMonths = 24, discountPct = 0.09, invoiceRef = "INV-12114",
    signupDate = @2012/4/24 }
]

-- ================================================================ the pipeline

-- STEP 1. A DENSE INTEGER MONTH INDEX, derived from the date. `dateDiff` on
-- `months` from a fixed epoch (December 2010) gives 1 for January 2011 and 16
-- for April 2012, which is what makes "twelve months earlier" subtraction.
monthIndexed = combine_Op (monthsSince @2010/12/1 eventDate) monthIx events

-- STEP 2. The waterfall components: net MRR movement per month and event type.
byType : [ monthIx, eventType, mrrDelta ]
byType = materialize (groupBy {monthIx, eventType} (sumBy mrrDelta) monthIndexed)

-- STEP 3. The net line, one row per month with activity.
net : [ monthIx, netMrr ]
net = materialize (groupBy {monthIx} (sumBy mrrDelta) monthIndexed)
   |> rename mrrDelta netMrr

-- STEP 4. THE SHIFTED SELF-JOINS. `shiftBy` mints a fresh index column, adds
-- the lag to it, drops the original and renames the copy back on top -- so the
-- shifted relation lines up with the unshifted one on `monthIx` alone.
lastMonth = shiftBy monthIx netMrr priorMrr 1 net
lastYear  = shiftBy monthIx netMrr priorYearMrr 12 net

-- Month-over-month: only months whose predecessor also had activity survive.
mom = combine_Op (pctChange netMrr priorMrr) momPct (join net lastMonth)

-- Year-over-year: only the last four months of the history have a counterpart,
-- and the report SHOWS that rather than filling zeros.
yoy = combine_Op (pctChange netMrr priorYearMrr) yoyPct (join net lastYear)

-- STEP 5. Cumulative book and a trailing three-month sum, both windows over
-- the period index. The partition is the EMPTY row -- `Relation.Row.empty`,
-- spelled `empty_Rw` here, because `{}` is a record literal and not a row.
booked =
     net
  |> combine_Op (runningSum empty_Rw monthIx netMrr) cumulativeMrr
  |> combine_Op (movingSum empty_Rw monthIx netMrr 2) trailing3

-- STEP 6. Band the month-over-month growth. `band3` is a nested conditional in
-- a helper -- the shape `Ai/Common.e` warned about -- called here on a
-- four-column relation and, below, on the twenty-column detail.
momBanded = combine_Op (band3 momPct (0.0 - 0.0001) "Down" 0.25 "Steady" "Surging")
                    growthBand mom

-- The same conditional helper at a WIDE call site: twenty columns.
detailBanded =
  combine_Op (band3 discountPct 0.05 "List-ish" 0.12 "Discounted" "Heavily discounted")
             growthBand monthIndexed

-- ------------------------------------------------------------------- report

waterfallChart =
  chart_K ([chartTitle_O := "MRR movement by month and type"]_Opt)
          defaultUnscaled defaultScaled
          [bar eventType monthIx mrrDelta byType]

waterfallReport = vflow [
  atomShown "## Subscription revenue waterfall, FY2011 - FY2012",
  atomShown "### Movement by month and event type",
  waterfallChart,
  tabular Nothing byType,
  atomShown "### Net, cumulative and trailing three months",
  tabular Nothing booked,
  atomShown "### Month over month",
  tabular Nothing momBanded,
  atomShown "### Year over year (only months with a counterpart twelve back)",
  tabular Nothing yoy,
  atomShown "### Events, with the discount band",
  tabular Nothing (detailBanded # {eventId, eventDate, monthIx, accountName,
                                   eventType, mrrDelta, discountPct, growthBand})
]
