module Time.Shouldfail.Null01 where

{- SHOULD FAIL -- a NULLABLE column where a non-nullable one is expected.

   `Time.Helpers.fxConvert` multiplies a money column by a rate column into a
   third:

       fxConvert : (exists o. r <- (amt, rate, o), t <- (r, out)
                   , PrimitiveNum n, RelationalComb rel)
                => Field amt n -> Field rate n -> Field out n -> rel r -> rel t

   The three fields share ONE numeric type variable `n`, deliberately: a
   conversion whose input is a `Double` and whose output is a `Nullable Double`
   would silently change the type of the P&L. So handing it a rate table whose
   rate is nullable -- which is exactly what a left-joined rate table gives you,
   and what `Time.InterestAccrual` handles by `orElseNum` -- does not check.

   `Nullable Double` IS a `PrimitiveNum` (that is the whole point of
   `Primitive.e`, whose header says it is "slightly more general than those in
   Num, in that they support the Nullable numbers"), so the class constraint is
   satisfied and the failure is a plain unification failure on the value type.

   THE FIX is one of `Relation.Op.annul` (lift the amount to `Nullable`, and the
   result with it) or `Time.Helpers.orElseNum` (give the rate a default and keep
   everything non-null). `Time.InterestAccrual` takes the second road for rates
   and the first for a weighted mean.

   EXPECTED DIAGNOSTIC (verbatim):

     core/examples/Time/shouldfail/null01_nullable_rate_into_double.e:50:7: error: failed to unify type Double with type (Nullable Double)

   (the compiler line-wraps the type at the terminal width, so it prints as
   `... with type (Nullable` / `Double)` on two lines.)
-}

import Prelude
import Layout
import Relation.Op as Op
import Syntax.Relation
import Time.Helpers

field amountLocal, amountUsd : Double
field rateToUsd : Nullable Double
field entryId : Int

ledger : [ entryId, amountLocal, rateToUsd ]
ledger = relation [ { entryId = 1, amountLocal = 128400.0,
                      rateToUsd = Some 1.5942 } ]

bad = fxConvert amountLocal rateToUsd amountUsd ledger
