module Layout.SortPriority where

{- Non-relational sort info. -}

import Bool
import Function
import Field
import List
import List.Util
import Map as M
import Maybe
import Native.List
import Native.Maybe
import Native.Pair
import Num
import Ord
import Pair
import Syntax.List
import Relation.Sort as R
import Vector using type Vector; vector

-- | Where in the sort the column, in context, should be sorted, and
-- in which direction.  A lesser number means higher priority.
data SortPriority = Unsorted | SortPriority SortOrder_R Int

type SortPriority# = Maybe# (Pair# SortOrder#_R Int)

-- | Sort# zipped with numbers, natively.
type PartialSort# (a: *) = Vector (Pair# a (Pair# SortOrder#_R Int))

type SortPriorityAnnotated a = (a, SortPriority)

ascending = SortPriority Ascending_R
descending = SortPriority Descending_R

infix 5 ^ ^! ^' ^. ^.. ^*

-- | Mark a column with ascending or descending order at the given
-- priority, or as a column that shouldn't be considered in the sort.
(^), (^!) : forall a. a -> Int -> (a, SortPriority)
(^') : forall h a . Field h a -> Int -> ((Field h a, String), SortPriority)
unsorted : forall a. a -> (a, SortPriority)
(^) a i = (a, SortPriority Ascending_R i)
(^') a i = ((a, fieldName a), SortPriority Ascending_R i)
(^.) (p,a) i = ((p a, fieldName a), SortPriority Ascending_R i)
(^..) (a,p) i = ((p a, fieldName a), SortPriority Ascending_R i)
(^*) (a,p,s) i = ((p a, s), SortPriority Ascending_R i)

(^!) a i = (a, SortPriority Descending_R i)
unsorted a = (a, Unsorted)

-- | Extract and order `a's according to priority.
prioritize : List (a, SortPriority) -> List (a, SortOrder_R, Int)
prioritize = map ((s, (o, i)) -> (s, o, i))
           . sort (contramap (snd.snd) numOrd)
           . catMaybes
           . map xOrder
  where xOrder (s, SortPriority o i) = Just (s, (o, i))
        xOrder _ = Nothing

-- | Produce the initial sort for a set of logical columns.
toSort# : List (String, SortPriority) -> Sort#_R
toSort# = toSort#_R . Sort_R . map ((s, o, i) -> (s, o)) . prioritize

-- | As with `toSort#', but don't throw away the ints needed to merge
-- priorities.
toPartialSort# : List (a, SortPriority) -> PartialSort# a
toPartialSort# = vector . map nbias . prioritize
  where nbias (s, o, i) = toPair# (s, toPair# (toSortOrder#_R o, i))

-- | Usually, you'll want toSort# instead, doing the collection of
-- priorities in Ermine.
toSortPriority# : SortPriority -> SortPriority#
toSortPriority# Unsorted = toMaybe# Nothing
toSortPriority# (SortPriority o i) =
  toMaybe# . Just . toPair# $ (toSortOrder#_R o, i)
