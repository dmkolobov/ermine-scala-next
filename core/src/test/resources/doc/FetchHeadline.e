module FetchHeadline where

-- HEADLINE NUMBERS FROM THE DATA, AND A LAYOUT THAT DEPENDS ON THEM.
--
-- A `Params -> Node` report can put a relation in a widget, but it cannot
-- put "3 sales, 4350.75 in all, the largest 2310.25" in a heading: those
-- are values, and nothing in a pure report ever sees a row.  Nor can it
-- show a message INSTEAD of a table when the relation is empty, because it
-- does not know.  `scanRelation` executes the relation while the report is
-- built and hands the rows over as a `List {..r}`; from there it is
-- ordinary Ermine.
--
--   {"params": {"onlyRegion": "north"}}   the heading and the table
--   {"params": {"onlyRegion": "nowhere"}} one text widget, no table
--   {"params": {}}                        every region
--
-- The table below the heading is still a PLAN: the same relation the scan
-- executed, delivered inline or deferred as the request asks.

import Bool
import Eq
import Field
import Int
import Layout.Doc
import Layout.Fetch
import Layout.Widgets.Format
import Layout.Widgets.Table
import List using {length; sum'; map_List; foldl; empty_Bracket; cons_Bracket}
import Maybe
import Primitive
import Relation
import String using (++)
import FetchData

data Query = Query { onlyRegion : Maybe String }

-- what the "headline" widget is given
data Headline = Headline { hlScope : String, hlCount : Int, hlTotal : Double, hlLargest : Double }

picked : Query -> [region, day, amount, units]
picked q = maybe sales (r -> filterEq region r sales) (onlyRegion q)

place : Query -> String
place q = maybe "everywhere" (r -> "in " ++ r) (onlyRegion q)

report : Query -> Fetch Node
report q =
  scanRelation (picked q) (rows ->
    let amounts = map_List (r -> r ! amount) rows
        largest = foldl (a b -> if (b > a) b a) 0.0 amounts
    in done (if (length rows == 0)
               (widget "text" ("no sales " ++ place q))
               (vflow
                 [ widget "headline" (Headline (place q) (length rows) (sum' amounts) largest)
                 , tabular (simpleTable [ textColumn "region" "Region"
                                        , textColumn "day" "Day"
                                        , numberColumn "amount" "Amount" (Currency False False "$" 2) ]
                                        (picked q)) ])))
