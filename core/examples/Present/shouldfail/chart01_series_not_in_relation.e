module Present.Shouldfail.Chart01 where

{- NEGATIVE. A chart whose SERIES column is not in the relation it plots.

   `chartOf`'s constraint is `r <- (sr, xr, yr, o)`: the series, category and
   value rows are all parts of the relation's own row, and `o` absorbs whatever
   else the relation carries -- but it cannot absorb a column that is not
   there. Here the series selector names `channelName`, which the projected
   relation dropped.

   This is the most common chart error in practice: the relation is projected
   for one panel and reused for another.

   EXPECTED (verbatim):

     Row partitions are unsatisfiable at field
     'Present.Shouldfail.Chart01.channelName': the whole contains it but no part
     does

   NOTE ON THE WORDING. The sentence describes the OPPOSITE situation from the
   one here: a PART (the series row) contains `channelName` and the whole (the
   projected relation) does not. Verdict and field are right, the explanation
   is backwards; this is the defect `tracker/loopmodel/E1-EXAMPLES.md` section
   7.5 records, reproduced independently.
-}

import Prelude
import Layout
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Sort as Sort
import Syntax.Relation
import Present.Helpers

field regionName, channelName, quarterName : String
field amountUsd : Double

sales : [ regionName, channelName, quarterName, amountUsd ]
sales = relation [ { regionName = "AMER", channelName = "Direct",
                     quarterName = "Q1", amountUsd = 100.0 } ]

-- The projection drops `channelName`.
projected = sales # { regionName, quarterName, amountUsd }

-- REJECTED: the series column is not in the projected relation.
bad = chartOf "Sales" (unscaled Ascending_Sort) defaultScaled
              bar channelName regionName amountUsd projected
