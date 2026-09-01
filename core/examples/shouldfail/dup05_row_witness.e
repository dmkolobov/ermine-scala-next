module Shouldfail.Dup05 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: a ROW WITNESS that names the same field twice.

   `{a, a}` desugars to `snoc (single a) a`, i.e. `append`, whose signature is
   `r <- (r1, r2) => Row r1 -> Row r2 -> Row r`.  Both halves are the field
   `a`, so the witness row would contain `a` twice.  The reported location is
   inside the library (`Relation/Row.e`, the `append` that `snoc` calls).

   Expected message (verbatim, default -Dermine.genRules=all):
     .../classes/modules/Relation/Row.e:32:34: Fields appear twice in row: Shouldfail.Dup05.a

   Raised by: Constraints.scala:375, `RHS.build`
     tml.die("Fields appear twice in row: " + i.mkString(","))
-}

import Prelude

field a : Int

w : Row r
w = {a, a}
