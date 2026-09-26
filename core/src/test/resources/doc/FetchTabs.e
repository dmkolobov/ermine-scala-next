module FetchTabs where

-- A LAYOUT WHOSE SHAPE COMES FROM THE DATA.
--
-- One tab per region.  A pure report cannot write this: the number of tabs
-- and their labels are in the rows, and a `Params -> Node` report never
-- sees a row.  Here one scan reads the distinct regions (a projection, in
-- region order), and the report builds a tab for each.  What goes INTO each
-- tab is still a plan -- `filterEq region r sales`, a SQL restriction --
-- so with {"data": {"default": "deferred"}} every tab's table goes out as
-- columns plus a token and the client fetches the rows of the tab it
-- opens.  The scan read four rows; the eight sales were never read early.
--
--   {"params": {"showUnits": true}}

import Bool
import Field
import Layout.Doc
import Layout.Fetch
import Layout.Widgets.Format
import Layout.Widgets.Table
import List using {map_List; empty_Bracket; cons_Bracket}
import Relation
import Relation.Row hiding empty_Bracket; cons_Bracket
import Relation.Sort as Srt
import FetchData

data Query = Query { showUnits : Bool }

tabColumns : Query -> List (Column (|region, day, amount, units|))
tabColumns q =
  if (showUnits q)
    [ withHeader "Day" (col day), withHeader "Amount" (numCol amount (Currency False False "$" 2))
    , withHeader "Units" (numCol units Default) ]
    [ withHeader "Day" (col day), withHeader "Amount" (numCol amount (Currency False False "$" 2)) ]

report : Query -> Fetch Node
report q =
  scanRelationInOrder (ordering_Srt {region}) (sales # {region}) (regions ->
    done (tabbed (map_List (r -> (r ! region,
                                  tabular (simpleTable (tabColumns q) (filterEq region (r ! region) sales))))
                           regions)))
