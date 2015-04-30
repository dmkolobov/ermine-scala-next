module Layout.Report.SoftRelation where

import Either
import Function
import Layout.Column
import Layout.Presentation using type Presentation; extractScalar; rowUsed
import Layout.SortPriority as Pri
import Layout.SortStrategy as SS
import List as L
import List.Util using sort
import Maybe
import Ord using type Ord; fromLess
import Pair
import Relation.Predicate using filter; all
import Relation.Row using except; minus; type Row
import Relation.Sort using type Sort; recordOrd
import Syntax.List
import Void

-- | Presentational information that gives rise to a dependently-typed
-- relation.
data SoftRelation a b k v =
    SoftRelation (Presentation k a)
                 (Either (Sort k) (Ord {..k}))
                 ({..k} -> SortPriorityAnnotated_Pri (Presentation v b,
                                                      Maybe (SortStrategy_SS v)))

joinKey : (r <- (i, k, v))
       => SoftRelation a b k v -> {..k} -> Row r -> Row i
joinKey (SoftRelation ks _ vprf) k r =
  r ` minus ' rowUsed ks ` minus ' rowUsed . fst . fst . vprf <| k

-- | Reinterpret a SoftRelation in the Layout.Column language.
dynamicSchema : (r <- (i, k, v), Relational rel)
             => SoftRelation a b k v
             -> rel r
             -> List {..k}
             -> Column (Bound NameT, Unbound l,
                        Bound (Presentation v b), Unbound d) i {..v}
dynamicSchema (SoftRelation prk ksrt vprf) r ks =
  let pickk ktup = except (rowUsed prk) . filter (all ktup)
      single ktup = column (pickk ktup r)
                 |> heading (extractScalar prk ktup) |> presentBy (vprf ktup)
      presentBy ((prv, mss), spri) =
        formatV prv . maybe id sortStrategy mss . sortPriority spri
  in joinAll $ single <$> (sort (softRelationOrd ksrt) ks)

private
  softRelationOrd : Either (Sort k) (Ord {..k}) -> Ord {..k}
  softRelationOrd = either recordOrd id
