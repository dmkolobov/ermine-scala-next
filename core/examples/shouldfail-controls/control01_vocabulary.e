module Shouldfail.Control01 where

-- MUST LOAD. Fixes the vocabulary the should-fail cases are written in:
-- row headers, relations, join and rename all used correctly.

import Prelude
import Relation.Row as Rw

field a, b, c : Int

rA : Row (|a|)
rA = single_Rw a

rAB : Row (|a, b|)
rAB = append_Rw (single_Rw a) (single_Rw b)

relAB : [a, b]
relAB = relation [{ a = 1, b = 2 }]

relBC : [b, c]
relBC = relation [{ b = 2, c = 3 }]

joined : [a, b, c]
joined = join relAB relBC

renamed : [a, c]
renamed = rename b c relAB
