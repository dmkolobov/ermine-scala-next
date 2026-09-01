module Incomplete.Np03b where

{- NO BEST TYPE (3/5), companion -- SHOULD FAIL.

   np03 with the schema of the empty corrections feed written down as a header,
   the way a maintainer documenting the pipeline would write it.  The
   credit-control report still compiles; the returns desk's does not.

   The symmetric annotation -- `corrections : [orderId, refund]` -- rejects the
   credit-control report instead.  Neither header is more general than the
   other, and the empty table inhabits both, so the choice is arbitrary and
   load-bearing.

   (The one annotation that DOES keep both is `corrections : forall r.
   Relation r`, which was checked and accepted.  It is also a declaration that
   tells a reader nothing about the feed's schema, which was the point of
   writing it down.)

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false (rejected in
   0.04s):

     Row types failed to unify:
     R1 =
       Incomplete.Np03b.{ orderId, refund }
     R2 =
       Incomplete.Np03b.{ adjustment, amount, orderId, regionId }
     modules/Constraint.e:5:28: R1 inferred from
     np03b_pinned_placeholder_rejects_refunds.e:47:16: R2
-}

import Prelude
import Syntax.Relation

field orderId, regionId : Int
field amount, adjustment, refund : Double

orders : [orderId, regionId, amount]
orders = relation [{ orderId = 5001, regionId = 110, amount = 2998.80 }]

corrections : [orderId, adjustment]
corrections = relation []

adjusted = orders ** corrections

netByAdjustment = adjusted # { orderId, adjustment }

bad = adjusted # { orderId, refund }
