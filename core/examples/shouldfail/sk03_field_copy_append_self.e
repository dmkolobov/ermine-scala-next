module Shouldfail.Sk03 where

{- SHOULD FAIL -- error class 4, SKOLEM ESCAPE.
   Route: same emptiness as sk01, but the existential comes from the STANDARD
   LIBRARY, so no user-declared data type is needed.

   `Field.e` declares  `data EField a = forall r . EField (Field r a)`  and
   `ecopyF : Field r a -> EField a` mints a fresh copy of a field under a
   hidden row.  Matching on `EField f` makes that row a skolem, and building a
   row from `f` twice asks `append` for `x <- (r, r)`, forcing the skolem empty.

   This is the failure mode a real caller of `withFieldCopy` would hit if it
   used the copied field twice in one row.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/sk03_field_copy_append_self.e:1:1: .../classes/modules/Field.e:22:24: Cannot unify skolem variable with empty relation
   The location inside the message points at the library's own `EField`
   declaration, because that is where the skolemised variable was bound.

   Raised by: Constraints.scala:945, `makeEmpty`
     if (v.ty == Skolem) tml.die(v.report("Cannot unify skolem variable with empty relation", v.toString))

   Rule modes: rejected under all / cut / nongen alike (input partition).
-}

import Prelude
import Relation.Row as Rw

field a : Int

bad = case ecopyF a of EField f -> append_Rw (single_Rw f) (single_Rw f)
