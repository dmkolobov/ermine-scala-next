module DrilldownList where

import List hiding empty_Bracket; cons_Bracket
import Native.List
import Prim using prim#
import Field
import Function
import Relation.Row hiding empty_Bracket; cons_Bracket
import Control.Functor

data DrilldownList r = DD (List (String, String, PrimT)) (Row r)

fromDrilldown (DD xs r) = fmap listFunctor ((x,y,z) -> (x,y)) xs
fromDrilldown' (DD xs r) = xs

empty_Bracket = DD Nil empty

cons_Bracket : forall f1 f2 rout r id. (rout <- (f1, f2, r)) =>
               (Field f1 id, Field f2 id) -> DrilldownList r -> DrilldownList rout
cons_Bracket (f1, f2) (DD xs r) = DD ((fieldName f1, fieldName f2, prim# $ fieldType f1) :: xs) (append (single f2) . append (single f1) $ r)

toRow (DD xs r) = r

