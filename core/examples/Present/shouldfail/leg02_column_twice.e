module Present.Shouldfail.Leg02 where

{- NEGATIVE. One column named on BOTH sides of `withFormats`.

   `withFormats : r <- (k, m) => Legend k -> Format a -> Row m -> Legend r`. The
   partition is DISJOINT: `k` and `m` may not overlap. Here `amountUsd` is both
   labelled by hand in the key legend and swept up by the measure row, so the
   two parts share a field and the partition is unsatisfiable.

   A grid cannot show one column twice, and this is where the compiler says so.

   EXPECTED (verbatim):

     Fields appear twice in row: Present.Shouldfail.Leg02.amountUsd
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.SortPriority
import Syntax.Relation
import Syntax.List
import Present.Helpers

field regionName : String
field amountUsd, targetUsd : Double

-- REJECTED: `amountUsd` is in the key legend AND in the measure row.
bad = withFormats ([ (regionName, "Region") ^ 0
                   , (amountUsd,  "Amount") ^ 1 ]_Sorted_Lg)
                  (currency_Fmt "USD")
                  { amountUsd, targetUsd }
