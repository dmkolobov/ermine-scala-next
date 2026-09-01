module ShouldFail.Mis02 where

{- ERROR CLASS 5 -- ORDINARY ROW MISMATCH (join result cannot be reconciled
   with its declared row).

   Expected message:
     error: failed to unify type (|orderId,
       productId,
       productName|) with type (|units, productId, orderId, productName|)

   NOTE ON MECHANISM: the solver is what turns join's three partition
   constraints (d <- (a,b), e <- (b,c), f <- (a,b,c)) into the concrete row
   { units, productId, orderId, productName }; the final refutation is then the
   ordinary unifier's, Subst.scala:270, not a `die` in Constraints.scala. It is
   still a row refutation and still depends on the solver reaching a concrete
   row, so it belongs in the corpus.

   Shape: a star join whose declared signature forgot a fact column (`units`).

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
field productName : String

orders     = relation [{ orderId = 1, productId = 2, units = 10.0 }]
productDim = relation [{ productId = 2, productName = "Desk Lamp" }]

sales : [ orderId, productId, productName ]
sales = orders ** productDim
