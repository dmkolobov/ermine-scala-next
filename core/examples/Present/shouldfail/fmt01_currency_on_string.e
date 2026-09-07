module Present.Shouldfail.Fmt01 where

{- NEGATIVE. A currency format applied to a column that is not a number.

   `Layout.Presentation.currency : (AsOp op, PrimitiveNum n) => String -> op r n
   -> Presentation r n`. `statusName` is a `Field statusName String`, and
   `String` has no `PrimitiveNum` instance, so the class constraint cannot be
   discharged.

   This is the mistake a reader is most likely to make when copying a legend
   from one report to another: the SHAPE of the legend does not change, only the
   type of one column, and the format silently goes with it.

   EXPECTED (verbatim, `bin/ermine core/examples/Present/shouldfail/fmt01_currency_on_string.e`):

     No instance for (PrimitiveNum String)
-}

import Prelude
import Layout
import Layout.Presentation as Pres
import Syntax.Relation

field statusName : String
field amountUsd : Double

lines : [ statusName, amountUsd ]
lines = relation [ { statusName = "Posted", amountUsd = 100.0 } ]

-- REJECTED: String is not PrimitiveNum.
bad = currency_Pres "USD" statusName
