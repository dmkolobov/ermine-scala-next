module ShouldFail.Inc05 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS (subsumption failure).

   Expected message:
     Row types failed to unify:
     R1 =
       ShouldFail.Inc05.region
     R2 =
       ShouldFail.Inc05.{ amount, orderId }
   with "R1 inferred from" pointing at Constraint.e:5:28.

   Raised by: Constraints.scala:300-308, `ensureSuperset`, reached from
   `makeConcrete` (Constraints.scala:976).

   Shape: filtering on a column that is not in the relation. `filterEq` carries
   `Has r c`, so the failure arrives through a library function's constraint
   rather than through a syntactic row literal -- the everyday version of this
   error.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field orderId : Int
field amount : Double
field region : String

orders = relation [{ orderId = 1, amount = 25.0 }]

bad = filterEq region "NW" orders
