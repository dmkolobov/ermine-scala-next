module Incomplete.Np03 where

{- NO BEST TYPE (3/5) -- the placeholder table nobody can give a schema to.

   SCENARIO.  A month-end pack joins the order book to a table of manual
   corrections.  This month there were none, so the extract is empty:

       corrections = relation []

   Two reports draw on the joined table.  Credit control wants the goodwill
   `adjustment`; the returns desk wants the `refund`.  Both are columns the
   corrections feed carries when it is non-empty.

   WHAT A COMPETENT USER EXPECTS.  To write down the schema of `corrections` --
   it is a real table with a real header, temporarily empty -- and have both
   reports keep working.  `relationWithHeader` exists in Relation.e precisely to
   let you pin the header of an empty relation, so the library plainly expects
   you to want to.

   WHAT ACTUALLY HAPPENS.  Unannotated, everything compiles, and the joined
   table is inferred at a type that names no header at all:

     adjusted : forall (a: rho).
       (exists (b: rho) (c: rho) (d: rho) (r: rho).
        (|orderId, regionId, amount|) <- (c, b), r <- (d, c), a <- (d, c, b))
       => Relation a

   -- "some row containing orderId, regionId and amount, plus whatever the
   corrections feed turns out to have".  The two reports then instantiate `a`
   differently, to two incomparable headers, out of the same definition:

     netByAdjustment : Relation (|adjustment, orderId|)
     netByRefund     : Relation (|refund, orderId|)

   Write a header down and one of them dies.  np03b annotates `corrections` with
   the credit-control header and the returns report stops compiling; the
   symmetric annotation kills the other.  No header keeps both, because the two
   are incomparable and an empty relation genuinely inhabits both.  The only
   annotation that keeps both is `corrections : forall r. Relation r` -- checked
   and accepted -- which is a schema declaration that declares no schema.

   WHICH INCOMPLETENESS.  Non-principality reached from the value side rather
   than the function side: `relation []` is a term whose valid typings have no
   greatest element among the ones a person would write down.  The compiler's
   honest answer -- refuse to choose, carry a constraint -- is precisely the
   answer a schema declaration cannot express.

   This is not a soundness hole; an empty relation really does inhabit every
   header.  It is a documentation hole: the type that is true is not the type
   that is useful.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false: this file loads
   clean, "Importing module 'Incomplete.Np03' (0.07-0.16 seconds over several runs)".
-}

import Prelude
import Syntax.Relation

field orderId, regionId : Int
field amount, adjustment, refund : Double

orders : [orderId, regionId, amount]
orders = relation [
  { orderId = 5001, regionId = 110, amount = 2998.80 },
  { orderId = 5002, regionId = 120, amount = 6975.00 }
]

-- No manual corrections were filed this month.
corrections = relation []

adjusted = orders ** corrections

-- Credit control.
netByAdjustment = adjusted # { orderId, adjustment }

-- Returns desk.  Same definition of `adjusted`, a different and incomparable
-- header.
netByRefund = adjusted # { orderId, refund }
