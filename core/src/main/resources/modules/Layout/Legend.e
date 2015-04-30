module Layout.Legend where

import Control.Functor
import Field using {fieldName; existentialF; EField}
import Function
import Native
import Native.TraversableColumns as TC
import Layout.Format using type Format
import Layout.Presentation
import Layout.SortPriority
import Layout.SortStrategy as SS
import Layout.SortStrategy.Unsafe
import List as L
import List.Util using sort
import Ord using contramap
import Eq
import Bool
import Pair
import Prim using unsafePrim#
import Relation.Op using type Op; asOp
import Relation.Row using {type Row; Row; single; rowUsed#}
import Relation.Sort using {type Sort#; type SortOrder#}
import String as S
import Syntax.List
import Error

foreign data "com.clarifi.reporting.writers.Legend" Legend# (a: *)

--case class Legend[Lbl](inOrder: Seq[(Presentation, SortStrategy, Lbl)], undisplayed: Seq[(ColumnName, PrimT, SortOrder)])
-- | The "legend" (essentially, display metadata) for a set of fields.
data Legend (r: ρ) = Legend (List (Legend# String, SortPriority, String)) (Legend# String)

infixr 5 ++

private foreign
  subtype AsTraversableColumns : Legend# a -> TraversableColumns#_TC r
  function "com.clarifi.reporting.writers.Legend" "empty"
      empty# : Legend# lbl
  function "com.clarifi.reporting.writers.Legend" "overPresentation"
      unsafeLegend : Presentation r a -> List# (Pair# lbl SortDirection_SS)
                  -> lbl -> Legend# lbl

  function "com.clarifi.reporting.writers.Legend" "hiding"
      unsafeHidden: Op r a -> SortStrategy# r -> Maybe# (Pair# SortOrder# Int) -> Legend# lbl

  method "append" append# : Legend# lbl -> Legend# lbl -> Legend# lbl
  method "columnReferencesList" columnsUsed## : Legend# lbl -> List# String
  method "map" map## : Legend# a -> Function1 a b -> Legend# b

reprioritizeLabel : String -> SortPriority -> Legend r -> Legend r
reprioritizeLabel lbl newPriority (Legend l1 l2) =
  Legend (fmap listFunctor_L ((leg, oldPriority, lbl') -> 
           if (lbl == lbl')
                (leg, newPriority, lbl') 
                (leg, oldPriority, lbl')) l1)
         l2

-- | Give a label to a single presentation, producing its legend.
--
-- The Presentation's Ops must preserve the ordering of underlying r;
-- any deviation must be described in the SortStrategy argument to
-- `exoticLegend`.  Otherwise, `op` ought to be included in the
-- underlying relation instead, where the scanner can sort with it
-- correctly.
legend : AsPresentation pr => pr r a -> String -> Legend r
exoticLegend : AsPresentation pr
            => pr r a
            -> SortStrategy_SS r
            -> SortPriority
            -> String
            -> Legend r
legend p = exoticLegend p (sortBy_SS forward_SS p) Unsorted
exoticLegend p srt init lbl = Legend ([(unsafeLegend (asPresentation p)
                                                    (nativeSortStrategyData# srt)
                                                    lbl,
                                       init, lbl)]_L) empty#

hidden : AsOp op => SortPriorityAnnotated (op r a) -> Legend r
hidden (op, srt) = exoticHidden op (sortBy_SS forward_SS $ asOp op) srt
exoticHidden : AsOp op => op r a -> SortStrategy_SS r -> SortPriority -> Legend r
exoticHidden op ss sp = Legend ([]_L) $ unsafeHidden (asOp op) (sortStrategy# ss) (toSortPriority# sp)

-- | Do not use; meant for writers.  (Boxes a legend for report
-- nesting and export to writers.)
legend# : Legend r -> Legend# String
legend# (Legend xs hs) = append# (foldl_L append# empty# $ map ((nl, _, _) -> nl) xs) hs

-- | Do not use; meant for writers.  (Extract unique columns
-- references in a legend, in order.)
columnsUsed# : Legend# lbl -> List String
columnsUsed# = columnsUsed#_TC . AsTraversableColumns

-- | The database type described by this legend.
legendRow : Legend r -> Row r
legendRow = rowUsed# . AsTraversableColumns . legend#

-- | Do not use; meant for writers.  (Extracts initial sort order of
-- labels.)
initialSort# : Legend r -> Sort#
initialSort# = toSort# . partialSort

-- | List the initial sort priority of each label, in order.
partialSort : Legend r -> List (String, SortPriority)
partialSort (Legend xs _) = map ((_, pri, lbl) -> (lbl, pri)) xs

legendFunctor# : Functor Legend#
legendFunctor# = Functor (f l -> map## l (function1 f))

-- | An empty legend.
empty : Legend (| |)
empty = Legend ([]_L) empty#

-- | Default legend for a field.
fromField = fromRow . single

-- | Default legend for a row.  Note: legendRow . fromRow = id
fromRow : Row r -> Legend r
fromRow (Row sps) = Legend (col <$> sort (contramap fst ord_S) sps) empty#
  where col (s, pt) = ((case existentialF s (unsafePrim# pt) of
                         (EField e) -> unsafeLegend (asPresentation e)
                                         (nativeSortStrategyData# $
                                           sortBy_SS forward_SS e)
                                         s),
                       Unsorted, s)

-- | Default legend for a row, where all rows use a given Format.
fromRowWithFormat : Format a -> Row r -> Legend r
fromRowWithFormat f (Row sps) = Legend (col <$> sort (contramap fst ord_S) sps) empty#
  where col (s, pt) = ((case existentialF s (unsafePrim# pt) of
                         (EField e) -> unsafeLegend (presentation f e)
                                         (nativeSortStrategyData# $
                                           sortBy_SS forward_SS e)
                                         s),
                       Unsorted, s)

fromRowWithDisplayFunc : (String -> String) -> Row r -> Legend r
fromRowWithDisplayFunc f  (Row sps)= Legend (col <$> sort (contramap fst ord_S) sps) empty#
  where col (s, pt) = ((case existentialF s (unsafePrim# pt) of
                         (EField e) -> unsafeLegend (asPresentation e)
                                         (nativeSortStrategyData# $
                                           sortBy_SS forward_SS e)
                                         (f s)),
                       Unsorted, s)
-- | Combine two legends into one.  They may not specify information
-- for overlapping fields.
(++) : forall r s t. t <- (r, s) => Legend r -> Legend s -> Legend t
(++) (Legend l1 l2) (Legend r1 r2) = Legend (l1 ++_L r1) (append# l2 r2)

empty_Bracket, empty_Bracket_Simple, empty_Bracket_Sorted : Legend (| |)
empty_Bracket = empty
empty_Bracket_Simple = empty
empty_Bracket_Sorted = empty

cons_Bracket : forall r1 r2 r a . (r <- (r1, r2), AsOp op)
               => (op r1 a, Format a, op r1 a -> SortStrategy_SS r1, String)
                  -> Legend r2 -> Legend r
cons_Bracket (op, fmt, srt, lbl) t =
  exoticLegend (presentation fmt $ asOp op) (srt op) Unsorted lbl ++ t

cons_Bracket_Simple : (t <- (r, s), AsPresentation pr)
                   => (pr r a, String)
                   -> Legend s
                   -> Legend t
cons_Bracket_Simple = cons_Bracket_Sorted . unsorted

-- | The most complete legend list syntax.  This example sorts first
-- by name ascending, then by timeleft descending.
--
-- [unsorted (occupation, "Occupation"),
--  (name, "Name") ^ 0,
--  (timeleft, "Time Remaining") ^! 10]_Sorted_Lg
cons_Bracket_Sorted : (t <- (r, s), AsPresentation pr)
                   => SortPriorityAnnotated (pr r a, String)
                   -> Legend s
                   -> Legend t
cons_Bracket_Sorted ((pr, lbl), srt) =
  let pr' = asPresentation pr
  in (++) $ exoticLegend pr' (sortBy_SS forward_SS pr') srt lbl
