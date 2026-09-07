module Present.ProjectionCost where

{- WHAT A PARAMETERISED REPORT COSTS THE ROW SOLVER, and the one-line fix.

   This module has no data, no relation and no presentation. It is five lambdas
   that read fields out of one record, and a sixth that reads five fields out of
   a record whose row is WRITTEN DOWN. It is here because measuring it is the
   most useful thing this directory can tell a person who is about to write a
   production report.

   ---------------------------------------------------------------------------
   THE SHAPE

   `Record.(!)` is a row partition, not a lookup:

       (!) : t <- (r, s) => {..t} -> Field r a -> a

   So `p ! someField` says "the parameter row `t` splits into this one field and
   a remainder `s`". Read N fields out of one UNANNOTATED parameter and the
   solver gets N partitions that share a left-hand side and have N different
   right-hand sides, and it must close them against one another. That closure is
   not linear.

   MEASURED on this module (`-Dermine.rowTrace`, replayed through
   `tracker/lean/.lake/build/bin/looptrace --depth`; numbers in
   `tracker/loopmodel/E4-EXAMPLES.md` §4.10):

       reads   input partitions   draws     steps   splits
         2            2               3         5       0
         3            3              30        19       0
         4            4             212        72       0
         5            5           1,232       214       0
         6            6           6,804       686       0
         7            7        BUDGET EXHAUSTED -- see shouldfail/proj01

   Every draw is a `Resolution` step and none is a split, and the whole ladder
   is reported at `ProjectionCost.e(1:1)` because these are the module's own
   inferred binding types.

   Roughly SIX TIMES per additional read, and **seven reads of one record
   exhausts the adopted `-Dermine.solveBudget=20000`**. Not a wide table, not a
   join, not a chart: seven `p ! field` in one lambda. `proj6` alone is 34 % of
   the budget and is the costliest solve in the whole of `core/examples/Present`.

   ---------------------------------------------------------------------------
   THE FIX, and it is the same rule `Helpers.e` preaches everywhere else

   `proj5Pinned` reads the SAME five fields, and carries a hand-written
   signature saying what the parameter row is:

       forall r o. r <- ((| pAlpha, pBeta, pGamma, pDelta, pEpsilon |), o)
                => {..r} -> String

   **It draws nothing at all** -- it is one of the 434 zero-draw solves in this
   module. The partition is given rather than discovered, so there is nothing to
   close. One line of signature turns 1,232 draws into 0.

   The CALL SITES are cheap either way (`viaInference` and `viaSignature` below
   draw 1 and 3), because `sample`'s row is concrete: the cost is entirely in
   inferring the lambda's type, which is where a library's signature is decided.

   That is why `Present/WriterOutputs.e`'s `reportFor` is worth reading twice:
   its parameter row is inferred, and the REPL prints the constraint it inferred
   (`(exists b. a <- ((|pMinValue, pRegion, pTitle|), b))`) — three reads, and
   already 33 draws. At five it is 1,243; at seven the report does not compile.

   ---------------------------------------------------------------------------
   WHERE THIS BITES IN THE REST OF THE GROUP

   `Present/ValidationReport.e(214:14)` is the costliest HAND-WRITTEN solve in
   this directory -- everything above it is this module -- at 222 draws, all of them `Resolution` steps and
   none a split. It reads its parameter record five times. It costs 218 rather
   than 1,243 because `Layout.Validation`'s `FormValidator r` fixes `r` to a
   CONCRETE four-field row before the reads happen — so that call site is the
   cheap case, not the expensive one, and the expensive one is what a reader
   writes when they hand their report a bare record.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/ProjectionCost.e
     >> :type proj6
     >> :type proj5Pinned
-}

import Prelude
import Syntax.List

field pAlpha, pBeta, pGamma, pDelta, pEpsilon, pZeta : String

-- ------------------------------------------------- the ladder, unannotated

-- Two reads. Two partitions, three draws.
proj2 p = (p ! pAlpha) ++_String (p ! pBeta)

-- Three. Thirty-three draws -- an order of magnitude for one more field.
proj3 p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)

-- Four. Two hundred and seven.
proj4 p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)
                       ++_String (p ! pDelta)

-- Five. One thousand two hundred and forty-three.
proj5 p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)
                       ++_String (p ! pDelta) ++_String (p ! pEpsilon)

-- Six. Six thousand seven hundred and ninety-five -- a third of the budget for
-- one line of ordinary Ermine. Seven does not compile; see
-- `shouldfail/proj01_seven_reads.e`.
proj6 p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)
                       ++_String (p ! pDelta) ++_String (p ! pEpsilon)
                       ++_String (p ! pZeta)

-- --------------------------------------------------- the same five, pinned

-- The identical body under a written signature. `r <- ((| … |), o)` says the
-- parameter row is exactly these five fields plus whatever else the caller
-- carries -- which is what the five `!`s were going to force the solver to
-- discover, one partition at a time.
proj5Pinned : forall r o.
              r <- ((| pAlpha, pBeta, pGamma, pDelta, pEpsilon |), o)
           => {..r} -> String
proj5Pinned p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)
                             ++_String (p ! pDelta) ++_String (p ! pEpsilon)

-- And the six-field form, pinned, for the same reason. `proj6` above and
-- `proj6Pinned` here have the same body and differ by one line of type.
proj6Pinned : forall r o.
              r <- ((| pAlpha, pBeta, pGamma, pDelta, pEpsilon, pZeta |), o)
           => {..r} -> String
proj6Pinned p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)
                             ++_String (p ! pDelta) ++_String (p ! pEpsilon)
                             ++_String (p ! pZeta)

-- ----------------------------------------------------------- a call site

-- Both forms take the same argument, so a caller cannot tell them apart; only
-- the compiler can.
sample = { pAlpha = "a", pBeta = "b", pGamma = "c", pDelta = "d",
           pEpsilon = "e", pZeta = "f" }

viaInference = proj6 sample
viaSignature = proj6Pinned sample
