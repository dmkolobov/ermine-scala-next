module Relation.OpTest where

import Bool
import Native.List using toList#
import List as L
import Relation
import Relation.Op
import Relation.Predicate

field x: Int
field y: Int
field z: Int
field ll: Long
myrel = relation [{y = 2, z = 3}]_L

mino : OpBin Int
mino a b = if (a < b) a b

minxy : Op (|x, y|) Int
minxy = mino (col x) (col y)

asOps = [asOp x,
         -- TODO asOp 42,
         asOp (col x)]_L

primAsOps = toList# asOps

testMain = True
