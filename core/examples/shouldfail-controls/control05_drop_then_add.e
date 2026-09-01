module Shouldfail.Control05 where

-- MUST LOAD. Control for der04: `dropThenAdd`'s signature is satisfiable.
-- Dropping `a` and adding `c` is fine; only re-adding a name the remainder
-- still holds is not.

import Prelude
import Relation.Row as Rw

field a, b, c : Int

ab : Row (|a, b|)
ab = append_Rw (single_Rw a) (single_Rw b)

dropThenAdd : forall r s h t g x y. (r <- (h, t), s <- (t, g))
           => Field h x -> Field g y -> Row r -> Row s
dropThenAdd f g rw = snoc_Rw (minus_Rw rw (single_Rw f)) g

ok : Row (|b, c|)
ok = dropThenAdd a c ab
