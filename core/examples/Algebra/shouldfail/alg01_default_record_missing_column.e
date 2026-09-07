module Algebra.Shouldfail.Alg01 where

{- SHOULD FAIL -- an outer join whose DEFAULT RECORD does not cover the
   dimension's private columns.

   `Relation.leftJoinOr` (this directory's `enrich`) keeps every left row and
   fills the right side's private columns from a record:

       leftJoinOr : (RelationalComb rel, r1 <- (r,s), r2 <- (s,t), r3 <- (r,s,t))
                 => rel r1 -> rel r2 -> {..t} -> rel r3

   `t` occurs TWICE: once as the dimension's non-key row (`r2 <- (s,t)`) and
   once as the record's row. So the record must name EXACTLY the columns the
   dimension adds -- not a subset, not a superset. Here the dimension adds two
   (`customerName`, `customerTier`) and the record supplies one.

   This is the failure a reader of `Algebra/OrderLedger.e` will hit first, and
   the reason `enrich`'s doc comment says the record's row IS the dimension's
   non-key row.

   Expected diagnostic (measured 2026-09-06, defaults):
     core/examples/Algebra/shouldfail/alg01_default_record_missing_column.e:43:7: error: failed to unify type (|customerName,
       customerTier|) with type (|customerName|)

   A UNIFICATION failure, not a partition one: `t` is pinned by `r2 <- (s,t)`
   to the dimension's two private columns before the record's row is looked at,
   so the two rows are compared directly and neither is a variable by then.
-}

import Prelude
import Syntax.Relation
import Algebra.Helpers

field customerId : Int
field customerName, customerTier : String

orders : [customerId]
orders = relation [{ customerId = 1 }, { customerId = 2 }]

customerDim : [customerId, customerName, customerTier]
customerDim = relation [{ customerId = 1, customerName = "Aurora", customerTier = "gold" }]

bad = enrich orders customerDim { customerName = "(unknown)" }
