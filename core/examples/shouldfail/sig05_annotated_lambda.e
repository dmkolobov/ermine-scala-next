module ShouldFail.Sig05 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** CURRENTLY ACCEPTED ***

   Pinned 2026-09-11 (S1 review).  The same hole through an EXPRESSION ANNOTATION rather
   than a binding signature: `(e : T)` reaches `Subst.typeCheck` (the `ann` site, :638 at
   a15a97e), which calls `subsumeType` and discards the skolem-mentioning wanteds exactly
   as `typeCheckExplicitBinding` does.  `TyLower.annot` closes the annotation into a
   Forall, so `r` is skolemised and the body's `r <- ((|health|), t)` is dropped.  Both
   spellings below load; each `crash` evaluates to <error: key not found: health>.

   The S1 sweep found ZERO `ann` hits in the corpus -- nobody writes a row-polymorphic
   annotation -- which is a fact about the corpus, not about the site.  S3's acceptance
   covers this pin too.

   Rule modes: ACCEPTED under all / cut / nongen.
-}

import Prelude

field position : Double
field health   : Int

-- REPL: `crash` prints  <error: key not found: health>
crash  = ((r -> r ! health) : {..r} -> Int) { position = 2.0 }
crash2 = ((r -> r ! health) : forall r. {..r} -> Int) { position = 2.0 }
