module Wide.Shouldfail.Win02 where

{- SHOULD FAIL -- a running total ORDERED BY the column it accumulates.

   `Relation.Windowed.windowed` has
       windowed : (t <- (r, s)) => Windowed r a -> Window s -> Op t a
   where `r` is the row the window FUNCTION reads (for a sum, the measure) and
   `s` is the row the WINDOW reads (the partition and the sort).  The two are
   unioned disjointly, so a measure that is also a sort column appears twice.

   `Wide.Helpers.runningTotal` inherits that as `wm <- (m, w)`, and this module
   instantiates it with `m = amount` and `w` containing `amount`.

   It is worth having as an example rather than a footnote, because the mistake
   is natural -- "running total of amount, in amount order" sounds like a
   sentence -- and because the diagnostic names the field, so a reader learns
   the rule from the error.  Order by a date or a sequence instead; see
   `Wide.TrialBalance`.

   Expected message: see Wide/shouldfail/RESULTS.md.

   Raised by: Constraints.scala, the duplicate-field detector.
-}

import Prelude
import Syntax.Relation
import Wide.Helpers

field accountCode : String
field amount, runningAmount : Double

ledger : [ accountCode, amount ]
ledger = relation [{ accountCode = "4000", amount = 100.0 }]

-- `amount` is both the measure and the sort.
bad = runningTotal {accountCode} (asc amount) amount runningAmount ledger
