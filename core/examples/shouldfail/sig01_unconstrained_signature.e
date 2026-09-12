module ShouldFail.Sig01 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** REJECTED (S3) ***

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

   REJECTED since S3 (2026-09-11, `tracker/loopmodel/SIG-3-IMPL.md`), at the DEFAULT
   `-Dermine.sigEntail=error`.  Measured message, verbatim (ids vary per run):

       core/examples/shouldfail/sig01_unconstrained_signature.e:70:17: the signature does
       not entail this row constraint
           wanted   r^579411S <- ((|ShouldFail.Sig01.health|), _^579413A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig01.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig01_unconstrained_signature.e:69:13
           (sig healthOpt)

   The primary position is the BODY's `!` (70:17), the secondary the DECLARED TYPE (69:13).
   The witness is the label class `health` with every row empty -- the label is mentioned
   literally, so this is the one shape the plan's original refutation trick also decided.

   Rule modes: rejected under all / cut / nongen.  Under `-Dermine.sigEntail=off` the
   module loads again and `crash` evaluates to the error below: that is the escape hatch,
   pinned in `TestSigEntail`'s flag group.
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

healthOpt : forall r. {..r} -> Int
healthOpt r = r ! health

-- REPL: `crash` prints  <error: key not found: health>
crash = healthOpt { position = 2.0 }
