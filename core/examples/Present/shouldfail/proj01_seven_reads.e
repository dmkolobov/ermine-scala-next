module Present.Shouldfail.Proj01 where

{- NEGATIVE, and the only one in `core/examples` that trips the DRAW BUDGET
   rather than a type error.

   Seven reads of one unannotated record parameter. `Record.(!)` is a row
   partition -- `(!) : t <- (r, s) => {..t} -> Field r a -> a` -- so seven reads
   are seven partitions sharing a left-hand side, and closing them against one
   another costs about 5.3-6x as much per additional read -- exactly
   `D(N) = (5^N - 3*3^N + 2*2^N)/2`:
   **3 / 30 / 207 / 1,230 / 6,783** draws for two to six
   (`core/examples/Present/ProjectionCost.e`, measured on this compiler with
   `-Dermine.rowTrace.draws=true`). Seven needs 35,910 and runs past
   `-Dermine.solveBudget=20000` at 20,009.

   There is no relation here, no join, no window and no presentation. This is
   one line of ordinary Ermine, and it is the shape a parameterised report
   takes when its parameter row is left to inference.

   THE FIX is one line of signature: give the lambda
   `forall r o. r <- ((| … the seven fields … |), o) => {..r} -> String` and it
   draws NOTHING -- see `ProjectionCost.proj5Pinned` / `proj6Pinned`.

   EXPECTED (verbatim):

     Row solver resource limit reached (this is NOT a type error): the row
     constraint solver drew 20009 fresh row variables at this signature, past
     the -Dermine.solveBudget=20000 limit, so it was stopped rather than left
     to run.  Raise the limit with -Dermine.solveBudget=<n>, simplify the row
     constraints at this signature, or report it.

   -- reported at 1:1, the module header, because the offending signature is
   the module's own inferred one; the module takes 2.7 s to be rejected.

   The exact draw count in the message may move with the solver; the class of
   diagnostic -- a RESOURCE limit, explicitly not a type error -- is the point.
-}

import Prelude
import Syntax.List

field qAlpha, qBeta, qGamma, qDelta, qEpsilon, qZeta, qEta : String

-- REJECTED: seven partitions on one unannotated parameter row.
bad p = (p ! qAlpha) ++_String (p ! qBeta) ++_String (p ! qGamma)
                     ++_String (p ! qDelta) ++_String (p ! qEpsilon)
                     ++_String (p ! qZeta) ++_String (p ! qEta)
