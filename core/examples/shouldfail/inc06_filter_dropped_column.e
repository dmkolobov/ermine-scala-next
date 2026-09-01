module ShouldFail.Inc06 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS (subsumption failure).

   Expected message:
     Row types failed to unify:
     R1 =
       ShouldFail.Inc06.amount
     R2 =
       ShouldFail.Inc06.orderId
   with "R1 inferred from" pointing at Constraint.e:5:28.

   Raised by: Constraints.scala:300-308, `ensureSuperset`, reached from
   `makeConcrete` (Constraints.scala:976).

   Shape: a two-step pipeline. `keys` projects the relation down to its key
   column, and the next stage filters on the value column that projection just
   discarded. The concrete row R2 here is the *inferred* result of the first
   stage, not an annotation, so the solver must concretise it before the
   contradiction is visible.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field orderId : Int
field amount : Double

orders = relation [{ orderId = 1, amount = 25.0 }]
keys   = project {orderId} orders

bad = filterEq amount 25.0 keys
