module Incomplete.Np01b where

{- NO BEST TYPE (1/5), companion A -- SHOULD FAIL.

   The "add the money columns" reading of np01's restatement, applied to the
   table that already has them.  Under the OTHER maximal typing (`recomputeBoth`
   in np01) this exact call is fine and means "restate the stale figures".
   Under this one it does not typecheck.

   Neither signature is more general than the other; the author had to pick, and
   the pick is what rejects this call.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false (rejected in
   0.03s; line breaks are the pretty-printer's):

     np01b_add_signature_rejects_published.e:36:1: error: failed to unify type
     (|qty, sku, unitCost, lineId, unitPrice|) with type
     (|revenue, qty, margin, sku, unitCost, lineId, unitPrice|)
-}

import Prelude
import Relation.Op as Op
import Syntax.Relation

field lineId, sku : Int
field qty, unitPrice, unitCost, revenue, margin : Double

publishedLines : [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
publishedLines = relation [
  { lineId = 1, sku = 400, qty = 12.0, unitPrice = 22.50, unitCost = 11.10
  , revenue = 270.00, margin = 136.80 }
]

addBoth : [lineId, sku, qty, unitPrice, unitCost]
       -> [lineId, sku, qty, unitPrice, unitCost, revenue, margin]
addBoth r =
  combine_Op (col_Op revenue -_Op col_Op unitCost) margin
    (combine_Op (col_Op unitPrice *_Op col_Op qty) revenue r)

bad = addBoth publishedLines
