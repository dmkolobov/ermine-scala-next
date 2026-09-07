module Algebra.Shouldfail.Alg04 where

{- SHOULD FAIL -- deduplicating by a column that is also part of the grouping
   key.

   `groupBy` hands its group function only the NON-KEY part of the row:

       groupBy : (kv <- (k,v), kv2 <- (k,v2))
              => Row k -> (Mem v -> Mem v2) -> rel kv -> Mem kv2

   so a helper that ranks inside a group (`Helpers.dedupeBy`, whose signature
   carries `v <- (ord, o)`) needs the ranking column to be in `v`, which is
   exactly the columns NOT in `k`. Grouping by (customerId, eventVersion) and
   then asking for the row with the largest eventVersion is therefore not a
   subtle logic error, it is a partition with no solution -- `eventVersion`
   would have to be in `k` and in `v` at once.

   It is worth knowing that this is caught, because the SQL spelling of the
   same mistake (`GROUP BY a, b ... ORDER BY b LIMIT 1`) is legal and silently
   returns one row per (a,b).

   Expected diagnostic (measured 2026-09-06, defaults):
     core/examples/Algebra/shouldfail/alg04_dedupe_key_contains_order.e:45:7: Fields appear twice in row: Algebra.Shouldfail.Alg04.eventVersion

   The `RHS.merge` message (`Constraints.scala:329`), reached by SUBSTITUTION
   rather than directly: nothing in the input constraint set names
   `eventVersion` twice. `kv <- (k, v)` with `k` concrete gives `v`, and only
   when that `v` is substituted into `v <- (ord, o)` -- with `ord` also
   concrete and also `eventVersion` -- does one row end up holding it twice.
-}

import Prelude
import Syntax.Relation
import Algebra.Helpers

field customerId, eventVersion : Int
field emailAddress : String

feed : [customerId, eventVersion, emailAddress]
feed = relation [
  { customerId = 1, eventVersion = 1, emailAddress = "a@ex" },
  { customerId = 1, eventVersion = 2, emailAddress = "b@ex" }
]

bad = dedupeBy {customerId, eventVersion} {eventVersion} feed
