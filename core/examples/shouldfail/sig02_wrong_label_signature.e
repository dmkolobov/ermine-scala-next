module ShouldFail.Sig02 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** REJECTED (S3) ***

   Pinned 2026-09-10.  Sibling of sig01: the signature DOES carry a row constraint, but
   on the wrong label.  It promises `mana` and the body reads `health`.  Accepted under
   all / cut / nongen; `crash` evaluates to <error: key not found: health>.

   This rules out the reading "a signature with no context is treated specially": the
   skolem-mentioning wanted r <- ((|health|), t) was dropped whatever the givens said
   (Subst.scala:535-536, :553 at a15a97e -- see sig01's header for the mechanism).

   REJECTED since S3 (2026-09-11), at the default `-Dermine.sigEntail=error`.  Measured:

       core/examples/shouldfail/sig02_wrong_label_signature.e:45:18: the signature does
       not entail this row constraint
           wanted   r^579453S <- ((|ShouldFail.Sig02.health|), _^579455A)
           given    r^579453S <- ((|ShouldFail.Sig02.mana|), t^579339B)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig02.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig02_wrong_label_signature.e:44:14
           (sig wrongLabel)

   The GIVEN is printed as the check read it, `mana`'s partition included, so the message
   distinguishes "no constraint" (sig01) from "a constraint about another column" (here).
   `t^N B` is a dangling `Bound`: `Forall.mk` keeps only binders that occur in the
   type's BODY, and `t` occurs only in the constraint.  Rigid, as the design says.
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
field mana     : Nullable Int

wrongLabel : forall r t. r <- ((|mana|), t) => {..r} -> Int
wrongLabel r = r ! health

-- REPL: `crash` prints  <error: key not found: health>
crash = wrongLabel { position = 2.0, mana = Null Int }
