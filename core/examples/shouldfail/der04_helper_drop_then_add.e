module Shouldfail.Der04 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD, reached only through a
   DERIVED constraint.

   The same contradiction as der03, but hidden behind a row-polymorphic helper
   so that the intermediate row `t` exists ONLY in the helper's signature and
   the error is reported at the CALL SITE.

       dropThenAdd : (r <- (h, t), s <- (t, g))
                  => Field h x -> Field g y -> Row r -> Row s

   is satisfiable in general -- see the control at
   core/examples/shouldfail-controls/control05_drop_then_add.e -- and becomes
   contradictory only for the instantiation `h := (|a|)`, `g := (|b|)`,
   `r := (|a, b|)`, where cancellation forces `t <- (|b|)` and substitution
   then puts `b` in `s` twice.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/der04_helper_drop_then_add.e:38:1: Fields appear twice in row: Set(Shouldfail.Der04.b)

   Raised by: Constraints.scala:329, `RHS.merge`
     else tml.die("Fields appear twice in row: " + cint)

   Rule modes: rejected under all / cut / nongen alike.
-}

import Prelude
import Relation.Row as Rw

field a, b : Int

ab : Row (|a, b|)
ab = append_Rw (single_Rw a) (single_Rw b)

dropThenAdd : forall r s h t g x y. (r <- (h, t), s <- (t, g))
           => Field h x -> Field g y -> Row r -> Row s
dropThenAdd f g rw = snoc_Rw (minus_Rw rw (single_Rw f)) g

bad = dropThenAdd a b ab
