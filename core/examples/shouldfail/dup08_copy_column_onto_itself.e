module Shouldfail.Dup08 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: a library relation operator whose source and destination columns
   must be disjoint.

   `copyColumn : (ri <- (r1,t), ro <- (r1,r2,t)) => Field r1 a -> Field r2 a
                 -> rel ri -> rel ro`
   makes a second column from an existing one.  Copying `a` onto `a` gives
   `ro <- ((|a|), (|a|), t)`.  The reported location is inside the library
   (`Relation.e`, `copyColumn`).

   Expected message (verbatim, default -Dermine.genRules=all):
     .../classes/modules/Relation.e:251:29: Fields appear twice in row: Shouldfail.Dup08.a

   Raised by: Constraints.scala:375, `RHS.build`
     tml.die("Fields appear twice in row: " + i.mkString(","))
-}

import Prelude

field a : Int

bad = copyColumn a a (relation [{ a = 1 }])
