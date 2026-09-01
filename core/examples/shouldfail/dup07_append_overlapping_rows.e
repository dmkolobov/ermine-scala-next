module Shouldfail.Dup07 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: appending two ROW WITNESSES that overlap.

   `append : r <- (r1, r2) => Row r1 -> Row r2 -> Row r` requires the two
   witnesses to be disjoint.  Both name `b`.
   (`Relation.Row` is imported qualified because Prelude's unqualified
   `append` is `Relation.Sort`'s.)

   Expected message (verbatim, default -Dermine.genRules=all):
     .../classes/modules/Relation/Row.e:29:36: Fields appear twice in row: Shouldfail.Dup07.b

   Raised by: Constraints.scala:375, `RHS.build`
     tml.die("Fields appear twice in row: " + i.mkString(","))
-}

import Prelude
import Relation.Row as Rw

field a, b, c : Int

w = append_Rw {a, b} {b, c}
