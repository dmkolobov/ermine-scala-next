module Shouldfail.Dup06 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: a RECORD operation -- adding a field the record already has.

   `cons : t <- (r, s) => Field r a -> a -> {..s} -> {..t}` extends a record
   and requires the new field to be absent from it.  The literal already
   carries `a`, so `t <- ((|a|), (|a|))`.

   Expected message (verbatim, default -Dermine.genRules=all):
     Fields appear twice in row: Shouldfail.Dup06.a
   (this one is reported without a source location prefix)

   Raised by: Constraints.scala:375, `RHS.build`
     tml.die("Fields appear twice in row: " + i.mkString(","))
-}

import Prelude

field a : Int

bad = cons a 1 { a = 2 }
