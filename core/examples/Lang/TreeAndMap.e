module Lang.TreeAndMap where

{- A CATEGORY TREE FLATTENED AND RE-ROLLED, and `Map` as the index a report keeps in
   memory.

   Fact: spendRel (8 fields: catNode, catParent, catLabel, catOwner, catStatus,
         catBudget, catActual, catQuarter)

   WHY THIS FILE EXISTS. Two of the stdlib's biggest modules -- `Map.e` (146 lines) and
   `Tree.e` (184) -- have no example anywhere, and they are the two data structures a
   reporting language needs at the VALUE level: a tree because every report hierarchy is
   one, and a map because grouping without a database is a map.

   `Tree` is `scalaz.Tree` behind eleven `foreign` declarations, and the interesting
   half of `Tree.e` is the bridge to relations:

       fromRel      : RunScan List z -> n -> Field pid n -> Field cid n -> rel t
                   -> Cont z (Tree {..h})
       toRel        : s <- (pid,cid,r) => n -> Field pid n -> Field cid n
                   -> Tree (n, {..r}) -> [..s]
       toRootedRel  : (s <- (pid,cid,r), PrimitiveNum n)
                   => n -> (n -> n) -> Field pid n -> Field cid n -> Tree {..r} -> [..s]

   -- a parent-id/child-id relation IS a tree, and the two are interconvertible. Note
   what `toRootedRel` does: it MINTS the ids, walking an infinite `List.Stream` of them
   (`identify (iterate inc (inc z))`), so a tree built in memory can be turned into a
   relation with no id column at all. That is the "re-rolled" half.

   `Tree.fromRel`'s continuation type is `Cont z`, and the only `RunScan List z` the
   stdlib provides is `Layout.Scan.runner`, whose `z` is `Report f z'`. So the
   relation-to-tree direction can only be taken INSIDE a report -- which `treeSection`
   below does -- while the tree-to-relation direction is available anywhere.

   ONE STDLIB COMMENT WORTH KNOWING ABOUT. `Tree.join` carries the comment
   `-- BUSTED: join : c <- (a,b) => Tree {..a} -> Tree {..b} -> Tree {..c}` above a
   definition with the same signature at different variable names. It works; the comment
   records that the more natural spelling did not.

   SHAPES EXERCISED
     * `Tree`: `leaf`, `node`, `root`, `children`, `flatten`, `map`, `zip`, `unfold`,
       `fold`, `scan`, `aggregate`, `sum`, `identify`, `toString'`, `traversable`.
     * `Tree.toRootedRel`'s `s <- (pid, cid, r)` -- a THREE-part partition, minted ids,
       and a relation out of a value.
     * `Tree.fromRel` under `Layout.Scan.runner` inside a report.
     * `Map`: `fromAssocList`, `toAssocList`, `lookup`, `lookupOr`, `insert`, `member`,
       `union`, `unionWith`, `valueMonoid`, `mapKeys`, `orderList`, `values`, `size`,
       `firstEntry`, `groupBy` (which is the `Vector` one).
     * `Ord` as a value: `String.ord`, `Ord.contramap`, `Ord.ordMonoid` composing two
       orderings, `Primitive.primOrd`.
     * `List.NonEmpty`: the honest type for a flattened tree, and its `(:|)` constructor.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/TreeAndMap.e
   >> spendTreeShown
   >> nodeCount
   >> rootLabel, restLabels     -- through `List.NonEmpty`
   >> rolledUp
   >> reRolledRel
   >> ownerTally
   >> ownerBudgetList
   >> quarterOrderList
   >> treeReport
-}

import Prelude
import Syntax.List
import Control.Monoid as Mo
import Control.Functor as Fn
import Layout
import Layout.Scan as LS
import Relation.Op as Op
import Relation.Predicate as Pred
import Tree as Tr
import Map as Mp
import Vector as V
import Ord as O
import Primitive as Pm
import List as L
import List.Util as LU
import List.Stream as Inf
import List.NonEmpty as NE
import Native.Stream as NS
import String as S
import Pair as P
import Lang.Helpers

field catNode    : Int
field catParent  : Int
field catLabel   : String
field catOwner   : String
field catStatus  : String
field catBudget  : Double
field catActual  : Double
field catQuarter : String

-- ---------------------------------------------------------------------------
-- 1. The facts: a spend hierarchy as a parent/child relation.

spendRows : List {catNode, catParent, catLabel, catOwner, catStatus, catBudget,
                  catActual, catQuarter}
spendRows = [
  { catNode = 1, catParent = 0, catLabel = "Group",        catOwner = "Board",
    catStatus = "OPEN", catBudget = 4000000.0, catActual = 3820000.0, catQuarter = "Q2" },
  { catNode = 2, catParent = 1, catLabel = "Technology",   catOwner = "Ravi Menon",
    catStatus = "OPEN", catBudget = 1750000.0, catActual = 1690000.0, catQuarter = "Q2" },
  { catNode = 3, catParent = 2, catLabel = "Platform",     catOwner = "Ravi Menon",
    catStatus = "OPEN", catBudget = 950000.0,  catActual = 921000.0,  catQuarter = "Q2" },
  { catNode = 4, catParent = 2, catLabel = "Data",         catOwner = "Sofia Marek",
    catStatus = "OPEN", catBudget = 800000.0,  catActual = 769000.0,  catQuarter = "Q2" },
  { catNode = 5, catParent = 1, catLabel = "Operations",   catOwner = "Tom Achterberg",
    catStatus = "OPEN", catBudget = 1350000.0, catActual = 1298000.0, catQuarter = "Q2" },
  { catNode = 6, catParent = 5, catLabel = "Facilities",   catOwner = "Tom Achterberg",
    catStatus = "HELD", catBudget = 610000.0,  catActual = 588000.0,  catQuarter = "Q2" },
  { catNode = 7, catParent = 5, catLabel = "Logistics",    catOwner = "Sofia Marek",
    catStatus = "OPEN", catBudget = 740000.0,  catActual = 710000.0,  catQuarter = "Q2" },
  { catNode = 8, catParent = 1, catLabel = "Commercial",   catOwner = "Ada Nwosu",
    catStatus = "OPEN", catBudget = 900000.0,  catActual = 832000.0,  catQuarter = "Q2" }
  ]_L

spendRel : Relation (|catNode, catParent, catLabel, catOwner, catStatus, catBudget,
                      catActual, catQuarter|)
spendRel = relation spendRows

-- ---------------------------------------------------------------------------
-- 2. A tree built at the value level, from the same parent/child data.
--
-- `Tree.unfold : (b -> (a, List b)) -> b -> Tree a` needs a seed and a step. The seed
-- here is a node id, the step looks up the label and the children.

childrenOf : Int -> List Int
childrenOf p = map (t -> t ! catNode) (filter_L (t -> (t ! catParent) == p) spendRows)

labelOf : Int -> String
labelOf n = orElse "?" (fmap maybeFunctor (t -> t ! catLabel)
                             (find_L (t -> (t ! catNode) == n) spendRows))

budgetOf : Int -> Double
budgetOf n = orElse 0.0 (fmap maybeFunctor (t -> t ! catBudget)
                              (find_L (t -> (t ! catNode) == n) spendRows))

spendTree : Tree_Tr (String, Double)
spendTree = unfold_Tr (n -> ((labelOf n, budgetOf n), childrenOf n)) 1

spendTreeShown : String
spendTreeShown = toString'_Tr spendTree

-- | `List.NonEmpty`, named. `Tree.flatten` returns a `Native.Stream`, and a flattened
--   tree is never empty -- there is always a root -- so the honest type for the result is
--   `NonEmpty`, which `List/NonEmpty.e` provides and nothing in `core/examples` used.
--   `(:|)` is its constructor: a head and a (possibly empty) tail.
labelsNonEmpty : NonEmpty_NE (String, Double)
labelsNonEmpty = case toList_NS (flatten_Tr spendTree) of
  (x :: xs) -> x :|_NE xs
  Nil       -> (labelOf 1, budgetOf 1) :|_NE Nil

rootLabel : String
rootLabel = fst_P (head_NE labelsNonEmpty)

restLabels : List String
restLabels = map fst_P (tail_NE labelsNonEmpty)

-- | `fold : (a -> List b -> b) -> Tree a -> b` is the catamorphism; three uses.
nodeCount : Int
nodeCount = fold_Tr (_ kids -> 1 + foldl_L (+) 0 kids) spendTree

treeDepth : Int
treeDepth = fold_Tr (_ kids -> 1 + foldl_L (max_O primOrd_Pm) 0 kids) spendTree

leafLabels : List String
leafLabels = fold_Tr (a kids -> if (null_L kids) (fst_P a :: Nil) (concat_L kids)) spendTree

-- | `aggregate : (n -> n -> n) -> (a -> n) -> Tree a -> Tree (n, a)` is the SCAN: every
--   node is replaced by (rollup of its subtree, itself). This is the roll-up a
--   hierarchy report wants and no relational aggregate provides.
rolledTree : Tree_Tr (Double, (String, Double))
--   NOTE that a node's own budget is INCLUDED in its subtree total, so `Group`'s
--   11,100,000 is the 4,000,000 booked at group level plus its seven descendants;
--   `aggregateLeaves` is the variant for data that lives only at the leaves.
rolledTree = aggregate_Tr (+) snd_P spendTree

rolledUp : List (String, Double)
rolledUp = map (p -> (fst_P (snd_P p), fst_P p)) (toList_NS (flatten_Tr rolledTree))

-- | `map`, `zip` and `identify` -- the last of which walks an infinite `List.Stream`
--   of ids in step with the tree, and is how `toRootedRel` mints its keys.
labelledTree : Tree_Tr String
labelledTree = map_Tr fst_P spendTree

numberedTree : Tree_Tr (Int, String)
numberedTree = identify_Tr (iterate_Inf (n -> n + 1) 100) labelledTree

numberedPairs : List (Int, String)
numberedPairs = toList_NS (flatten_Tr numberedTree)

-- ---------------------------------------------------------------------------
-- 3. Re-rolling the tree into a relation, with ids MINTED by the stdlib.
--
-- `toRootedRel z inc pid cid : Tree {..r} -> [..s]` where `s <- (pid, cid, r)`. The
-- input tree's payload is a record, so the value tree is mapped into records first.

field nodeKey    : Int
field parentKey  : Int
field nodeLabel  : String
field nodeBudget : Double

recordTree : Tree_Tr {nodeLabel, nodeBudget}
recordTree = map_Tr ((l, b) -> {nodeLabel = l, nodeBudget = b}) spendTree

reRolledRel : Relation (|parentKey, nodeKey, nodeLabel, nodeBudget|)
reRolledRel = toRootedRel_Tr 0 (n -> n + 1) parentKey nodeKey recordTree

-- ---------------------------------------------------------------------------
-- 4. `Map`: the index a report keeps in memory.

-- | An assoc list to a map, and back. `Map` is `scala.collection.immutable.SortedMap`,
--   so it needs an `Ord k` -- a VALUE, not a class -- at construction.
ownerTally : Map_Mp String Int
ownerTally = foldl_L (m t -> insert_Mp (t ! catOwner)
                                       (1 + lookupOr_Mp 0 (t ! catOwner) m) m)
                     (empty_Mp ord_S) spendRows

ownerTallyList : List (String, Int)
ownerTallyList = toAssocList_Mp ownerTally

-- | `valueMonoid : Ord k -> (v -> v -> v) -> Monoid (Map k v)` turns any value
--   semigroup into a monoid on maps, which is `foldMap` for grouping.
budgetMonoid : Monoid_Mo (Map_Mp String Double)
budgetMonoid = valueMonoid_Mp ord_S (+)

ownerBudgets : Map_Mp String Double
ownerBudgets = foldRows budgetMonoid
                        (t -> insert_Mp (t ! catOwner) (t ! catBudget) (empty_Mp ord_S))
                        spendRows

ownerBudgetList : List (String, Double)
ownerBudgetList = toAssocList_Mp ownerBudgets

-- | `union` is LEFT-biased; `unionWith` is the lifted semigroup. Both are worth
--   knowing about before a report silently drops a key.
heldBudgets : Map_Mp String Double
heldBudgets = fromAssocList_Mp ord_S
                (map (t -> (t ! catOwner, t ! catBudget))
                     (filter_L (t -> (t ! catStatus) == "HELD") spendRows))

unionLeftBiased : List (String, Double)
unionLeftBiased = toAssocList_Mp (union_Mp heldBudgets ownerBudgets)

unionSummed : List (String, Double)
unionSummed = toAssocList_Mp (unionWith_Mp (+) heldBudgets ownerBudgets)

-- | `orderList` turns a list into a map from element to its 1-based position: the
--   stdlib's way of imposing a bespoke column or category order.
quarterOrder : Map_Mp String Int
quarterOrder = orderList_Mp ord_S (["Q1", "Q2", "Q3", "Q4"]_L)

quarterOrderList : List (String, Int)
quarterOrderList = toAssocList_Mp quarterOrder

-- | `Map.groupBy` is the `Vector` one: `Ord k -> (a -> k) -> Vector a -> Map k (Vector a)`.
ownersByStatus : List (String, Int)
ownersByStatus = map (p -> (fst_P p, length_L (toList_V (snd_P p))))
                     (toAssocList_Mp (groupBy_Mp ord_S (t -> t ! catStatus)
                                                 (vector_V spendRows)))

-- | `Ord` is a value, so orderings COMPOSE with a monoid: status first, then owner.
statusThenOwner : Ord_O {catNode, catParent, catLabel, catOwner, catStatus, catBudget,
                         catActual, catQuarter}
statusThenOwner = mappend_Mo ordMonoid_O (contramap_O (t -> t ! catStatus) ord_S)
                                         (contramap_O (t -> t ! catOwner) ord_S)

sortedLabels : List String
sortedLabels = map (t -> t ! catLabel) (sort_LU statusThenOwner spendRows)

-- ---------------------------------------------------------------------------
-- 5. The report, including the relation-to-tree direction.

overspend : Relation (|catNode, catParent, catLabel, catOwner, catStatus, catBudget,
                       catActual, catQuarter|)
overspend = spendRel |> filter_Pred (col_Op catActual >=_Pred col_Op catBudget)

byOwner : Mem (|catOwner, catBudget|)
byOwner = spendRel |> groupBy {catOwner} (sumBy catBudget)

-- | `Tree.fromRel` reads the relation through `Layout.Scan.runner`, whose continuation
--   type is a `Report`, and hands back a `Tree {..h}` -- here a tree of the non-id
--   columns. The rest of the report is written inside the continuation.
treeSection : Report f z
treeSection = runCont (fromRel_Tr runner_LS 0 catParent catNode spendRel) (t ->
  vflow [ text "### The same hierarchy as a `Tree`, read back out of the relation",
          text (toString'_Tr (map_Tr (r -> r ! catLabel) t)),
          text ("nodes: " ++_S toString (length_L (toList_NS (flatten_Tr t)))) ]_L)

treeReport : Report f z
treeReport = vflow [
    text "## Spend hierarchy, Q2",
    tabular Nothing (spendRel # {catNode, catParent, catLabel, catOwner, catBudget,
                                 catActual}),
    text "### Rolled up by subtree (`Tree.aggregate`)",
    text (mdTable (["Node", "Subtree budget"]_L)
                  (map (p -> [fst_P p, toString (snd_P p)]_L) rolledUp)),
    text "### Re-rolled into a relation with minted ids (`Tree.toRootedRel`)",
    tabular Nothing reRolledRel,
    treeSection,
    text "### Budget by owner",
    tabular Nothing byOwner,
    text "### At or over budget",
    tabular Nothing (overspend # {catLabel, catOwner, catBudget, catActual})
  ]_L
