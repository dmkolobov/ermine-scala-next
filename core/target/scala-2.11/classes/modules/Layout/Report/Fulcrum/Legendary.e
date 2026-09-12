
module Layout.Report.Fulcrum.Legendary where

import Constraint

import Field
import Function

import List
import Layout.Legend as Lg
import Layout.Presentation

import Record hiding (++)
import Relation
import Relation.Row as R
import Relation.Op hiding empty_Bracket ; cons_Bracket ; (++)
import Relation.Op.Unsafe
import Relation.Pivot as Piv

data LegendaryFulcrum k v p
  = LF (Fulcrum_Piv k v p) (Legend_Lg p)

single_Brace
  : forall f a v k
  . (Field f a, Legend_Lg f, Op v a, {..k})
 -> LegendaryFulcrum k v f
single_Brace (f, lg, o, k) = LF (single_Brace_Piv (f,o,k)) lg

snoc_Brace
   : forall s f p v3 v2 v1 a k
   . (s <- (f,p), RUnion2 v3 v2 v1)
  => LegendaryFulcrum k v1 p
  -> (Field f a, Legend_Lg f, Op v2 a, {..k})
  -> LegendaryFulcrum k v3 s
snoc_Brace (LF ful lg) (f, lg', o, k)
  = LF (snoc_Brace_Piv ful (f,o,k)) (lg ++_Lg lg')

singleRow
  : forall f a v v' k
  . (exists e. v <- (v',e))
 => Row_R v
 -> Field f a
 -> Legend_Lg f
 -> Op v' a
 -> {..k}
 -> LegendaryFulcrum k v f
singleRow r f lg o k = LF (consFulcrum_Piv f o k $ nilFulcrum_Piv (header k) r) lg

mapLegend : forall p k v
          . (Legend_Lg p -> Legend_Lg p)
         -> LegendaryFulcrum k v p -> LegendaryFulcrum k v p
mapLegend f (LF ful lg) = LF ful (f lg)

fulcrumGroup : forall k v p
             . String -> LegendaryFulcrum k v p -> LegendaryFulcrum k v p
fulcrumGroup s = mapLegend (legendGroup_Lg s)

infixr 5 <>

(<>) : forall t p s v3 v2 v1 k
     . (t <- (p, s), RUnion2 v3 v2 v1)
    => LegendaryFulcrum k v1 p
    -> LegendaryFulcrum k v2 s
    -> LegendaryFulcrum k v3 t
(<>) (LF ful1 lg1) (LF ful2 lg2) = LF (catFulcrum_Piv ful1 ful2) (lg1 ++_Lg lg2)

emptyLF : forall k v. Row_R k -> Row_R v -> LegendaryFulcrum k v (||)
emptyLF kr vr = LF (nilFulcrum_Piv kr vr) (empty_Lg)

data MythicalFulcrum k v = forall p. MF (LegendaryFulcrum k v p)
  
infixr 5 ><
(><) : forall v3 v2 v1 k
     . (RUnion2 v3 v2 v1)
    => MythicalFulcrum k v1
    -> MythicalFulcrum k v2
    -> MythicalFulcrum k v3
(><) (MF l1) (MF l2) = MF (l1 <> l2)

mapLegendary : forall k v
             . (forall p. LegendaryFulcrum k v p -> LegendaryFulcrum k v p)
            -> MythicalFulcrum k v -> MythicalFulcrum k v
mapLegendary
  (f : some k v. forall p. LegendaryFulcrum k v p -> LegendaryFulcrum k v p)
  (MF l) = MF (f l)

emptyMF : forall k v. Row_R k -> Row_R v -> MythicalFulcrum k v
emptyMF kr vr = MF $ emptyLF kr vr
