module Shouldfail.Dup01 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD.
   Route: the duplicate is written straight into a partition constraint.

   The right-hand side of `r <- ((|a|), (|a|))` names the concrete field `a`
   in two different parts.  Parts of a partition must be pairwise disjoint,
   so `a` would have to appear twice in `r`.  A signature's constraints are
   only ASSUMPTIONS, so the module needs the call site `use` to discharge it.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/dup01_partition_literal.e:23:1: Fields appear twice in row: Shouldfail.Dup01.a

   Raised by: Constraints.scala:375, `RHS.build`
     tml.die("Fields appear twice in row: " + i.mkString(","))
-}

import Prelude

field a : Int

f : r <- ((|a|), (|a|)) => [..r] -> [..r]
f x = x

use = f (relation [{ a = 1 }])
