module Shouldfail.Dup04 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: an ANNOTATED join key -- a row witness pins the shared part of the
   join, so the remainders collide.

   `joinBy : (r1 <- (k,t1), r2 <- (k,t2), r <- (k,t1,t2)) => Row k
             -> rel r1 -> rel r2 -> rel r`
   The witness {k} says the join key is exactly `k`, so each operand's
   remainder is (|x|), and the result partition names `x` twice.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/dup04_joinby_shared_column.e:30:7: Fields appear twice in row: Set(Shouldfail.Dup04.x)

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

bad = joinBy {k} left right
