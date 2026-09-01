module Shouldfail.Dup02 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: no single partition names `a` twice; the duplicate only appears
   after the solver SUBSTITUTES one rule into the other.

   `r` is `a` plus `s`, and `s` is `a` plus `t`.  Substituting the second
   into the first gives `r <- ((|a|), (|a|), t)`.  Because the duplicate is
   produced by substitution rather than by parsing a literal RHS, this file
   hits `RHS.merge`, a different `die` site from dup01.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/dup02_signature_chain.e:24:1: Fields appear twice in row: Set(Shouldfail.Dup02.a)

   Raised by: Constraints.scala:329, `RHS.merge`
     tml.die("Fields appear twice in row: " + cint)
-}

import Prelude

field a, b : Int

f : (r <- ((|a|), s), s <- ((|a|), t)) => [..t] -> Int
f _ = 1

use = f (relation [{ b = 1 }])
