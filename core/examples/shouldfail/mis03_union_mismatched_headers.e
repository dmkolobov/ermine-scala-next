module ShouldFail.Mis03 where

{- ERROR CLASS 5 -- ORDINARY ROW MISMATCH.

   Expected message:
     error: failed to unify type (|amount,
       customerId,
       orderId|) with type (|region, orderId|)

   NOTE ON MECHANISM: `union : rel r -> rel r -> rel r` ties both operands to
   one row variable, which is then instantiated to two different concrete rows.
   That refutation is the ordinary unifier's (Subst.scala:270), not a `die` in
   Constraints.scala -- see mis02's note.

   Shape: unioning two relations with different headers, the SQL "UNION of two
   SELECTs with different column lists" mistake.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field orderId, customerId : Int
field amount : Double
field region : String

orders  = relation [{ orderId = 1, customerId = 7, amount = 25.0 }]
regions = relation [{ orderId = 1, region = "NW" }]

bad = union orders regions
