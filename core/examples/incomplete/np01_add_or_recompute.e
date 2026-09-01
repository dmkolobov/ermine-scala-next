module Incomplete.Np01 where

{- NO BEST TYPE (1/5) -- "does this query ADD a column or OVERWRITE one?"

   SCENARIO.  An ERP extract of order lines.  Finance wants the two money
   columns restated from the raw quantities:

       revenue = unitPrice * qty
       margin  = revenue - unitCost

   which is the two-line pipeline below.  Two tables get fed to it in the same
   reporting run:

       orderLines      -- this quarter's extract; no money columns yet
       publishedLines  -- last quarter's published table, which ALREADY carries
                          revenue and margin, now stale after a price revision

   WHAT A COMPETENT USER EXPECTS.  One helper with one declared schema, used on
   both tables -- the way every report in core/examples/ai declares its schemas:
   as concrete headers, `sales : [ orderId, productId, ... ]`.

   WHAT ACTUALLY HAPPENS.  There is no concrete header that serves both, and not
   because one is missing: because there are FOUR, and they are pairwise
   incomparable.  `combine`'s constraint is `RUnion2 t r c` -- an OVERLAPPING
   union, not a disjoint one -- so the input row may or may not already contain
   the column being written.  All four of these are valid typings of the SAME
   expression and the compiler accepts all four:

       addBoth              [.. ]                  -> [.., revenue, margin]
       recomputeBoth        [.., revenue, margin]  -> [.., revenue, margin]
       recomputeRevenueOnly [.., revenue]          -> [.., revenue, margin]
       recomputeMarginOnly  [.., margin]           -> [.., revenue, margin]

   As function types no two are related by instantiation: they differ in the
   ARGUMENT position, where the ordering runs the wrong way.  Each is maximal.
   There is no best one, and picking one rejects calls the others accept --
   np01b and np01c are the two rejections, each produced by the signature the
   other file does not use.

   WHICH INCOMPLETENESS.  Wand (1989): record concatenation has no principal
   types, only finite complete sets of typings.  This is that theorem in
   ordinary reporting code.

   WHAT ERMINE DOES ABOUT IT, HONESTLY.  The right thing.  Left alone it refuses
   to choose and keeps the whole complete set alive inside an existential --
   `inferredRestate` below, whose browsed type is quoted at the bottom.  And the
   constrained type is WRITABLE by hand; this signature was checked and accepts
   all four instantiations above:

       restate : forall r u t rel.
                 (exists o. RUnion2 u r (|revenue|), RUnion2 t u (|margin|),
                  r <- ((|qty, unitPrice, unitCost|), o), RelationalComb rel)
              => rel r -> rel t

   So Ermine escapes Wand's theorem, by never producing a constraint-free type
   unless asked.  The escape has a price, and np05 measures it on an expression
   one `if` more complicated than this one: there the constrained type takes
   280s to infer and 527s to use once, against 1.18s for the concrete headers.
   Where that happens the author has no real choice but to write one of the
   incomparable concrete headers, and the other reports break.

   The narrower and always-true statement, which is what this file demonstrates:
   the set of CONCRETE-HEADER typings -- the only kind a schema declaration can
   express, and the only kind any shipped example in this repo actually writes --
   has several maximal elements and no greatest one.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false: this file loads
   clean, "Importing module 'Incomplete.Np01' (0.60 seconds)".
-}

import Prelude
import Relation.Op as Op
import Syntax.Relation

field lineId, sku : Int
field qty, unitPrice, unitCost, revenue, margin : Double

-- This quarter's extract: quantities only.
orderLines : [lineId, sku, qty, unitPrice, unitCost]
orderLines = relation [
  { lineId = 1, sku = 400, qty = 12.0, unitPrice = 24.99, unitCost = 11.10 },
  { lineId = 2, sku = 401, qty =  3.0, unitPrice = 149.00, unitCost = 92.40 }
]

-- Last quarter's published table: the money columns are there, and stale.
publishedLines : [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
publishedLines = relation [
  { lineId = 1, sku = 400, qty = 12.0, unitPrice = 22.50, unitCost = 11.10
  , revenue = 270.00, margin = 136.80 }
]

-- ------------------------------------------------------------------ the query
-- One expression.  Four maximal typings.  All four are accepted.

addBoth : [lineId, sku, qty, unitPrice, unitCost]
       -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
addBoth r =
  combine_Op (col_Op revenue -_Op col_Op unitCost) margin
    (combine_Op (col_Op unitPrice *_Op col_Op qty) revenue r)

recomputeBoth : [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
             -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
recomputeBoth r =
  combine_Op (col_Op revenue -_Op col_Op unitCost) margin
    (combine_Op (col_Op unitPrice *_Op col_Op qty) revenue r)

recomputeRevenueOnly : [lineId, sku, qty, unitPrice, unitCost, revenue]
                    -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
recomputeRevenueOnly r =
  combine_Op (col_Op revenue -_Op col_Op unitCost) margin
    (combine_Op (col_Op unitPrice *_Op col_Op qty) revenue r)

recomputeMarginOnly : [lineId, sku, qty, unitPrice, unitCost, margin]
                   -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
recomputeMarginOnly r =
  combine_Op (col_Op revenue -_Op col_Op unitCost) margin
    (combine_Op (col_Op unitPrice *_Op col_Op qty) revenue r)

-- ------------------------------------------- what the compiler infers unaided
inferredRestate r =
  combine_Op (col_Op revenue -_Op col_Op unitCost) margin
    (combine_Op (col_Op unitPrice *_Op col_Op qty) revenue r)

-- and it really does cover all four readings: each of these is `inferredRestate`
-- eta-reduced into the annotation above it, and each is accepted.
viaInferredAdd : [lineId, sku, qty, unitPrice, unitCost]
              -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
viaInferredAdd = inferredRestate

viaInferredRecompute : [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
                    -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
viaInferredRecompute = inferredRestate

thisQuarter = inferredRestate orderLines
restated    = inferredRestate publishedLines

{- OBSERVED, `:browse inferredRestate` (continuation lines joined; the naming
   and ordering of the existential variables varies from run to run):

inferredRestate : forall (rel: rho -> *) (r: rho) (t: rho).
  (exists (t1: rho) (rs: rho) (a: rho) (b: rho) (rs1: rho) (so: rho) (so1: rho).
   r <- ((|unitCost, qty, unitPrice|), rs1, b),
   RelationalComb rel,
   (|margin|) <- (rs, so),
   r <- ((|unitCost, qty, unitPrice|), b, rs1),
   t1 <- ((|unitCost, qty, unitPrice|), rs1, so1, b),
   t <- ((|qty, unitPrice, unitCost, revenue|), rs, so, a),
   t1 <- ((|qty, unitPrice, unitCost, revenue|), rs, a),
   t1 <- ((|qty, unitPrice, unitCost, revenue|), a, rs),
   (|revenue|) <- (rs1, so1)) =>
  rel r -> rel t

   Read `(|margin|) <- (rs, so)` as the choice itself: the single label `margin`
   is split into the part already present in the input (rs) and the part newly
   added (so), and the solver leaves BOTH halves as free row variables rather
   than picking.  That existential IS the complete set of typings, and a written
   concrete header collapses it to one element.

   (Two of those nine partitions are the same constraint with a permuted
   right-hand side -- `r <- (..., rs1, b)` and `r <- (..., b, rs1)`, and
   likewise the two `t1 <- ((|qty, unitPrice, unitCost, revenue|), ...)`.  That
   is the known non-canonical-residual defect, a DIFFERENT failure mode from
   this one; it is visible here only because we printed the residual.)
-}
