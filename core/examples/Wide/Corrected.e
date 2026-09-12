module Wide.Corrected where

{- THE CORRECTED `melt` SIGNATURES, CALLED -- the positive control for stage S3b
   in this group.

   `Wide.Helpers.melt2`, `melt3`, `melt4` and `Wide.Signatures.melt3Simple` each
   gained ONE constraint on 2026-09-11: `r | key`, "the key column is not already
   in the input".  Without it the signature is dishonest -- each arm of the body
   drops the other measures, `combine`s the literal column name into `key` and
   renames the survivor to `val`, so it needs `key` disjoint from every melted
   column, and `r <- (i, fa, fb)` with `out <- (i, key, val)` gives that only for
   `i` and `val`.  `melt2 fa vf fa fb r` -- the key column and one melted column
   the SAME field -- type-checked before the correction and evaluated to
   `Failure(Cannot union columns: expected Map(x, vcol), found Map(x, pp, vcol))`.

   WHICH CORRECTION EACH BINDING EXERCISES
     `long`      `Wide.Helpers.melt2` at `key = (|measure|)`, which is outside
                 `r = (|storeId, month, salesAmt, refundAmt|)`: the row the new
                 constraint asks for, and the shape every honest call has.
     `long3`     `Wide.Helpers.melt3` at arity three, same shape.

   The other two of the four melt corrections are exercised where they already
   were: `melt4` by `Wide/SurveyPanel.e`, and `Wide.Signatures.melt3Simple` by
   `Wide/Signatures.e` itself, whose body is written out -- loading that module IS
   the check that the body has the corrected type.  This module deliberately
   imports only `Wide.Helpers`: `tracker/tools/corpus-run.sh` hoists a group's
   `Helpers.e` and nothing else, and `Corrected.e` sorts BEFORE `Signatures.e`, so
   an `import Wide.Signatures` here is `Module not found` in a corpus batch
   (measured, 2026-09-11).

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/Corrected.e
     >> long
-}

import Prelude
import Relation.Op as Op
import Syntax.Relation
import Wide.Helpers

field storeId : Int
field month : String
field salesAmt, refundAmt, discountAmt : Double
field measure : String
field amount : Double

-- `r <- (i, fa, fb)` with i = (|storeId, month|), and `measure` in neither.
takings : [ storeId, month, salesAmt, refundAmt ]
takings = relation
  [ { storeId = 10, month = "2025-01", salesAmt = 412000.0, refundAmt = 3100.0 }
  , { storeId = 10, month = "2025-02", salesAmt = 388500.0, refundAmt = 2450.0 }
  , { storeId = 20, month = "2025-01", salesAmt = 188000.0, refundAmt =  900.0 } ]

-- Two rows out per row in, the measure's own name in `measure` and its value in
-- `amount`; the identity columns repeat.
long : [ storeId, month, measure, amount ]
long = melt2 measure amount salesAmt refundAmt takings

threeWay : [ storeId, month, salesAmt, refundAmt, discountAmt ]
threeWay = relation
  [ { storeId = 10, month = "2025-01", salesAmt = 412000.0, refundAmt = 3100.0
    , discountAmt = 14200.0 }
  , { storeId = 20, month = "2025-01", salesAmt = 188000.0, refundAmt = 900.0
    , discountAmt = 5100.0 } ]

long3 : [ storeId, month, measure, amount ]
long3 = melt3 measure amount salesAmt refundAmt discountAmt threeWay
