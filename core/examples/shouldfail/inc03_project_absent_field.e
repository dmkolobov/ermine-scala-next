module ShouldFail.Inc03 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS (subsumption failure).

   Expected message:
     Row types failed to unify:
     R1 =
       ShouldFail.Inc03.shipDate
     R2 =
       ShouldFail.Inc03.{ amount, orderId }
   with "R1 inferred from" pointing at Constraint.e:5:28 (the `Has` alias).

   Raised by: Constraints.scala:300-308, `ensureSuperset`, reached from
   `makeConcrete` (Constraints.scala:976).

   Shape: projecting a column the relation does not have. `project` needs
   `Has r (|shipDate|)`, i.e. r <- (shipDate, c); r is already the concrete
   row { amount, orderId }, which does not subsume { shipDate }.

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

bad = project {shipDate} orders
