module Shouldfail.Inf07 where

{- SHOULD FAIL -- error class 2, INFINITE ROW.
   Route: a RECORD rather than a relation or a row witness.

   `exceptT : r <- (h, t) => Row h -> {..r} -> {..t}` drops a field from a
   record.  `same` forces the shrunken record to have the same row as the
   original, so `r <- ((|a|), r)`.

   Expected message (verbatim, default -Dermine.genRules=all; the ^NNNNNN
   suffix is a fresh-name counter and varies between runs):
     core/examples/shouldfail/inf07_record_drop.e:1:1: Infinite row partition for 't^599889'

   Raised by: Constraints.scala:805, `selfSubstitution`
     tml.die("Infinite row partition for '" + v + "'")
-}

import Prelude

field a : Int

same : {..r} -> {..r} -> Int
same _ _ = 1

bad rec = same rec (exceptT {a} rec)
