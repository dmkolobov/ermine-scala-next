module Wide.Shouldfail.Pivot01 where

{- SHOULD FAIL -- a pivot whose KEY column is also its VALUE column.

   `Relation.Pivot.pivot` relates the narrow row to the wide one with
       r <- (k, v, i)
   -- the input row is the key columns, the value columns and the identity
   columns, DISJOINTLY.  Asking for a pivot keyed on `period` whose value is
   also `period` instantiates that as `r <- (period, period, i)`, and a
   partition constraint whose right-hand side repeats a field has no solution.

   This is the negative example the corpus needs for the pivot: the constraint
   that makes a pivot meaningful is a DISJOINTNESS, and it is checked.

   Expected message: see Wide/shouldfail/RESULTS.md.

   Raised by: Constraints.scala, `RHS.build` / `RHS.merge` -- the same
   duplicate-field detector as `core/examples/shouldfail/dup01`.
-}

import Prelude
import Syntax.Relation
import Wide.Helpers

field period : String
field amount : Double
field customerName : String
field q1 : String

sales : [ customerName, period, amount ]
sales = relation [{ customerName = "Northwind", period = "Q1", amount = 100.0 }]

-- `period` in both roles.
badPlan = pivotColumn q1 "Q1" period period (startPivot period period)

bad = pivotBy badPlan sales
