module Shouldfail.Der07 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD, derived, generativity-
   sensitive.  Same shape as der06 with a THREE-variable shared remainder, to
   show the effect is not specific to the two-variable case that
   `commonSubexpression`'s `int.size < 2` test just barely admits.

   *** GENERATIVITY-SENSITIVE. ***
   Observed:  -Dermine.genRules=all     -> REJECTED
              -Dermine.genRules=cut     -> REJECTED
              -Dermine.genRules=nongen  -> LOADS.

       t <- ((|a|), x, y, z)
       u <- ((|b|), x, y, z)

   instantiated with t = (|a, b, c, d|) and u = (|b, c, d|).  As in der06 the
   contradiction is only visible once a minted variable names `x + y + z`
   (Constraints.scala:1104 `GenRules.cseMints`, or Constraints.scala:821
   `GenRules.splitMints`), after which cancellation reduces it to
   `(|b, c, d|)` and substitution duplicates `b`.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/der07_shared_three_var_remainder.e:42:1: Fields appear twice in row: Set(Shouldfail.Der07.b)

   Raised by: Constraints.scala:329, `RHS.merge`
     else tml.die("Fields appear twice in row: " + cint)
-}

import Prelude
import Relation.Row as Rw

field a, b, c, d : Int

abcd : Row (|a, b, c, d|)
abcd = append_Rw (append_Rw (single_Rw a) (single_Rw b)) (append_Rw (single_Rw c) (single_Rw d))

bcd : Row (|b, c, d|)
bcd = append_Rw (single_Rw b) (append_Rw (single_Rw c) (single_Rw d))

triple : forall t u x y z. (t <- ((|a|), x, y, z), u <- ((|b|), x, y, z))
      => Row t -> Row u -> Int
triple _ _ = 0

bad = triple abcd bcd
