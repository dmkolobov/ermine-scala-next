module Shouldfail.Sk04 where

{- SHOULD FAIL -- error class 4, SKOLEM ESCAPE, reached only through a DERIVED
   constraint.

   This is the same die site as sk01-sk03, but nothing in the INPUT constraint
   set mentions the skolem twice.  The input is

       b <- (r, (|a|))          -- from step2's first given, x := r, d := (|a|)
       (|a|) <- (b, r)          -- from step2's second given, c := (|a|), y := r

   Each partition is individually satisfiable and neither repeats a variable.
   The contradiction appears only after the solver SUBSTITUTES b's partition
   into the second rule (Constraints.scala:1074, `substitution`):

       (|a|) <- (r, (|a|), r)

   `RHS.merge` then sees `r` on both sides of the union, returns it in the
   `es` set, and `subBody` turns that into `r <- ` (DeDuplication,
   Constraints.scala:1062).  `r` is the skolem introduced by matching on
   `ERow r`, so emptying it is refused.

   `step2`'s signature is satisfiable in general -- `x` and `y` are independent
   rows -- see the control at
   core/examples/shouldfail-controls/control04_step2_satisfiable.e, which must
   load.  Only passing the SAME row for `x` and `y` collapses it.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/sk04_derived_skolem_substitution.e:1:1: core/examples/shouldfail/sk04_derived_skolem_substitution.e:47:20: Cannot unify skolem variable with empty relation
   The next line prints the skolem's raw id, which is not stable across runs.

   Raised by: Constraints.scala:945, `makeEmpty`
     if (v.ty == Skolem) tml.die(v.report("Cannot unify skolem variable with empty relation", v.toString))

   Rule modes: rejected under all / cut / nongen alike.  `substitution` is not
   a generative rule, so cutting the minting rules does not lose this one.
-}

import Prelude
import Relation.Row as Rw

field a : Int

rA : Row (|a|)
rA = single_Rw a

data ERow = forall r. ERow (Row r)

step2 : forall x c d y. (exists b. b <- (x, d), c <- (b, y))
     => Row x -> Row y -> Row c -> Row d -> Int
step2 _ _ _ _ = 0

bad e = case e of ERow r -> step2 r r rA rA
