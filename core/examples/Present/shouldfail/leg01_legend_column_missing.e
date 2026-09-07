module Present.Shouldfail.Leg01 where

{- NEGATIVE. A legend over a category the relation has not got.

   The legend names three columns; the relation has two. `Layout.Report.tabular`
   is `Maybe (Legend r) -> rel (|..r|) -> Report f z` -- ONE row variable used
   twice, so the legend's row and the relation's row must be the SAME row, not
   merely compatible. There is no partition here to absorb the extra column.

   This is the "legend over a missing category" case: adding a column to a
   legend without adding it to the relation is a type error, which is exactly
   what one wants, because the alternative is a blank column in the document.

   EXPECTED (verbatim):

     error: failed to unify type (|regionName, amountUsd, missingColumn|)
       with type (|regionName, amountUsd|)
-}

import Prelude
import Layout
import Layout.Legend as Lg
import Layout.SortPriority
import Syntax.Relation
import Syntax.List

field regionName, missingColumn : String
field amountUsd : Double

lines : [ regionName, amountUsd ]
lines = relation [ { regionName = "AMER", amountUsd = 100.0 } ]

overreaching : Legend_Lg (| regionName, amountUsd, missingColumn |)
overreaching = [ (regionName,    "Region") ^ 0
               , (amountUsd,     "Amount") ^ 1
               , (missingColumn, "Missing") ^ 2 ]_Sorted_Lg

-- REJECTED: the legend's row is not the relation's row.
bad = tabular (Just overreaching) lines
