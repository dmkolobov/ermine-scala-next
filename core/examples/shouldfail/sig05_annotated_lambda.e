module ShouldFail.Sig05 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** REJECTED (S3) ***

   Pinned 2026-09-11 (S1 review).  The same hole through an EXPRESSION ANNOTATION rather
   than a binding signature: `(e : T)` reaches `Subst.typeCheck` (the `ann` site, :638 at
   a15a97e), which calls `subsumeType` and discards the skolem-mentioning wanteds exactly
   as `typeCheckExplicitBinding` does.  `TyLower.annot` closes the annotation into a
   Forall, so `r` is skolemised and the body's `r <- ((|health|), t)` is dropped.  Both
   spellings below load; each `crash` evaluates to <error: key not found: health>.

   The S1 sweep found ZERO `ann` hits in the corpus -- nobody writes a row-polymorphic
   annotation -- which is a fact about the corpus, not about the site.

   REJECTED since S3 (2026-09-11), at the default `-Dermine.sigEntail=error`, through the
   `ann` site -- `Subst.typeCheck`, `SigEntail.siteAt("ann", e.loc)`.  Measured on the
   FIRST spelling (`crash`, line 48; the module dies there, and `crash2` is the same
   judgement with the quantifier written out):

       core/examples/shouldfail/sig05_annotated_lambda.e:48:19: the signature does not
       entail this row constraint
           wanted   r^579385S <- ((|ShouldFail.Sig05.health|), _^579387A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig05.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig05_annotated_lambda.e:48:12 (ann <annot>)

   An annotation has no binding name, so the secondary location is the annotated
   EXPRESSION (48:12) and the site prints as `ann <annot>`.

   Rule modes: rejected under all / cut / nongen.
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
crash  = ((r -> r ! health) : {..r} -> Int) { position = 2.0 }
crash2 = ((r -> r ! health) : forall r. {..r} -> Int) { position = 2.0 }
