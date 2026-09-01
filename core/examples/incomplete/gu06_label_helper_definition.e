module Incomplete.Gu06 where

{- INFERENCE GIVES UP WHERE CHECKING SUCCEEDS -- the library author's version,
   1 of 3: the helper that defines fine.

   THE SCENARIO.  Every report in core/examples/ai/ needs the same thing: a
   display column whose value depends on a flag.  SalesByRegion labels a line
   with the product name for direct sales and "product via channel" for partner
   sales; SupplyChainInventory picks a unit word; HeadcountPlan picks between a
   person's name and a requisition number.  The obvious move for whoever
   maintains the shared library is to factor it out:

       withLabel predicate whenTrue whenFalse column relation

   one call instead of a nested `combine_Op (if_Op ...)` in ten reports.

   WHAT A COMPETENT USER EXPECTS.  A helper that type-checks is a helper you can
   call.

   WHAT ACTUALLY HAPPENS -- IN THIS FILE, NOTHING BAD.  The definition checks,
   and quickly.  That is the trap: the author writes this, sees it compile,
   commits it, and only the first CALLER finds out.  Gu07 is that caller.

   THE INCOMPLETENESS.  The signature below bundles `if`'s `RUnion3` (a
   four-constraint inclusion/exclusion lattice over three row variables,
   Constraint.e:7) with `combine`'s `RUnion2` (three constraints,
   Constraint.e:6) and the remainder `inrow <- (v, o)`.  Checking the body
   against that bundle is cheap because the body is one application of each.
   Instantiating the bundle at a call site is not, because the caller must solve
   the whole overlapping system at once -- see Gu07.  core/examples/ai/
   Common.e's `withColumn` exists precisely to avoid this shape, and its header
   comment records that the first draft of that file hung the compiler.
-}

import Prelude
import Relation
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation

-- Add a column whose value is chosen by a predicate over the same row.
withLabel : forall a c v pr tr er inrow outrow rel opc opa.
            ( exists o. RUnion3 v pr tr er, RUnion2 outrow inrow c,
              inrow <- (v, o), AsOp opc, AsOp opa, RelationalComb rel )
         => Predicate pr -> opc tr a -> opa er a -> Field c a -> rel inrow -> rel outrow
withLabel p whenTrue whenFalse fld = combine_Op (if_Op p whenTrue whenFalse) fld
