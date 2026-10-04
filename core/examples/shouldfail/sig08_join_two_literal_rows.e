module ShouldFail.Sig08 where

{- SHOULD FAIL -- the signature's context is too weak (error class 6).

   The first operand is (|a|), the result is (|a, b|), and the second operand
   may be anything.  The join only has column b if the second operand does.

   Two literal-left partitions are needed together to see it:

       (|a|)    <- (k, t1)
       (|a, b|) <- (k, t1, t2)

   Take the second operand's row empty: then t2 is empty and nothing holds b.
   The message should name the partition that mentions b, the column of its
   counterexample.
-}

import Prelude

field a : Int
field b : Int

joinLitHalf : Relation (|a|) -> Relation r -> Relation (|a, b|)
joinLitHalf x y = join x y
