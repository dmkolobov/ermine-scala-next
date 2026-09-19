module Layout.Widgets.Crosstab where

-- Registry name "crosstab": a table whose COLUMNS are the distinct values of
-- a data column -- regions down the side, days across the top, a measure in
-- the cells.
--
-- This is the widget a query cannot produce.  A relation's row type is fixed
-- at compile time, so `table` (Layout.Widgets.Table) can show any number of
-- ROWS but only the columns its `TableColumn` list names; a crosstab's
-- column set IS the data, and nothing in the algebra can name it before the
-- rows are read.  So the wire carries a MATRIX -- two label lists and a
-- `List (List (Maybe Double))` -- and not a relation, and the client has its
-- own renderer for it (client/src/widgets/crosstab.ts) rather than reusing
-- the table's.
--
-- `Nothing` is "no row had that pair", which is not the same as 0.0 (a cell
-- whose rows sum to zero).  Inside a LIST a `Nothing` goes on the wire as
-- `null`; the encoder's omit-the-key rule is for a named field, and there is
-- no key to omit inside an array (json/Encode.scala, `data`).
--
-- THE FETCH WIDGET SHAPE (stage J3i).  A widget whose constructor scans has
-- two records and one function between them:
--
--     CrosstabProps    the WIRE props: registered, schema-checked, rendered
--     CrosstabSource   what the constructor needs: fields and a relation
--     crosstabOf : CrosstabSource .. -> Fetch Node
--
-- The source record never leaves the server -- no registry, no zod, nothing
-- on the wire knows it -- and it is a record rather than seven positional
-- arguments for the same reason the props are.  `Layout.Widgets.Headline`
-- has the same shape.
--
-- FIELD NAMES.  `Layout.Widgets` re-exports every widget module into one
-- scope and Ermine field selectors are global, so a name two widget modules
-- both want has to be prefixed: `crosstabRowLabels` because
-- `Layout.Widgets.StyleBox` owns `rowLabels` (verified: with `rowLabels`
-- here, `rowLabels` applied to a `StyleBoxProps` fails to unify), and
-- `crosstabSourceTitle`/`crosstabMeasure`/`crosstabSource` because
-- `HeadlineSource` wants the same three.  A name only this module wants
-- (`rowKey`, `colKey`, `rowKeyHeader`, `colKeyHeader`, `sourceFormat`,
-- `cells`) is spelt plainly.
--
-- KEYS ARE STRINGS.  A caller with an `Int`, a `Date` or a `Bool` key
-- projects it into a String column first (`Relation` has the operators);
-- the label lists and the client's header cells are text either way, and a
-- String key keeps one ordering (`primOrd`) for both axes.
--
-- CASE.  That ordering IGNORES CASE -- `primOrd` on a String compares both
-- sides lower-cased (`PrimExpr.scala`), where Ermine's own `==` and a SQL
-- GROUP BY do not -- so "North" and "north" are ONE label here, whose cells
-- and totals add the rows of both, and both axes sort case-insensitively.
-- WHICH spelling the label takes is the one the SCAN met first, and a
-- relation is a SET of rows, so that is not the report's to choose.  Fold
-- the case in the projection to be rid of either question (`TestRunner
-- (fxc-1)`).

import Control.Monoid using mappend
import Field using getF
import Layout.Doc using widget; type Node
import Layout.Fetch using {type Fetch; done; scanRelation}
import Layout.Widgets.Format using type CellFormat
import List using {foldl; map_List; sum'; empty_Bracket; cons_Bracket}
import List.Util using {sort; distinct}
import Map as M
import Maybe
import Ord using {type Ord; ordMonoid; contramap}
import Pair using {fst; snd}
import Primitive
import Relation

-- | The matrix, its two label lists, and the totals that come free with it.
-- `cells` is `crosstabRowLabels` x `crosstabColLabels`, row-major: `cells`
-- has one entry per row label, each with one entry per column label.
data CrosstabProps = CrosstabProps { crosstabTitle : String
                                   , rowHeader : String   -- what the row keys are
                                   , colHeader : String   -- what the column keys are
                                   , crosstabRowLabels : List String  -- sorted, distinct
                                   , crosstabColLabels : List String  -- sorted, distinct
                                   , cells : List (List (Maybe Double))
                                   , rowTotals : List Double  -- one per row label
                                   , colTotals : List Double  -- one per column label
                                   , grandTotal : Double
                                   , crosstabFormat : CellFormat }

crosstab : CrosstabProps -> Node
crosstab p = widget "crosstab" p

-- | What `crosstabOf` scans: the relation, the two key fields, the measure,
-- the headings, and the format the cells are shown with.  Server-side only.
data CrosstabSource h1 h2 h3 rel r =
  CrosstabSource { crosstabSourceTitle : String
                 , rowKeyHeader : String
                 , colKeyHeader : String
                 , rowKey : Field h1 String
                 , colKey : Field h2 String
                 , crosstabMeasure : Field h3 Double
                 , crosstabSource : rel r
                 , sourceFormat : CellFormat }

-- | Order a pair of keys by the first component, then the second.
keyOrd : Ord (String, String)
keyOrd = mappend ordMonoid (contramap fst primOrd) (contramap snd primOrd)

-- | The sum of `val` per `key`.  A key with no rows is ABSENT from the map,
-- which is what makes an empty cell `Nothing` rather than 0.0.  A STRICT
-- `foldl`, NOT `foldMap`: `foldMap` is `foldr`, whose stack grows with the
-- ROWS, and a crosstab over 5,000 of them died on it (review R1).
sumsBy : Ord k -> (a -> k) -> (a -> Double) -> List a -> Map_M k Double
sumsBy o key val xs = foldl (acc x -> unionWith_M (+) acc (fromAssocList_M o [(key x, val x)])) (empty_M o) xs

-- | Scan the source and lay its rows out as a matrix: the distinct row keys
-- sorted, the distinct column keys sorted, and the sum of the measure at
-- each pair (`Nothing` where no row had that pair).  The rows come in no
-- particular order -- the shape is the data, not the order.
crosstabOf : (Relational rel, r <- (h1, h2, h3, t))
          => CrosstabSource h1 h2 h3 rel r -> Fetch Node
crosstabOf s =
  scanRelation (crosstabSource s) (rows ->
    let rk = getF (rowKey s)
        ck = getF (colKey s)
        mv = getF (crosstabMeasure s)
        rls = sort primOrd (distinct primOrd (map_List rk rows))
        cls = sort primOrd (distinct primOrd (map_List ck rows))
        cellSums = sumsBy keyOrd (r -> (rk r, ck r)) mv rows
        rowSums  = sumsBy primOrd rk mv rows
        colSums  = sumsBy primOrd ck mv rows
    in done (crosstab (CrosstabProps
         (crosstabSourceTitle s) (rowKeyHeader s) (colKeyHeader s) rls cls
         (map_List (rl -> map_List (cl -> lookup_M (rl, cl) cellSums) cls) rls)
         (map_List (rl -> lookupOr_M 0.0 rl rowSums) rls)
         (map_List (cl -> lookupOr_M 0.0 cl colSums) cls)
         (sum' (map_List mv rows))
         (sourceFormat s))))
