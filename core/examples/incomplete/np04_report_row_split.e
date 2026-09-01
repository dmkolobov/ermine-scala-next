module Incomplete.Np04 where

{- NO BEST TYPE (4/5) -- Wand's own example, as a report footer.

   SCENARIO.  The summary line at the bottom of a regional sales page is
   assembled from two records produced by different parts of the pipeline: a
   "caption" part built by the page layout code and a "figures" part built by
   the aggregation.  The assembly is a record concatenation:

       summaryLine caption figures = appendR caption figures

   WHAT A COMPETENT USER EXPECTS.  One helper with one declared schema, used
   wherever a summary line is built.

   WHAT ACTUALLY HAPPENS.  The cut between the two operands is not recoverable
   from the result.  For the four-column line { asOfDate, regionName,
   orderCount, revenue } there are sixteen splits, and every one of them is a
   valid typing of the SAME expression.  Three are written out below and all
   three are accepted:

     captionIsDateAndRegion : {asOfDate, regionName} -> {orderCount, revenue}
     captionIsDateOnly      : {asOfDate} -> {regionName, orderCount, revenue}
     captionIsAllButRevenue : {asOfDate, regionName, orderCount} -> {revenue}

   all with the same result {asOfDate, regionName, orderCount, revenue}.  They
   are pairwise incomparable: each differs from the others in argument position.
   Sixteen maximal typings, no greatest one.  This is a FINITE COMPLETE SET,
   which is exactly what Wand (1989) proved is the best that exists for record
   concatenation -- no principal type, only finite complete sets.

   WHICH INCOMPLETENESS.  The textbook case, in the shape it actually turns up
   in: `Record.appendR : c <- (a,b) => {..a} -> {..b} -> {..c}`.  Fixing `c`
   leaves 2^|c| solutions for (a,b) and nothing to prefer one by.

   WHAT ERMINE DOES ABOUT IT.  Here the escape is cheap and a competent user
   would take it: the inferred type is `c <- (b, a) => Record a -> Record b ->
   Record c`, one short constraint, and writing it by hand was checked and
   accepts all three instantiations.  So for plain concatenation Ermine really
   does dodge Wand.  np04b is what happens to the other fifteen splits when
   somebody writes the concrete one instead -- and np05 is the case where the
   same escape costs 527 seconds and nobody takes it.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false: this file loads
   clean, "Importing module 'Incomplete.Np04' (0.05-0.14 seconds over several runs)".
-}

import Prelude
import Record using appendR

field asOfDate, regionName : String
field orderCount : Int
field revenue : Double

-- ------------------------------------------------------------------ the query
-- One expression.  Three of its sixteen maximal typings.  All accepted.

captionIsDateAndRegion : {asOfDate, regionName} -> {orderCount, revenue}
                      -> {asOfDate, regionName, orderCount, revenue}
captionIsDateAndRegion caption figures = appendR caption figures

captionIsDateOnly : {asOfDate} -> {regionName, orderCount, revenue}
                 -> {asOfDate, regionName, orderCount, revenue}
captionIsDateOnly caption figures = appendR caption figures

captionIsAllButRevenue : {asOfDate, regionName, orderCount} -> {revenue}
                      -> {asOfDate, regionName, orderCount, revenue}
captionIsAllButRevenue caption figures = appendR caption figures

-- ------------------------------------------- what the compiler infers unaided
summaryLine caption figures = appendR caption figures

pacificNorthwest =
  summaryLine { asOfDate = "2026-08-31", regionName = "Pacific Northwest" }
              { orderCount = 41, revenue = 2998.80 }

california =
  summaryLine { asOfDate = "2026-08-31" }
              { regionName = "California", orderCount = 63, revenue = 6975.00 }

{- OBSERVED, `:browse summaryLine`:

summaryLine : forall (a: rho) (b: rho) (c: rho).
  c <- (b, a) => Record a -> Record b -> Record c
-}
