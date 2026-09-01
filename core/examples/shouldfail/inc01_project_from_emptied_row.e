module ShouldFail.Inc01 where

{- ERROR CLASS 3 -- INCOMPATIBLE INSTANTIATIONS.

   Expected message:
     Incompatible instantiations of 'N'
   (N is a raw TypeVar id and is NOT stable across runs -- it depends on how
   many modules the Supply has already served. Match on the prefix.)

   Raised by: Constraints.scala:933, the `case _` of `makeEmpty`'s `aux`.

   Shape: `except` drops every column of `orders`, so the remainder row
   variable is forced empty; `project {amount}` then demands that same variable
   contain `amount`. A variable that is both empty and non-empty is the
   incompatible-instantiation contradiction.  A plausible refactoring slip: the
   `except` list was widened and the downstream projection was not revisited.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     genRules=all    -> rejected
     genRules=cut    -> rejected
     genRules=nongen -> rejected
-}

import Prelude

field orderId : Int
field amount : Double

orders = relation [{ orderId = 1, amount = 25.0 }]

bad = project {amount} (except {orderId, amount} orders)
