module FetchRunning where

-- A RUNNING TOTAL, FOLDED IN ERMINE, JOINED BACK IN SQL.
--
-- `groupBy {region} (sumBy amount)` is one number per region: correct, and
-- not a running total.  There is no order inside a relational aggregate,
-- so no aggregate in this stdlib produces a cumulative column or a row
-- number.  What the relation CAN do is deliver its rows in order, and that
-- is `scanRelationInOrder`: the rows come sorted by `day`, a fold gives
-- each one the total so far and its sequence number, `relation` turns the
-- list back into a relation, and `join` takes THAT to the targets -- in
-- SQL, on the same connection, as a `VALUES` literal joined to a table.
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
import FetchData

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
               [ numberColumn "seqNo" "#" Default
               , textColumn "region" "Region"
               , textColumn "day" "Day"
               , numberColumn "amount" "Amount" (Currency False False "$" 2)
               , numberColumn "runningAmount" "Running" (Currency False False "$" 2)
               , numberColumn "target" "Target" (Currency False False "$" 0) ]
               (joined # {seqNo, region, day, amount, runningAmount, target}))))
