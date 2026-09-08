module Present.SevenReads where

{- SEVEN READS of one unannotated record parameter -- the shape that used to trip the
   DRAW BUDGET, and the reason `-Dermine.topNormalise` is on by default.

   `Record.(!)` is a row partition -- `(!) : t <- (r, s) => {..t} -> Field r a -> a` --
   so seven reads are seven partitions sharing a left-hand side, and closing them against
   one another by `resolution` alone costs `D(N) = (5^N - 3*3^N + 2*2^N)/2` draws:
   3 / 30 / 207 / 1,230 / 6,783 for two to six reads (`ProjectionCost.e`), and 35,910 for
   seven -- past `-Dermine.solveBudget=20000` at 20,009.

   UNTIL 2026-09-08 this module lived at `shouldfail/proj01_seven_reads.e` and was REJECTED
   with the resource diagnostic (verbatim):

     Row solver resource limit reached (this is NOT a type error): the row
     constraint solver drew 20009 fresh row variables at this signature, past
     the -Dermine.solveBudget=20000 limit, so it was stopped rather than left
     to run.  Raise the limit with -Dermine.solveBudget=<n>, simplify the row
     constraints at this signature, or report it.

   WHAT CHANGED. Stage S4's WRITTEN-PARTITION NORMALISATION (`-Dermine.topNormalise`,
   default ON since 2026-09-08): when one row variable carries three or more reads with
   distinct, pairwise-incomparable fields and no concrete row, the solver replaces them by
   the single partition a careful user would have written --
   `p <- (c, (| qAlpha, ..., qEta |))` plus one re-expression per read -- BEFORE the loop
   runs. The seven reads cost ONE pre-loop draw and no loop draws (one `tnorm` record in
   the row trace), and the module compiles in a few hundredths of a second. The rewrite is
   proved satisfiability-equivalent in both directions and tied to the executable model
   (`tracker/lean/Rowpartition/Loop/TopNormalise.lean`); see `tracker/loopmodel/S4-CHANGE.md`.

   TO SEE THE OLD BEHAVIOUR (the budget diagnostic above, in 2.7 s):

       ERMINE_JAVA_OPTS="-Dermine.topNormalise=false" \
         bin/ermine core/examples/Present/SevenReads.e

   The written partition is still the better spelling -- it is what the solver now
   writes for you -- see `ProjectionCost.proj5Pinned` / `proj6Pinned`.
-}

import Prelude
import Syntax.List

field qAlpha, qBeta, qGamma, qDelta, qEpsilon, qZeta, qEta : String

-- Compiles: seven partitions on one unannotated parameter row, normalised to one.
sevenReads p = (p ! qAlpha) ++_String (p ! qBeta) ++_String (p ! qGamma)
                            ++_String (p ! qDelta) ++_String (p ! qEpsilon)
                            ++_String (p ! qZeta) ++_String (p ! qEta)
