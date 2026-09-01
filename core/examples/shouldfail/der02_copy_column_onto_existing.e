module Shouldfail.Der02 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD, reached only through a
   DERIVED constraint.

   Contrast with dup08, which copies a column onto ITSELF and is caught
   directly when the partition is built.  Here the destination column is a
   DIFFERENT name that the relation happens to contain already, so nothing in
   the input set is duplicated.

       copyColumn : (ri <- (r1, t), ro <- (r1, r2, t))
                 => Field r1 x -> Field r2 x -> rel ri -> rel ro

   At `copyColumn a b ab` the input constraints are

       (|a, b|) <- ((|a|), t)
       ro       <- ((|a|), (|b|), t)

   Cancellation (Constraints.scala:1017) against the concrete left-hand side
   gives `t <- (|b|)`; substituting that into the second rule is what puts `b`
   in a row twice.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/der02_copy_column_onto_existing.e:39:7: Fields appear twice in row: Set(Shouldfail.Der02.b)

   Raised by: Constraints.scala:329, `RHS.merge`
     else tml.die("Fields appear twice in row: " + cint)

   Rule modes: rejected under all / cut / nongen alike.
-}

import Prelude

field a, b : Int

ab : [a, b]
ab = relation [{ a = 1, b = 2 }]

bad = copyColumn a b ab
