module ShouldFail.Sig01 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  MEASURED on 2.11, 2026-09-12.

   Back-ported to branch `backport-2.11` by BP-2 from scala3-migration 5162945
   (pinned there 2026-09-10, tracker/SIG-ENTAIL-PLAN.md stage S0; rejected there since S3,
   2026-09-11, tracker/loopmodel/SIG-3-IMPL.md).  The declared signature promises
   `healthOpt` for EVERY row r; the body reads `health`, which needs
   r <- ((|health|), t).  On an UNPORTED tree the checker accepts the module under every
   rule mode (all / cut / nongen), with -Dermine.useInterface=false and with it on, and in
   the REPL `crash` then evaluates to

       <error: key not found: health>

   A well-typed program gets stuck: a soundness defect, not an incompleteness.

   Control: shouldfail-controls/control08_sig_declared.e (same bodies, honest signatures).
   Inference alone is right -- `:type (r -> r ! health)` prints
       forall (a: rho). (exists (b: rho). a <- ((|health|), b)) => Record a -> Int
   so the hole opens only through an explicit signature.

   Mechanism, at THIS branch's `Subst.scala` (HEAD 4fefc51 -- the pre-port file BP-1 is
   replacing; the line numbers below are this branch's and coincide with the scala3
   branch's at a15a97e except where noted): `subsumeType` (:527-553) splits the inferred
   residual by `Type.fskvs` into skolem-free `ds` and skolem-mentioning `rs` -- the
   obligations (:534) -- runs `for (r <- rs) entails(qs, r)` (:535-536) and DISCARDS the
   Boolean, then returns only `ds` (:553); `typeCheckExplicitBinding` (:647 here, :655 on
   the scala3 branch) never sees the obligation.  `entails` (:313) is class-only
   (bySuper/byInst need a Con head), `entail` (:394) is gated on isClassConstraint (:398),
   and `restrictTypes(tts)` (:540) removes the substitution entries the skolem-escape check
   (:543) would need.  The .ei publishes the DECLARED type, so every caller instantiates it
   with no obligation.  Upstream comment at :639: "TODO: ADD warnings here later if we need
   to check subsumption involving constraints".  Present since the initial export; not a
   regression of the 2026-09 work.

   Distinct from incomplete/README-unsound.md (unsatisfiable sets accepted at call sites):
   here the wanted set IS satisfiable; what is missing is entailment by the signature's
   givens, with the signature's variables rigid and the solver's minted remainder free.

   MEASURED ON THIS BRANCH, 2026-09-12 (BP-1, `backport/SIG-ENTAIL-2.11.md`): sbt 0.13.5 /
   Scala 2.11.5 / JDK 8, `-Dermine.typeCheck=true -Dermine.useInterface=false` at the
   DEFAULT `-Dermine.sigEntail=error`, `:load`ed into the 2.11 REPL
   (`com.clarifi.reporting.ermine.session.Console`).  The module is REFUSED; the `^N` ids
   below are this run's and vary per run, nothing else does.

       core/examples/shouldfail/sig01_unconstrained_signature.e:113:17: the signature does
       not entail this row constraint
       healthOpt r = r ! health
                       ^
           wanted   r^521153S <- ((|ShouldFail.Sig01.health|), _^521155A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig01.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig01_unconstrained_signature.e:112:13
           (sig healthOpt)
       Unable to load module

   Word for word the scala3 branch's message, at this file's own positions: PRIMARY the
   body's `!` (:113:17), SECONDARY the DECLARED TYPE (:112:13, the `sig` site).  Under
   `-Dermine.sigEntail=off` the module loads again -- measured, in the off-vs-error corpus
   sweep where sig01..sig05 are the ONLY five files whose outcome differs.

   For reference only -- the text measured on scala3-migration at 5162945, at the default
   `-Dermine.sigEntail=error`.  This is NOT a claim about this branch: ids vary per run,
   and the positions below are that file's, whose header is a different length from this
   one's.

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

   There the primary position is the BODY's `!` and the secondary the DECLARED TYPE.  The
   witness is the label class `health` with every row empty -- the label is mentioned
   literally, so this is the one shape the plan's original refutation trick also decided.
   Rule modes there: rejected under all / cut / nongen.  Under `-Dermine.sigEntail=off` the
   module loads again and `crash` evaluates to the error above: that is the escape hatch,
   pinned in `TestSigEntail`'s flag group.

   ON THIS BRANCH (backport-2.11), checked by BP-2 by reading the fused Scala-2 grammar and
   `Subst.scala` at HEAD 4fefc51, not by building:
     * SYNTAX: every construct used below is in this branch's grammar.  No `\x ->` lambda
       is used (`(x -> ...)` is what `TermParsers.lam` takes: `patternL0.some << keyOp("->")`).
     * A free lowercase type variable in a signature or an annotation is quantified by
       `Annot.close` (Annot.scala:15, `body.closeWith(exists)`), which `Binding.close`
       reaches from `Session.scala:931-932` at module load.  That is this branch's
       counterpart of the scala3 branch's `rename/TyLower.scala`, which does not exist here.
     * sig03 (the let-bound sibling) is NOT the LET-1 case on this branch: the fused
       `let` production collects sig statements (`TermParsers.let` :224-243 ->
       `Statement.gatherBindings` :284-289 -> `checkBindings`), so it builds ExplicitBindings
       and let signatures reach the same `sig` site this module's does.  sig03 must
       therefore be rejected by the entailment check exactly as sig01 is, not at the call.
     * The seven stdlib signature corrections ARE applied on this branch (BP-2,
       backport/CORRECTIONS.md).  Without them `error` refuses `DrilldownList.e` during the
       boot and NO corpus module reaches its own diagnostic, so a sweep of an uncorrected
       tree says nothing about this pin.
-}

import Prelude

field position : Double
field health   : Int

healthOpt : forall r. {..r} -> Int
healthOpt r = r ! health

-- REPL: `crash` prints  <error: key not found: health>
crash = healthOpt { position = 2.0 }
