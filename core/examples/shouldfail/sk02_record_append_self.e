module Shouldfail.Sk02 where

{- SHOULD FAIL -- error class 4, SKOLEM ESCAPE.
   Route: same as sk01 but through the RECORD vocabulary rather than `Row`,
   so the case does not depend on one library function.

   `ERec` hides a record's row behind an existential; matching on `ERec x`
   makes that row a skolem (Subst.scala:1117, `unfurl`).
   `appendR : c <- (a, b) => {..a} -> {..b} -> {..c}` needs its operands to be
   disjoint, so `appendR x x` gives `c <- (r, r)` and forces the skolem `r`
   empty.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/sk02_record_append_self.e:1:1: core/examples/shouldfail/sk02_record_append_self.e:26:20: Cannot unify skolem variable with empty relation
   The following line prints the skolem's raw id, which is not stable.

   Raised by: Constraints.scala:945, `makeEmpty`
     if (v.ty == Skolem) tml.die(v.report("Cannot unify skolem variable with empty relation", v.toString))

   Rule modes: rejected under all / cut / nongen alike (input partition).
-}

import Prelude
import Record as Rec

data ERec = forall r. ERec {..r}

bad e = case e of ERec x -> appendR_Rec x x
