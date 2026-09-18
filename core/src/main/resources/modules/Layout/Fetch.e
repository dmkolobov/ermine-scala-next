module Layout.Fetch where

-- A report that needs ROWS while it is being built.
--
-- `Layout.Doc.Node` is pure wire data: a relation inside a widget's props is
-- a plan that the document writer scans AFTER the report has been evaluated
-- (json/Runner.scala).  Nothing in `Params -> Node` ever sees a row.  The
-- old `Layout.Report.scanRelation` did: it executed a relation while the
-- layout was being built and handed the rows to a continuation as a
-- `List {..r}`, so a heading could carry a total, a layout could take its
-- shape from the data, and a list transformed in memory could go back into
-- SQL through `Relation.relation`.
--
-- `Fetch a` is that continuation with a place to live.  A report is
--
--     report : Params -> Fetch Node
--
-- and the runner interprets it: `Done n` is the document, `Scan` is one
-- relation to execute in the given order, whose rows the runner feeds to
-- the continuation before going on.  `Fetch` is NOT a `Node`, so the wire
-- and the client's schema are untouched, and a scan cannot sit inside a
-- `vflow`: hoist it,
--
--     scanRelation r (rows -> done (vflow [a, k rows]))
--
-- or use `scan` / `runScan`, the same in continuation-monad clothing, to
-- read several relations in one `do` block.  Every relation that survives
-- into the final Node is still a plan and is delivered as the request asks.
--
-- There is no Monad instance for `Fetch` and none is needed: `Relation.Scan`
-- only wants a runner over a fixed result type (`runner`, below), and
-- `Cont` is a monad over the continuation, not over `a`.

import Native.List
import Native.Record
import Native.Relation
import Control.Monad
import Control.Monad.Cont
import Function
import List using map_List
import Relation.Sort using {type Sort; type Sort#; toSort#; empty}
import Relation.Scan as S

-- | The order the rows come in (`Sort#`), the plan (`Relation#`), and what
-- to do with the rows.  The row type is erased the way the old writer's
-- `scanRelationDMTL` erased it: `Record#` is the runtime record, and
-- `scanRelationInOrder` puts the `{..r}` back with `unsafeRecordIn#`.
data Fetch a = Done a
             | Scan Sort# Relation# (List Record# -> Fetch a)

done : a -> Fetch a
done = Done

-- | Execute a relation and hand its rows, in no particular order, to the
-- continuation.
scanRelation : Relational rel => rel r -> (List {..r} -> Fetch a) -> Fetch a
scanRelation r f = scanRelationInOrder empty r f

-- | Execute a relation and hand its rows, sorted as `srt` says, to the
-- continuation: what a running total, a rank or a top-N needs, and what no
-- relational aggregate can say (there is no order inside a group).
scanRelationInOrder : (Has r s, Relational rel) => Sort s -> rel r -> (List {..r} -> Fetch a) -> Fetch a
scanRelationInOrder srt r f = Scan (toSort# srt) (relation# r) (rows -> f (map_List unsafeRecordIn# rows))

-- | `scanRelation` as a continuation, for a `do` block under `runScan`:
--
--     report p = runScan (do
--       sales   <- scan salesRel
--       targets <- scan targetsRel
--       unit (done (vflow [..])))
scan : Relational rel => rel r -> monad -> Cont (Fetch a) (List {..r})
scan r _ = Cont (scanRelation r)

scanInOrder : (Has r s, Relational rel) => Sort s -> rel r -> monad -> Cont (Fetch a) (List {..r})
scanInOrder srt r _ = Cont (scanRelationInOrder srt r)

runScan : forall a r . (Monad (Cont r) -> Cont (Fetch a) (Fetch a)) -> Fetch a
runScan report = runCont (report contMonad) id

-- | The `Relation.Scan` runner: `groupBy_S runner`, `sumBy_S runner`,
-- `count_S runner` and `fromRelation_S runner` work over a `Fetch a` the
-- way `Layout.Scan` made them work over a `Report f z`.
runner : forall a . RunScan_S List (Fetch a)
runner = RunScan_S scanRelation
