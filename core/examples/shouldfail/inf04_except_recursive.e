module Shouldfail.Inf04 where

{- SHOULD FAIL -- error class 2, INFINITE ROW.
   Route: RECURSION.  `g` drops a column and calls itself; monomorphic
   recursion unifies the argument row with the shrunken row, so the row must
   equal itself plus the concrete field `a`.

   Expected message (verbatim, default -Dermine.genRules=all; the ^NNNNNN
   suffix is a fresh-name counter and varies between runs):
     core/examples/shouldfail/inf04_except_recursive.e:20:1: Infinite row partition for 'r^595812'

   Raised by: Constraints.scala:805, `selfSubstitution`
     tml.die("Infinite row partition for '" + v + "'")
-}

import Prelude

field a, b : Int

g x = g (except {a} x)

use = g (relation [{ a = 1, b = 2 }])
