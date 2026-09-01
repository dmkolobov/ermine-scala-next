module Incomplete.Np01c where

{- NO BEST TYPE (1/5), companion B -- SHOULD FAIL.

   The mirror image of np01b: the "restate the stale figures" reading applied to
   this quarter's raw extract.  Under np01's `addBoth` typing this call is fine;
   under this one it is not.

   Between np01b and np01c: two maximal typings of one expression, each
   accepting a call the other rejects.  That is what it means, operationally,
   for the set of valid concrete typings to have no greatest element.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false (rejected in
   0.03s):

     np01c_recompute_signature_rejects_raw.e:35:1: error: failed to unify type
     (|sku, margin, unitCost, lineId, unitPrice, revenue, qty|) with type
     (|sku, unitCost, lineId, unitPrice, qty|)
-}

import Prelude
import Relation.Op as Op
import Syntax.Relation

field lineId, sku : Int
field qty, unitPrice, unitCost, revenue, margin : Double

orderLines : [lineId, sku, qty, unitPrice, unitCost]
orderLines = relation [
  { lineId = 1, sku = 400, qty = 12.0, unitPrice = 24.99, unitCost = 11.10 }
]

recomputeBoth : [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
             -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
recomputeBoth r =
  combine_Op (col_Op revenue -_Op col_Op unitCost) margin
    (combine_Op (col_Op unitPrice *_Op col_Op qty) revenue r)

bad = recomputeBoth orderLines
