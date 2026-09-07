module Time.InterestAccrual where

{- A LATE-PAYMENT INTEREST LEDGER, and the two things about it that a date library
   has to get right: DAY-COUNT CONVENTIONS, and an agreed rate that may be NULL
   because the contract falls back on a published reference rate instead.

   Fact:   receivables (18 fields: invoiceId, customer, customerGroup, paymentTermsCode,
                     dunningStage, invoiceCategory, teamCode, raisedBy, dayCountBasis,
                     rateCode, contractTerms, overdueAmount, agreedRate (NULLABLE),
                     penaltyBps, accrualStart, accrualEnd, valueDate, dueDate)
   Rates:  baseRates (rateCode, rateDate, baseRate) -- published on the dates
                     below only, so an invoice valued between two of them needs
                     the last one

   The two conventions differ by 1.39%: ACT/365 divides the same day count by 365
   and ACT/360 by 360, so the SAME rate on the SAME amount over the SAME period
   accrues 365/360 = 1.0139 times as much on ACT/360. That is not rounding, it is
   real money, and `conventionCost` below is the column an auditor asks for.

   SHAPES EXERCISED
     * `dayCount` / `yearFrac365` / `yearFrac360` -- `Relation.Op.dateDiff`, whose
       result-row is UNCONSTRAINED (see the note on `Helpers.dayCount`).
     * `nearestBy` -- the reference rate as of the value date, per rate code.
     * `orElseNum` -- the nullable agreed rate falling back to base + surcharge.
       NOT `orZero`: a missing agreed rate is not a rate of zero.
     * `accrual` -- amount * rate * yearFraction, with the year fraction
       passed in as an `Op` so the convention stays visible at the call site.
     * `pow_Op` -- compound rather than simple interest, in the relational
       algebra rather than in Ermine.
     * EVERY aggregate `Relation.Aggregate` exports: `countAgg`, `sum`, `mean`
       (= `avg`), `min`, `max`, `stddev`, `variance`, `weightedMean` and
       `weightedHarmonicMean` -- nine, on one relation. The corpus previously
       used `sum` and `count` and nothing else.
     * `Math` at the value level, and the limit that goes with it (see the note
       above `continuousFactor`).

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/InterestAccrual.e
     >> accrualReport

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
import Math as M
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field invoiceId, penaltyBps : Int
field customer, customerGroup, paymentTermsCode, dunningStage, invoiceCategory : String
field teamCode, raisedBy, dayCountBasis, rateCode, contractTerms : String
field overdueAmount, baseRate : Double
field agreedRate : Nullable Double
field accrualStart, accrualEnd, valueDate, dueDate, rateDate : Date
field accrualDays : Int
field yf365, yf360, effectiveRate : Double
field interest365, interest360, conventionCost, compoundInterest : Double
field invoiceCount, overdueSum, overdueMean, overdueMin, overdueMax : Double
field rateMean, rateStdDev, rateVariance, weightedRate : Nullable Double
field harmonicRate : Nullable Double
field ageBand : String

-- ------------------------------------------------------------- the fact table

-- Eighteen columns. Note `agreedRate = Null Double` on the four invoices whose
-- contract names no rate at all: that is a different statement from a rate of
-- zero, and the whole reason the column is nullable.
receivables : [ invoiceId, customer, customerGroup, paymentTermsCode, dunningStage
              , invoiceCategory, teamCode, raisedBy, dayCountBasis, rateCode
              , contractTerms, overdueAmount, agreedRate, penaltyBps, accrualStart
              , accrualEnd, valueDate, dueDate ]
receivables = relation [
  { invoiceId = 7001, customer = "Northwind Traders", customerGroup = "Northwind Group",
    paymentTermsCode = "NET30", dunningStage = "Reminder", invoiceCategory = "Goods",
    teamCode = "AR-EMEA", raisedBy = "j.okafor", dayCountBasis = "ACT/360",
    rateCode = "USD-BASE", contractTerms = "Framework", overdueAmount = 12500000.0,
    agreedRate = Null Double, penaltyBps = 275, accrualStart = @2011/1/1,
    accrualEnd = @2011/3/31, valueDate = @2011/3/31, dueDate = @2010/12/31 },
  { invoiceId = 7002, customer = "Contoso GmbH", customerGroup = "Contoso AG",
    paymentTermsCode = "NET45", dunningStage = "Final notice", invoiceCategory = "Services",
    teamCode = "AR-EMEA", raisedBy = "m.lindqvist", dayCountBasis = "ACT/365",
    rateCode = "EUR-ECB-BASE", contractTerms = "Spot", overdueAmount = 8000000.0,
    agreedRate = Some 0.0425, penaltyBps = 0, accrualStart = @2011/1/1,
    accrualEnd = @2011/3/31, valueDate = @2011/3/31, dueDate = @2010/12/31 },
  { invoiceId = 7003, customer = "Fabrikam Ltd", customerGroup = "Fabrikam plc",
    paymentTermsCode = "NET30", dunningStage = "Collections", invoiceCategory = "Rental",
    teamCode = "AR-SMB", raisedBy = "a.petrova", dayCountBasis = "ACT/365",
    rateCode = "GBP-BOE-BASE", contractTerms = "Framework", overdueAmount = 2250000.0,
    agreedRate = Some 0.0715, penaltyBps = 0, accrualStart = @2011/1/15,
    accrualEnd = @2011/4/15, valueDate = @2011/4/15, dueDate = @2011/1/14 },
  { invoiceId = 7004, customer = "Litware Print", customerGroup = "Litware Group",
    paymentTermsCode = "NET90", dunningStage = "Reminder", invoiceCategory = "Licences",
    teamCode = "AR-KEY", raisedBy = "a.petrova", dayCountBasis = "ACT/360",
    rateCode = "CHF-SNB-BASE", contractTerms = "None", overdueAmount = 31000000.0,
    agreedRate = Null Double, penaltyBps = 95, accrualStart = @2011/2/1,
    accrualEnd = @2011/5/1, valueDate = @2011/5/1, dueDate = @2011/1/31 },
  { invoiceId = 7005, customer = "Wingtip Devices", customerGroup = "Wingtip KK",
    paymentTermsCode = "NET60", dunningStage = "Final notice", invoiceCategory = "Services",
    teamCode = "AR-APAC", raisedBy = "s.ahmed", dayCountBasis = "ACT/365",
    rateCode = "JPY-BOJ-BASE", contractTerms = "Spot", overdueAmount = 940000000.0,
    agreedRate = Some 0.0138, penaltyBps = 0, accrualStart = @2011/1/1,
    accrualEnd = @2011/6/30, valueDate = @2011/6/30, dueDate = @2010/12/31 },
  { invoiceId = 7006, customer = "Tailspin Toys", customerGroup = "Tailspin Inc",
    paymentTermsCode = "NET30", dunningStage = "Collections", invoiceCategory = "Goods",
    teamCode = "AR-SMB", raisedBy = "s.ahmed", dayCountBasis = "ACT/360",
    rateCode = "USD-BASE", contractTerms = "Framework", overdueAmount = 1750000.0,
    agreedRate = Null Double, penaltyBps = 650, accrualStart = @2011/3/1,
    accrualEnd = @2011/6/1, valueDate = @2011/6/1, dueDate = @2011/2/28 },
  { invoiceId = 7007, customer = "Proseware Health", customerGroup = "Proseware Inc",
    paymentTermsCode = "NET45", dunningStage = "Reminder", invoiceCategory = "Equipment",
    teamCode = "AR-AMER", raisedBy = "j.okafor", dayCountBasis = "ACT/365",
    rateCode = "USD-BASE", contractTerms = "Framework", overdueAmount = 5600000.0,
    agreedRate = Some 0.0388, penaltyBps = 0, accrualStart = @2011/4/1,
    accrualEnd = @2011/6/30, valueDate = @2011/6/30, dueDate = @2011/3/31 },
  { invoiceId = 7008, customer = "Trey Logistics", customerGroup = "Trey NV",
    paymentTermsCode = "NET60", dunningStage = "Final notice", invoiceCategory = "Freight",
    teamCode = "AR-AMER", raisedBy = "m.lindqvist", dayCountBasis = "ACT/360",
    rateCode = "EUR-ECB-BASE", contractTerms = "Spot", overdueAmount = 4300000.0,
    agreedRate = Null Double, penaltyBps = 410, accrualStart = @2011/2/15,
    accrualEnd = @2011/5/15, valueDate = @2011/5/15, dueDate = @2011/2/14 }
]

-- ------------------------------------------------------------- the base rates

-- Reference rates, published on the dates below and nowhere else. Two of the
-- value dates above (15 May, 1 June) fall between publications, which is what
-- `nearestBy` is for.
baseRates : [ rateCode, rateDate, baseRate ]
baseRates = relation [
  { rateCode = "USD-BASE",     rateDate = @2011/1/3,  baseRate = 0.00303 },
  { rateCode = "USD-BASE",     rateDate = @2011/3/31, baseRate = 0.00305 },
  { rateCode = "USD-BASE",     rateDate = @2011/5/31, baseRate = 0.00258 },
  { rateCode = "USD-BASE",     rateDate = @2011/6/30, baseRate = 0.00246 },
  { rateCode = "EUR-ECB-BASE", rateDate = @2011/3/31, baseRate = 0.01766 },
  { rateCode = "EUR-ECB-BASE", rateDate = @2011/4/29, baseRate = 0.02051 },
  { rateCode = "CHF-SNB-BASE", rateDate = @2011/5/1,  baseRate = 0.00170 },
  { rateCode = "GBP-BOE-BASE", rateDate = @2011/4/15, baseRate = 0.00495 },
  { rateCode = "JPY-BOJ-BASE", rateDate = @2011/6/30, baseRate = 0.00078 }
]

-- ================================================================ the pipeline

-- STEP 1. The reference rate CURRENT ON EACH INVOICE'S VALUE DATE, per code.
-- Invoice 7006 is valued on 1 June and the USD rate last moved on 31 May;
-- invoice 7008 is valued on 15 May and the EUR rate last moved on 29 April.
withBaseRate = nearestBy {rateCode} rateDate baseRates valueDate receivables

-- STEP 2. The effective rate. An invoice with an agreed rate uses it; one
-- without falls back to the published base rate plus its surcharge, in basis
-- points. `orElseNum` is `coalesce`: the FIRST argument is the nullable one.
accrualRated =
  combine_Op (orElseNum agreedRate
                        (col_Op baseRate
                         +_Op fromNumericOp_Op (col_Op penaltyBps) /_Op prim_Op 10000.0))
             effectiveRate
             withBaseRate

-- STEP 3. The day count and both year fractions.
dated =
     accrualRated
  |> combine_Op (dayCount accrualStart accrualEnd) accrualDays
  |> combine_Op (yearFrac365 accrualStart accrualEnd) yf365
  |> combine_Op (yearFrac360 accrualStart accrualEnd) yf360

-- STEP 4. Simple interest on each convention, and the difference between them.
accrued =
     dated
  |> combine_Op (accrual overdueAmount effectiveRate yf365) interest365
  |> combine_Op (accrual overdueAmount effectiveRate yf360) interest360
  |> combine_Op (col_Op interest360 -_Op col_Op interest365) conventionCost

-- STEP 5. Compound rather than simple: amount * (1 + r)^t - amount, with the
-- exponent taken in the relational algebra by `Relation.Op.pow`.
compounded =
  combine_Op (col_Op overdueAmount
              *_Op pow_Op (prim_Op 1.0 +_Op col_Op effectiveRate) (col_Op yf365)
              -_Op col_Op overdueAmount)
             compoundInterest
             accrued

-- STEP 6. Band the age of the debt. `band3` on the accrual day count.
accrualBanded = combine_Op (band3 accrualDays 80 "Under a quarter" 100 "About a quarter"
                           "Longer")
                    ageBand compounded

-- ------------------------------------------------------- nullable projections

statutory = missing agreedRate receivables   -- no agreed rate: four invoices
contracted = present agreedRate receivables  -- the other four

-- ---------------------------------------------------------------- aggregates

-- EVERY aggregate the stdlib offers, on one relation. Before this file the
-- examples used `sum` and `count` and nothing else.
statCount    = aggregate_Agg countAgg_Agg invoiceCount receivables
statSum      = aggregate_Agg (sum_Agg (col_Op overdueAmount)) overdueSum receivables
statMean     = aggregate_Agg (mean_Agg (col_Op overdueAmount)) overdueMean receivables
statMin      = aggregate_Agg (min_Agg (col_Op overdueAmount)) overdueMin receivables
statMax      = aggregate_Agg (max_Agg (col_Op overdueAmount)) overdueMax receivables

-- The nullable ones: the four invoices with no agreed rate are SKIPPED, not
-- read as zero, so `rateMean` is the mean of four numbers and not of eight.
statRateMean = aggregate_Agg (mean_Agg (col_Op agreedRate)) rateMean receivables
statRateSd   = aggregate_Agg (stddev_Agg (col_Op agreedRate)) rateStdDev receivables
statRateVar  = aggregate_Agg (variance_Agg (col_Op agreedRate)) rateVariance receivables

-- Amount-weighted average agreed rate: `weightedMean` has no other use anywhere.
--
-- `weightedMean` has no signature in `Relation.Aggregate`, and what it infers
-- forces the value and the weight to the SAME type -- so a nullable rate cannot
-- be weighted by a non-null amount until the amount is LIFTED with
-- `Relation.Op.annul`, which is `Op r a -> Op r (Nullable a)`. Without the
-- `annul_Op` the module fails with
--     failed to unify type (Nullable Double) with type Double
statWeighted =
  aggregate_Agg (weightedMean_Agg (col_Op agreedRate) (annul_Op (col_Op overdueAmount)))
                weightedRate receivables

-- The amount-weighted HARMONIC mean of the agreed rates. For a rate this is the
-- right average and the arithmetic one is not: the harmonic mean of rates
-- weighted by amount is the rate a single debt of the total amount would have to
-- carry to produce the same total interest. `weightedHarmonicMean` has no other
-- use anywhere in `core/examples`, and it needs the same `annul_Op` on the
-- weight that `weightedMean` does.
statHarmonic =
  aggregate_Agg (weightedHarmonicMean_Agg (col_Op agreedRate) (annul_Op (col_Op overdueAmount)))
                harmonicRate receivables

-- One row, TEN columns: single-column single-row relations sharing no columns,
-- so the natural join is their cartesian product. Ten because there are ten
-- distinct aggregate functions in `Relation.Aggregate` and every one is here.
statsPanel =
  statCount ** statSum ** statMean ** statMin ** statMax
            ** statRateMean ** statRateSd ** statRateVar ** statWeighted
            ** statHarmonic

-- Per-team statistics: the same aggregates under a grouping.
byTeam : [ teamCode, overdueSum ]
byTeam = materialize (groupBy {teamCode} (sumBy overdueAmount) receivables)
      |> rename overdueAmount overdueSum

-- ------------------------------------------------ what Math can and cannot do

{- `Math` is an ordinary Ermine module of `Double -> Double` functions: it works
   on VALUES, not on relational `Op`s. So a constant computed with it can be
   injected into a query with `prim_Op` --

       continuousFactor  is  e^(0.05 * 0.25), a quarter at 5% continuously
       compounded, and `prim_Op continuousFactor` is a perfectly good `Op`

   -- but there is NO way to apply `Math.exp` to a COLUMN. The relational algebra
   has its own `exp`, `log`, `log10`, `pow`, `abs` in `Relation.Op` and those are
   the only transcendental functions available per row; anything else has to be
   composed out of them or precomputed. `compounded` above uses `Relation.Op.pow`
   for exactly that reason. This is recorded in E3-EXAMPLES.md as a language
   limit, not a bug. -}

continuousFactor : Double
continuousFactor = exp_M (0.05 * 0.25)

-- The same quarter, discretely compounded, for comparison -- and `sqrt` and
-- `log` to show the module is really there.
discreteFactor : Double
discreteFactor = pow (1.0 + 0.05) 0.25

rootOfQuarter : Double
rootOfQuarter = sqrt_M 0.25

logFactor : Double
logFactor = log_M continuousFactor

-- The constant, injected as a column: what a relational query may do with Math.
withContinuous =
  combine_Op (col_Op overdueAmount *_Op prim_Op continuousFactor -_Op col_Op overdueAmount)
             compoundInterest
             receivables

-- ------------------------------------------------------------------- report

accrualReport = vflow [
  atomShown "## Late-payment interest, Q1-Q2 2011",
  atomShown "### Invoices, the base rate as of their value date, and both conventions",
  tabular Nothing (accrualBanded # {invoiceId, customer, dayCountBasis, rateCode,
                             valueDate, rateDate, baseRate, agreedRate,
                             effectiveRate, accrualDays, yf365, yf360}),
  atomShown "### What the convention costs",
  tabular Nothing (accrualBanded # {invoiceId, customer, overdueAmount, interest365,
                             interest360, conventionCost, compoundInterest,
                             ageBand}),
  atomShown "### Invoices with no agreed rate (the reference rate applies)",
  tabular Nothing (statutory # {invoiceId, customer, rateCode, penaltyBps}),
  atomShown "### All ten aggregates, on one relation",
  tabular Nothing statsPanel,
  atomShown "### Overdue amount by team",
  tabular Nothing byTeam
]
