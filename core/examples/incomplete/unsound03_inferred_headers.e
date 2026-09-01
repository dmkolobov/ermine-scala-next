module Incomplete.Unsound03 where

{- *** SOUNDNESS BUG (3 of 4): unsatisfiable, accepted.  This module LOADS. ***
   Default mode, -Dermine.genRules=all.

   The point of this one: NOT ONE CONSTRAINT IS HAND-WRITTEN.  There is no
   signature anywhere in the module.  Every partition below is emitted by the
   standard library -- `minus_Rw` (Relation/Row.e:35, `t <- (r, s)`) and
   `snoc_Rw` (Relation/Row.e:32, `r <- (r1, r2)`) -- and the unsatisfiable set
   is the solver's OWN inferred residual, which it then prints back at you.

   ------------------------------------------------------------------ scenario

   A ledger's header is `(|accountId, regionCode, productCode|)`.  You want to
   split its columns into two groups and hand each group to `project` /
   `groupBy` / `aggregateBy` as a header, with `accountId` on both halves so the
   two reports line up row for row.  So: take the caller's chosen columns, take
   everything else, and `snoc` the key onto each.  That is `keyedHalves`.

   ---------------------------------------------------------- what a user expects

   `accountId` is one of the three columns being divided up, so it is in one of
   the halves already and that half ends up with it twice.  This should not
   type-check.  `keyedHalvesOk` is the fix -- take the key out of the header
   before dividing -- and a user would expect the compiler to be the thing that
   tells them which of the two they wrote.

   ------------------------------------------------------------- what happens

   OBSERVED 2026-09-01, branch scala3-migration.  The module loads
   ("Importing module 'Incomplete.Unsound03'") and `:browse`
   reports these two inferred types (continuation lines joined):

     keyedHalves : forall (r: rho) (r1: rho) (r2: rho).
       (exists (s: rho). (|accountId, regionCode, productCode|) <- (s, r),
        r1 <- ((|accountId|), r), r2 <- ((|accountId|), s))
       => Row r -> (Row r1, Row r2)

     keyedHalvesOk : forall (r: rho) (r1: rho) (r2: rho).
       (exists (s: rho). (|regionCode, productCode|) <- (s, r),
        r1 <- ((|accountId|), r), r2 <- ((|accountId|), s))
       => Row r -> (Row r1, Row r2)

   They differ in one place: whether `accountId` is inside the row being split.
   The second set is satisfiable (r = (|regionCode|), s = (|productCode|)).  The
   first has no solution, for the reason proved in `unsound01_keyed_halves.e`.
   The solver hands both back as ordinary polymorphic types and reports no
   error, so the type it printed for `keyedHalves` is one that no instantiation
   can ever satisfy.

   ------------------------------------------------------- how far the bug travels

   Nothing recovers later, either: `leftHeaderOf` / `rightHeaderOf` below call
   `keyedHalves` and inherit the unsatisfiable set into THEIR inferred types,
   and all four appear in `:browse`.

   The one thing that does trip it is grounding: naming an actual column group
   for the left half.  `witness03_grounded_call.e` in this directory is this
   module's `keyedHalves` verbatim plus `keyedHalves (single_Rw regionCode)`,
   and it is REJECTED with
     witness03_grounded_call.e:29:1: Fields appear twice in row: Set(Incomplete.Witness03.accountId)
   which is the compiler agreeing, after the fact, that the type it just
   published was uninhabited.
-}

import Prelude
import Relation.Row as Rw

field accountId, regionCode, productCode : Int

ledgerHeader : Row (|accountId, regionCode, productCode|)
ledgerHeader = append_Rw (single_Rw accountId)
                         (append_Rw (single_Rw regionCode) (single_Rw productCode))

-- THE BUG: divide the ledger's columns in two and put the account key on each
-- half, so the two halves can be reported side by side.  `accountId` is one of
-- the columns being divided, so one half gets it twice.  Compiles.
keyedHalves leftCols =
  let rightCols = minus_Rw ledgerHeader leftCols
  in ( snoc_Rw leftCols  accountId
     , snoc_Rw rightCols accountId )

-- THE FIX, for contrast: drop the key from the header before dividing.
-- Also compiles, and the compiler cannot tell you which of the two you meant.
keyedHalvesOk leftCols =
  let body      = minus_Rw ledgerHeader (single_Rw accountId)
      rightCols = minus_Rw body leftCols
  in ( snoc_Rw leftCols  accountId
     , snoc_Rw rightCols accountId )

-- The unsatisfiable set propagates into everything downstream.
leftHeaderOf  cols = fst (keyedHalves cols)
rightHeaderOf cols = snd (keyedHalves cols)
