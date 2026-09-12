module Layout.Report.Fulcrum.Dynamic where

import Layout.Presentation using type Presentation
import Ord using {type Ord; fromLess}
import Relation.Op using type Op; typeOfOp
import Field
import Either
import Maybe
import Relation.Sort
import Relation.Row using type Row

data PivotColumn v = forall a f. PivotColumn (Op v a) (Presentation f a) (Field f a)

data DynamicFulcrum k v =
  DynamicFulcrum (Row k)
                 (Either (Sort k) (Ord {..k}))
                 ({..k} -> PivotColumn v)

pivotColumn : Op v a -> String -> (forall f. Field f a -> Presentation f a) -> PivotColumn v
pivotColumn op nm (k : some a. forall f. Field f a -> Presentation f a) = case existentialF nm (typeOfOp op) of
  EField f -> PivotColumn op (k f) f
