module Shouldfail.Control04 where

-- MUST LOAD. Control for sk04 / sk05: `step2`'s signature is satisfiable.
-- `x` and `y` are independent rows; only passing the SAME row for both
-- collapses the constraint set and forces that row empty.

import Prelude
import Relation.Row as Rw

field a, b : Int

rA : Row (|a|)
rA = single_Rw a

rB : Row (|b|)
rB = single_Rw b

rAB : Row (|a, b|)
rAB = append_Rw rA rB

rE : Row (| |)
rE = empty_Rw

step2 : forall x c d y. (exists b. b <- (x, d), c <- (b, y))
     => Row x -> Row y -> Row c -> Row d -> Int
step2 _ _ _ _ = 0

-- x = (|a|), y = (|b|), d = (| |)  =>  b = (|a|), c = (|a, b|).
ok = step2 rA rB rAB rE
