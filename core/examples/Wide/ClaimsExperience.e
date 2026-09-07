module Wide.ClaimsExperience where

{- THE WIDEST TABLE IN THIS DIRECTORY: a THIRTY-SIX-COLUMN claims fact, reported
   on by helpers that name at most three columns each.

   An insurance claims extract is wide because a claim is a long story: five
   keys, three dates, ten money columns, four counts, four scores, three lags
   and seven codes.  A claims report is narrow because a reader wants four
   numbers.  Everything in between -- the decile of severity, the fraud rank
   within a state, paid-to-incurred, the loss ratio -- is a helper call that
   mentions two of the thirty-six and carries the other thirty-four in a row
   variable.

   This module is where the corpus's "how wide can it get" question is measured.
   Every WINDOW and DERIVED-COLUMN helper here is applied to the 43-column joined
   row.  The two pivot helpers are not: a pivot's input must be exactly key +
   value + identity, so `pivotOnRowWithDefault`/`pivotByWithDefault` see the
   three-column `groupBy` result, as they do in every module.

   Fact:       claim (36 columns)
                 keys    claimId, policyId, claimantId, perilId, adjusterId
                 dates   claimDay, reportDay, closeDay
                 money   paidAmt, reservedAmt, incurredAmt, recoveryAmt,
                         deductibleAmt, salvageAmt, subrogationAmt,
                         legalCostAmt, adjusterCostAmt, premiumAmt
                 counts  reopenCount, claimCount, exposureCount, priorClaimCount
                 scores  fraudScore, severityScore, complexityScore,
                         satisfactionScore
                 lags    reportLagDays, settleLagDays, contactLagDays
                 codes   litigationFlag, severityBand, claimStatus,
                         lineOfBusiness, stateCode, catastropheCode,
                         channelOfNotice
   Dimensions: policy   (policyId   -> policyholderName, productTier, agencyName)
               peril    (perilId    -> perilName, perilClass)
               adjuster (adjusterId -> adjusterName, officeName)

   Helpers used: withDerived3, nTileWithin, denseWithin, topNWithin, melt3,
                 pivotOnRowWithDefault, pivotByWithDefault, desc (Wide.Helpers).

   Solver shapes exercised:
     * every window and derived-column helper instantiated against a 43-column row
       -- the widest instantiation in the corpus, and the one that tells you whether the
       solver's cost grows with the ROW or with the CONSTRAINT SET.  It grows
       with the constraint set: this module carries 43 columns and checks in
       2.6 s, `Wide.Leaderboard` carries 38 and checks in 0.6 s, and the
       difference is `withDerived3`, not five columns (E1 report, section 5);
     * `withDerived3`, three row unions in one signature, on that same row;
     * a three-way pivot on `claimStatus` WITH defaults, so that the open,
       closed and reopened columns can be added up;
     * `melt3` on the 43-column row -- the widest unpivot call site in the tree:
       three `except`s, three `combine`s, three `rename`s and two `union`s, all
       reconciled against a TWO-constraint signature over a forty-column identity.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/ClaimsExperience.e
     >> :type claimsWithRatios
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field claimId, policyId, claimantId, perilId, adjusterId : Int
field claimDay, reportDay, closeDay : Date
field paidAmt, reservedAmt, incurredAmt, recoveryAmt : Double
field deductibleAmt, salvageAmt, subrogationAmt, legalCostAmt : Double
field adjusterCostAmt, premiumAmt : Double
field reopenCount, claimCount, exposureCount, priorClaimCount : Int
field fraudScore, severityScore, complexityScore, satisfactionScore : Double
field reportLagDays, settleLagDays, contactLagDays : Int
field litigationFlag, severityBand, claimStatus : String
field lineOfBusiness, stateCode, catastropheCode, channelOfNotice : String
field policyholderName, productTier, agencyName : String
field perilName, perilClass, adjusterName, officeName : String
field paidToIncurredPct, lossRatioPct, netIncurred : Double
field severityDecile, fraudRank, incurredRank : Int
field amountKind : String
field amountValue : Double
field open, closed, reopened : Double

-- Thirty-six columns.  Eight claims across three lines of business and four
-- states, with two open, one reopened and the rest closed.
claim = relation [
  { claimId = 7001, policyId = 300101, claimantId = 91001, perilId = 1, adjusterId = 51,
    claimDay = yyyymmdd 2025 1 12, reportDay = yyyymmdd 2025 1 15, closeDay = yyyymmdd 2025 2 25,
    paidAmt = 18400.0, reservedAmt = 0.0, incurredAmt = 18400.0, recoveryAmt = 2100.0,
    deductibleAmt = 1000.0, salvageAmt = 900.0, subrogationAmt = 0.0, legalCostAmt = 0.0,
    adjusterCostAmt = 1200.0, premiumAmt = 4100.0,
    reopenCount = 0, claimCount = 1, exposureCount = 1, priorClaimCount = 2,
    fraudScore = 11.5, severityScore = 2.1, complexityScore = 1.4, satisfactionScore = 8.4,
    reportLagDays = 3, settleLagDays = 41, contactLagDays = 1,
    litigationFlag = "no", severityBand = "Minor", claimStatus = "closed",
    lineOfBusiness = "Motor", stateCode = "TX", catastropheCode = "none",
    channelOfNotice = "Phone" },
  { claimId = 7002, policyId = 300101, claimantId = 91002, perilId = 2, adjusterId = 52,
    claimDay = yyyymmdd 2025 3 4, reportDay = yyyymmdd 2025 3 6, closeDay = yyyymmdd 1970 1 1,
    paidAmt = 0.0, reservedAmt = 62000.0, incurredAmt = 62000.0, recoveryAmt = 0.0,
    deductibleAmt = 1000.0, salvageAmt = 0.0, subrogationAmt = 0.0, legalCostAmt = 0.0,
    adjusterCostAmt = 800.0, premiumAmt = 4100.0,
    reopenCount = 0, claimCount = 1, exposureCount = 1, priorClaimCount = 0,
    fraudScore = 38.0, severityScore = 4.0, complexityScore = 2.2, satisfactionScore = 6.1,
    reportLagDays = 1, settleLagDays = 0, contactLagDays = 2,
    litigationFlag = "no", severityBand = "Moderate", claimStatus = "open",
    lineOfBusiness = "Motor", stateCode = "TX", catastropheCode = "none",
    channelOfNotice = "App" },
  { claimId = 7003, policyId = 300204, claimantId = 91003, perilId = 3, adjusterId = 51,
    claimDay = yyyymmdd 2024 9 28, reportDay = yyyymmdd 2024 10 3, closeDay = yyyymmdd 2025 6 18,
    paidAmt = 241000.0, reservedAmt = 88000.0, incurredAmt = 329000.0, recoveryAmt = 41000.0,
    deductibleAmt = 5000.0, salvageAmt = 12000.0, subrogationAmt = 18000.0, legalCostAmt = 46000.0,
    adjusterCostAmt = 9800.0, premiumAmt = 12600.0,
    reopenCount = 2, claimCount = 1, exposureCount = 1, priorClaimCount = 4,
    fraudScore = 72.4, severityScore = 8.9, complexityScore = 9.1, satisfactionScore = 3.2,
    reportLagDays = 6, settleLagDays = 214, contactLagDays = 5,
    litigationFlag = "yes", severityBand = "Severe", claimStatus = "reopened",
    lineOfBusiness = "Property", stateCode = "FL", catastropheCode = "HU2024",
    channelOfNotice = "Phone" },
  { claimId = 7004, policyId = 300204, claimantId = 91004, perilId = 3, adjusterId = 53,
    claimDay = yyyymmdd 2024 9 29, reportDay = yyyymmdd 2024 10 1, closeDay = yyyymmdd 2025 2 10,
    paidAmt = 96500.0, reservedAmt = 0.0, incurredAmt = 96500.0, recoveryAmt = 8200.0,
    deductibleAmt = 5000.0, salvageAmt = 3400.0, subrogationAmt = 0.0, legalCostAmt = 0.0,
    adjusterCostAmt = 4100.0, premiumAmt = 12600.0,
    reopenCount = 0, claimCount = 1, exposureCount = 1, priorClaimCount = 1,
    fraudScore = 21.0, severityScore = 5.5, complexityScore = 4.0, satisfactionScore = 7.7,
    reportLagDays = 9, settleLagDays = 132, contactLagDays = 3,
    litigationFlag = "no", severityBand = "Moderate", claimStatus = "closed",
    lineOfBusiness = "Property", stateCode = "FL", catastropheCode = "HU2024",
    channelOfNotice = "Agent" },
  { claimId = 7005, policyId = 300310, claimantId = 91005, perilId = 4, adjusterId = 52,
    claimDay = yyyymmdd 2025 2 17, reportDay = yyyymmdd 2025 2 20, closeDay = yyyymmdd 1970 1 1,
    paidAmt = 0.0, reservedAmt = 415000.0, incurredAmt = 415000.0, recoveryAmt = 0.0,
    deductibleAmt = 10000.0, salvageAmt = 0.0, subrogationAmt = 60000.0, legalCostAmt = 121000.0,
    adjusterCostAmt = 14200.0, premiumAmt = 22800.0,
    reopenCount = 0, claimCount = 1, exposureCount = 1, priorClaimCount = 3,
    fraudScore = 55.8, severityScore = 9.4, complexityScore = 8.6, satisfactionScore = 4.9,
    reportLagDays = 12, settleLagDays = 0, contactLagDays = 7,
    litigationFlag = "yes", severityBand = "Severe", claimStatus = "open",
    lineOfBusiness = "Liability", stateCode = "NY", catastropheCode = "none",
    channelOfNotice = "Web" },
  { claimId = 7006, policyId = 300310, claimantId = 91006, perilId = 1, adjusterId = 53,
    claimDay = yyyymmdd 2025 4 8, reportDay = yyyymmdd 2025 4 8, closeDay = yyyymmdd 2025 5 2,
    paidAmt = 7300.0, reservedAmt = 0.0, incurredAmt = 7300.0, recoveryAmt = 0.0,
    deductibleAmt = 10000.0, salvageAmt = 0.0, subrogationAmt = 0.0, legalCostAmt = 0.0,
    adjusterCostAmt = 600.0, premiumAmt = 22800.0,
    reopenCount = 1, claimCount = 1, exposureCount = 1, priorClaimCount = 0,
    fraudScore = 9.2, severityScore = 1.4, complexityScore = 1.1, satisfactionScore = 9.0,
    reportLagDays = 2, settleLagDays = 18, contactLagDays = 1,
    litigationFlag = "no", severityBand = "Minor", claimStatus = "closed",
    lineOfBusiness = "Liability", stateCode = "NY", catastropheCode = "none",
    channelOfNotice = "Web" },
  { claimId = 7007, policyId = 300415, claimantId = 91007, perilId = 2, adjusterId = 51,
    claimDay = yyyymmdd 2025 1 30, reportDay = yyyymmdd 2025 2 3, closeDay = yyyymmdd 2025 4 22,
    paidAmt = 31900.0, reservedAmt = 0.0, incurredAmt = 31900.0, recoveryAmt = 4400.0,
    deductibleAmt = 2500.0, salvageAmt = 1800.0, subrogationAmt = 2200.0, legalCostAmt = 0.0,
    adjusterCostAmt = 2000.0, premiumAmt = 5900.0,
    reopenCount = 0, claimCount = 1, exposureCount = 1, priorClaimCount = 1,
    fraudScore = 16.7, severityScore = 3.3, complexityScore = 2.8, satisfactionScore = 8.1,
    reportLagDays = 4, settleLagDays = 63, contactLagDays = 2,
    litigationFlag = "no", severityBand = "Moderate", claimStatus = "closed",
    lineOfBusiness = "Motor", stateCode = "CA", catastropheCode = "none",
    channelOfNotice = "App" },
  { claimId = 7008, policyId = 300415, claimantId = 91008, perilId = 4, adjusterId = 52,
    claimDay = yyyymmdd 2025 5 11, reportDay = yyyymmdd 2025 5 11, closeDay = yyyymmdd 1970 1 1,
    paidAmt = 0.0, reservedAmt = 14200.0, incurredAmt = 14200.0, recoveryAmt = 0.0,
    deductibleAmt = 2500.0, salvageAmt = 0.0, subrogationAmt = 0.0, legalCostAmt = 0.0,
    adjusterCostAmt = 700.0, premiumAmt = 5900.0,
    reopenCount = 0, claimCount = 1, exposureCount = 1, priorClaimCount = 0,
    fraudScore = 27.3, severityScore = 2.0, complexityScore = 1.9, satisfactionScore = 7.4,
    reportLagDays = 2, settleLagDays = 0, contactLagDays = 1,
    litigationFlag = "no", severityBand = "Minor", claimStatus = "open",
    lineOfBusiness = "Property", stateCode = "CA", catastropheCode = "none",
    channelOfNotice = "Agent" }
]

policyDim = relation [
  { policyId = 300101, policyholderName = "Ana Villalobos",  productTier = "Standard", agencyName = "Rio Grande Brokers" },
  { policyId = 300204, policyholderName = "Coastline Rentals", productTier = "Premier", agencyName = "Gulfshore Agency" },
  { policyId = 300310, policyholderName = "Delacroix Foods", productTier = "Premier",  agencyName = "Hudson Partners" },
  { policyId = 300415, policyholderName = "Ines Karimi",     productTier = "Standard", agencyName = "Pacific Direct" }
]

perilDim = relation [
  { perilId = 1, perilName = "Collision",      perilClass = "Physical damage" },
  { perilId = 2, perilName = "Theft",          perilClass = "Physical damage" },
  { perilId = 3, perilName = "Windstorm",      perilClass = "Catastrophe" },
  { perilId = 4, perilName = "Bodily injury",  perilClass = "Casualty" }
]

adjusterDim = relation [
  { adjusterId = 51, adjusterName = "C. Whitfield", officeName = "Dallas" },
  { adjusterId = 52, adjusterName = "E. Nakagawa",  officeName = "Newark" },
  { adjusterId = 53, adjusterName = "S. Aliyev",    officeName = "Tampa" }
]

-- Forty-three columns after the three dimension joins.
claims = claim ** policyDim ** perilDim ** adjusterDim

-- ------------------------------------------------------------ three ratios
--
-- Three derived columns, three row unions, ONE helper call.  This is the shape
-- `Ai/Common.e` says to avoid, written on purpose so that its cost can be
-- measured on the widest row in the corpus.
claimsWithRatios =
  withDerived3 (col_Op paidAmt /_Op col_Op incurredAmt)        paidToIncurredPct
               (col_Op incurredAmt /_Op col_Op premiumAmt)     lossRatioPct
               (col_Op incurredAmt -_Op col_Op recoveryAmt)    netIncurred
               claims

-- ------------------------------------------------------------ three windows
--
-- Deciles of severity within a line of business; fraud rank within a state;
-- the two largest claims per line.
severityDeciles = nTileWithin {lineOfBusiness} (desc incurredAmt) 10 severityDecile claims
fraudRanks      = denseWithin {stateCode}      (desc fraudScore)     fraudRank      claims
biggestClaims   = topNWithin  {lineOfBusiness} (desc incurredAmt) 2  incurredRank   claims

-- ------------------------------------------------------------- the unpivot
--
-- The three money buckets a claims report actually argues about -- what has been
-- PAID, what is still RESERVED, what has been RECOVERED -- are three columns of
-- the fact table and three rows of the report.  `melt3` on the full FORTY-THREE
-- column row turns one into the other: forty identity columns come through
-- untouched and are repeated on all three output rows, which is exactly what the
-- identity row `i` in `r <- (i, fa, fb, fc)` is for.  It is the widest unpivot
-- call site in the examples tree.
claimMoneyLong = melt3 amountKind amountValue paidAmt reservedAmt recoveryAmt claims

-- The analysis the long form makes writable: one total per bucket per line of
-- business, over however many buckets there turn out to be.
moneyByBucket = groupBy {lineOfBusiness, amountKind} (sumBy amountValue) claimMoneyLong

-- -------------------------------------------------------------- the pivot
--
-- Incurred by status, one column per status, zeros where a status did not
-- occur -- so that the three columns can be added up to the total incurred.
byLobStatus = groupBy {lineOfBusiness, claimStatus} (sumBy incurredAmt) claims

statusPlan  = pivotOnRowWithDefault {open, closed, reopened} incurredAmt claimStatus
incurredByStatus = pivotByWithDefault statusPlan byLobStatus

claimsReport = vflow [
  atomShown "## Claims experience",
  atomShown "### Ratios",
  tabular Nothing
    (claimsWithRatios # { claimId, lineOfBusiness, perilName, incurredAmt, paidAmt,
                          paidToIncurredPct, lossRatioPct, netIncurred }),
  atomShown "### Severity decile within line of business",
  tabular Nothing
    (severityDeciles # { lineOfBusiness, claimId, incurredAmt, severityDecile }),
  atomShown "### Fraud rank within state",
  tabular Nothing
    (fraudRanks # { stateCode, claimId, fraudScore, fraudRank }),
  atomShown "### Two largest claims per line of business",
  tabular Nothing
    (biggestClaims # { lineOfBusiness, claimId, incurredAmt, incurredRank }),
  atomShown "### Paid, reserved and recovered, one row per bucket",
  tabular Nothing
    (claimMoneyLong # { claimId, lineOfBusiness, amountKind, amountValue }),
  atomShown "### Each bucket totalled by line of business",
  tabular Nothing moneyByBucket,
  atomShown "### Incurred by status",
  tabular Nothing incurredByStatus,
  atomShown "### Claims",
  tabular Nothing
    (claims # { claimId, policyholderName, perilName, adjusterName, claimDay,
                claimStatus, incurredAmt, settleLagDays })
]
