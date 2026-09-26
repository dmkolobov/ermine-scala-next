module DbFetchTopN where

-- THE DB-BACKED TWIN of FetchTopN (DB-PLAN D7, tracker/db/REPORTS.md): the
-- same report, line for line, importing DbFetchData instead of FetchData,
-- so `sales` and `targets` are `table`s scanned on the runner's connection
-- (ErmineSales on SQL Server, or the loader's SQLite twin) rather than
-- literals.  At tier xs its document equals FetchTopN's (TestDbReports).
-- The original's notes follow unchanged.
--
-- TOP N PLUS "OTHER", AND TWO SCANS IN ONE DO BLOCK.
--
-- A pie of every region is unreadable past a handful of slices; the usual
-- cure is the N largest and one "Other" slice that keeps the total exact.
-- The relational algebra here has no LIMIT and no "everything but the top
-- N", so this is a scan: `aggregateByGroup (sum amount) {region} amount`
-- totals each region IN SQL (one GROUP BY, one row per region; before F-1
-- this was `groupBy {region} (sumBy amount)`, which fetched every sale row
-- and summed in memory), `scanInOrder` delivers those totals largest first,
-- and `take`/`drop` split them.  The second scan reads the targets, and a
-- count over both lists says how many regions met theirs.  `scan` /
-- `scanInOrder` under `runScan` are `scanRelation` in continuation-monad
-- form, so the two reads sit in one `do` block instead of nesting.
--
--   {"params": {"keep": 2}}   north, east, Other (= south + west)

import Bool
import Eq
import Field
import Int
import Json using type Inline; Inline
import Layout.Doc
import Layout.Fetch
import Layout.Widgets.Format
import Layout.Widgets.Chart
import Layout.Widgets.PieChart
import List using {take; drop; length; sum'; map_List; filter; any; (++); empty_Bracket; cons_Bracket}
import Primitive
import Relation
import Relation.Row hiding empty_Bracket; cons_Bracket
import Relation.Sort as Srt
import Syntax.Do
import DbFetchData

data Query = Query { keep : Int }

-- one SQL `GROUP BY region` with `SUM(amount)` written back into `amount`
-- (F-1): `aggregateByGroup` lowers to the relational AggregateByGroup, so the
-- database returns one row per region; `groupBy` would fetch every sale row
-- and total them in memory, because its per-group function is arbitrary.
byRegion : [region, amount]
byRegion = aggregateByGroup_Aggregate (sum_Aggregate amount) {region} amount sales

report : Query -> Fetch Node
report q = runScan (do
  ranked <- scanInOrder (append_Srt (invert_Srt (ordering_Srt {amount})) (ordering_Srt {region})) byRegion
  goals  <- scan targets
  unit (let top    = take (keep q) ranked
            other  = sum' (map_List (r -> r ! amount) (drop (keep q) ranked))
            slices = relation (map_List (r -> { region = r ! region, amount = r ! amount }) top
                               ++ [ { region = "Other", amount = other } ])
            met    = length (filter (t -> any (r -> r ! region == t ! region && r ! amount >= t ! target) ranked)
                                    goals)
        in done (vflow
             [ pieChart (pieChartOf (PieSource "Sales by region" "Sales" region amount
                                                   Nothing Nothing Nothing
                                                   Default (Currency False False "$" 2)
                                                   (ChartLegendOptions LegendRightTable) (ChartRenderHints True)
                                                   (Inline slices)))
             , rawWidget "metTargets" met ])))
