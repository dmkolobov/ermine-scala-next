module Wide.TrialBalance where

{- A GENERAL-LEDGER TRIAL BALANCE with a RUNNING BALANCE per account.

   The running balance is the report step that a relational language without
   window functions cannot express at all: each row's value depends on the rows
   BEFORE it in a particular order, within a particular group.  `runningTotal`
   says that in one line -- partition by account, order by posting date, frame
   from the start of the partition to the current row -- and says nothing about
   the other twenty columns of the journal.

   Fact:       journal (21 columns)
                 keys      journalId, entryId, accountId, costCentreId, projectId
                 dates     postingDay, effectiveDay
                 amounts   debitAmt, creditAmt, netAmt, baseAmt, taxAmt, fxRate
                 refs      docNo, batchId, taxCode, sourceSystem, currencyCode
                 people    preparerName, approverName
                 flags     reversalFlag
   Dimensions: account    (accountId    -> accountCode, accountName,
                                           accountType, statement)
               costCentre (costCentreId -> costCentreName, ownerName)

   Helpers used: runningTotal, movingAverage, melt2, asc (Wide.Helpers).

   Solver shapes exercised:
     * the FRAMED window, whose measure row is disjoint from the window row:
       `w <- (k, s)`, then `wm <- (m, w)`, then `r <- (wm, o)` -- three minted
       rows in a chain before `combine`'s own union is reached at all.  Whether
       that makes the SOLVER's derivation chain deeper is a different question,
       and section 4 of `tracker/loopmodel/E1-EXAMPLES.md` measures it against
       the existing corpus;
     * two framed windows over the same 27-column joined row with different
       frames, so the same chain is solved twice with different instantiations;
     * an ordinary `combine` for contrast (`netAmt = debitAmt - creditAmt` is
       already in the data, but `absAmt` is derived);
     * `melt2` on the full twenty-seven-column row -- two `except`s, two
       `combine`s, two `rename`s and a `union`, reconciled against a TWO-constraint
       signature whose identity row `i` is twenty-five columns wide.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/TrialBalance.e
     >> :type ledgerWithBalance
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field journalId, entryId, accountId, costCentreId, projectId, batchId : Int
field postingDay, effectiveDay : Date
field debitAmt, creditAmt, netAmt, baseAmt, taxAmt, fxRate : Double
field docNo, taxCode, sourceSystem, currencyCode : String
field preparerName, approverName, reversalFlag : String
field accountCode, accountName, accountType, statement : String
field costCentreName, ownerName : String
field runningBalance, trailingAvg, absAmt : Double
field entrySide : String
field entryAmount : Double

-- Twenty-one columns.  Ten postings across three accounts, in date order within
-- each account so that a running balance is meaningful to read.
journal = relation [
  { journalId = 1, entryId = 1001, accountId = 4000, costCentreId = 10, projectId = 0,
    postingDay = yyyymmdd 2025 1 31, effectiveDay = yyyymmdd 2025 1 31,
    debitAmt = 0.0, creditAmt = 412000.0, netAmt = -412000.0,
    baseAmt = -412000.0, taxAmt = 0.0, fxRate = 1.0,
    docNo = "INV-2025-0031", batchId = 77, taxCode = "OUT-STD", sourceSystem = "Billing",
    currencyCode = "USD", preparerName = "R. Adeyemi", approverName = "K. Ilves",
    reversalFlag = "no" },
  { journalId = 2, entryId = 1002, accountId = 4000, costCentreId = 10, projectId = 0,
    postingDay = yyyymmdd 2025 2 28, effectiveDay = yyyymmdd 2025 2 28,
    debitAmt = 0.0, creditAmt = 388500.0, netAmt = -388500.0,
    baseAmt = -388500.0, taxAmt = 0.0, fxRate = 1.0,
    docNo = "INV-2025-0058", batchId = 78, taxCode = "OUT-STD", sourceSystem = "Billing",
    currencyCode = "USD", preparerName = "R. Adeyemi", approverName = "K. Ilves",
    reversalFlag = "no" },
  { journalId = 3, entryId = 1003, accountId = 4000, costCentreId = 10, projectId = 0,
    postingDay = yyyymmdd 2025 3 31, effectiveDay = yyyymmdd 2025 3 31,
    debitAmt = 24000.0, creditAmt = 0.0, netAmt = 24000.0,
    baseAmt = 24000.0, taxAmt = 0.0, fxRate = 1.0,
    docNo = "CRN-2025-0004", batchId = 79, taxCode = "OUT-STD", sourceSystem = "Billing",
    currencyCode = "USD", preparerName = "R. Adeyemi", approverName = "K. Ilves",
    reversalFlag = "yes" },
  { journalId = 4, entryId = 1004, accountId = 4000, costCentreId = 10, projectId = 0,
    postingDay = yyyymmdd 2025 4 30, effectiveDay = yyyymmdd 2025 4 30,
    debitAmt = 0.0, creditAmt = 451200.0, netAmt = -451200.0,
    baseAmt = -451200.0, taxAmt = 0.0, fxRate = 1.0,
    docNo = "INV-2025-0091", batchId = 80, taxCode = "OUT-STD", sourceSystem = "Billing",
    currencyCode = "USD", preparerName = "R. Adeyemi", approverName = "K. Ilves",
    reversalFlag = "no" },
  { journalId = 5, entryId = 2001, accountId = 6100, costCentreId = 20, projectId = 501,
    postingDay = yyyymmdd 2025 1 31, effectiveDay = yyyymmdd 2025 1 31,
    debitAmt = 188000.0, creditAmt = 0.0, netAmt = 188000.0,
    baseAmt = 188000.0, taxAmt = 0.0, fxRate = 1.0,
    docNo = "PAY-2025-01", batchId = 91, taxCode = "NONE", sourceSystem = "Payroll",
    currencyCode = "USD", preparerName = "T. Nakamura", approverName = "K. Ilves",
    reversalFlag = "no" },
  { journalId = 6, entryId = 2002, accountId = 6100, costCentreId = 20, projectId = 501,
    postingDay = yyyymmdd 2025 2 28, effectiveDay = yyyymmdd 2025 2 28,
    debitAmt = 191400.0, creditAmt = 0.0, netAmt = 191400.0,
    baseAmt = 191400.0, taxAmt = 0.0, fxRate = 1.0,
    docNo = "PAY-2025-02", batchId = 92, taxCode = "NONE", sourceSystem = "Payroll",
    currencyCode = "USD", preparerName = "T. Nakamura", approverName = "K. Ilves",
    reversalFlag = "no" },
  { journalId = 7, entryId = 2003, accountId = 6100, costCentreId = 20, projectId = 501,
    postingDay = yyyymmdd 2025 3 31, effectiveDay = yyyymmdd 2025 3 31,
    debitAmt = 203900.0, creditAmt = 0.0, netAmt = 203900.0,
    baseAmt = 203900.0, taxAmt = 0.0, fxRate = 1.0,
    docNo = "PAY-2025-03", batchId = 93, taxCode = "NONE", sourceSystem = "Payroll",
    currencyCode = "USD", preparerName = "T. Nakamura", approverName = "K. Ilves",
    reversalFlag = "no" },
  { journalId = 8, entryId = 3001, accountId = 6400, costCentreId = 30, projectId = 0,
    postingDay = yyyymmdd 2025 1 15, effectiveDay = yyyymmdd 2025 1 15,
    debitAmt = 41200.0, creditAmt = 0.0, netAmt = 41200.0,
    baseAmt = 37080.0, taxAmt = 8240.0, fxRate = 0.9,
    docNo = "AP-2025-0142", batchId = 104, taxCode = "IN-STD", sourceSystem = "Purchasing",
    currencyCode = "EUR", preparerName = "M. Blount", approverName = "S. Farouk",
    reversalFlag = "no" },
  { journalId = 9, entryId = 3002, accountId = 6400, costCentreId = 30, projectId = 0,
    postingDay = yyyymmdd 2025 2 15, effectiveDay = yyyymmdd 2025 2 15,
    debitAmt = 38800.0, creditAmt = 0.0, netAmt = 38800.0,
    baseAmt = 34920.0, taxAmt = 7760.0, fxRate = 0.9,
    docNo = "AP-2025-0188", batchId = 105, taxCode = "IN-STD", sourceSystem = "Purchasing",
    currencyCode = "EUR", preparerName = "M. Blount", approverName = "S. Farouk",
    reversalFlag = "no" },
  { journalId = 10, entryId = 3003, accountId = 6400, costCentreId = 30, projectId = 0,
    postingDay = yyyymmdd 2025 3 15, effectiveDay = yyyymmdd 2025 3 15,
    debitAmt = 52600.0, creditAmt = 0.0, netAmt = 52600.0,
    baseAmt = 47340.0, taxAmt = 10520.0, fxRate = 0.9,
    docNo = "AP-2025-0233", batchId = 106, taxCode = "IN-STD", sourceSystem = "Purchasing",
    currencyCode = "EUR", preparerName = "M. Blount", approverName = "S. Farouk",
    reversalFlag = "no" }
]

accountDim = relation [
  { accountId = 4000, accountCode = "4000", accountName = "Product revenue",
    accountType = "Revenue", statement = "P&L" },
  { accountId = 6100, accountCode = "6100", accountName = "Salaries and wages",
    accountType = "Expense", statement = "P&L" },
  { accountId = 6400, accountCode = "6400", accountName = "Contract services",
    accountType = "Expense", statement = "P&L" }
]

costCentreDim = relation [
  { costCentreId = 10, costCentreName = "Commercial",  ownerName = "A. Duarte" },
  { costCentreId = 20, costCentreName = "Engineering", ownerName = "J. Hallgren" },
  { costCentreId = 30, costCentreName = "Operations",  ownerName = "P. Ceylan" }
]

-- Twenty-seven columns after the joins.
ledger = journal ** accountDim ** costCentreDim

-- The report step: balance carried forward, per account, in posting order.
-- `netAmt` is the measure; `accountCode` and `postingDay` are the window.  The
-- three are disjoint, which is what `Relation.Windowed` requires -- ordering a
-- running total BY the column it accumulates is a type error, and
-- `shouldfail/win02_running_total_ordered_by_measure.e` shows exactly that error.
ledgerWithBalance =
  runningTotal {accountCode} (asc postingDay) netAmt runningBalance ledger

-- A three-posting trailing mean of the same measure, same partition, a bounded
-- frame instead of an unbounded one.
ledgerWithTrend =
  movingAverage 3 {accountCode} (asc postingDay) netAmt trailingAvg ledger

-- An ordinary derived column, for contrast: no window, no partition, one union.
ledgerWithAbs = combine_Op (abs_Op (col_Op netAmt)) absAmt ledger

-- ---------------------------------------------------------------- the unpivot
--
-- A trial balance is PRESENTED in two columns, debit and credit, because that is
-- how a ledger is read.  It is ANALYSED in one column plus a side, because "the
-- total posted on each side, per account" cannot be written over a table whose
-- sides are columns.  `melt2` is that move -- the same helper `Wide.SurveyPanel`
-- uses at arity four, here on the TWENTY-SEVEN-column joined row, so twenty-five
-- identity columns come through untouched and are repeated on both output rows.
-- That repetition is what the identity row `i` in `r <- (i, fa, fb)` is for.
sidedLedger = melt2 entrySide entryAmount debitAmt creditAmt ledger

-- The analysis the long form makes writable.
bySide = groupBy {accountCode, entrySide} (sumBy entryAmount) sidedLedger

trialBalanceReport = vflow [
  atomShown "## Trial balance",
  atomShown "### Balance carried forward, by account",
  tabular Nothing
    (ledgerWithBalance # { accountCode, accountName, postingDay, netAmt, runningBalance }),
  atomShown "### Three-posting trailing mean",
  tabular Nothing
    (ledgerWithTrend # { accountCode, postingDay, netAmt, trailingAvg }),
  atomShown "### The same postings, one row per side",
  tabular Nothing
    (sidedLedger # { accountCode, postingDay, docNo, entrySide, entryAmount }),
  atomShown "### Posted per side, per account",
  tabular Nothing bySide,
  atomShown "### Journal",
  tabular Nothing
    (ledger # { docNo, accountCode, costCentreName, postingDay, debitAmt, creditAmt, netAmt })
]
