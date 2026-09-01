module Shouldfail.Der03 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD, reached only through a
   DERIVED constraint.

   Drop a column from a row header, then put a column back under a name the
   remainder still holds.

       minus : t <- (r, s) => Row t -> Row r -> Row s
       snoc  : r <- (r1, r2) => Row r1 -> Field r2 x -> Row r

   The input set is

       (|a, b|) <- ((|a|), s)      -- from minus
       r        <- (s, (|b|))      -- from snoc

   Neither row names a field twice.  Cancellation (Constraints.scala:1017)
   solves `s <- (|b|)`, and only then is `b` asked for twice.

   NOTE the reported location is inside the library (Relation/Row.e, `snoc`),
   because by the time the offending partition is constructed the remainder has
   already been substituted into `snoc`'s own constraint.  That also means this
   one is caught at RHS.BUILD rather than RHS.merge -- hence the bare field
   name in the message instead of a `Set(...)`.

   Expected message (verbatim, default -Dermine.genRules=all):
     .../classes/modules/Relation/Row.e:32:34: Fields appear twice in row: Shouldfail.Der03.b

   Raised by: Constraints.scala:375, `RHS.build`
     tml.die("Fields appear twice in row: " + i.mkString(","))

   Rule modes: rejected under all / cut / nongen alike.
-}

import Prelude
import Relation.Row as Rw

field a, b : Int

ab : Row (|a, b|)
ab = append_Rw (single_Rw a) (single_Rw b)

bad = snoc_Rw (minus_Rw ab (single_Rw a)) b
