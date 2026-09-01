module Shouldfail.Inf03 where

{- SHOULD FAIL -- error class 2, INFINITE ROW.
   Route: pure INFERENCE -- nothing is annotated and no self-partition is
   written anywhere in the source.

   `except {a}` yields a strictly smaller row (`r <- ((|a|), r2)`), while
   `union : [..a] -> [..a] -> [..a]` forces its two operands to carry the
   SAME row.  Unifying `r2` with `r` is what closes the cycle.

   Expected message (verbatim, default -Dermine.genRules=all; the ^NNNNNN
   suffix is a fresh-name counter and varies between runs):
     core/examples/shouldfail/inf03_union_shrunken.e:1:1: Infinite row partition for 'r2^595531'

   Raised by: Constraints.scala:805, `selfSubstitution`
     tml.die("Infinite row partition for '" + v + "'")
-}

import Prelude

field a : Int

bad x = union x (except {a} x)
