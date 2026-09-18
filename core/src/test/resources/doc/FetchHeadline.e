module FetchHeadline where

-- A WIDGET THAT SCANS, AND A LAYOUT THAT DEPENDS ON THE DATA.
--
-- A `Params -> Node` report can put a relation in a widget, but it cannot
-- put "3 sales, 4350.75 in all, the largest 2310.25" in a heading: those
-- are values, and nothing in a pure report ever sees a row.  Nor can it
-- show one thing INSTEAD of another when the relation is empty, because it
-- does not know.
--
-- Since J3g the scan does not have to be hoisted above the layout, and a
-- widget's own constructor may do it: `headlineOf` (Layout.Widgets.Headline)
-- IS a `Fetch Node` -- it scans the relation it is given, counts the rows,
-- sums a field and takes the largest -- and `vflowF` is `vflow` over
-- children that scan.  `headline` is the same widget for a caller that
-- already has the numbers; the empty arm below uses it, because there is
-- nothing to scan.
--
--   {"params": {"onlyRegion": "north"}}   the headline and the table
--   {"params": {"onlyRegion": "nowhere"}} one headline, all zeros, no table
--   {"params": {}}                        every region
--
-- The table below the headline is still a PLAN: the same relation the
-- headline scanned, delivered inline or deferred as the request asks.  The
-- report therefore reads `picked q` twice on the non-empty arm -- once to
-- learn whether there is anything, once inside the widget -- which is what
-- a widget that owns its scan costs.

import Bool
import Eq
import Field
import Int
import Layout.Doc
import Layout.Fetch
import Layout.Widgets.Format
import Layout.Widgets.Headline
import Layout.Widgets.Table
import List using {length; empty_Bracket; cons_Bracket}
import Maybe
import Primitive
import Relation
import String using (++)
import FetchData

data Query = Query { onlyRegion : Maybe String }

picked : Query -> [region, day, amount, units]
picked q = maybe sales (r -> filterEq region r sales) (onlyRegion q)

place : Query -> String
place q = maybe "everywhere" (r -> "in " ++ r) (onlyRegion q)

report : Query -> Fetch Node
report q =
  scanRelation (picked q) (rows ->
    if (length rows == 0)
      -- nothing to scan: the pure constructor, with the numbers in hand
      (done (headline (HeadlineProps "Sales" (place q) 0 0.0 0.0 Default)))
      (vflowF
        [ headlineOf "Sales" (place q) amount (picked q)
        , done (tabular (simpleTable [ textColumn "region" "Region"
                                     , textColumn "day" "Day"
                                     , numberColumn "amount" "Amount" (Currency False False "$" 2) ]
                                     (picked q))) ]))
