module ShouldFail.Mis04 where

{- ERROR CLASS 5 -- ORDINARY ROW MISMATCH (record operation).

   Expected message:
     error: failed to unify type (|orderId|) with type (|amount,
       orderId|)
   (field order inside (|...|) is NOT stable across runs -- see the note below.)

   NOTE ON MECHANISM: `appendR : c <- (a,b) => {..a} -> {..b} -> {..c}` gives
   the solver c <- ({orderId}, {amount}); the solver concretises c, and the
   declared `{ orderId }` then loses to it in the ordinary unifier,
   Subst.scala:270, rather than in a `die` in Constraints.scala.

   Shape: a record merge whose declared type was not updated when a field was
   added to the right-hand record.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field orderId : Int
field amount : Double

merged : { orderId }
merged = { orderId = 1 } ++_Record { amount = 25.0 }
