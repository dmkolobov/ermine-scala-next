module Shouldfail.Inf05 where

{- SHOULD FAIL -- error class 2, INFINITE ROW.
   Route: INFERENCE through a TWO-STEP chain, so the cycle needs an
   intermediate row variable to be substituted away first.

   The nested `except`s introduce `r <- ((|b|), s)` and `s <- ((|a|), r2)`;
   `union` unifies `r2` with `r`.  Neither partition is self-referential on
   its own.

   Expected message (verbatim, default -Dermine.genRules=all; the ^NNNNNN
   suffix is a fresh-name counter and varies between runs):
     core/examples/shouldfail/inf05_union_two_fields.e:1:1: Infinite row partition for 'r2^599062'

   Raised by: Constraints.scala:805, `selfSubstitution`
     tml.die("Infinite row partition for '" + v + "'")
-}

import Prelude

field a, b : Int

bad x = union x (except {a} (except {b} x))
