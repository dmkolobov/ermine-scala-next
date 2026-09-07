module Algebra.Shouldfail.Alg02 where

{- SHOULD FAIL -- a set difference between two relations that do not have the
   same header.

   `difference : RelationalComb rel => rel r -> rel r -> rel r` uses ONE row
   variable three times: the two operands and the result all have the same
   header, which is what makes set difference well defined. Ermine has no
   implicit projection, so subtracting a three-column relation from a
   four-column one is a type error rather than a silent nonsense.

   The lesson `Algebra/InventorySnapshots.e` is built on: an anti-join is NOT
   `difference` -- `difference` compares WHOLE ROWS -- and getting from one to
   the other needs a projection to the key and a join back, which is what
   `antiJoin` in `Helpers.e` does.

   Expected diagnostic (measured 2026-09-06, defaults):
     core/examples/Algebra/shouldfail/alg02_difference_mismatched_headers.e:41:7: error: failed to unify type (|sku,
       binCode,
       onHandQty,
       allocatedQty|) with type (|sku, binCode, onHandQty|)

   Again a plain unification failure -- `difference`'s single row variable is
   bound by the first operand and then met by the second -- which is why this
   is the cheapest of the six to diagnose and the easiest to read.
-}

import Prelude
import Syntax.Relation
import Algebra.Helpers

field sku, binCode : String
field onHandQty, allocatedQty : Double

monday : [sku, binCode, onHandQty, allocatedQty]
monday = relation [{ sku = "A", binCode = "b1", onHandQty = 1.0, allocatedQty = 0.0 }]

friday : [sku, binCode, onHandQty]
friday = relation [{ sku = "A", binCode = "b1", onHandQty = 1.0 }]

bad = exceptRows monday friday
