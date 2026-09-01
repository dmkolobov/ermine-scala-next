module Incomplete.Np02 where

{- NO BEST TYPE (2/5) -- "which table does the measure come from?"

   SCENARIO.  The universal reporting idiom: join a fact table to a dimension
   and project the label and the number.

       byRegion facts dims = (facts ** dims) # { regionName, amount }

   Two reports in the same pack call it:

     * Actuals.  `amount` is the order amount and lives on the FACT side; the
       region dimension only supplies `regionName`.
     * Budget.   `amount` is the regional budget for the period and lives on the
       DIMENSION side; the fact table is just the list of regions that traded.

   WHAT A COMPETENT USER EXPECTS.  One helper with one declared schema.  It is
   the same join and the same projection; only the provenance of a column
   differs, and provenance is exactly what a natural join is supposed to
   abstract over.

   WHAT ACTUALLY HAPPENS.  Both readings typecheck and they are incomparable:

     factSideMeasure : [orderId, regionId, amount] -> [regionId, regionName]
                                                   -> [regionName, amount]
     dimSideMeasure  : [orderId, regionId] -> [regionId, regionName, amount]
                                           -> [regionName, amount]

   Neither is an instance of the other -- they disagree in BOTH argument
   positions, in opposite directions -- so a signature naming one rejects the
   other report.  np02b is that rejection.

   WHICH INCOMPLETENESS.  Wand's non-principality in its join guise.  `join`'s
   constraint is `d <- (a,b), e <- (b,c), f <- (a,b,c)`: the compiler knows the
   result is the union and knows nothing about which operand a given column came
   out of.  That is not a solver defect -- it is the correct answer, and the
   reason the answer is not a concrete type is that there is no single concrete
   type to give.

   WHAT ERMINE DOES ABOUT IT.  Left to itself it declines to choose and keeps
   the set in an existential (browsed type quoted at the bottom).  The
   constrained form is also writable by hand -- this was checked and accepts
   both instantiations:

     byRegion : forall rel b c d.
        (exists e f g o. b <- (f, e), c <- (g, f), d <- (g, f, e),
         d <- ((|regionName, amount|), o), RelationalComb rel)
      => rel b -> rel c -> rel (|regionName, amount|)

   Note what that signature costs the reader: five row variables and four
   partitions to say "join and project two columns", and it still does not say
   which table the money is in -- because saying so would be false.  Every
   report in core/examples/ai writes concrete headers instead, and every one of
   them therefore picks.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false: this file loads
   clean, "Importing module 'Incomplete.Np02' (0.13-0.35 seconds over several runs)".
-}

import Prelude
import Syntax.Relation

field orderId, regionId : Int
field amount : Double
field regionName : String

-- Actuals feed: the money is on the fact side.
orders : [orderId, regionId, amount]
orders = relation [
  { orderId = 5001, regionId = 110, amount = 2998.80 },
  { orderId = 5002, regionId = 120, amount = 6975.00 }
]

regionDim : [regionId, regionName]
regionDim = relation [
  { regionId = 110, regionName = "Pacific Northwest" },
  { regionId = 120, regionName = "California" }
]

-- Budget feed: the money is on the dimension side.
tradedRegions : [orderId, regionId]
tradedRegions = relation [
  { orderId = 5001, regionId = 110 },
  { orderId = 5002, regionId = 120 }
]

regionBudget : [regionId, regionName, amount]
regionBudget = relation [
  { regionId = 110, regionName = "Pacific Northwest", amount = 3200.00 },
  { regionId = 120, regionName = "California",        amount = 6500.00 }
]

-- ------------------------------------------------------------------ the query
-- One expression.  Two maximal typings.  Both accepted.

factSideMeasure : [orderId, regionId, amount] -> [regionId, regionName]
               -> [regionName, amount]
factSideMeasure facts dims = (facts ** dims) # { regionName, amount }

dimSideMeasure : [orderId, regionId] -> [regionId, regionName, amount]
              -> [regionName, amount]
dimSideMeasure facts dims = (facts ** dims) # { regionName, amount }

-- ------------------------------------------- what the compiler infers unaided
byRegion facts dims = (facts ** dims) # { regionName, amount }

actuals = byRegion orders regionDim
budget  = byRegion tradedRegions regionBudget

-- and both maximal typings really are instances of the inferred one:
viaInferredFactSide : [orderId, regionId, amount] -> [regionId, regionName]
                   -> [regionName, amount]
viaInferredFactSide = byRegion

viaInferredDimSide : [orderId, regionId] -> [regionId, regionName, amount]
                  -> [regionName, amount]
viaInferredDimSide = byRegion

{- OBSERVED, `:browse byRegion` (continuation lines joined; the order in which
   the partitions print, and the naming of the existential variables, varies
   between runs):

byRegion : forall (a: rho -> *) (b: rho) (c: rho).
  (exists (d: rho) (c1: rho) (e: rho) (f: rho) (g: rho).
   c <- (g, f),
   d <- (g, f, e),
   d <- ((|amount, regionName|), c1),
   RelationalComb a,
   b <- (f, e)) =>
  a b -> a c -> a (|amount, regionName|)

   `d` is the join result, `b` and `c` the two operands, `e`/`f`/`g` the
   left-only / shared / right-only parts.  Nothing in the constraint set says
   where `amount` sits, and nothing can: both placements satisfy it.
-}
