module DbFetchFragments where

-- THE DB-BACKED TWIN of FetchFragments (DB-PLAN D7, tracker/db/REPORTS.md): the
-- same report, line for line, importing DbFetchData instead of FetchData,
-- so `sales` and `targets` are `table`s scanned on the runner's connection
-- (ErmineSales on SQL Server, or the loader's SQLite twin) rather than
-- literals.  At tier xs its document equals FetchFragments's (TestDbReports).
-- The original's notes follow unchanged.
--
-- ONE REPORT, THREE FRAGMENTS.
--
-- The point of this example is that a piece of a report is an ORDINARY
-- FUNCTION returning `Fetch Node`, and the report is their composition.
-- `regionHeadline`, `runningTable` and `topSlices` below each scan on their
-- own; none of them knows where it will be put; `report` puts them in an
-- `hflow` (through `sequence_Fetch`), a `tabbed` (`tabbedF`) and a `vflow`
-- (`vflowF`).  Before J3g none of this was expressible: every layout
-- combinator took a `Node`, so every scan had to be hoisted above the whole
-- layout and a fragment could not carry its own.
--
-- Each fragment is also the body of one of the other examples -- a headline
-- over a region (FetchHeadline), a running total joined back to targets in
-- SQL (FetchRunning), a top-N pie with an "Other" slice (FetchTopN) -- so
-- this report scans five relations and the document has them all.
--
--   {"params": {"tabsFor": ["north", "south"], "topN": 2}}
--
-- The scans run in the order the fragments are written: the headlines left
-- to right, then the running table, then the pie (TestRunner (fxl-order)).

import Bool
import Eq
import Field
import Int
import Json using type Inline; Inline
import Layout.Doc
import Layout.Fetch
import Layout.Widgets.Chart
import Layout.Widgets.Format
import Layout.Widgets.Headline
import Layout.Widgets.PieChart
import Layout.Widgets.Table
import List using {take; drop; length; sum'; map_List; foldl; reverse; (++); empty_Bracket; cons_Bracket}
import Pair
import Primitive
import Relation
import Relation.Row hiding empty_Bracket; cons_Bracket
import Relation.Sort as Srt
import DbFetchData

field runTotal : Double
field rowNo : Int

data Query = Query { tabsFor : List String, topN : Int }

-- fragment 1: the headline of one region.  The widget's own constructor
-- scans; the fragment is a function of the region name.
regionHeadline : String -> Fetch Node
regionHeadline r = headlineOf (HeadlineSource "Sales" r amount (filterEq region r sales))

-- fragment 2: a fold in Ermine over rows delivered in day order, joined
-- back to the targets IN SQL (FetchRunning's body; a running total itself
-- is a `Relation.Windowed` job -- the fold stands for per-row Ermine code).
withRunning : List {region, day, amount, units} -> List {region, day, amount, runTotal, rowNo}
withRunning rows = reverse (snd (foldl step ((0.0, 0), []) rows))
  where step ((tot, n), acc) r =
          let tot' = tot + (r ! amount)
              n'   = n + 1
          in ((tot', n'), { region = r ! region, day = r ! day, amount = r ! amount,
                            runTotal = tot', rowNo = n' } :: acc)

runningTable : Fetch Node
runningTable =
  scanRelationInOrder (ordering_Srt {day}) sales (rows ->
    done (tabular (simpleTable
            [ numberColumn "rowNo" "#" Default
            , textColumn "region" "Region"
            , textColumn "day" "Day"
            , numberColumn "runTotal" "Running" (Currency False False "$" 2)
            , numberColumn "target" "Target" (Currency False False "$" 0) ]
            (join (relation (withRunning rows)) targets
               # {rowNo, region, day, runTotal, target}))))

-- fragment 3: the N largest regions and one "Other" slice (FetchTopN's body).
byRegion : Mem (|region, amount|)
byRegion = groupBy {region} (sumBy amount) sales

topSlices : Int -> Fetch Node
topSlices n =
  scanRelationInOrder (invert_Srt (ordering_Srt {amount})) byRegion (ranked ->
    let top   = take n ranked
        other = sum' (map_List (r -> r ! amount) (drop n ranked))
        slices = relation (map_List (r -> { region = r ! region, amount = r ! amount }) top
                           ++ [ { region = "Other", amount = other } ])
    in done (pieChart (PieChartProps "Sales by region" "Sales" "region" "amount"
                                     Nothing Nothing Nothing
                                     Default (Currency False False "$" 2)
                                     (ChartLegendOptions LegendRightTable) (ChartRenderHints True)
                                     (Inline slices))))

-- the report: the fragments, composed.  `sequence_Fetch` for the row of
-- headlines, `tabbedF` for the two big pieces, `vflowF` for the page.
report : Query -> Fetch Node
report q =
  vflowF [ map_Fetch hflow (sequence_Fetch (map_List regionHeadline (tabsFor q)))
         , tabbedF [ ("Running", runningTable), ("Top", topSlices (topN q)) ] ]
