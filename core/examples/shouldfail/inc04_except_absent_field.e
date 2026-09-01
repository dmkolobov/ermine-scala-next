module ShouldFail.Inc04 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS (subsumption failure).

   Expected message:
     Row types failed to unify:
     R1 =
       ShouldFail.Inc04.shipDate
     R2 =
       ShouldFail.Inc04.{ amount, orderId }
   with "R1 inferred from" pointing at Relation/Row.e:51:48 (`except`'s own
   r <- (r1,r2) constraint, not the `Has` alias -- that is what distinguishes
   this case from inc03).

   Raised by: Constraints.scala:300-308, `ensureSuperset`, reached from
   `makeConcrete` (Constraints.scala:976).

   Shape: dropping a column the relation does not have.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field orderId : Int
field amount : Double
field shipDate : Date

orders = relation [{ orderId = 1, amount = 25.0 }]

bad = except {shipDate} orders
