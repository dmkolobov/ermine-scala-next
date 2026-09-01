module ShouldFail.Mis01 where

{- ERROR CLASS 5 -- ORDINARY ROW MISMATCH (join operands cannot be reconciled).

   Expected message:
     Row types failed to unify:
     R1 =
       ShouldFail.Mis01.{ city, customerId }
     R2 =
       ShouldFail.Mis01.{ amount, customerId, orderId }
   with "R1 inferred from" pointing at Syntax/Relation.e:53:12 (`**'`).

   Raised by: Constraints.scala:300-308, `ensureSuperset`, reached from
   `makeConcrete` (Constraints.scala:976).

   Shape: `**'` is the join that asserts the right operand's row is a sub-row
   of the left operand's result: (**') : a <- (r, o) => rel a -> rel r -> rel a.
   Here `customers` overlaps `orders` on customerId but also brings `city`,
   which the left operand does not have, so the two operands' rows cannot be
   reconciled. Writing `**'` where `**` was meant is the common slip.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude
import Syntax.Relation

field orderId, customerId : Int
field amount : Double
field city : String

orders    = relation [{ orderId = 1, customerId = 7, amount = 25.0 }]
customers = relation [{ customerId = 7, city = "Seattle" }]

bad = orders **' customers
