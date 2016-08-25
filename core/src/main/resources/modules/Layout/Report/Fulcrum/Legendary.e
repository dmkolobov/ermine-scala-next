
module Layout.Report.Fulcrum.Legendary where

import Field

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

single_Brace : (Field f a, Presentation f a, Op v a, {..k}) -> LegendaryFulcrum k v f
single_Brace (f, pr, o, k) = LF (single_Brace_Piv (f,o,k)) ([(pr, fieldName f)]_Simple_Lg)

snoc_Brace : (s <- (f,p))
  => LegendaryFulcrum k v p
  -> (Field f a, Presentation f a, Op v a, {..k})
  -> LegendaryFulcrum k v s
snoc_Brace (LF ful lg) (f, pr, o, k)
  = LF (snoc_Brace_Piv ful (f,o,k)) (cons_Bracket_Simple_Lg (pr, fieldName f) lg)

mapLegend : (Legend_Lg p -> Legend_Lg p)
         -> LegendaryFulcrum k v p -> LegendaryFulcrum k v p
mapLegend f (LF ful lg) = LF ful (f lg)

fulcrumGroup : String -> LegendaryFulcrum k v p -> LegendaryFulcrum k v p
fulcrumGroup s = mapLegend (legendGroup_Lg s)

infixr 5 <>

(<>) : (t <- (p, s))
    => LegendaryFulcrum k v p
    -> LegendaryFulcrum k v s
    -> LegendaryFulcrum k v t
(<>) (LF ful1 lg1) (LF ful2 lg2) = LF (catFulcrum_Piv ful1 ful2) (lg1 ++_Lg lg2)

data MythicalFulcrum k v = forall p. MF (LegendaryFulcrum k v p)
  
infixr 5 ><
(><) : MythicalFulcrum k v -> MythicalFulcrum k v -> MythicalFulcrum k v
(><) (MF l1) (MF l2) = MF (l1 <> l2)
