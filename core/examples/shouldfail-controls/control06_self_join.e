module Shouldfail.Control06 where

-- MUST LOAD. Control for der05: pinning a join's result header to the left
-- operand's is a satisfiable signature, so long as the right operand really
-- does contribute no new columns.

import Prelude

field a, b : Int

ab : [a, b]
ab = relation [{ a = 1, b = 2 }]

b1 : [b]
b1 = relation [{ b = 2 }]

selfJoin : forall p q d e f. (p <- (d, e), q <- (e, f), p <- (d, e, f))
        => [..p] -> [..q] -> [..p]
selfJoin r s = join r s

ok : [a, b]
ok = selfJoin ab b1
