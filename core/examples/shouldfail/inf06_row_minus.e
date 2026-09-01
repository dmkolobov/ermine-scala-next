module Shouldfail.Inf06 where

{- SHOULD FAIL -- error class 2, INFINITE ROW.
   Route: a ROW WITNESS rather than a relation, so the constraint arises in
   `Relation.Row` rather than in a relational operator.

   `minus : t <- (r, s) => Row t -> Row r -> Row s` removes columns from a
   row witness.  `same` forces the shrunken witness to have the same row as
   the original, so `t <- ((|a|), t)`.

   Expected message (verbatim, default -Dermine.genRules=all; the ^NNNNNN
   suffix is a fresh-name counter and varies between runs):
     core/examples/shouldfail/inf06_row_minus.e:1:1: Infinite row partition for 's^599613'

   Raised by: Constraints.scala:805, `selfSubstitution`
     tml.die("Infinite row partition for '" + v + "'")
-}

import Prelude

field a : Int

same : Row r -> Row r -> Int
same _ _ = 1

bad w = same w (minus w {a})
