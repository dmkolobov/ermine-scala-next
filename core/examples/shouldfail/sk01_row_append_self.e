module Shouldfail.Sk01 where

{- SHOULD FAIL -- error class 4, SKOLEM ESCAPE.
   Route: a rigid (skolem) row variable is forced to be the empty row.

   `ERow` hides a row behind an existential.  Matching on `ERow r` turns that
   row into a SKOLEM -- Subst.scala:1117, `unfurl`: a constructor's quantified
   variables that do not occur in its result type are refreshed to `Skolem` --
   so `r` denotes one fixed, unknown, rigid row.

   `append : r <- (r1, r2) => Row r1 -> Row r2 -> Row r` requires its two
   operands to be DISJOINT.  Appending the row to itself gives `x <- (r, r)`,
   and a variable that appears twice on one right-hand side can only be empty.
   Emptying a skolem is what the checker refuses.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/sk01_row_append_self.e:1:1: core/examples/shouldfail/sk01_row_append_self.e:33:20: Cannot unify skolem variable with empty relation
   The next output line prints the skolem's raw id (e.g. `r^579348S`); that id
   is NOT stable across runs -- it depends on how many modules the Supply has
   already served.  Match on the message text, not the id.

   Raised by: Constraints.scala:945, `makeEmpty`
     if (v.ty == Skolem) tml.die(v.report("Cannot unify skolem variable with empty relation", v.toString))

   Rule modes: rejected under all / cut / nongen alike.  The emptiness here is
   an INPUT partition -- PQueue.build emits `r <- ` for the repeated variable
   at Constraints.scala:647-648 -- so no generative rule is involved.
-}

import Prelude
import Relation.Row as Rw

data ERow = forall r. ERow (Row r)

bad e = case e of ERow r -> append_Rw r r
