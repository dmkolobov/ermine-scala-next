module ShouldFail.Inc08 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS (subsumption failure).

   Expected message:
     Row types failed to unify:
     R1 =
       ShouldFail.Inc08.regionName
     R2 =
       ShouldFail.Inc08.{
         orderId,
         productId,
         productName,
         units }
   with "R1 inferred from" pointing at Constraint.e:5:28.

   Raised by: Constraints.scala:300-308, `ensureSuperset`, reached from
   `makeConcrete` (Constraints.scala:976).

   Shape: the most solver-dependent case in this family. R2 is not written
   anywhere -- the solver has to discharge join's three partition constraints
   (d <- (a,b), e <- (b,c), f <- (a,b,c)) into the concrete four-column row
   before it can see that `regionName` is missing. Reporting by a dimension
   column that was never joined in is the everyday version of this mistake.

   *** MODE-SENSITIVE -- THIS IS THE CASE THE CORPUS EXISTS TO CATCH ***
   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected (message above)
     genRules=cut    -> rejected (same message)
     genRules=nongen -> ACCEPTED. "Importing module ... (0.04 seconds)".
   With no rule minting, splitConcrete can never name the two-variable
   remainder of join's f <- (a,b,c), the join result is never driven to a
   concrete row, and the missing column is never noticed. The program
   type-checks. This is a LOST REFUTATION, not a preserved one.
-}

import Prelude
import Syntax.Relation

field orderId, productId : Int
field units : Double
field productName, regionName : String

orders     = relation [{ orderId = 1, productId = 2, units = 10.0 }]
productDim = relation [{ productId = 2, productName = "Desk Lamp" }]

sales    = orders ** productDim
byRegion = project {regionName} sales
