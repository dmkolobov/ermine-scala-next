module Layout.Column.Unsafe where

{- Glue from the Layout.Column structures to their equivalents in
Scala.  You only care about column#. -}

import Bool
import Control.Alt
import Control.Monoid
import Eq
import Field
import Function
import Layout.Column
import Layout.Format
import Layout.Legend using {type Legend; type Legend#; legend#;
                            columnsUsed#; partialSort; legendFunctor#}
import Layout.Presentation using {type Presentation; asPresentation;
                                  columnsUsed}
import Layout.Report.Atomic
import Layout.SortPriority
import Layout.SortStrategy
import Layout.SortStrategy.Unsafe
import List as L
import DrilldownList
import Maybe
import Native.Maybe
import Native.Pair
import Native.List
import Native.Relation
import Pair
import Prim using prim#
import Relation using rheader#
import Relation.Op using foldFromRow
import Relation.Row using Row; type Row
import Relation.Sort using type SortOrder#
import String as S
import Syntax.List
import Unsafe.Coerce
import Vector hiding {sortBy; traverse; map}
import Void
import Native.Bool


import Error

foreign
  data "com.clarifi.reporting.writers.Column$Single"
       Single# (lbl: *) (a: *)
  data "com.clarifi.reporting.writers.Column$Join"
       Join# (a: *) (b: *)
  data "com.clarifi.reporting.writers.Column$Table"
       Table# (lbl: *) (a: *)
  -- construction of the above
  data "com.clarifi.reporting.writers.Column$Single$" SingleModule
  value "com.clarifi.reporting.writers.Column$Single$"
        "MODULE$" singleModule : SingleModule
  method "apply" single# : SingleModule -> a -> lbl -> Presentation r ra
                        -> SortStrategy# r -> Maybe# (Pair# SortOrder# Int)
                        -> Bool
                        -> Single# lbl a
  data "com.clarifi.reporting.writers.Column$Joinee$"
       JoineeModule
  value "com.clarifi.reporting.writers.Column$Joinee$"
        "MODULE$" joineeModule : JoineeModule
  method "apply" joinee# : JoineeModule -> b -> Join# a b
  data "com.clarifi.reporting.writers.Column$InnerJoin$"
       InnerJoinModule
  value "com.clarifi.reporting.writers.Column$InnerJoin$"
        "MODULE$" innerJoinModule : InnerJoinModule
  method "apply" innerJoin# : InnerJoinModule -> Vector (Join# a b) -> Join# a b
  data "com.clarifi.reporting.writers.Column$OuterJoin$" OuterJoinModule
  value "com.clarifi.reporting.writers.Column$OuterJoin$"
        "MODULE$" outerJoinModule : OuterJoinModule
  method "apply" outerJoin# : OuterJoinModule -> Vector (Join# a b) -> Join# a b
  data "com.clarifi.reporting.writers.Column$JoinHeading$" JoinHeadingModule
  value "com.clarifi.reporting.writers.Column$JoinHeading$"
        "MODULE$" joinHeadingModule : JoinHeadingModule
  method "apply" joinHeading# : JoinHeadingModule -> a -> Join# a b -> Join# a b
  data "com.clarifi.reporting.writers.Column$Table$" TableModule
  value "com.clarifi.reporting.writers.Column$Table$"
        "MODULE$" tableModule : TableModule
  method "apply" table# : TableModule -> Join# lbl (Single# lbl a)
                       -> Legend# lbl -> PartialSort# lbl
                       -> Maybe# (List# (Pair# (Pair# String String) PrimT))
                       -> Maybe# Relation#
                       -> Table# lbl a

private foreign
  method "setGroupingColumn" setGroupingColumn# : Legend# lbl -> Maybe# (Pair# String PrimT) -> Legend# lbl

-- TODO: setDrilldown2'; fix finalize

-- | Rewrite a column into a form that Scala-level code can
-- understand.  Total for the given phantom bounds.
column# : Column (n, Bound (Legend k), p, d) k v
       -> Table# EAtomic# Relation#
column# = finalize . foldColumn single' hc' join' joinGroup' setLegend' setSortPrio' setDrilldown' setDrilldown2' setRowGroups'

single' r a p s (sp, kcols) =
  let pr = orElse (foldFromRow (unsafePres . asPresentation) valueCols) p
      valueCols = Row $ rheader# r |> (Row allcols) ->
        removeAll fst allcols kcols
      unsafePres : Presentation r a -> Presentation r b
      unsafePres = unsafeCoerce
  in (tableBot, singular $ single# singleModule r
        (maybe (eatomic $ singleHeading valueCols) eatomic a) pr
        (sortStrategy# $ maybe (sortBy forward pr) (coerceSortStrategy pr) s)
        (toSortPriority# sp) False)

hc' r (sp, kcols) =
    let valueCols = Row $ rheader# r |> (Row allcols) ->
                    removeAll fst allcols kcols
        pr = foldFromRow (unsafePres . asPresentation) valueCols
        unsafePres : Presentation r a -> Presentation r b
        unsafePres = unsafeCoerce
    in (tableBot, singular $ single# singleModule r (eatomic $ singleHeading valueCols) pr (sortStrategy# (sortBy forward pr)) (toSortPriority# sp) True)

{-
  method "apply" single# : SingleModule -> a -> lbl -> Presentation r ra
                        -> SortStrategy# r -> Maybe# (Pair# SortOrder# Int)
                        -> Single# lbl a
((SortPriority, List a) -> ((Maybe (Legend r), Maybe ((List (String, String, PrimT))), Maybe (Relation#)), Join# EAtomic# (Single# EAtomic# a1)))
-}

join' jt zs s =
  let trees = cosequence zs s
  in (foldMap_L (mproduct4 (altMonoid maybeAlt) (altMonoid maybeAlt) (altMonoid maybeAlt) (altMonoid maybeAlt))
                fst trees,
      joinConcat jt (snd <$> trees))

joinGroup' gn z = mapSnd (joinHeading# joinHeadingModule . eatomic ' gn) . z

setLegend' lg z (sp, kcols) =
  let saveLg ((_, dd, root, rg), jt) = ((Just $ unsafeLg lg, dd, root, rg), jt)
  in saveLg (z (sp, (columnsUsed# $ legend# lg) ++_L kcols))

setSortPrio' sp z (_, kcols) = z (sp, kcols)

setDrilldown' pid cid z (sp, kcols) =
  let pid' = fieldName pid
      cid' = fieldName cid
      saveDrilldown ((lg, _, _, _), jt) =
          ((lg, Just [(pid', cid', prim# $ fieldType cid)]_L, Nothing, Nothing), jt)
  in saveDrilldown (z (sp, pid' :: cid' :: kcols))

setDrilldown2' drilldownList rel z (sp, kcols) =
  let dd = fromDrilldown drilldownList
      kcols' = foldl_L (xs (pid, cid) -> pid :: cid :: xs) kcols dd
  in case z (sp, kcols') of ((lg, _, _, _), jt) ->
                             ((lg, Just $ fromDrilldown' drilldownList, Just rel, Nothing), jt)

setRowGroups' : Field pid id -> FinalizeInput r a -> FinalizeInput r a
setRowGroups' pid z (sp, kcols) = 
  let pid' = fieldName pid
      saveRowGroups ((lg, _, _, _), jt) = -- ^ Won't have drilldown and rowgroups
          ((lg, Nothing, Nothing, Just (pid', prim# $ fieldType pid)), jt)
  in saveRowGroups (z (sp, pid' :: kcols))

tableBot = (Nothing, Nothing, Nothing, Nothing)

type ColumnKeys r = (Maybe (Legend r) -- ^ Column Legend
    , Maybe (List (String, String, PrimT)) -- ^ Drilldown list
    , Maybe Relation# -- ^ Drilldown2 Relation
    , Maybe (String, PrimT)) -- ^ Row groups

type FinalizeInput r a = (SortPriority, List String) -> (ColumnKeys r, Join# EAtomic# (Single# EAtomic# a))

finalize : forall r a . FinalizeInput r a -> Table# EAtomic# a
finalize st = st (Unsorted, []_L) |> ((Just lg, ddCols, rootRel, rowGroups), cols) ->
  table# tableModule cols
         (fmap legendFunctor# (eatomic . Atomic unit)
                              (setGroupingColumn# (legend# lg) 
                                  (toMaybe# (fmap maybeFunctor toPair# rowGroups))))
         (toPartialSort# . map (mapFst (eatomic . Atomic unit)) . partialSort $ lg)
         (toMaybe# (fmap maybeFunctor  -- toList# . fmap toPair#
                         (toList# . (fmap listFunctor_L ((p,c,ty) -> toPair# (toPair# (p, c), ty))))
                         ddCols))
         (toMaybe# rootRel)

joinConcat : JoinType -> List (Join# a b) -> Join# a b
joinConcat Outer = outerJoin# outerJoinModule . vector
joinConcat Inner = innerJoin# innerJoinModule . vector

private
  -- | Rewrite a sort strategy to only contain fields that make sense,
  -- given the presentation, and completely describe that
  -- presentation.
  coerceSortStrategy : Presentation r a -> SortStrategy s -> SortStrategy r
  coerceSortStrategy pr (SortStrategy s) =
    let prcols = columnsUsed pr
    in SortStrategy $ (filter_L (intersects prcols . snd) s)
                 ++_L [(forward, removeAll id prcols (s >>= snd))]_L

  intersects : Eq a => List a -> List a -> Bool
  intersects l = any_L id . liftA2 listAp_L (==) l

  removeAll : Eq b => (a -> b) -> List a -> List b -> List a
  removeAll f haystack needles =
    filter_L (a -> and_L ((!=) (f a) <$> needles)) haystack

  singular : Single# l a -> Join# g (Single# l a)
  singular = joinee# joineeModule

  -- | Make a single heading providing the default heading for a row.
  singleHeading : Row r -> Atomic String
  singleHeading (Row cols) =
    Atomic unit $ orElse "" (foldl1_L (a b -> a ++_S ", " ++_S b) (fst <$> cols))

  eatomic = AtomicExistentially# . atomic#

  cosequence : List (rv -> a) -> rv -> List a
  cosequence = mapply listFunctor_L

  unsafeLg : Legend r -> Legend s
  unsafeLg = unsafeCoerce
