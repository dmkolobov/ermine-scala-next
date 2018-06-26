module Relation.WindowFunc where

import Relation.WindowFunc.Unsafe
import Function
import Native.Function
import Relation.Op using asOp
import Relation.Op.Type
import Relation.Row
import Field
import Native.List
import List using map_List
import Native.Pair
import Relation.Aggregate.Type
export Relation.WindowFunc.Type

rank : WindowFunc (||) Int
rank = rankModule

denseRank : WindowFunc (||) Int
denseRank = denseRankModule

rowNumber : WindowFunc (||) Int
rowNumber = rowNumberModule

nTile : (AsOp op) => op r Int -> WindowFunc r Int
nTile = funcall1# nTileModule . asOp

toWindowFunc : Aggregate r a -> WindowFunc r a
toWindowFunc = funcall1# toWindowFuncModule
