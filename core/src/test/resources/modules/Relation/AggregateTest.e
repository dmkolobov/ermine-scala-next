module Relation.AggregateTest where

import Field
import Function
import Relation.Op using col; prim
import Relation
import Relation.Aggregate
import Relation.Aggregate.Type
import List using cons_Bracket; empty_Bracket
import Prim
import Native.Relation

field x: Int
field y: Int
field z: Int
field ll: Long
int4 = prim 4
long4 = prim 4L
myrel = relation [{y = 2, z = 3}]

countIntoX = aggregate count x myrel
countIntoY = aggregate count y myrel
likeX = [relation [{x = 1}], countIntoX]
likeY = [relation [{y = 1}], countIntoY]

type TooWideForSumYs = forall r s. (exists o. r <- (s, o))
                       => Field s Int -> [..r] -> [..s]

sumYs : forall r s. (exists o. r <- ((|y|), o))
        => Field s Int -> [..r] -> [..s]
sumYs = aggregate (sum (col y))
sumMyYs = sumYs x myrel

aggBackOnto = aggregate (avg (col x)) x

avgConst = aggregate (avg int4) x myrel

-- Used for Scala-level structural test.
nativeCountIntoX = relation# countIntoX

testMain = True
