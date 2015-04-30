module Relation.SortTest where

import Field
import Relation.Row
import Relation.Sort

field x: Int
table xtable: [x]

-- Test that limit reaches whnf, and structure.
someLimit36 = limit (ordering {x}) (Just 3) (Just 6) xtable
