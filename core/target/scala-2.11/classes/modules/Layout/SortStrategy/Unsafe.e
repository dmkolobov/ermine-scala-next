module Layout.SortStrategy.Unsafe where

import Function
import Layout.SortStrategy
import Native.List
import Native.Pair
import Syntax.List

foreign
  data "com.clarifi.reporting.writers.SortStrategy" SortStrategy# (r: ρ)
  function "com.clarifi.reporting.writers.SortStrategy" "fromList"
    unsafeSortStrategy# : List# (Pair# String SortDirection) -> SortStrategy# r

sortStrategy# : SortStrategy r -> SortStrategy# r
sortStrategy# = unsafeSortStrategy# . nativeSortStrategyData#

nativeSortStrategyData# : SortStrategy r -> List# (Pair# String SortDirection)
nativeSortStrategyData# (SortStrategy sort) = toList# $ sort >>= flatSort
    where flatSort (dir, strs) = (s -> toPair# (s, dir)) <$> strs
