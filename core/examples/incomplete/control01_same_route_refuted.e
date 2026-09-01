module Incomplete.Control01 where

{- CALIBRATION FOR `unsound04_dead_helper.e`.  THIS FILE MUST FAIL.

   Identical shape to `unsound04`: an unsatisfiable signature, a body that just
   returns its argument, and a `use` that applies it to a concrete relation so
   the assumptions become wanted constraints.  The only difference is that this
   signature's contradiction is one the solver can see -- `(|amount|)` written
   twice in the same partition -- rather than one that needs a step of
   elimination.

   OBSERVED 2026-09-01, -Dermine.useInterface=false, default genRules=all:
     control01_same_route_refuted.e:29:1: Fields appear twice in row: Incomplete.Control01.amount

   That is the point: the `use` route DOES force the solver to discharge a
   signature's constraints, and it DOES reject an unsatisfiable one.  So
   "signature constraints are only assumptions" is not an explanation for
   `unsound04` loading.  (This is the shape of
   `core/examples/shouldfail/dup01_partition_literal.e`, restated here in the
   same field vocabulary so the two files differ in exactly one thing.)
-}

import Prelude

field regionCode : Int
field amount : Double

withAmountBlocks : forall t. t <- ((|amount|), (|amount|)) => [..t] -> [..t]
withAmountBlocks src = src

use : [regionCode, amount]
use = withAmountBlocks (relation [{ regionCode = 1, amount = 2.0 }])
