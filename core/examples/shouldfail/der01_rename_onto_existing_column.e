module Shouldfail.Der01 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD, reached only through a
   DERIVED constraint.

   Renaming a column onto a name the relation ALREADY carries.  The library's
       rename : (u1 <- (r1, t), u2 <- (r2, t)) => Field r1 x -> Field r2 x
                -> [..u1] -> [..u2]
   names the untouched remainder `t`.  Instantiated at `rename a b ab` the
   INPUT constraint set is just

       (|a, b|) <- ((|a|), t)
       u2       <- ((|b|), t)

   No row here mentions a field twice; `t` is an unknown.  The solver first
   CANCELS the first rule against the concrete left-hand side
   (Constraints.scala:1017) to learn `t <- (|b|)`, and only when that is
   substituted into the second rule does `b` end up in a row twice.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/der01_rename_onto_existing_column.e:41:7: Fields appear twice in row: Set(Shouldfail.Der01.b)
   The `Set(...)` shape of the field list is the signature of RHS.merge; the
   direct-detection site (RHS.build, Constraints.scala:375) prints a bare,
   comma-joined list instead.

   Raised by: Constraints.scala:329, `RHS.merge`
     else tml.die("Fields appear twice in row: " + cint)
   reached from `RHS.substitute` via `subPartitions`/`destructiveSub`.

   Rule modes: rejected under all / cut / nongen alike -- cancellation and
   substitution are non-generative.
-}

import Prelude

field a, b : Int

ab : [a, b]
ab = relation [{ a = 1, b = 2 }]

bad = rename a b ab
