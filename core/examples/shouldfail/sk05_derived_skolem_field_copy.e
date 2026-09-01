module Shouldfail.Sk05 where

{- SHOULD FAIL -- error class 4, SKOLEM ESCAPE, reached only through a DERIVED
   constraint.

   Identical derivation to sk04 -- substitution of `b`'s partition produces a
   repeated variable, which becomes `r <- ` -- but the skolem comes from the
   standard library's `EField` existential (`Field.e`, `ecopyF`) rather than
   from a data type declared here.  So the derived route is not an artefact of
   the hand-written `ERow`.

   Input constraints (neither repeats a variable):
       b <- (r, (|a|))
       (|a|) <- (b, r)

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/sk05_derived_skolem_field_copy.e:1:1: .../classes/modules/Field.e:22:24: Cannot unify skolem variable with empty relation
   The location inside the message points at the library's `EField`
   declaration, where the skolemised variable was bound.  The next line prints
   the skolem's raw id, which is not stable across runs.

   Raised by: Constraints.scala:945, `makeEmpty`
     if (v.ty == Skolem) tml.die(v.report("Cannot unify skolem variable with empty relation", v.toString))

   Rule modes: rejected under all / cut / nongen alike.
-}

import Prelude
import Relation.Row as Rw

field a : Int

rA : Row (|a|)
rA = single_Rw a

step2 : forall x c d y. (exists b. b <- (x, d), c <- (b, y))
     => Row x -> Row y -> Row c -> Row d -> Int
step2 _ _ _ _ = 0

bad = case ecopyF a of EField f -> step2 (single_Rw f) (single_Rw f) rA rA
