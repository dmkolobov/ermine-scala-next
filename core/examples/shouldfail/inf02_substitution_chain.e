module Shouldfail.Inf02 where

{- SHOULD FAIL -- error class 2, INFINITE ROW.
   Route: neither partition mentions its own left-hand side; the cycle only
   appears after SUBSTITUTION.

   `r <- ((|a|), s)` and `s <- ((|b|), r)` are each well-formed.  Substituting
   the second into the first yields `r <- ((|a|), (|b|), r)`.

   Expected message (verbatim, default -Dermine.genRules=all; the ^NNNNNN
   suffix is a fresh-name counter and varies between runs):
     core/examples/shouldfail/inf02_substitution_chain.e:23:1: Infinite row partition for 's^594983'

   Raised by: Constraints.scala:805, `selfSubstitution`
     tml.die("Infinite row partition for '" + v + "'")
-}

import Prelude

field a, b, c : Int

f : (r <- ((|a|), s), s <- ((|b|), r)) => [..t] -> Int
f _ = 1

use = f (relation [{ c = 1 }])
