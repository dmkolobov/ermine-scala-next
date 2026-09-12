module ShouldFail.Sig03 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** REJECTED (S3) ***
   (since LET-1, cff6c42, honours let-bound signatures: this is sig01 in a let, and S3
   rejects it AT THE SIGNATURE).  Before LET-1 it was refused at the CALL SITE -- and NOT
   because the checker caught it:

   Pinned 2026-09-10; explained 2026-09-11 (S1, tracker/loopmodel/SIG-1-SURVEY.md and
   SIG-1-REVIEW.md).  sig01's shape on a LET-BOUND binding.  The module is refused with
   the message on the call `local { position = 2.0 }` (line 32, col 12):

       Row partitions are unsatisfiable at field 'ShouldFail.Sig03.health':
       the whole contains it but no part does

   The reason is a SECOND BUG: the renamer's lowering of `let` DISCARDS explicit (signed)
   bindings.  `rename/Lower.scala` SLet case (:185-187) does
   `val (implicits, _) = bindings(ss, c); Let(pos, implicits, Nil, ...)`, and
   `Lower.bindings` is typed `(List[ImplicitBinding], List[Nothing])` with
   `case _: SSigStatement => ()  // 4.1` -- it never builds an explicit binding (second
   site :298-299, a `where` inside a `let`).  So `local`'s signature never reaches the
   checker; `local` is INFERRED (`forall r t. r <- ((|health|), t) => {..r} -> Int`) and
   the call is refused by ordinary inference.  Decisive probe: `let g : Int -> Int; g x = x
   in g "hello"` LOADS, its `where` twin is rejected.  A regression of the new pipeline:
   the fused `let` production (parsing/TermParsers.scala:224-243 at 9ad5909^) filled both
   halves of `Let`; the empty stub was written in 91c0d52, became the only path in 80df1eb
   (2026-08-31).  Top-level and `where` go through `NewPipeline.pairSigs`, so sig01 is
   accepted.

   Consequences: this pin does NOT witness the entailment hole -- it witnesses the let
   drop.  Fixing the drop before S3 lands would turn this module from a rejection into an
   acceptance (it would then be sig01 in a let).  After both fixes the blame should sit on
   the signature and the `!`, not on the call.  The let drop is outside this plan's scope:
   ticketed for the LSP loop (it owns rename/Lower.scala).

   AFTER BOTH FIXES, as predicted: the blame sits on the signature and the `!`, not on the
   call.  Measured at S3 (2026-09-11, default `-Dermine.sigEntail=error`):

       core/examples/shouldfail/sig03_let_bound_signature.e:70:25: the signature does not
       entail this row constraint
           wanted   r^579378S <- ((|ShouldFail.Sig03.health|), _^579380A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig03.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig03_let_bound_signature.e:69:21 (sig local)

   70:25 is the `!` inside the let body; 69:21 is the DECLARED TYPE on the let's signature
   line, which is what makes a let-bound signature's diagnostic readable.  The site is `sig`
   (`typeCheckExplicitBinding` through `inferBindingGroupTypes`), the same one a top-level
   binding uses, so LET-1 is what brought this module under the check.

   Rule modes: rejected under all / cut / nongen (same message).  Under
   `-Dermine.sigEntail=off` the module is refused again by ordinary inference, at the CALL: the old message, from a different mechanism.
   HOW THE MESSAGE ABOVE WAS MEASURED: under the default `-Dermine.sigEntail=error` with
   the seven stdlib signature corrections applied (branch `sig-fixes`), and under
   `-Dermine.sigEntail=warn` on an uncorrected tree, where the text is identical with a
   `warning:` prefix and the module then loads.  Without the stdlib corrections `error`
   refuses `DrilldownList.e:20:98` during the boot and NO corpus module reaches its own
   diagnostic, so a sweep of an uncorrected tree says nothing about this pin.
-}

import Prelude

field position : Double
field health   : Int

-- REPL: `crash` prints  <error: key not found: health>
crash = let local : forall r. {..r} -> Int
            local r = r ! health
        in local { position = 2.0 }
