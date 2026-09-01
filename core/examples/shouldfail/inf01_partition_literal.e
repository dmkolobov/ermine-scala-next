module Shouldfail.Inf01 where

{- SHOULD FAIL -- error class 2, INFINITE ROW.
   Route: the self-partition is written straight into a signature.

   `r <- ((|a|), r)` partitions `r` into itself plus a non-empty concrete
   part, so `r` would have to strictly contain itself.  A signature's
   constraints are only ASSUMPTIONS, so the module needs the call site `use`
   to discharge it.

   Expected message (verbatim, default -Dermine.genRules=all; the ^NNNNNN
   suffix is a fresh-name counter and varies between runs):
     core/examples/shouldfail/inf01_partition_literal.e:24:1: Infinite row partition for 'r^590786'

   Raised by: Constraints.scala:805, `selfSubstitution`
     tml.die("Infinite row partition for '" + v + "'")
-}

import Prelude

field a : Int

f : r <- ((|a|), r) => [..r] -> [..r]
f x = x

use = f (relation [{ a = 1 }])
