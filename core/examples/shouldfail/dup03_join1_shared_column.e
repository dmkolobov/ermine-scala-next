module Shouldfail.Dup03 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: a JOIN of two relations that share a column beyond the join key.

   `join1 : (ra <- (k, r1), rb <- (k, r2), r <- (k, r1, r2)) => Field k a
            -> rel ra -> rel rb -> rel r`
   pins the join key to the single field `k` and requires the two remainders
   to be disjoint.  Both operands are (k, x), so both remainders are forced
   to (|x|) and the result row would contain `x` twice.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/dup03_join1_shared_column.e:30:7: Fields appear twice in row: Set(Shouldfail.Dup03.x)

   Raised by: Constraints.scala:329, `RHS.merge`
     tml.die("Fields appear twice in row: " + cint)
-}

import Prelude
import Syntax.Relation

field k, x : Int

left : [ k, x ]
left = relation [{ k = 1, x = 10 }]

right : [ k, x ]
right = relation [{ k = 1, x = 20 }]

bad = join1 k left right
