module Layout.Column where

import Void
import Error
import Relation.Row
import Function
import List as L
import DrilldownList using {type DrilldownList; fromDrilldown}
import Layout.Report.Atomic
import Layout.Presentation using { asPresentation; type Presentation }
import Layout.Legend
import Layout.SortStrategy
import Layout.SortPriority
import Native.Relation
import Native.Throwable
import Maybe
import Either
import Syntax.List
import Unsafe.Coerce

private
                        --  name      key columns   value fmt     drilldown
  type JoinReady a p d = (Bound NameT, Unbound a,        p,        d)
  -- terrible coercions because we lack GADTs
  unsafeCol : Column t k v -> Column t' k' v'
  unsafeFCol : f (Column t k v) -> f (Column t' k' v')
  unsafePhantomCol : Column t k v -> Column t' k v
  unsafePhantomColK : Column t k v -> Column t' k' v
  unsafeCol = unsafeCoerce
  unsafeFCol = unsafeCoerce
  unsafePhantomCol = unsafeCoerce
  unsafePhantomColK = unsafeCoerce

-- things that can be bound
data NameT -- the name of the column
data MulticolumnT
-- the legend (just use the legend for this)
-- the presentation
-- column rel |> name "hi" . keys {ticker}
data DrilldownT a -- the drilldown
data KeysT
data FormatT

data JoinType = Inner | Outer

data Column t (k:row) v =
    forall r2 r3 a b . Single
      Relation#
      (Maybe (Atomic a))
      (Maybe (Presentation r2 b))
      (Maybe (SortStrategy r3))
  | JoinAll JoinType (List (Column t k v))
  | forall t2 . SetLegend (Legend k) (Column t2 k v)
  | SetSortPriority SortPriority (Column t k v)
  | forall t2 k2 pid cid a . SetDrilldown (Field pid a) (Field cid a) (Column t2 k2 v)
  | forall t2 k2 r r2 rel . SetDrilldown2 (DrilldownList r) Relation# (Column t2 k2 v)

private
  endoColumn (s: some t1 k1 v1. forall a r2 b r3.
                 Relation# -> Maybe (Atomic a)
              -> Maybe (Presentation r2 b)
              -> Maybe (SortStrategy r3) -> Column t1 k1 v1)
             (ja: some t2 k2 v2.
                  JoinType -> List (Column t2 k2 v2) -> Column t2 k2 v2)
             (sl: some t3 k3 v3. forall t' k'.
                  Legend k' -> Column t' k' v3 -> Column t3 k' v3)
             (ss: some t4 k4 v4.
                  SortPriority -> Column t4 k4 v4 -> Column t4 k4 v4)
             (sd: some t5 k5 v5. forall pid cid a t' k'.
                  Field pid a -> Field cid a -> Column t' k' v5
               -> Column t5 k5 v5)
             (sd2: some t5 k5 v5. forall a t' k'.
                  DrilldownList a -> Relation# -> Column t' k' v5
               -> Column t5 k5 v5)  =
    foldColumn (r a p -> unsafeCol . s r a p)
               (jt -> unsafeCol . ja jt)
               (lg -> unsafeCol . sl lg . unsafeCol)
               (sp -> unsafeCol . ss sp)
               (pid cid -> unsafeCol . sd pid cid)
               (dd roots -> unsafeCol . sd2 dd roots)

-- | Polymorphic fold to monomorphic Column representations.
foldColumn : (forall a r2 b r3. Relation# -> Maybe (Atomic a) -> Maybe (Presentation r2 b) -> Maybe (SortStrategy r3) -> z)
          -> (JoinType -> List z -> z)
          -> (forall k. Legend k -> z -> z)
          -> (SortPriority -> z -> z)
          -> (forall pid cid id. Field pid id -> Field cid id -> z -> z)
          -> (forall r r2. DrilldownList r -> Relation# -> z -> z)
          -> Column t k v
          -> z
foldColumn (s: some z. forall r2 r3 a b.
               Relation# -> Maybe (Atomic a)
            -> Maybe (Presentation r2 b)
            -> Maybe (SortStrategy r3) -> z)          -- ^ Single.
           (ja: some z. JoinType -> List z -> z)      -- ^ JoinAll.
           (sl: some z. forall k. Legend k -> z -> z) -- ^ SetLegend.
           (ss: some z. SortPriority -> z -> z)       -- ^ SetSortPriority.
           (sd: some z. forall pid cid a.
                Field pid a -> Field cid a -> z -> z) -- ^ SetDrilldown.
           (sd2: some z. forall r.
                DrilldownList r -> Relation# -> z -> z)
           = fc . unsafeCol
  where fc (Single r a p ss) = s r a p ss
        fc (JoinAll jt cs) = ja jt ' map fc cs
        fc (SetLegend lg c) = sl lg ' fc (unsafePhantomCol c)
        fc (SetSortPriority sp c) = ss sp ' fc c
        fc (SetDrilldown pid cid c) = sd pid cid ' fc (unsafePhantomColK c)
        fc (SetDrilldown2 cols root c) = sd2 cols root ' fc (unsafePhantomColK c)

-- can change v to v:row, since it is assumed everywhere
-- BUT: think about columns that contain reports

column : (r <- (k, r2), Relational rel) => rel r
      -> Column (Unbound a, Unbound l, Unbound p, Unbound d) k {..r2}
column r = Single (relation# r) Nothing Nothing Nothing

{-
Allow arbitrary
flatReportColumn : Row r
    -> ({..r} -> Report f z)
    -> Column (Unbound a, Unbound l, Bound (Report f z)) r ReportColumn
nestedReportColumn : Row r -> Field pid a -> Field cid a ->
    -> ({..r} -> Report f z)
    -> Column (Unbound a, Unbound l, Bound (Report f z)) r ReportColumn
-}

-- | Join columns in order.  Include some sensible default for missing
-- data columns.
joinAll : List (Column (JoinReady a p d) k v)
       -> Column (JoinReady a p d) k v
joinAll [x] = x
joinAll xs = JoinAll Outer (xs >>= fcja)
  where fcja (JoinAll Outer xs') = xs'
        fcja (JoinAll _ []) = []_L
        fcja x = [x]_L

-- | Join columns in order, excluding those `k`s that lack a `v` in
-- *any* subcolumn.
joinAllStrict : List (Column (JoinReady a p d) k v)
             -> Column (JoinReady a p d) k v
joinAllStrict [x] = x
joinAllStrict xs = JoinAll Inner (xs >>= fcjas)
  where fcjas (JoinAll Inner xs') = xs'
        fcjas (JoinAll _ []) = []_L
        fcjas x = [x]_L

join : Column (JoinReady a p d) k v
    -> Column (JoinReady a p d) k v2
    -> Column (JoinReady a p d) k MulticolumnT
join c1 c2 = unsafeCol $ JoinAll Inner [c1, unsafeCol c2]_L

outerJoin : Column (JoinReady a p d) k v
         -> Column (JoinReady a p d) k v2
         -> Column (JoinReady a p d) k MulticolumnT
outerJoin c1 c2 = unsafeCol $ JoinAll Outer [c1, unsafeCol c2]_L

heading : Atomic x
       -> Column (Unbound a, l, p, d) k v
       -> Column (Bound NameT, l, p, d) k v
heading x = endoColumn (r _ -> Single r (Just x))
                       JoinAll SetLegend SetSortPriority SetDrilldown SetDrilldown2

formatV : AsPresentation pr
       => pr v a
       -> Column (n, l, Unbound x, d) k {..v}
       -> Column (n, l, Bound (Presentation v a), d) k {..v}
formatV = updateFormatV

reformatV : AsPresentation pr
       => pr v a
       -> Column (n, l, Bound (Presentation v a), d) k {..v}
       -> Column (n, l, Bound (Presentation v a), d) k {..v}
reformatV = updateFormatV

updateFormatV : AsPresentation pr
       => pr v a
       -> Column (n, l, x, d) k {..v}
       -> Column (n, l, Bound (Presentation v a), d) k {..v}
updateFormatV pr = endoColumn (r a _ -> Single r a (Just ' asPresentation pr))
                        JoinAll SetLegend SetSortPriority SetDrilldown SetDrilldown2

updateFormatSortedV : AsPresentation pr
       => pr v a -> SortStrategy v
       -> Column (n, l, x, d) k {..v}
       -> Column (n, l, Bound (Presentation v a), d) k {..v}
updateFormatSortedV p ss = updateFormatV p . sortStrategy ss

formatSortedV : AsPresentation pr
       => pr v a -> SortStrategy v
       -> Column (n, l, Unbound x, d) k {..v}
       -> Column (n, l, Bound (Presentation v a), d) k {..v}
formatSortedV = updateFormatSortedV

reformatSortedV : AsPresentation pr
       => pr v a -> SortStrategy v
       -> Column (n, l, Unbound x, d) k {..v}
       -> Column (n, l, Bound (Presentation v a), d) k {..v}
reformatSortedV = updateFormatSortedV

keys : Row k
    -> Column (n, Unbound KeysT, pres, d) k v
    -> Column (n, Bound (Legend k), pres, d) k v
keys = formatK . fromRow

formatK : Legend k
       -> Column (n, Unbound KeysT, pres, d) k v
       -> Column (n, Bound (Legend k), pres, d) k v
formatK = SetLegend

sortPriority : SortPriority -> Column t k v -> Column t k v
sortPriority prio = SetSortPriority prio
                  . endoColumn Single JoinAll SetLegend (flip const) SetDrilldown SetDrilldown2

sortStrategy : SortStrategy v -> Column t k {..v} -> Column t k {..v}
sortStrategy ss = endoColumn (r a p _ -> Single r a p (Just ss))
                             JoinAll SetLegend SetSortPriority SetDrilldown SetDrilldown2

drilldown : k' <- (pid, cid, k)
         => Field pid a -> Field cid a
         -> Column (n, Unbound KeysT, pres, Unbound (DrilldownT x)) k' v
         -> Column (n, Unbound KeysT, pres, Bound (DrilldownT (Row (|pid,cid|)))) k v
drilldown = SetDrilldown

drilldown2 : (k' <- (r, k), Relational rel)
         => DrilldownList r
         -> rel r2
         -> Column (n, Unbound KeysT, pres, Unbound (DrilldownT x)) k' v
         -> Column (n, Unbound KeysT, pres, Bound (DrilldownT (Row r))) k v
drilldown2 dd r = SetDrilldown2 dd (relation# r)

-- col {ticker} ` drilldown nodeId parentId
--              . name "hi"
--              .
--              . sortPriority 11
--              . sortStrategy blah

-- column {blah} rel ^! 10
