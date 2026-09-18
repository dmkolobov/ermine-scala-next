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
-- and the client's schema are untouched.
--
-- `Fetch Node` IS the report type (stage J3g): a report that never scans is
-- `Params -> Node` still, and the runner reads it as `done` of its value --
-- sugar, one interpreter either way.  A scan therefore does NOT have to be
-- hoisted above its layout.  `vflowF`, `hflowF`, `gridF` and `tabbedF` are
-- `Layout.Doc`'s combinators over `Fetch Node`, so
--
--     vflowF [ headlineOf "Sales" "north" amount sales, done (tabular t) ]
--
-- is a layout two of whose children scan, and a fragment of a report is an
-- ordinary function returning `Fetch Node` that the report composes.  The
-- lifts are plain functions -- `map_Fetch`, `bind_Fetch`, `sequence_Fetch`
-- -- and not a `Monad` instance: `Relation.Scan` only wants a runner over a
-- fixed result type (`runner`, below), and `Cont` is a monad over the
-- continuation, not over `a`.  `scan` / `runScan` are still there for
-- several reads in one `do` block.
--
-- ORDER.  `sequence_Fetch` scans left to right, and so do the layout lifts,
-- which are built on it: the scans of `vflowF [a, b]` happen in the order
-- the children are written (`TestRunner (fxl-order)`).  Every relation that
-- survives into the final Node is still a plan and is delivered as the
-- request asks.

import Native.List
import Native.Record
import Native.Relation
import Control.Monad
import Control.Monad.Cont
import Function
import Layout.Doc
import List using {map_List; zip; empty_Bracket; cons_Bracket}
import Pair
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

-- ---------------------------------------------------------------- lifts
--
-- Plain functions, not an instance: `Fetch` has one operation and the
-- runner interprets the constructors directly (design note 3.4c).

-- | Change what a `Fetch` produces, leaving its scans alone.
map_Fetch : (a -> b) -> Fetch a -> Fetch b
map_Fetch f (Done a)     = Done (f a)
map_Fetch f (Scan s r k) = Scan s r (rows -> map_Fetch f (k rows))

-- | Go on with what a `Fetch` produced.  The scans of `m` all happen before
-- any scan of `f a`.
bind_Fetch : Fetch a -> (a -> Fetch b) -> Fetch b
bind_Fetch (Done a) f     = f a
bind_Fetch (Scan s r k) f = Scan s r (rows -> bind_Fetch (k rows) f)

-- | Left to right: the scans happen in list order.
sequence_Fetch : List (Fetch a) -> Fetch (List a)
sequence_Fetch []        = Done []
sequence_Fetch (m :: ms) = bind_Fetch m (a -> map_Fetch (as -> a :: as) (sequence_Fetch ms))

-- | `Layout.Doc.vflow` over children that may scan.
vflowF : List (Fetch Node) -> Fetch Node
vflowF ns = map_Fetch vflow (sequence_Fetch ns)

-- | `Layout.Doc.hflow` over children that may scan.
hflowF : List (Fetch Node) -> Fetch Node
hflowF ns = map_Fetch hflow (sequence_Fetch ns)

-- | `Layout.Doc.grid` over cells that may scan: row by row, left to right.
gridF : List (List (Fetch Node)) -> Fetch Node
gridF rs = map_Fetch grid (sequence_Fetch (map_List sequence_Fetch rs))

-- | `Layout.Doc.tabbed` over tab contents that may scan.  The labels are
-- known before any scan; the contents are scanned in tab order.
tabbedF : List (String, Fetch Node) -> Fetch Node
tabbedF ts = map_Fetch (ns -> tabbed (zip (map_List fst ts) ns))
                       (sequence_Fetch (map_List snd ts))
