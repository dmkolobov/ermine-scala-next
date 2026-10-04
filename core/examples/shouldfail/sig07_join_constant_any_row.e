module ShouldFail.Sig07 where

{- SHOULD FAIL -- the signature's context is too weak (error class 6).

   Joining with a constant relation over (|a|) keeps the input's row only if
   the input already has the column a.  The signature accepts any row.

   What refutes it is `(|a|) <- (k, t2)`: take the input row empty, and no
   part can hold a.  Until 2026-10 the check dropped that partition, warned
   "NO VERDICT" and accepted.

   The honest version is shouldfail-controls/control09_literal_row_join.e, `onlyKeyOne`.
-}

import Prelude

field a : Int

onlyA1 : Relation r -> Relation r
onlyA1 x = join x (relation [{a = 1}])
