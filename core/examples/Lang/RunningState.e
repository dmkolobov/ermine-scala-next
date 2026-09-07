module Lang.RunningState where

{- A RUNNING BALANCE THREE WAYS: `Control.Monad.State` over a list, the same fold
   driven from the relation by `scanRelation`, and the relational aggregate that
   cannot do it.

   Fact: postings (13 fields: postingSeq, postingDate, postingRef, postingKind,
         ledgerCode, ledgerLabel, teamName, clerkName, currencyCode, grossAmt,
         feeAmt, netAmt, postedMark) — the group's wide table.

   WHY THIS FILE EXISTS. A running total is the smallest report an SQL-shaped language
   cannot write: `groupBy` has no order, so `sum` over a group gives ONE number, not one
   per row. Ermine's answer is that the value level is a real programming language --
   you scan the relation into a `List {..r}` and fold. This file is about the fold.

     `withState`   : ({..r} -> s -> (a, s)) -> s -> List {..r} -> (List a, s)
     `scanRows`    : (s -> {..r} -> s) -> s -> List {..r} -> List s
     `withRunning` : t <- (r, c) => Field c n -> (n -> {..r} -> n) -> n
                                 -> List {..r} -> List {..t}

   All three are `Control.Monad.State` underneath, and `withRunning` is the one that
   carries a row: `t <- (r, c)` says the output row is the input row plus EXACTLY the
   new column, so a name the input already has is a compile error, not a silent
   overwrite (`Lang/shouldfail/lang03_running_column_exists.e`).

   THE STATE MONAD IS TWENTY LINES. `Control/Monad/State.e` is

       data State s a = State (s -> (a, s))
       stateMonad = Monad (a -> State (s -> (a, s)))
                          ((State x) f -> State (s -> case x s of (v, s') -> runState (f v) s'))

   and there is no `modify`, no `gets`, no `evalState`, no `execState` and no `MonadState`
   — because there are no classes. `get` and `put` are values, and `StateT` is there too
   with `stateTMonad : Monad m -> Monad (StateT s m)`, used at the bottom of this file.

   SHAPES EXERCISED
     * `withRunning`'s `t <- (r, c)` at a 13-column input row: the widest row-under-a-
       monad instance in the group.
     * `Control.Traversable.mapM` at `List` with `stateMonad` — the row variable travels
       under `State s` for the whole traversal.
     * `Layout.Report.scanRelation` and `scanRelationInOrder`: the bridge that takes the
       relation to the list, so the fold runs on REAL relational output inside a report.
     * `traverseRows`, `checkedRel` and `showRows` at the same 13-column row, so three
       different type constructors carry it in one file.
     * `Control.Monoid` and `mproduct`: two measures accumulated in one pass.
     * `StateT s Maybe`: the fold that can FAIL, with `Control.Monad.State.stateTMonad`.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/RunningState.e
   >> runningRows        -- 14 columns: the 13 plus runningNet
   >> closingBalance
   >> netAndFees
   >> feeRatios          -- Nothing: one posting has a zero gross
   >> grossFeeRatios
   >> checkedPostings
   >> postingMarkdown
   >> guardedRun         -- Just (…, 90947.07); `overdrawnRun` is Nothing
   >> balanceReport
-}

import Prelude
import Syntax.List
import Control.Monad as M
import Control.Monad.State as St
import Control.Monoid as Mo
import Control.Traversable as T
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Sort as Srt
import List as L
import String as S
import Date as D
import Maybe as Mb
import Lang.Helpers

field postingSeq   : Int
field postingDate  : Date
field postingRef   : String
field postingKind  : String
field ledgerCode   : String
field ledgerLabel  : String
field teamName     : String
field clerkName   : String
field currencyCode : String
field grossAmt     : Double
field feeAmt       : Double
field netAmt       : Double
field postedMark  : String
field runningNet   : Double

-- ---------------------------------------------------------------------------
-- 1. The postings. Thirteen columns, in sequence order.

postingList : List {postingSeq, postingDate, postingRef, postingKind, ledgerCode,
                    ledgerLabel, teamName, clerkName, currencyCode, grossAmt, feeAmt,
                    netAmt, postedMark}
postingList = [
  { postingSeq = 1, postingDate = yyyymmdd_D 2011 4 1, postingRef = "PST-4401",
    postingKind = "OPENING", ledgerCode = "L100", ledgerLabel = "Sales ledger",
    teamName = "Sales", clerkName = "Ines Halloran", currencyCode = "USD",
    grossAmt = 250000.00, feeAmt = 0.00, netAmt = 250000.00, postedMark = "Y" },
  { postingSeq = 2, postingDate = yyyymmdd_D 2011 4 5, postingRef = "PST-4402",
    postingKind = "INVOICE", ledgerCode = "L100", ledgerLabel = "Sales ledger",
    teamName = "Sales", clerkName = "Ines Halloran", currencyCode = "USD",
    grossAmt = -84500.00, feeAmt = 125.00, netAmt = -84625.00, postedMark = "Y" },
  { postingSeq = 3, postingDate = yyyymmdd_D 2011 4 8, postingRef = "PST-4403",
    postingKind = "RECEIPT", ledgerCode = "L100", ledgerLabel = "Sales ledger",
    teamName = "Purchasing", clerkName = "Nnamdi Achebe", currencyCode = "USD",
    grossAmt = 43200.00, feeAmt = 64.80, netAmt = 43135.20, postedMark = "Y" },
  { postingSeq = 4, postingDate = yyyymmdd_D 2011 4 12, postingRef = "PST-4404",
    postingKind = "INVOICE", ledgerCode = "L200", ledgerLabel = "Purchase ledger",
    teamName = "Purchasing", clerkName = "Nnamdi Achebe", currencyCode = "USD",
    grossAmt = -160000.00, feeAmt = 240.00, netAmt = -160240.00, postedMark = "N" },
  { postingSeq = 5, postingDate = yyyymmdd_D 2011 4 19, postingRef = "PST-4405",
    postingKind = "FEE", ledgerCode = "L200", ledgerLabel = "Purchase ledger",
    teamName = "Ops", clerkName = "Priya Raghunathan", currencyCode = "USD",
    grossAmt = 0.00, feeAmt = 1850.00, netAmt = -1850.00, postedMark = "Y" },
  { postingSeq = 6, postingDate = yyyymmdd_D 2011 4 22, postingRef = "PST-4406",
    postingKind = "RECEIPT", ledgerCode = "L100", ledgerLabel = "Sales ledger",
    teamName = "Sales", clerkName = "Ines Halloran", currencyCode = "USD",
    grossAmt = 96750.00, feeAmt = 145.13, netAmt = 96604.87, postedMark = "Y" },
  { postingSeq = 7, postingDate = yyyymmdd_D 2011 4 28, postingRef = "PST-4407",
    postingKind = "INVOICE", ledgerCode = "L300", ledgerLabel = "Treasury",
    teamName = "Ops", clerkName = "Priya Raghunathan", currencyCode = "USD",
    grossAmt = -52000.00, feeAmt = 78.00, netAmt = -52078.00, postedMark = "N" }
  ]_L

postings : Relation (|postingSeq, postingDate, postingRef, postingKind, ledgerCode,
                      ledgerLabel, teamName, clerkName, currencyCode, grossAmt, feeAmt,
                      netAmt, postedMark|)
postings = relation postingList

-- ---------------------------------------------------------------------------
-- 2. The State fold: one new column, thirteen kept.

runningRows : List {postingSeq, postingDate, postingRef, postingKind, ledgerCode,
                    ledgerLabel, teamName, clerkName, currencyCode, grossAmt, feeAmt,
                    netAmt, postedMark, runningNet}
runningRows = withRunning runningNet (bal t -> bal + (t ! netAmt)) 0.0 postingList

withRunningRel : Relation (|postingSeq, postingDate, postingRef, postingKind,
                            ledgerCode, ledgerLabel, teamName, clerkName, currencyCode,
                            grossAmt, feeAmt, netAmt, postedMark, runningNet|)
withRunningRel = relation runningRows

-- | The final state on its own. `withState` returns both halves; the running column
--   above throws the second away and this throws the first away.
closingBalance : Double
closingBalance = snd (withState (t -> s -> ((), s + (t ! netAmt))) 0.0 postingList)

-- | Just the running values, without rebuilding the rows.
balanceTrail : List Double
balanceTrail = scanRows (s t -> s + (t ! netAmt)) 0.0 postingList

-- ---------------------------------------------------------------------------
-- 3. Two measures in one pass: `Control.Monoid.mproduct`.

netAndFees : (Double, Double)
netAndFees = foldRows (mproduct_Mo sumMonoid sumMonoid) (t -> (t ! netAmt, t ! feeAmt))
                      postingList

-- | The biggest single posting and how many there are, again in one pass.
extremes : (Double, Int)
extremes = foldRows (mproduct_Mo maxMonoid countMonoid) (t -> (t ! grossAmt, 1))
                    postingList

-- | And the other three row traversals, at the group's widest row: `traverseRows` in
--   `Maybe`, `checkedRel` in the accumulating `Either`, and `showRows` rendering the
--   13-column table to markdown. Each carries the row variable `r` under a different
--   type constructor and none of them names a column but the one it measures.

feeRatios : Maybe (List Double)
feeRatios = traverseRows maybeAp (t -> if ((t ! grossAmt) == 0.0) Nothing
                                          (Just ((t ! feeAmt) / (t ! grossAmt)))) postingList

-- | The same traversal over the rows that HAVE a gross, so it succeeds. (It was called
--   `postedRatios` until E5's reviewer pointed out that it filters on `grossAmt` and
--   has nothing to do with `postedMark` -- L-13.)
grossFeeRatios : Maybe (List Double)
grossFeeRatios = traverseRows maybeAp (t -> if ((t ! grossAmt) == 0.0) Nothing
                                               (Just ((t ! feeAmt) / (t ! grossAmt))))
                              (filter_L (t -> (t ! grossAmt) != 0.0) postingList)

postingChecks : {postingSeq, postingDate, postingRef, postingKind, ledgerCode,
                 ledgerLabel, teamName, clerkName, currencyCode, grossAmt, feeAmt,
                 netAmt, postedMark} -> List Err
postingChecks t =
  (if ((t ! feeAmt) < 0.0)
      (("feeAmt", (t ! postingRef) ++_S ": negative fee") :: Nil) Nil)
  ++_L
  (if ((t ! postedMark) != "Y" && (t ! postedMark) != "N")
      (("postedMark", (t ! postingRef) ++_S ": bad mark") :: Nil) Nil)

checkedPostings : Either (List Err) (Relation (|postingSeq, postingDate, postingRef,
                                                postingKind, ledgerCode, ledgerLabel,
                                                teamName, clerkName, currencyCode,
                                                grossAmt, feeAmt, netAmt, postedMark|))
checkedPostings = checkedRel postingChecks postingList

-- | `showRows` at the 13-column row. NOTE THE COST: this cell lambda projects the record
--   five times against a row VARIABLE and is one of the three most expensive solves in
--   the E-series corpus -- **1,230 draws**, exactly as many as
--   `TextTables.catalogueMarkdown` and `catalogueAscii`. All three are the SAME number,
--   not three numbers within 1 %: five reads of one unannotated record cost
--   `(5^5 - 3*3^5 + 2*2^5)/2 = 1,230`, whatever else is in the expression. (Measured with
--   `-Dermine.rowTrace.draws=true`; the round-1 figures 1,233 / 1,241 were model runs at
--   one id base.) `postingMarkdownPinned` below is the same table with the argument
--   annotated: **no draws at all**. See `Lang/ProjectionCliff.slow` and
--   `tracker/loopmodel/S4-DESIGN.md`.
postingMarkdown : String
postingMarkdown =
  showRows (["Seq", "Ref", "Kind", "Net", "Running"]_L)
           (t -> [ toString (t ! postingSeq), t ! postingRef, t ! postingKind
                 , toString (t ! netAmt), toString (t ! runningNet) ]_L)
           runningRows

-- | The annotated spelling, for comparison. Zero draws instead of 1,230.
postingMarkdownPinned : String
postingMarkdownPinned =
  showRows (["Seq", "Ref", "Kind", "Net", "Running"]_L)
           ((t : {postingSeq, postingDate, postingRef, postingKind, ledgerCode,
                  ledgerLabel, teamName, clerkName, currencyCode, grossAmt, feeAmt,
                  netAmt, postedMark, runningNet})
              -> [ toString (t ! postingSeq), t ! postingRef, t ! postingKind
                 , toString (t ! netAmt), toString (t ! runningNet) ]_L)
           runningRows

-- ---------------------------------------------------------------------------
-- 4. A fold that can FAIL: `StateT s Maybe`.
--
-- `stateTMonad : Monad m -> Monad (StateT s m)` is the transformer, and `Maybe` is the
-- base. The fold refuses as soon as the running balance would go negative, and the
-- whole traversal returns `Nothing` — which a pure `State` fold cannot express.

guardedStep : {postingSeq, postingDate, postingRef, postingKind, ledgerCode,
               ledgerLabel, teamName, clerkName, currencyCode, grossAmt, feeAmt,
               netAmt, postedMark} -> StateT_St Double Maybe Double
guardedStep t = StateT_St (s ->
  let s' = s + (t ! netAmt)
  in if (s' < 0.0) Nothing (Just (s', s')))

guardedRun : Maybe (List Double, Double)
guardedRun = runStateT_St (mapMRows (stateTMonad_St maybeMonad) guardedStep postingList) 0.0

-- | The same fold on a book that goes overdrawn: `Nothing`.
overdrawnRun : Maybe (List Double, Double)
overdrawnRun = runStateT_St (mapMRows (stateTMonad_St maybeMonad) guardedStep
                                      (filter_L (t -> (t ! postingSeq) != 1) postingList)) 0.0

-- ---------------------------------------------------------------------------
-- 5. What the RELATION can and cannot do.
--
-- `groupBy {ledgerCode} (sumBy netAmt)` is one number per ledger: correct, and not a
-- running balance. There is no ordering inside a group, so no relational aggregate in
-- this stdlib produces the column above. What the relation CAN do is deliver the rows
-- in order to the fold, and that is `scanRelationInOrder`.

byLedger : Mem (|ledgerCode, netAmt|)
byLedger = postings |> groupBy {ledgerCode} (sumBy netAmt)

unposted : Relation (|postingSeq, postingDate, postingRef, postingKind, ledgerCode,
                      ledgerLabel, teamName, clerkName, currencyCode, grossAmt,
                      feeAmt, netAmt, postedMark|)
unposted = postings |> filter_Pred (col_Op postedMark ==_Pred prim_Op "N")

-- | The fold driven from the relation. `scanRelationInOrder` executes the relation,
--   sorts it, hands the rows to the continuation as a `List {..r}`, and the SAME
--   `withRunning` runs on them. This is the one path that would still be right if the
--   postings lived in a database.
scannedBalance : Report f z
scannedBalance =
  scanRelationInOrder (ordering_Srt {postingSeq}) postings (rows ->
    tabular Nothing (relation (withRunning runningNet (bal t -> bal + (t ! netAmt))
                                           0.0 rows)
                     # {postingSeq, postingRef, netAmt, runningNet}))

balanceReport : Report f z
balanceReport = vflow [
    text "## Ledger L100/L200/L300 - April 2011",
    tabular Nothing (postings # {postingSeq, postingDate, postingRef, postingKind,
                                 ledgerCode, netAmt}),
    text "### Running balance, folded in `State` from the list",
    tabular Nothing (withRunningRel # {postingSeq, postingRef, netAmt, runningNet}),
    text "### Running balance, folded from the RELATION by `scanRelationInOrder`",
    scannedBalance,
    text "### Net by ledger - what the relational aggregate can say",
    tabular Nothing byLedger,
    text "### Unposted",
    tabular Nothing (unposted # {postingRef, clerkName, netAmt, postedMark})
  ]_L
