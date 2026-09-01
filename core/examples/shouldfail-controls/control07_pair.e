module Shouldfail.Control07 where

-- MUST LOAD. Control for der06 / der07 / der08: sharing a multi-variable
-- remainder between two partitions is satisfiable. Here x + y = (|c|), so
-- t = (|a, c|) and u = (|b, c|) with no field appearing twice.

import Prelude
import Relation.Row as Rw

field a, b, c : Int

rAC : Row (|a, c|)
rAC = append_Rw (single_Rw a) (single_Rw c)

rBC : Row (|b, c|)
rBC = append_Rw (single_Rw b) (single_Rw c)

pair : forall t u x y. (t <- ((|a|), x, y), u <- ((|b|), x, y))
    => Row t -> Row u -> Int
pair _ _ = 0

ok = pair rAC rBC
