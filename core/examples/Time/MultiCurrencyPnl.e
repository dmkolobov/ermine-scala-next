module Time.MultiCurrencyPnl where

{- A MULTI-CURRENCY P&L: a 19-column general-ledger extract, translated into the
   reporting currency at the rate CURRENT ON EACH POSTING'S BOOK DATE, and rolled
   up into a fiscal calendar that is not the Gregorian one.

   Fact:       ledger    (19 fields: entryId, bookDate, entity, ledgerAccount,
                          accountGroup, costCentre, region, partyName,
                          contractRef, sourceSystem, postedBy, taxCode, memo,
                          accrualFlag, quantity, approvalDays, amountLocal,
                          unitCost (NULLABLE), currencyCode)
   Rates:      fxRates   (currencyCode, rateDate, rateToUsd) -- PUBLISHED ON
                          BUSINESS DAYS ONLY, and for CHF not until 4 April,
                          which is the whole difficulty
   Calendar:   fiscalCal (periodStart, periodEnd, periodName, fiscalYear,
                          fiscalQuarter, periodNo) -- a 4-4-5 style calendar
                          whose periods do NOT start on the 1st
   Reference:  Currency.currencies -- the stdlib's ISO 4217 table, used here for
                          the first time in any example, for the symbol

   SHAPES EXERCISED
     * `bucketBy` -- a range join (cross product filtered on two date
       inequalities) putting each posting in its fiscal period.
     * `nearestBy` -- the PER-KEY as-of lookup, over a 25-column fine relation
       and a 3-column sparse one. This is the residual chain the census had
       never seen: `nearestBy` is applied to the OUTPUT of `bucketBy`, so the
       partition constraints of both compose at one call site.
     * `fxConvert` over the joined rate.
     * `orZero` / `nullSum` / `missing` / `present` on a genuinely nullable
       column (`unitCost` is null for postings that are not inventory
       movements), and the skipping mean beside the zeroing one.
     * `Currency.currencies`, joined on `currencyCode`.
     * `runningSum` -- a cumulative window over the fiscal period axis.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/MultiCurrencyPnl.e
     >> pnlReport

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
import Currency
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field entryId, quantity, approvalDays, periodNo : Int
field bookDate, rateDate, periodStart, periodEnd : Date
field entity, ledgerAccount, accountGroup, costCentre, region : String
field partyName, contractRef, sourceSystem, postedBy, taxCode, memo : String
field accrualFlag, periodName, fiscalYear, fiscalQuarter : String
field amountLocal, rateToUsd, amountUsd, cumulativeUsd : Double
field unitCostZero, zeroedMean : Double
field unitCost : Nullable Double
field entryLabel : String

-- ------------------------------------------------------------- the fact table

-- Nineteen columns. Twelve postings across four entities and five currencies,
-- booked on days that include two weekends -- 5 March 2011 and 3 April 2011 are
-- Saturday and Sunday, and no rate is published on either.
ledger : [ entryId, bookDate, entity, ledgerAccount, accountGroup, costCentre
         , region, partyName, contractRef, sourceSystem, postedBy, taxCode
         , memo, accrualFlag, quantity, approvalDays, amountLocal, unitCost
         , currencyCode ]
ledger = relation [
  { entryId = 4101, bookDate = @2011/1/17, entity = "Aurora UK Ltd",
    ledgerAccount = "4000 Revenue", accountGroup = "Revenue", costCentre = "CC-100",
    region = "EMEA", partyName = "Northwind Traders", contractRef = "CT-2210",
    sourceSystem = "SalesOrder", postedBy = "j.okafor", taxCode = "VAT-STD",
    memo = "Q1 licence renewal", accrualFlag = "N", quantity = 40,
    approvalDays = 2, amountLocal = 128400.0, unitCost = Some 1810.0,
    currencyCode = "GBP" },
  { entryId = 4102, bookDate = @2011/1/31, entity = "Aurora GmbH",
    ledgerAccount = "5100 Cost of Sales", accountGroup = "Cost of Sales",
    costCentre = "CC-220", region = "EMEA", partyName = "Contoso GmbH",
    contractRef = "CT-2211", sourceSystem = "Purchase", postedBy = "m.lindqvist",
    taxCode = "VAT-RC", memo = "Hosting passthrough", accrualFlag = "N",
    quantity = 12, approvalDays = 5, amountLocal = -41250.0,
    unitCost = Some 3437.5, currencyCode = "EUR" },
  { entryId = 4103, bookDate = @2011/2/14, entity = "Aurora Inc",
    ledgerAccount = "4000 Revenue", accountGroup = "Revenue", costCentre = "CC-100",
    region = "AMER", partyName = "Fabrikam Ltd", contractRef = "CT-2215",
    sourceSystem = "SalesOrder", postedBy = "j.okafor", taxCode = "US-EXEMPT",
    memo = "Platform subscription", accrualFlag = "N", quantity = 220,
    approvalDays = 1, amountLocal = 486000.0, unitCost = Some 1104.5,
    currencyCode = "USD" },
  { entryId = 4104, bookDate = @2011/2/28, entity = "Aurora KK",
    ledgerAccount = "6200 Payroll", accountGroup = "Operating Expense",
    costCentre = "CC-310", region = "APAC", partyName = "Internal",
    contractRef = "PAY-0211", sourceSystem = "Payroll", postedBy = "batch",
    taxCode = "JP-WHT", memo = "February payroll", accrualFlag = "Y",
    quantity = 0, approvalDays = 0, amountLocal = -18400000.0,
    unitCost = Null Double, currencyCode = "JPY" },
  { entryId = 4105, bookDate = @2011/3/5, entity = "Aurora UK Ltd",
    ledgerAccount = "4000 Revenue", accountGroup = "Revenue", costCentre = "CC-110",
    region = "EMEA", partyName = "Tailspin Toys", contractRef = "CT-2219",
    sourceSystem = "SalesOrder", postedBy = "a.petrova", taxCode = "VAT-STD",
    memo = "Weekend web order", accrualFlag = "N", quantity = 6,
    approvalDays = 0, amountLocal = 9750.0, unitCost = Some 1625.0,
    currencyCode = "GBP" },
  { entryId = 4106, bookDate = @2011/3/16, entity = "Aurora GmbH",
    ledgerAccount = "6100 Marketing", accountGroup = "Operating Expense",
    costCentre = "CC-410", region = "EMEA", partyName = "Adatum Media",
    contractRef = "PO-7781", sourceSystem = "Purchase", postedBy = "m.lindqvist",
    taxCode = "VAT-STD", memo = "Exhibition stand", accrualFlag = "N",
    quantity = 1, approvalDays = 9, amountLocal = -63200.0,
    unitCost = Some 63200.0, currencyCode = "EUR" },
  { entryId = 4107, bookDate = @2011/3/31, entity = "Aurora Inc",
    ledgerAccount = "4100 Services", accountGroup = "Revenue",
    costCentre = "CC-120", region = "AMER", partyName = "Northwind Traders",
    contractRef = "CT-2210", sourceSystem = "Timesheet", postedBy = "s.ahmed",
    taxCode = "US-EXEMPT", memo = "Implementation, March", accrualFlag = "Y",
    quantity = 310, approvalDays = 4, amountLocal = 232500.0,
    unitCost = Null Double, currencyCode = "USD" },
  { entryId = 4108, bookDate = @2011/4/3, entity = "Aurora CH AG",
    ledgerAccount = "4000 Revenue", accountGroup = "Revenue",
    costCentre = "CC-100", region = "EMEA", partyName = "Litware Bank",
    contractRef = "CT-2224", sourceSystem = "SalesOrder", postedBy = "a.petrova",
    taxCode = "CH-STD", memo = "Sunday close", accrualFlag = "N",
    quantity = 15, approvalDays = 0, amountLocal = 74250.0,
    unitCost = Some 4950.0, currencyCode = "CHF" },
  { entryId = 4109, bookDate = @2011/4/18, entity = "Aurora KK",
    ledgerAccount = "5100 Cost of Sales", accountGroup = "Cost of Sales",
    costCentre = "CC-220", region = "APAC", partyName = "Wingtip Devices",
    contractRef = "PO-7802", sourceSystem = "Purchase", postedBy = "batch",
    taxCode = "JP-CT", memo = "Hardware for rollout", accrualFlag = "N",
    quantity = 90, approvalDays = 7, amountLocal = -6930000.0,
    unitCost = Some 77000.0, currencyCode = "JPY" },
  { entryId = 4110, bookDate = @2011/5/9, entity = "Aurora UK Ltd",
    ledgerAccount = "6200 Payroll", accountGroup = "Operating Expense",
    costCentre = "CC-310", region = "EMEA", partyName = "Internal",
    contractRef = "PAY-0511", sourceSystem = "Payroll", postedBy = "batch",
    taxCode = "UK-PAYE", memo = "May payroll", accrualFlag = "Y",
    quantity = 0, approvalDays = 0, amountLocal = -215600.0,
    unitCost = Null Double, currencyCode = "GBP" },
  { entryId = 4111, bookDate = @2011/5/23, entity = "Aurora Inc",
    ledgerAccount = "4000 Revenue", accountGroup = "Revenue",
    costCentre = "CC-100", region = "AMER", partyName = "Fabrikam Ltd",
    contractRef = "CT-2215", sourceSystem = "SalesOrder", postedBy = "s.ahmed",
    taxCode = "US-EXEMPT", memo = "Seat expansion", accrualFlag = "N",
    quantity = 75, approvalDays = 2, amountLocal = 168750.0,
    unitCost = Some 2250.0, currencyCode = "USD" },
  { entryId = 4112, bookDate = @2011/6/13, entity = "Aurora GmbH",
    ledgerAccount = "4100 Services", accountGroup = "Revenue",
    costCentre = "CC-120", region = "EMEA", partyName = "Contoso GmbH",
    contractRef = "CT-2211", sourceSystem = "Timesheet", postedBy = "a.petrova",
    taxCode = "VAT-STD", memo = "Migration workshop", accrualFlag = "N",
    quantity = 48, approvalDays = 3, amountLocal = 57600.0,
    unitCost = Some 1200.0, currencyCode = "EUR" }
]

-- ------------------------------------------------------------------ the rates

-- Rates on business days only. Note there is NOTHING on 5 March or 3 April, the
-- two weekend postings above, and nothing at all for CHF before 4 APRIL -- which
-- is AFTER the 3 April CHF posting, so that posting has no rate at any date on
-- or before its own and drops out of the translation entirely. That is the
-- `unrated` line below, and it is the report's finding.
fxRates : [ currencyCode, rateDate, rateToUsd ]
fxRates = relation [
  { currencyCode = "GBP", rateDate = @2011/1/17, rateToUsd = 1.5942 },
  { currencyCode = "GBP", rateDate = @2011/1/31, rateToUsd = 1.6031 },
  { currencyCode = "GBP", rateDate = @2011/3/4,  rateToUsd = 1.6222 },
  { currencyCode = "GBP", rateDate = @2011/5/9,  rateToUsd = 1.6392 },
  { currencyCode = "EUR", rateDate = @2011/1/31, rateToUsd = 1.3692 },
  { currencyCode = "EUR", rateDate = @2011/3/16, rateToUsd = 1.3985 },
  { currencyCode = "EUR", rateDate = @2011/6/13, rateToUsd = 1.4441 },
  { currencyCode = "USD", rateDate = @2011/1/3,  rateToUsd = 1.0 },
  { currencyCode = "JPY", rateDate = @2011/2/28, rateToUsd = 0.012219 },
  { currencyCode = "JPY", rateDate = @2011/4/18, rateToUsd = 0.012135 },
  { currencyCode = "CHF", rateDate = @2011/4/4,  rateToUsd = 1.0891 }
]

-- --------------------------------------------------------- the fiscal calendar

-- A 4-4-5 calendar: periods end on a Sunday, so P1 runs 3 Jan to 30 Jan and no
-- period boundary falls on the 1st of a month. This is why the report cannot
-- just group by `formatMonthYear bookDate`.
fiscalCal : [ periodStart, periodEnd, periodName, fiscalYear, fiscalQuarter, periodNo ]
fiscalCal = relation [
  { periodStart = @2011/1/3,  periodEnd = @2011/1/30, periodName = "FY11 P01",
    fiscalYear = "FY2011", fiscalQuarter = "Q1", periodNo = 1 },
  { periodStart = @2011/1/31, periodEnd = @2011/2/27, periodName = "FY11 P02",
    fiscalYear = "FY2011", fiscalQuarter = "Q1", periodNo = 2 },
  { periodStart = @2011/2/28, periodEnd = @2011/4/3,  periodName = "FY11 P03",
    fiscalYear = "FY2011", fiscalQuarter = "Q1", periodNo = 3 },
  { periodStart = @2011/4/4,  periodEnd = @2011/5/1,  periodName = "FY11 P04",
    fiscalYear = "FY2011", fiscalQuarter = "Q2", periodNo = 4 },
  { periodStart = @2011/5/2,  periodEnd = @2011/5/29, periodName = "FY11 P05",
    fiscalYear = "FY2011", fiscalQuarter = "Q2", periodNo = 5 },
  { periodStart = @2011/5/30, periodEnd = @2011/7/3,  periodName = "FY11 P06",
    fiscalYear = "FY2011", fiscalQuarter = "Q2", periodNo = 6 }
]

-- ================================================================= the pipeline

-- STEP 1. Every posting gains its fiscal period: a range join on two
-- inequalities. 19 columns in, 25 out.
bucketed = bucketBy periodStart periodEnd bookDate fiscalCal ledger

-- STEP 2. Every posting gains the rate CURRENT FOR ITS OWN CURRENCY on its own
-- book date. This is the per-key as-of: the 5 March weekend posting (entry 4105,
-- a Saturday) picks up the 4 March GBP rate, and the 3 April one (entry 4108, a
-- Sunday) picks up NOTHING AT ALL, because the CHF curve's first fixing is 4
-- April -- one day after the posting. That MISSING ROW is the report's finding,
-- and `unrated` below is where it shows up.
--
-- 25-column fine relation, 3-column sparse one, key {currencyCode}.
pnlRated = nearestBy {currencyCode} rateDate fxRates bookDate bucketed

-- STEP 3. Translate. `pnlRated` is 27 columns and `translated` is 28.
translated = fxConvert amountLocal rateToUsd amountUsd pnlRated

-- STEP 4. The ISO table, for the symbol. `Currency.currencies` has 115 rows and
-- the natural join on `currencyCode` cuts it to the five in use.
withSymbol = join translated currencies

-- The postings that FELL OUT of step 2 -- no rate on or before the book date.
-- A P&L that does not show this line is lying about its own completeness.
--
-- MEASURED, not asserted. `nearestBy`'s answer goes through `materialize` and so
-- cannot be dumped to SQL, but the CANDIDATE SET it reduces --
-- `[| rateDate <= bookDate |] (fxRates ** ledger)` -- is a plain filtered join
-- and dumps fine. Run through `tracker/tools/sql-render.sh` it returns 20 rows
-- covering eleven of the twelve `entryId`s; the one missing is 4108. So
-- `unrated` is exactly {4108}, and the section below prints one line.
unrated = difference ledger (ledger ** (pnlRated # {entryId}))

-- ---------------------------------------------------------------- roll-ups

-- Translated P&L by fiscal period and account group.
-- `Relation.groupBy` returns a `Mem`, not a `Relation`; `materialize` is how the
-- stdlib gets back to a relation (it is what `nearestDate` itself does).
byPeriod : [ periodNo, periodName, accountGroup, amountUsd ]
byPeriod = materialize (groupBy {periodNo, periodName, accountGroup}
                                (sumBy amountUsd) translated)

-- Cumulative translated P&L along the period axis, per account group: a running
-- window, `Unbounded` back to the first period.
cumulative =
  combine_Op (runningSum {accountGroup} periodNo amountUsd) cumulativeUsd byPeriod

-- --------------------------------------------------------- nullable columns

-- `unitCost` is null on payroll and timesheet postings -- there is no unit.
-- Three things a report does with that:
noUnitCost   = missing unitCost ledger            -- the exceptions list
withUnitCost = present unitCost ledger            -- the population
unitCostTotal : [ unitCost ]
unitCostTotal = nullSum unitCost ledger           -- nulls skipped, not zeroed

-- The two are the SAME number for a sum and DIFFERENT numbers for a mean, which
-- is the whole reason `orZero` has to be a decision and not a default: with
-- three of twelve postings carrying no unit cost, the skipping mean divides by
-- nine and the zeroing mean by twelve.
unitCostMeanSkipped : [ unitCost ]
unitCostMeanSkipped = aggregate_Agg (mean_Agg (col_Op unitCost)) unitCost ledger

unitCostMeanZeroed : [ zeroedMean ]
unitCostMeanZeroed = aggregate_Agg (mean_Agg (orZero unitCost)) zeroedMean ledger

-- and the per-row column `orZero` produces, for a reader who wants to see it.
unitCostZeroed = combine_Op (orZero unitCost) unitCostZero ledger

-- ----------------------------------------------------------------- labelling

-- The conditional stays at the CALL SITE, per the rule in `Helpers.e`.
labelled =
  combine_Op (if_Op (col_Op accrualFlag ==_Pred prim_Op "Y")
                    (col_Op contractRef ++_Op prim_Op " (accrual)")
                    (col_Op contractRef))
             entryLabel
             withSymbol

-- ------------------------------------------------------------------- report

pnlReport = vflow [
  atomShown "## Multi-currency P&L, FY2011 P01-P06",
  atomShown "### Fiscal calendar (4-4-5; periods do not start on the 1st)",
  tabular Nothing fiscalCal,
  atomShown "### Postings translated at the rate as of the book date",
  tabular Nothing (translated # {entryId, bookDate, periodName, currencyCode,
                                 amountLocal, rateDate, rateToUsd, amountUsd}),
  atomShown "### Postings with NO rate on or before their book date",
  tabular Nothing (unrated # {entryId, bookDate, currencyCode, amountLocal}),
  atomShown "### P&L by fiscal period and account group, cumulative",
  tabular Nothing cumulative,
  atomShown "### Postings with no unit cost, and the two means",
  tabular Nothing (noUnitCost # {entryId, ledgerAccount, memo}),
  tabular Nothing (unitCostMeanSkipped ** unitCostMeanZeroed),
  atomShown "### Full detail with ISO symbol and label",
  tabular Nothing (labelled # {entryId, entryLabel, currencyCode, currencySymbol,
                               currencyName, amountLocal, amountUsd})
]
