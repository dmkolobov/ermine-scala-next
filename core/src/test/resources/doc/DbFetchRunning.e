module DbFetchRunning where

-- THE DB-BACKED TWIN of FetchRunning (DB-PLAN D7, tracker/db/REPORTS.md): the
-- same report, line for line, importing DbFetchData instead of FetchData,
-- so `sales` and `targets` are `table`s scanned on the runner's connection
-- (ErmineSales on SQL Server, or the loader's SQLite twin) rather than
-- literals.  At tier xs its document equals FetchRunning's (TestDbReports).
-- The original's notes follow unchanged.
--
-- A LIST FOLDED IN ERMINE, JOINED BACK IN SQL.
--
-- The point of this example is the ROUND TRIP, not the running total: the
-- rows come sorted by `day` through `scanRelationInOrder`, a fold in Ermine
-- gives each one the total so far and its sequence number, `relation` turns
-- the list back into a relation, and `join` takes THAT to the targets -- in
-- SQL, on the same connection, as a `VALUES` literal joined to a table.
--
-- A running total and a row number by themselves do NOT need this:
-- `Relation.Windowed` computes them in SQL (`windowedAggregate` over a
-- window sorted by `day`, `rowNumber`).  Read the fold as a stand-in for any
-- per-row Ermine computation the algebra cannot express.
--
--   {"params": {"newestFirst": false}}   day order, running up to 12682.0
--   {"params": {"newestFirst": true}}    newest first

import Bool
import Field
import Layout.Doc
import Layout.Fetch
import Layout.Widgets.Format
import Layout.Widgets.Table
import List using {foldl; reverse; empty_Bracket; cons_Bracket}
import Pair
import Primitive
import Relation
import Relation.Row hiding empty_Bracket; cons_Bracket
import Relation.Sort as Srt
import DbFetchData

field runningAmount : Double
field seqNo : Int

data Query = Query { newestFirst : Bool }

-- the fold: rows in the order they came, each with the total so far and
-- its position
withRunning : List {region, day, amount, units}
           -> List {region, day, amount, runningAmount, seqNo}
withRunning rows = reverse (snd (foldl step ((0.0, 0), []) rows))
  where step ((tot, n), acc) r =
          let tot' = tot + (r ! amount)
              n'   = n + 1
          in ((tot', n'), { region = r ! region, day = r ! day, amount = r ! amount,
                            runningAmount = tot', seqNo = n' } :: acc)

order : Query -> Sort_Srt (|day|)
order q = if (newestFirst q) (invert_Srt (ordering_Srt {day})) (ordering_Srt {day})

report : Query -> Fetch Node
report q =
  scanRelationInOrder (order q) sales (rows ->
    let running = relation (withRunning rows)   -- back into SQL as a literal
        joined  = join running targets          -- a SQL join on `region`
    in done (tabular (simpleTable
               [ withHeader "#" (numCol seqNo Default)
               , withHeader "Region" (col region)
               , withHeader "Day" (col day)
               , withHeader "Amount" (numCol amount (Currency False False "$" 2))
               , withHeader "Running" (numCol runningAmount (Currency False False "$" 2))
               , withHeader "Target" (numCol target (Currency False False "$" 0)) ]
               (joined # {seqNo, region, day, amount, runningAmount, target}))))
