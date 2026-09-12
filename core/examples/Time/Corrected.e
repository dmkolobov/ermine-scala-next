module Time.Corrected where

{- THE CORRECTED DATE-DIFFERENCE SIGNATURES, CALLED -- the positive control for
   stage S3b in this group.

   The five `Time.Helpers` date differences (`dayCount`, `monthsBetween`,
   `monthsSince`, `daysSince`, `daysUntil`) declared `forall r r1 out` with the
   result row `out` in NO constraint, which is the hole the stdlib closed in
   `Relation.Op.dateDiff` at stage F3 and `Time/Helpers.e`'s own comment left open
   on purpose.  2026-09-11 closed it: the obligations the bodies incur are exactly
   `RUnion2 out r r1` -- "the result row is the union of the operand rows" -- so
   the two-column forms carry that, and in the forms whose other operand is a
   CONSTANT the union collapses (the constant's row is `(||)`), so there is nothing
   for `out` to be but `r` and the signature does not quantify over it at all.

   WHICH CORRECTION EACH BINDING EXERCISES
     `withSpan`    `dayCount`, the two-column form: `RUnion2 out r r1` with
                   r = (|startDay|), r1 = (|endDay|), and `out` the row
                   `combine` is instantiating -- both operands really are columns
                   of the relation, which is what the old signature failed to
                   require.  `monthsBetween` is the same shape.
     `withTenure`  `daysUntil`, the constant form, whose result row IS the date
                   column's row (`Op r Int` at r = (|startDay|)); `combine` asks
                   only that the op's row be part of the relation's, so the
                   collapsed form is what every real caller wants.  `monthsSince`
                   and `daysSince` are the same shape with the constant on the
                   other side.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/Corrected.e
     >> withSpan
-}

import Prelude
import Relation.Op as Op
import Syntax.Relation
import Time.Helpers

field contractId : Int
field startDay, endDay : Date
field spanDays, tenureDays : Int

contracts : [ contractId, startDay, endDay ]
contracts = relation
  [ { contractId = 1, startDay = @2025/1/1,  endDay = @2025/3/31 }
  , { contractId = 2, startDay = @2025/2/15, endDay = @2025/6/30 }
  , { contractId = 3, startDay = @2024/11/1, endDay = @2025/1/31 } ]

-- `dayCount startDay endDay : Op out Int` with `RUnion2 out (|startDay|)
-- (|endDay|)`, and `combine` asks for a row of the relation, so `out` is
-- (|startDay, endDay|) -- both columns are there.
withSpan : [ contractId, startDay, endDay, spanDays ]
withSpan = combine_Op (dayCount startDay endDay) spanDays contracts

-- `daysUntil startDay @2025/12/31 : Op (|startDay|) Int` -- the collapsed form.
withTenure : [ contractId, startDay, endDay, tenureDays ]
withTenure = combine_Op (daysUntil startDay @2025/12/31) tenureDays contracts
