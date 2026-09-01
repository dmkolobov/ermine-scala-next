module ShouldFail.Inc07 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS (subsumption failure).

   Expected message:
     Row types failed to unify:
     R1 =
       ShouldFail.Inc07.customerId
     R2 =
       ShouldFail.Inc07.{ amount, orderId }
   with "R1 inferred from" pointing at Constraint.e:5:28.

   Raised by: Constraints.scala:300-308, `ensureSuperset`, reached from
   `makeConcrete` (Constraints.scala:976).

   Shape: a hand-written row-polymorphic helper -- the Ai.Common idiom -- whose
   `Has r (|customerId|)` obligation is discharged at the CALL SITE against a
   relation that lacks the column. The refutation therefore happens while
   instantiating a user signature, not while checking a library primitive.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field orderId, customerId : Int
field amount : Double

orders = relation [{ orderId = 1, amount = 25.0 }]

byCustomer : forall r. Has r (|customerId|) => [..r] -> [..r]
byCustomer = filterEq customerId 7

bad = byCustomer orders
