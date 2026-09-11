module ShouldFail.Sig01 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** CURRENTLY ACCEPTED ***

   Pinned 2026-09-10 (tracker/SIG-ENTAIL-PLAN.md, stage S0).  The declared signature
   promises `healthOpt` for EVERY row r; the body reads `health`, which needs
   r <- ((|health|), t).  The checker accepts the module under every rule mode
   (all / cut / nongen), with -Dermine.useInterface=false and with it on, and in the
   REPL `crash` then evaluates to

       <error: key not found: health>

   A well-typed program gets stuck: a soundness defect, not an incompleteness.

   Control: shouldfail-controls/control08_sig_declared.e (same bodies, honest signatures).
   Inference alone is right -- `:type (r -> r ! health)` prints
       forall (a: rho). (exists (b: rho). a <- ((|health|), b)) => Record a -> Int
   so the hole opens only through an explicit signature.

   Mechanism (Subst.scala at a15a97e): `subsumeType` (:527-553) splits the inferred
   residual by `Type.fskvs` into skolem-free `ds` and skolem-mentioning `rs` -- the
   obligations -- runs `for (r <- rs) entails(qs, r)` (:535-536) and DISCARDS the Boolean,
   then returns only `ds` (:553); `typeCheckExplicitBinding` (:655) never sees the
   obligation.  `entails` (:313) is class-only (bySuper/byInst need a Con head), `entail`
   (:394) is gated on isClassConstraint, and `restrictTypes(tts)` (:540) removes the
   substitution entries the skolem-escape check (:543) would need.  The .ei publishes the
   DECLARED type, so every caller instantiates it with no obligation.  Upstream comment at
   :639: "TODO: ADD warnings here later if we need to check subsumption involving
   constraints".  Present since the initial export; not a regression of the 2026-09 work.

   Distinct from incomplete/README-unsound.md (unsatisfiable sets accepted at call sites):
   here the wanted set IS satisfiable; what is missing is entailment by the signature's
   givens, with the signature's variables rigid and the solver's minted remainder free.

   Expected message once fixed (proposed wording; S3 settles it):
       .../sig01_unconstrained_signature.e:<line of `r ! health`>: signature does not
         entail the body's row constraint  r <- ((|health|), t)
       with a second location "declared at" on the signature line.

   Rule modes: ACCEPTED under all / cut / nongen.  Flip this header and RESULTS.md when
   S3 lands.
-}

import Prelude

field position : Double
field health   : Int

healthOpt : forall r. {..r} -> Int
healthOpt r = r ! health

-- REPL: `crash` prints  <error: key not found: health>
crash = healthOpt { position = 2.0 }
