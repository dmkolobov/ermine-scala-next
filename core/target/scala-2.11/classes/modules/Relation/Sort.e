module Relation.Sort where

import Native.Maybe
import Native.List
import Native.Ord
import Native.Pair
import Native.Record
import Control.Functor using fmap
import Bool
import Eq
import Field
import Int
import List
import Ord
import Pair
import Prim using prim#
import Syntax.List
import Relation.Row hiding empty_Bracket; cons_Bracket; empty; single; append
import Function
import Constraint

data SortOrder = Ascending | Descending

private
  data MultiSortOrder#
    = SingleSort SortOrder
    | DualSort SortOrder SortOrder

type MultiSortOrder a = MultiSortOrder#

singleSort : Primitive a => SortOrder -> MultiSortOrder a
singleSort = SingleSort

dualSort
  :  (Primitive a, Primitive b)
  => SortOrder -> SortOrder
  -> MultiSortOrder (a, b)
dualSort = DualSort

data Sort (r:row) = Sort (List (String, PrimT, SortOrder))

type Sort# = List# (Pair# String SortOrder#)

type TypedSort# = List# (Pair# (Pair# String PrimT) SortOrder#)

empty : Sort (| |)
empty = Sort []

ordering : Row r -> Sort r
ordering (Row r) = Sort (map ((t, pt) -> (t, pt, Ascending)) r)

single : (Field f a, SortOrder) -> Sort f
single (f, s) = Sort $ [(fieldName f, prim# $ fieldType f, s)]

-- | Advance and rewrite priorities as needed.  For softRelations,
-- you'll need to try reorderSome instead.
reorder : forall r s. (Has r s) => Sort r -- ^ Based on this sort...
                                -> Sort s -- ^ Raise this sort to first priority.
                                -> Sort r
reorder = reorderSome

-- | Advance and rewrite priorities as needed.  Note that this
-- function only ensures your result makes sense at runtime; for a
-- typesafe second argument, use `reorder` instead.
reorderSome : forall r s. Sort r -- ^ Based on this sort...
                       -> Sort s -- ^ Raise this sort to first priority.
                       -> Sort r
reorderSome r s = uncurry append $ reorderSplit r s

-- | Replace a first-argument sort with the second argument.  For
-- softRelations, you'll need to try onlySome instead.
only : forall r s. Has r s
    => Sort r                   -- ^ Replace this sort...
    -> Sort s                   -- ^ With its subset from this one.
    -> Sort s
only = onlySome

-- | Replace a first-argument sort with the second argument.  This
-- removes columns, but only checks s at runtime; use `only` instead
-- if you can.
onlySome : forall r s rs. (Has s rs, Has r rs)
        => Sort r               -- ^ Replace this sort...
        -> Sort s               -- ^ With its subset from this one.
        -> Sort rs
onlySome r = fst . reorderSplit r

-- | The subset of r described by s in s-order, and the remainder of
-- r.  This function is probably overly general for your needs;
-- consider one of the other `reorder` functions in this module before
-- this one.
reorderSplit : forall r s ro rs. (Has s rs, r <- (rs, ro))
            => Sort r -> Sort s -> (Sort rs, Sort ro)
reorderSplit (Sort r) (Sort s) = (Sort $ intersect s r, Sort $ minusS r s)

invert : Sort r -> Sort r
invert (Sort r) = Sort (map invertPair r) where
  invertPair (n, t, Ascending) = (n, t, Descending)
  invertPair (n, t, Descending) = (n, t, Ascending)

isAscending : SortOrder -> Bool
isAscending Ascending = True
isAscending _ = False

append : forall (r1:row) (r2:row) (r:row) . r <- (r1,r2) => Sort r1 -> Sort r2 -> Sort r
append (Sort r1) (Sort r2) = Sort (r1 ++ r2)

-- | Functional partial ordering based on a sort specification.
partialRecordOrd : (s <- (r, o)) => Sort r -> Ord {..s}
partialRecordOrd = contramap (scalaRecord# . record#) . fromOrd#
                 . scalaRecordOrd# . toSort#

-- | Functional total ordering based on a sort specification.
recordOrd : Sort r -> Ord {..r}
recordOrd = partialRecordOrd

-- | Nativize a sort.
toSort# : Sort r -> Sort#
toSort# (Sort o) = toList# $ map ((f,_,o) -> toPair# (f,toSortOrder# o)) o

toTypedSort# : Sort r -> TypedSort#
toTypedSort# (Sort o) = toList# $ map ((f,t,o) -> pair# (pair# f t) (toSortOrder# o)) o

-- | Nativize a sort order.
toSortOrder# : SortOrder -> SortOrder#
toSortOrder# Ascending = asc#
toSortOrder# Descending = desc#

private
  foreign
    value "com.clarifi.reporting.SortOrder$Asc$" "MODULE$" asc# : SortOrder#
    value "com.clarifi.reporting.SortOrder$Desc$" "MODULE$" desc# : SortOrder#
    function "com.clarifi.reporting.relational.package" "recordOrd"
      scalaRecordOrd# : Sort# -> Ord# ScalaRecord#

-----------------------------------------------------------------------------
-- indexing in relation model is one-based, so the functions below assume
-- the first record is the record number 1, not 0
-----------------------------------------------------------------------------
limit : forall r h . (Has r h, RelationalComb rel) => Sort h -> Maybe Int -> Maybe Int -> rel r -> rel r
limit o start stop rel = limit# (toSort# o) (toMaybe# start) (toMaybe# stop) rel

firstK : Int -> [..r] -> [..r]
firstK k r = limit empty Nothing (Just k) r

topK : forall r h a. (Has r h, RelationalComb rel) => Row h -> Int -> rel r -> rel r
topK f k r = limit (invert $ ordering f) Nothing (Just k) r

bottomK : forall r h a. (Has r h, RelationalComb rel) => Row h -> Int -> rel r -> rel r
bottomK f k r = limit (ordering f) Nothing (Just k) r

private
  minusS = pairwiseFilt and (!=)
  intersect = pairwiseFilt or (==)
  pairwiseFilt comb bin a b =
    filter ((ai, _, _) -> comb $ ((bi, _, _) -> bin ai bi) <$> b) a

-- builtin
--   foreign data "com.clarifi.reporting.SortOrder" SortOrder#
--   limit# : List# (Pair# String Bool) -> Maybe# Int -> Maybe# Int -> [..r] -> [..r]
