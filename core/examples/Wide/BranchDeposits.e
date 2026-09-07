module Wide.BranchDeposits where

{- A MONTHLY DEPOSIT SERIES joined to TWO CALENDARS that do not share its dates.

   The fact table is monthly.  The policy rate changes when a central bank
   decides it should, and the exchange rate is published on business days.
   Neither calendar lines up with month ends, so the join is "the latest value
   at or before this date" rather than an equality -- `lookupLatest`, which
   `Relation.e` builds out of `nearestDate` and a copy of the date column.

   On top of that sit two window steps that need nothing from the calendars: a
   three-month trailing mean of the balance, and the latest month per branch.

   Fact:       deposit (22 columns)
                 keys      depositId, branchId, productId, asOfDay
                 balances  balanceEur, averageBalanceEur, peakBalanceEur,
                           minimumBalanceEur
                 flow      inflowEur, outflowEur, netFlowEur, feeIncomeEur
                 accounts  accountCount, newAccounts, closedAccounts,
                           dormantAccounts
                 pricing   headlineRatePct, blendedRatePct, promoRatePct
                 service   branchVisits, digitalLogins, complaintCount
   Calendars:  rateCard (rateDay -> policyRatePct)       -- irregular
               fxCard   (fxDay   -> eurUsdRate)          -- business days
   Dimensions: branch  (branchId  -> branchName, cityName, regionName)
               product (productId -> productName, productClass)

   Helpers used: asOfDates, movingAverage, latestPerKey, asc (Wide.Helpers);
                 rename, combine (stdlib).  `groupBy` is reached only through
                 `latestPerKey`'s body, never called here.  The module uses BOTH
                 date helpers on one table: `asOfDates` for "what was the rate on
                 each month end", `latestPerKey` for "what is the newest month
                 for each branch".  They are not the same question.

   Solver shapes exercised:
     * `asOfDates` (= stdlib `lookupLatest`), whose own signature is a single
       `r <- (h, t)` but whose
       BODY (`withFieldCopy`, `nearestDate`, two renames and a join) is one of
       the heaviest in the standard library -- `core/examples/incomplete/
       Signatures.e` records FIFTEEN inferred constraints for a close relative --
       instantiated twice here, at two different date columns;
     * `movingAverage`'s three-deep chain of minted rows over a 27-column row;
     * `latestPerKey`, whose `groupBy` solves `kv <- (k, v)` and `kv2 <- (k, v2)`
       with `v2 = v` -- the degenerate case where the two constraints coincide.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/BranchDeposits.e
     >> :type seriesWithRates
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field depositId, branchId, productId : Int
field accountCount, newAccounts, closedAccounts, dormantAccounts : Int
field branchVisits, digitalLogins, complaintCount : Int
field asOfDay, rateDay, fxDay : Date
field balanceEur, averageBalanceEur, peakBalanceEur, minimumBalanceEur : Double
field inflowEur, outflowEur, netFlowEur, feeIncomeEur : Double
field headlineRatePct, blendedRatePct, promoRatePct : Double
field policyRatePct, eurUsdRate : Double
field branchName, cityName, regionName, productName, productClass : String
field balance3m, spreadPct, balanceUsd : Double

-- Twenty-two columns.  Two branches, five month ends each.
deposit = relation [
  { depositId = 1, branchId = 1, productId = 10, asOfDay = yyyymmdd 2025 1 31,
    balanceEur = 41200000.0, averageBalanceEur = 40800000.0,
    peakBalanceEur = 42600000.0, minimumBalanceEur = 39100000.0,
    inflowEur = 5100000.0, outflowEur = 4400000.0, netFlowEur = 700000.0,
    feeIncomeEur = 118000.0,
    accountCount = 18400, newAccounts = 310, closedAccounts = 190, dormantAccounts = 1420,
    headlineRatePct = 2.10, blendedRatePct = 1.84, promoRatePct = 2.75,
    branchVisits = 6100, digitalLogins = 214000, complaintCount = 22 },
  { depositId = 2, branchId = 1, productId = 10, asOfDay = yyyymmdd 2025 2 28,
    balanceEur = 42800000.0, averageBalanceEur = 41900000.0,
    peakBalanceEur = 43400000.0, minimumBalanceEur = 40700000.0,
    inflowEur = 5600000.0, outflowEur = 4000000.0, netFlowEur = 1600000.0,
    feeIncomeEur = 121000.0,
    accountCount = 18610, newAccounts = 340, closedAccounts = 130, dormantAccounts = 1405,
    headlineRatePct = 2.10, blendedRatePct = 1.88, promoRatePct = 2.75,
    branchVisits = 5800, digitalLogins = 221000, complaintCount = 19 },
  { depositId = 3, branchId = 1, productId = 10, asOfDay = yyyymmdd 2025 3 31,
    balanceEur = 41100000.0, averageBalanceEur = 42000000.0,
    peakBalanceEur = 43100000.0, minimumBalanceEur = 40200000.0,
    inflowEur = 4700000.0, outflowEur = 6400000.0, netFlowEur = -1700000.0,
    feeIncomeEur = 116000.0,
    accountCount = 18520, newAccounts = 260, closedAccounts = 350, dormantAccounts = 1441,
    headlineRatePct = 2.35, blendedRatePct = 2.02, promoRatePct = 3.00,
    branchVisits = 6400, digitalLogins = 229000, complaintCount = 31 },
  { depositId = 4, branchId = 1, productId = 10, asOfDay = yyyymmdd 2025 4 30,
    balanceEur = 43900000.0, averageBalanceEur = 42400000.0,
    peakBalanceEur = 44800000.0, minimumBalanceEur = 41000000.0,
    inflowEur = 6900000.0, outflowEur = 4100000.0, netFlowEur = 2800000.0,
    feeIncomeEur = 129000.0,
    accountCount = 18790, newAccounts = 420, closedAccounts = 150, dormantAccounts = 1398,
    headlineRatePct = 2.35, blendedRatePct = 2.11, promoRatePct = 3.00,
    branchVisits = 6050, digitalLogins = 236000, complaintCount = 17 },
  { depositId = 5, branchId = 1, productId = 10, asOfDay = yyyymmdd 2025 5 31,
    balanceEur = 45300000.0, averageBalanceEur = 44600000.0,
    peakBalanceEur = 46100000.0, minimumBalanceEur = 43600000.0,
    inflowEur = 6200000.0, outflowEur = 4800000.0, netFlowEur = 1400000.0,
    feeIncomeEur = 134000.0,
    accountCount = 19010, newAccounts = 380, closedAccounts = 160, dormantAccounts = 1376,
    headlineRatePct = 2.35, blendedRatePct = 2.14, promoRatePct = 3.00,
    branchVisits = 5900, digitalLogins = 244000, complaintCount = 20 },
  { depositId = 6, branchId = 2, productId = 20, asOfDay = yyyymmdd 2025 1 31,
    balanceEur = 17800000.0, averageBalanceEur = 17500000.0,
    peakBalanceEur = 18200000.0, minimumBalanceEur = 16900000.0,
    inflowEur = 2200000.0, outflowEur = 2000000.0, netFlowEur = 200000.0,
    feeIncomeEur = 61000.0,
    accountCount = 9100, newAccounts = 140, closedAccounts = 110, dormantAccounts = 880,
    headlineRatePct = 1.90, blendedRatePct = 1.61, promoRatePct = 2.40,
    branchVisits = 3100, digitalLogins = 98000, complaintCount = 11 },
  { depositId = 7, branchId = 2, productId = 20, asOfDay = yyyymmdd 2025 2 28,
    balanceEur = 17400000.0, averageBalanceEur = 17600000.0,
    peakBalanceEur = 18000000.0, minimumBalanceEur = 17000000.0,
    inflowEur = 1900000.0, outflowEur = 2300000.0, netFlowEur = -400000.0,
    feeIncomeEur = 59000.0,
    accountCount = 9040, newAccounts = 120, closedAccounts = 180, dormantAccounts = 903,
    headlineRatePct = 1.90, blendedRatePct = 1.63, promoRatePct = 2.40,
    branchVisits = 2950, digitalLogins = 101000, complaintCount = 14 },
  { depositId = 8, branchId = 2, productId = 20, asOfDay = yyyymmdd 2025 3 31,
    balanceEur = 18600000.0, averageBalanceEur = 18000000.0,
    peakBalanceEur = 19100000.0, minimumBalanceEur = 17300000.0,
    inflowEur = 3000000.0, outflowEur = 1800000.0, netFlowEur = 1200000.0,
    feeIncomeEur = 66000.0,
    accountCount = 9260, newAccounts = 300, closedAccounts = 80, dormantAccounts = 871,
    headlineRatePct = 2.15, blendedRatePct = 1.79, promoRatePct = 2.65,
    branchVisits = 3200, digitalLogins = 106000, complaintCount = 9 },
  { depositId = 9, branchId = 2, productId = 20, asOfDay = yyyymmdd 2025 4 30,
    balanceEur = 19100000.0, averageBalanceEur = 18800000.0,
    peakBalanceEur = 19400000.0, minimumBalanceEur = 18400000.0,
    inflowEur = 2600000.0, outflowEur = 2100000.0, netFlowEur = 500000.0,
    feeIncomeEur = 68000.0,
    accountCount = 9380, newAccounts = 210, closedAccounts = 90, dormantAccounts = 858,
    headlineRatePct = 2.15, blendedRatePct = 1.84, promoRatePct = 2.65,
    branchVisits = 3050, digitalLogins = 110000, complaintCount = 12 },
  { depositId = 10, branchId = 2, productId = 20, asOfDay = yyyymmdd 2025 5 31,
    balanceEur = 18900000.0, averageBalanceEur = 19000000.0,
    peakBalanceEur = 19600000.0, minimumBalanceEur = 18500000.0,
    inflowEur = 2300000.0, outflowEur = 2500000.0, netFlowEur = -200000.0,
    feeIncomeEur = 67000.0,
    accountCount = 9330, newAccounts = 160, closedAccounts = 210, dormantAccounts = 869,
    headlineRatePct = 2.15, blendedRatePct = 1.86, promoRatePct = 2.65,
    branchVisits = 2900, digitalLogins = 113000, complaintCount = 15 }
]

branchDim = relation [
  { branchId = 1, branchName = "Rathmines", cityName = "Dublin", regionName = "Leinster" },
  { branchId = 2, branchName = "Salthill",  cityName = "Galway", regionName = "Connacht" }
]

productDim = relation [
  { productId = 10, productName = "Instant access saver", productClass = "Demand" },
  { productId = 20, productName = "Two-year term",        productClass = "Term" }
]

-- Calendar one: the policy rate, which moves when it moves.
rateCard = relation [
  { rateDay = yyyymmdd 2024 12 12, policyRatePct = 3.15 },
  { rateDay = yyyymmdd 2025 3 6,   policyRatePct = 2.90 },
  { rateDay = yyyymmdd 2025 4 17,  policyRatePct = 2.65 }
]

-- Calendar two: the exchange rate, published on business days.
fxCard = relation [
  { fxDay = yyyymmdd 2025 1 30, eurUsdRate = 1.0412 },
  { fxDay = yyyymmdd 2025 2 27, eurUsdRate = 1.0488 },
  { fxDay = yyyymmdd 2025 3 28, eurUsdRate = 1.0801 },
  { fxDay = yyyymmdd 2025 4 30, eurUsdRate = 1.1372 },
  { fxDay = yyyymmdd 2025 5 30, eurUsdRate = 1.1290 }
]

-- Twenty-seven columns after the dimension joins.
depositSeries = deposit ** branchDim ** productDim

-- --------------------------------------------------- as-of the first calendar
--
-- The month ends, renamed into the rate calendar's date column, are the dates
-- to look up; `lookupLatest` answers with the rate row in force on each.
monthEndsAsRateDays = rename asOfDay rateDay (depositSeries # {asOfDay})
ratesAtMonthEnds    = asOfDates rateDay monthEndsAsRateDays rateCard
seriesWithPolicy    = depositSeries ** rename rateDay asOfDay ratesAtMonthEnds

-- --------------------------------------------------- as-of the second calendar
monthEndsAsFxDays = rename asOfDay fxDay (depositSeries # {asOfDay})
fxAtMonthEnds     = asOfDates fxDay monthEndsAsFxDays fxCard
seriesWithRates   = seriesWithPolicy ** rename fxDay asOfDay fxAtMonthEnds

-- Two ordinary derived columns on the doubly-joined row.
withSpread  = combine_Op (col_Op headlineRatePct -_Op col_Op policyRatePct)
                         spreadPct seriesWithRates
withUsd     = combine_Op (col_Op balanceEur *_Op col_Op eurUsdRate)
                         balanceUsd seriesWithRates

-- ------------------------------------------------------------- window steps
--
-- A three-month trailing mean per branch, and the latest month per branch.
withTrend   = movingAverage 3 {branchName} (asc asOfDay) balanceEur balance3m depositSeries
latestMonth = latestPerKey {branchName} asOfDay depositSeries

depositReport = vflow [
  atomShown "## Branch deposits",
  atomShown "### Balance against the policy rate in force",
  tabular Nothing
    (withSpread # { branchName, asOfDay, balanceEur, headlineRatePct,
                    policyRatePct, spreadPct }),
  atomShown "### Balance in dollars at the month-end rate set",
  tabular Nothing
    (withUsd # { branchName, asOfDay, balanceEur, eurUsdRate, balanceUsd }),
  atomShown "### Three-month trailing mean",
  tabular Nothing (withTrend # { branchName, asOfDay, balanceEur, balance3m }),
  atomShown "### Latest month per branch",
  tabular Nothing (latestMonth # { branchName, asOfDay, balanceEur, accountCount })
]
