module Wide.RevenueShare where

{- SHARE OF TOTAL AT TWO LEVELS, over a wide subscription book.

   "What fraction of its region does this account represent, and what fraction
   of its industry segment?"  Both numbers are the same report step with a
   different partition, and both are window aggregates rather than joins: the
   denominator is attached to each row without collapsing it, so the detail
   survives next to the ratio.

   The module deliberately shows BOTH spellings of that step:

     bookWithRegionShare  -- `share`, one helper call, one column
                             (`shareOfRegionPct`)
     bookWithShares       -- `windowTotal` then an ordinary `combine`, two steps
                             per level (`regionTotal`+`regionPct`,
                             `segmentTotal`+`segmentPct`)

   They compute the same number, and the module exists partly to MEASURE which
   is cheaper to check.  The expectation was the two-step form, because `share`'s
   Op is `col m /_Op windowed(sum m) w` and `(/_Op)` carries `OpBin`'s
   four-constraint inclusion-exclusion lattice on top of the window's own
   constraints.  The measurement says the opposite -- one larger solve beats two
   smaller ones, 0.05-0.06 s against 0.08-0.09 s on this very row.  Section 5 of
   `tracker/loopmodel/E1-EXAMPLES.md` has the reproduction.

   Fact:       subscription (21 columns)
                 keys      subscriptionId, accountId, planId, regionId
                 money     mrr, annualRun, expansionMrr, contractionMrr,
                           discountPct
                 usage     seats, activeSeats, usageGb, apiCalls,
                           integrationCount
                 health    churnRiskPct, nps, supportTickets, tenureMonths
                 dates     startDay, renewalDay
                 people    csmName
   Dimensions: account (accountId -> accountName, segmentName, tierName)
               region  (regionId  -> regionName, theatreName)

   Helpers used: share, windowTotal (Wide.Helpers).

   Solver shapes exercised:
     * `windowTotal` twice with DIFFERENT partitions over the same row, so the
       same existential pattern `wm <- (m, k)` / `r <- (wm, o)` is instantiated
       twice and the two results are then combined -- the residuals chain;
     * `share`, the arithmetic combination of two Ops over different rows, which
       is the only place in this directory where an `OpBin` lattice meets a
       window's minted row -- the shape expected to be dear and measured cheap;
     * an unsorted window (`empty_Srt`), the one shape the SQL emitter accepts
       without an ORDER BY.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/RevenueShare.e
     >> :type bookWithShares
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field subscriptionId, accountId, planId, regionId : Int
field seats, activeSeats, supportTickets, tenureMonths, integrationCount : Int
field mrr, annualRun, expansionMrr, contractionMrr, discountPct : Double
field usageGb, apiCalls, churnRiskPct, nps : Double
field startDay, renewalDay : Date
field csmName, accountName, segmentName, tierName : String
field regionName, theatreName : String
field regionTotal, segmentTotal, regionPct, segmentPct, shareOfRegionPct : Double

-- Twenty-one columns, eight subscriptions across two regions and two segments,
-- so that both partitions have something to divide by.
subscription = relation [
  { subscriptionId = 5001, accountId = 1, planId = 3, regionId = 1,
    mrr = 41800.0, annualRun = 501600.0, expansionMrr = 3100.0, contractionMrr = 0.0,
    discountPct = 12.0, seats = 480, activeSeats = 441, usageGb = 8120.0,
    apiCalls = 1240000.0, integrationCount = 7, churnRiskPct = 6.5, nps = 62.0,
    supportTickets = 18, tenureMonths = 41,
    startDay = yyyymmdd 2021 11 1, renewalDay = yyyymmdd 2026 11 1, csmName = "L. Barros" },
  { subscriptionId = 5002, accountId = 2, planId = 2, regionId = 1,
    mrr = 18200.0, annualRun = 218400.0, expansionMrr = 900.0, contractionMrr = 1200.0,
    discountPct = 5.0, seats = 210, activeSeats = 168, usageGb = 3310.0,
    apiCalls = 402000.0, integrationCount = 3, churnRiskPct = 22.0, nps = 31.0,
    supportTickets = 44, tenureMonths = 19,
    startDay = yyyymmdd 2024 3 1, renewalDay = yyyymmdd 2026 3 1, csmName = "L. Barros" },
  { subscriptionId = 5003, accountId = 3, planId = 3, regionId = 1,
    mrr = 27400.0, annualRun = 328800.0, expansionMrr = 5600.0, contractionMrr = 0.0,
    discountPct = 0.0, seats = 300, activeSeats = 291, usageGb = 6040.0,
    apiCalls = 883000.0, integrationCount = 9, churnRiskPct = 3.1, nps = 74.0,
    supportTickets = 9, tenureMonths = 28,
    startDay = yyyymmdd 2023 6 1, renewalDay = yyyymmdd 2026 6 1, csmName = "N. Osei" },
  { subscriptionId = 5004, accountId = 4, planId = 1, regionId = 1,
    mrr = 6100.0, annualRun = 73200.0, expansionMrr = 0.0, contractionMrr = 800.0,
    discountPct = 18.0, seats = 60, activeSeats = 38, usageGb = 740.0,
    apiCalls = 61000.0, integrationCount = 1, churnRiskPct = 48.0, nps = 12.0,
    supportTickets = 61, tenureMonths = 8,
    startDay = yyyymmdd 2025 2 1, renewalDay = yyyymmdd 2026 2 1, csmName = "N. Osei" },
  { subscriptionId = 5005, accountId = 5, planId = 3, regionId = 2,
    mrr = 33900.0, annualRun = 406800.0, expansionMrr = 2200.0, contractionMrr = 0.0,
    discountPct = 8.0, seats = 390, activeSeats = 372, usageGb = 7210.0,
    apiCalls = 1010000.0, integrationCount = 6, churnRiskPct = 9.0, nps = 58.0,
    supportTickets = 21, tenureMonths = 35,
    startDay = yyyymmdd 2022 8 1, renewalDay = yyyymmdd 2026 8 1, csmName = "I. Kovac" },
  { subscriptionId = 5006, accountId = 6, planId = 2, regionId = 2,
    mrr = 15600.0, annualRun = 187200.0, expansionMrr = 1400.0, contractionMrr = 0.0,
    discountPct = 10.0, seats = 175, activeSeats = 160, usageGb = 2880.0,
    apiCalls = 341000.0, integrationCount = 4, churnRiskPct = 14.0, nps = 44.0,
    supportTickets = 27, tenureMonths = 22,
    startDay = yyyymmdd 2023 12 1, renewalDay = yyyymmdd 2026 12 1, csmName = "I. Kovac" },
  { subscriptionId = 5007, accountId = 7, planId = 1, regionId = 2,
    mrr = 9200.0, annualRun = 110400.0, expansionMrr = 300.0, contractionMrr = 0.0,
    discountPct = 0.0, seats = 95, activeSeats = 88, usageGb = 1190.0,
    apiCalls = 128000.0, integrationCount = 2, churnRiskPct = 17.5, nps = 39.0,
    supportTickets = 15, tenureMonths = 14,
    startDay = yyyymmdd 2024 8 1, renewalDay = yyyymmdd 2026 8 1, csmName = "R. Tesfaye" },
  { subscriptionId = 5008, accountId = 8, planId = 2, regionId = 2,
    mrr = 21300.0, annualRun = 255600.0, expansionMrr = 0.0, contractionMrr = 2600.0,
    discountPct = 15.0, seats = 240, activeSeats = 191, usageGb = 4460.0,
    apiCalls = 517000.0, integrationCount = 5, churnRiskPct = 31.0, nps = 25.0,
    supportTickets = 38, tenureMonths = 26,
    startDay = yyyymmdd 2023 9 1, renewalDay = yyyymmdd 2026 9 1, csmName = "R. Tesfaye" }
]

accountDim = relation [
  { accountId = 1, accountName = "Cadence Health",  segmentName = "Healthcare", tierName = "Enterprise" },
  { accountId = 2, accountName = "Bramble Logistics", segmentName = "Logistics", tierName = "Mid-market" },
  { accountId = 3, accountName = "Ostrava Bank",    segmentName = "Financial",  tierName = "Enterprise" },
  { accountId = 4, accountName = "Pellet Foods",    segmentName = "Logistics",  tierName = "SMB" },
  { accountId = 5, accountName = "Kestrel Insure",  segmentName = "Financial",  tierName = "Enterprise" },
  { accountId = 6, accountName = "Vireo Clinics",   segmentName = "Healthcare", tierName = "Mid-market" },
  { accountId = 7, accountName = "Talus Freight",   segmentName = "Logistics",  tierName = "SMB" },
  { accountId = 8, accountName = "Marrow Labs",     segmentName = "Healthcare", tierName = "Mid-market" }
]

regionDim = relation [
  { regionId = 1, regionName = "Americas", theatreName = "West" },
  { regionId = 2, regionName = "EMEA",     theatreName = "East" }
]

book = subscription ** accountDim ** regionDim

-- ---------------------------------------------------------- one helper call
--
-- The whole share-of-region step, in one line and one column.
bookWithRegionShare = share {regionName} mrr shareOfRegionPct book

-- ---------------------------------------------- the same thing in two steps
--
-- `windowTotal` attaches the denominator; an ordinary `combine` divides.  Two
-- levels: region and segment.  Because each step's OUTPUT is the next step's
-- INPUT, the row variables chain -- `book`'s row feeds `withRegionTotal`'s,
-- which feeds `withSegmentTotal`'s, and each link is a fresh existential.
withRegionTotal  = windowTotal {regionName}  mrr regionTotal  book
withSegmentTotal = windowTotal {segmentName} mrr segmentTotal withRegionTotal

bookWithShares =
  combine_Op (col_Op mrr /_Op col_Op segmentTotal) segmentPct
    (combine_Op (col_Op mrr /_Op col_Op regionTotal) regionPct withSegmentTotal)

shareReport = vflow [
  atomShown "## Recurring revenue, share of total",
  atomShown "### Share of region and of segment",
  tabular Nothing
    (bookWithShares # { accountName, regionName, segmentName, mrr,
                        regionTotal, regionPct, segmentTotal, segmentPct }),
  atomShown "### The same region share, written with `share`",
  tabular Nothing
    (bookWithRegionShare # { accountName, regionName, mrr, shareOfRegionPct }),
  atomShown "### The book",
  tabular Nothing
    (book # { accountName, tierName, regionName, mrr, seats, activeSeats, churnRiskPct })
]
