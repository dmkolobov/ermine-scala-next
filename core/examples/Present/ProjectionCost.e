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

   MEASURED on this module, on THIS compiler, with the compiler's own counters
   (`-Dermine.rowTrace -Dermine.rowTrace.draws=true`; loaded as `Helpers.e` +
   this file). Analysis in `tracker/loopmodel/S4-DESIGN.md`; the round-1 figures
   in `E4-EXAMPLES.md` §4.10 were model runs at one id base and read a few per
   cent high.

       reads   input partitions   draws   saturated set   splits
         2            2               3          5          0
         3            3              30         19          0
         4            4             207         65          0
         5            5           1,230        211          0
         6            6           6,783        665          0
         7            7        BUDGET EXHAUSTED at 20,009 -- see shouldfail/proj01

   Every draw is a `Resolution` step and none is a split, and the whole ladder
   is reported at `ProjectionCost.e(1:1)` because these are the module's own
   inferred binding types.

   BOTH COLUMNS ARE CLOSED FORMS, exact at every row: the saturated set is the
   set of strictly nested pairs of subsets of the N fields, `3^N - 2^N`, and the
   draws are the same-left-hand-side pairs the loop is offered,

       D(N) = (5^N - 3*3^N + 2*2^N) / 2

   so the cost of one more read tends to FIVE TIMES, not six (10.0, 6.9, 5.94,
   5.51, 5.29 ...). **Seven reads of one record exhausts the adopted
   `-Dermine.solveBudget=20000`**: D(7) is 35,910. Not a wide table, not a join,
   not a chart: seven `p ! field` in one lambda. `proj6` alone is 34 % of the
   budget and is the costliest solve in the whole of `core/examples/Present`.

   ---------------------------------------------------------------------------
   THE FIX, and it is the same rule `Helpers.e` preaches everywhere else

   `proj5Pinned` reads the SAME five fields, and carries a hand-written
   signature saying what the parameter row is:

       forall r o. r <- ((| pAlpha, pBeta, pGamma, pDelta, pEpsilon |), o)
                => {..r} -> String

   **It draws nothing at all** -- it is one of the 434 zero-draw solves in this
   module. The partition is given rather than discovered, so there is nothing to
   close. One line of signature turns 1,230 draws into 0.

   The CALL SITES are cheap either way (together they draw 1), because
   `sample`'s row is concrete: the cost is entirely in
   inferring the lambda's type, which is where a library's signature is decided.

   That is why `Present/WriterOutputs.e`'s `reportFor` is worth reading twice:
   its parameter row is inferred, and the REPL prints the constraint it inferred
   (`(exists b. a <- ((|pMinValue, pRegion, pTitle|), b))`) — three reads, and
   already 30 draws. At five it is 1,230; at seven the report does not compile.
   Note WHAT it prints: the residual is the SINGLE top partition. The compiler
   already knows the answer is one partition and spends the whole lattice
   re-deriving it.

   ---------------------------------------------------------------------------
   WHERE THIS BITES IN THE REST OF THE GROUP

   `Present/ValidationReport.e(214:14)` is the costliest HAND-WRITTEN solve in
   this directory -- everything above it is this module -- at 213 draws in a
   whole-group load (209 loaded with `Helpers.e` alone; the ambient environment
   moves it a little), all of them `Resolution` steps and none a split. It reads
   its parameter record five times, but only FOUR of the five concrete parts are
   pairwise incomparable, so it sits on the N = 4 rung: it costs 213 rather
   than 1,230 because `Layout.Validation`'s `FormValidator r` fixes `r` to a
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

-- Three. Thirty draws -- an order of magnitude for one more field.
proj3 p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)

-- Four. Two hundred and seven.
proj4 p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)
                       ++_String (p ! pDelta)

-- Five. One thousand two hundred and thirty.
proj5 p = (p ! pAlpha) ++_String (p ! pBeta) ++_String (p ! pGamma)
                       ++_String (p ! pDelta) ++_String (p ! pEpsilon)

-- Six. Six thousand seven hundred and eighty-three -- a third of the budget for
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
