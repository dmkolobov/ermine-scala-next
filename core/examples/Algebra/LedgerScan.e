module Algebra.LedgerScan where

{- A LEDGER SCANNED RATHER THAN JOINED: `Relation.Scan`, which is what Ermine
   has instead of a window function.

   Everything else in this directory is set-at-a-time. `Relation.Scan` is the
   escape hatch: it pulls a relation into a VECTOR OF RECORDS and hands it to
   ordinary functional code.

   WHAT THIS FILE DOES AND DOES NOT SHOW. Every scan here is either a
   COLUMN-SELECTION over the grouped scan (`sortK`, `pickK`, `filterK`,
   `mapK`, `removeK`, `updateK`) or a per-group FOLD (`sumBy'`, `count'`) --
   and the folds are things `groupBy` also does, which is why the file computes
   `totalsRelational` the other way for comparison. What `Relation.Scan` can do
   and the relational operators cannot is ORDER-DEPENDENT computation: a
   running total, a rank. That demonstration is in
   `Algebra/Comprehensions.e`, which builds a running balance both ways
   (a `Relation.Scan` cumulative fold, and the self-join every SQL dialect
   without window functions has to use). Read the two files together.

   The price is in the type. A `Scan z a` is a CPS computation whose answer
   type `z` is whatever consumes it; `Layout.Scan` fixes `z` to `Report`, which
   is why every function here mentions `Report` even when it does no layout,
   and why a Scan cannot be turned back into a relation. It is a one-way door
   out of the algebra and into the report.

   Table: postings (13 columns)
            journalId, postingDate, accountCode, accountName, costCentre,
            partyName, description, amountEur, currencyCode, fxRate,
            amountLocal, sourceLedger, reconciledFlag

   Helpers used: scanTotals, scanCounts, semiJoin, groupSum.
   Stdlib exercised: `Relation.Scan` DIRECTLY -- `groupBy1`, `groupBy1'`,
            `mapV`, `mapK`, `sortK`, `filterK`, `pickK`, `removeK`,
            `updateK`, `sumBy'`, `count'` -- of which only `groupBy1`/`mapV`
            /`pickK` had an example (`core/examples/GroupBy.e`).

   SOLVER SHAPES. `Relation.Scan.groupBy1`'s `r <- (h, t)` is solved with `h`
   a single named field and `t` the other twelve, and the result row `t` then
   flows into `sumBy'`, whose own `r <- (h, t)` must be solved against a row
   that is itself the REMAINDER of another partition. That chaining of a
   partition's output into another partition's input is the shape this
   directory has least of elsewhere.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/LedgerScan.e
     >> :import Algebra.LedgerScan
     >> scanReport
-}

import Prelude
import Layout
import Layout.Scan
import Relation.Scan as S
import Relation.Row as Rw
import Layout.Presentation as P
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Algebra.Helpers

field journalId : Int
field postingDate, accountCode, accountName, costCentre : String
field partyName, description, currencyCode, sourceLedger : String
field reconciledFlag : String
field amountEur, fxRate, amountLocal : Double
field totalEur : Double
field postingCount : Int

postings : [ journalId, postingDate, accountCode, accountName, costCentre
           , partyName, description, amountEur, currencyCode, fxRate
           , amountLocal, sourceLedger, reconciledFlag ]
postings = relation [
  { journalId = 70011, postingDate = "2026-01-05", accountCode = "4000", accountName = "Revenue",      costCentre = "CC-200", partyName = "Aurora Retail",  description = "invoice 9001", amountEur = -12400.00, currencyCode = "EUR", fxRate = 1.0000, amountLocal = -12400.00, sourceLedger = "AR", reconciledFlag = "yes" },
  { journalId = 70012, postingDate = "2026-01-05", accountCode = "1200", accountName = "Receivables",  costCentre = "CC-300", partyName = "Aurora Retail",  description = "invoice 9001", amountEur =  12400.00, currencyCode = "EUR", fxRate = 1.0000, amountLocal =  12400.00, sourceLedger = "AR", reconciledFlag = "yes" },
  { journalId = 70013, postingDate = "2026-01-08", accountCode = "6100", accountName = "Freight",      costCentre = "CC-210", partyName = "Baltic Haulage", description = "freight w1",   amountEur =    840.50, currencyCode = "EUR", fxRate = 1.0000, amountLocal =    840.50, sourceLedger = "AP", reconciledFlag = "yes" },
  { journalId = 70014, postingDate = "2026-01-08", accountCode = "2100", accountName = "Payables",     costCentre = "CC-300", partyName = "Baltic Haulage", description = "freight w1",   amountEur =   -840.50, currencyCode = "EUR", fxRate = 1.0000, amountLocal =   -840.50, sourceLedger = "AP", reconciledFlag = "yes" },
  { journalId = 70015, postingDate = "2026-01-12", accountCode = "4000", accountName = "Revenue",      costCentre = "CC-200", partyName = "Basalt Foundry", description = "invoice 9002", amountEur =  -3596.40, currencyCode = "USD", fxRate = 0.9210, amountLocal =  -3905.00, sourceLedger = "AR", reconciledFlag = "no" },
  { journalId = 70016, postingDate = "2026-01-12", accountCode = "1200", accountName = "Receivables",  costCentre = "CC-300", partyName = "Basalt Foundry", description = "invoice 9002", amountEur =   3596.40, currencyCode = "USD", fxRate = 0.9210, amountLocal =   3905.00, sourceLedger = "AR", reconciledFlag = "no" },
  { journalId = 70017, postingDate = "2026-01-15", accountCode = "6100", accountName = "Freight",      costCentre = "CC-220", partyName = "Rhine Express",  description = "freight w2",   amountEur =    295.75, currencyCode = "EUR", fxRate = 1.0000, amountLocal =    295.75, sourceLedger = "AP", reconciledFlag = "no" },
  { journalId = 70018, postingDate = "2026-01-15", accountCode = "2100", accountName = "Payables",     costCentre = "CC-300", partyName = "Rhine Express",  description = "freight w2",   amountEur =   -295.75, currencyCode = "EUR", fxRate = 1.0000, amountLocal =   -295.75, sourceLedger = "AP", reconciledFlag = "no" },
  { journalId = 70019, postingDate = "2026-01-19", accountCode = "4000", accountName = "Revenue",      costCentre = "CC-200", partyName = "Cinder & Co",    description = "invoice 9003", amountEur =  -1980.00, currencyCode = "EUR", fxRate = 1.0000, amountLocal =  -1980.00, sourceLedger = "AR", reconciledFlag = "yes" },
  { journalId = 70020, postingDate = "2026-01-19", accountCode = "1200", accountName = "Receivables",  costCentre = "CC-300", partyName = "Cinder & Co",    description = "invoice 9003", amountEur =   1980.00, currencyCode = "EUR", fxRate = 1.0000, amountLocal =   1980.00, sourceLedger = "AR", reconciledFlag = "yes" },
  { journalId = 70021, postingDate = "2026-01-22", accountCode = "6200", accountName = "Bank charges", costCentre = "CC-300", partyName = "Nordbank",       description = "fees jan",     amountEur =     67.20, currencyCode = "EUR", fxRate = 1.0000, amountLocal =     67.20, sourceLedger = "GL", reconciledFlag = "yes" },
  { journalId = 70022, postingDate = "2026-01-22", accountCode = "1000", accountName = "Cash",         costCentre = "CC-300", partyName = "Nordbank",       description = "fees jan",     amountEur =    -67.20, currencyCode = "EUR", fxRate = 1.0000, amountLocal =    -67.20, sourceLedger = "GL", reconciledFlag = "yes" }
]

-- ------------------------------------------------- the shape `columns` wants
--
-- A `Scan` of (heading, relation) pairs. `groupBy1` splits on one column and
-- gives back the rest of the row, so the projection decides what a cell holds:
-- keep `postingDate` and `amountEur` and the table is date x account.

byAccount = groupBy1 accountCode (postings # {accountCode, postingDate, amountEur})

plainGrid = byAccount |> mapV column |> columns ' keys {postingDate}

-- Column order is the scan's order, so `sortK` is how a report gets a stable
-- one -- there is no ORDER BY on the columns of a pivot.
sortedGrid = byAccount |> sortK ord_String |> mapV column |> columns ' keys {postingDate}

-- Only the two accounts this report is about, in the order given.
selectedGrid =
  byAccount |> pickK ["4000", "6100"] |> mapV column |> columns ' keys {postingDate}

-- Headings are just the key, so relabelling them is `mapK` and needs no
-- relational operation at all.
labelledGrid =
  byAccount
  |> mapK (a -> "Acct " ++_String a)
  |> sortK ord_String
  |> mapV column
  |> columns ' keys {postingDate}

-- Drop one column after the fact. `removeK` is one of the `Relation.Scan`
-- functions `Layout.Scan` does NOT re-export, so it is reached under its own
-- module's suffix -- worth knowing, because the re-export list is where the
-- Scan vocabulary a report can reach is actually decided.
withoutCash =
  byAccount |> removeK_S "1000" |> sortK ord_String |> mapV column
            |> columns ' keys {postingDate}

-- `filterK` keeps the columns whose heading passes a predicate; `updateK`
-- rewrites the CELLS of one named column and leaves the rest alone. Note what
-- `updateK`'s function is: `[..t] -> [..t]`, a whole relation to a whole
-- relation, so anything in the algebra can be applied to ONE column of a pivot
-- without touching the others.
largestFreightOnly =
  byAccount
  |> updateK "6100" (topK {amountEur} 1)
  |> sortK ord_String |> mapV column
  |> columns ' keys {postingDate}

balanceSheetOnly =
  byAccount
  |> filterK (a -> a <_Primitive "4000")
  |> sortK ord_String |> mapV column
  |> columns ' keys {postingDate}

-- Keep the whole row in each group (`groupBy1'`, note the prime) so the cell
-- can show more than one column.
detailGrid =
  groupBy1' sourceLedger (postings # {sourceLedger, journalId, amountEur})
  |> sortK ord_String
  |> mapV column
  |> columns ' keys {journalId}

-- --------------------------------------------------------- scanned totals
--
-- `sumBy'` and `count'` fold each group to a ONE-COLUMN relation, which is
-- still the shape `columns` renders -- so a total row and a detail grid are
-- the same kind of report, differing only in the fold.

totalsByAccount =
  scanTotals accountCode amountEur totalEur (postings # {accountCode, amountEur})
  |> sortK ord_String |> mapV column |> columns ' keys empty_Rw

countsByLedger =
  scanCounts sourceLedger postingCount (postings # {sourceLedger, journalId})
  |> sortK ord_String |> mapV column |> columns ' keys empty_Rw

-- ------------------------------------------------- and the same, set-at-a-time
--
-- The relational answer to the same question, for comparison: `groupSum` says
-- it in one line and gives back a RELATION, which can be joined against
-- something else. The scanned version cannot.
totalsRelational = groupSum {accountCode} amountEur (postings # {accountCode, amountEur})

unreconciled = filterEq reconciledFlag "no" postings
unreconciledAccounts = semiJoin {accountCode} (asMem unreconciled) (asMem postings)

-- ---------------------------------------------------------------- the report

scanReport = vflow [
  atomShown "## General ledger, scanned",
  atomShown "### Amount by date and account",
  plainGrid,
  atomShown "### The same, columns in a stable order",
  sortedGrid,
  atomShown "### Two accounts only, in the order asked for",
  selectedGrid,
  atomShown "### Headings relabelled by the scan, not by the query",
  labelledGrid,
  atomShown "### Cash dropped after the grouping",
  withoutCash,
  atomShown "### Balance-sheet accounts only, chosen by a predicate on the heading",
  balanceSheetOnly,
  atomShown "### The freight column cut to its single largest posting",
  largestFreightOnly,
  atomShown "### Whole rows in the cells, grouped by source ledger",
  detailGrid,
  atomShown "### Totals per account (scanned fold)",
  totalsByAccount,
  atomShown "### Postings per source ledger (scanned count)",
  countsByLedger,
  atomShown "### The same totals as a relation",
  tabular Nothing totalsRelational,
  atomShown "### Unreconciled postings",
  tabular Nothing unreconciled
]
