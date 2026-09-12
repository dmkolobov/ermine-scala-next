module ShouldFail.Sig05 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  MEASURED on 2.11, 2026-09-12.

   Back-ported to branch `backport-2.11` by BP-2 from scala3-migration 5162945 (pinned
   there 2026-09-11 at the S1 review; rejected there since S3).  The same hole through an
   EXPRESSION ANNOTATION rather than a binding signature: `(e : T)` reaches
   `Subst.typeCheck` -- the `ann` site, :633-640 on THIS branch (HEAD 4fefc51), reached from
   `case Sig(l, x, ann)` at :893 -- which calls `subsumeType` and discards the
   skolem-mentioning wanteds exactly as `typeCheckExplicitBinding` (:647) does.  Once the
   annotation is closed into a Forall, `r` is skolemised and the body's
   r <- ((|health|), t) is dropped (:534, :535-536, :553).  On an UNPORTED tree both
   spellings below load, and each `crash` evaluates to <error: key not found: health>.

   The S1 sweep found ZERO `ann` hits in the corpus -- nobody writes a row-polymorphic
   annotation -- which is a fact about the corpus, not about the site.

   MEASURED ON THIS BRANCH, 2026-09-12 (BP-1, `backport/SIG-ENTAIL-2.11.md`): sbt 0.13.5 /
   Scala 2.11.5 / JDK 8, `-Dermine.typeCheck=true -Dermine.useInterface=false` at the
   DEFAULT `-Dermine.sigEntail=error`, `:load`ed into the 2.11 REPL
   (`com.clarifi.reporting.ermine.session.Console`).  The module is REFUSED; the `^N` ids
   below are this run's and vary per run, nothing else does.

       core/examples/shouldfail/sig05_annotated_lambda.e:100:19: the signature does not
       entail this row constraint
       crash2 = ((r -> r ! health) : forall r. {..r} -> Int) { position = 2.0 }
                         ^
           wanted   r^521122S <- ((|ShouldFail.Sig05.health|), _^521124A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig05.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig05_annotated_lambda.e:100:12 (ann <annot>)
       Unable to load module

   WHICH JUDGEMENT: `crash2` (:100, the EXPLICIT `forall r.`), not `crash` (:99). On the
   scala3 branch it was `crash`.  Nothing about the check differs -- the 2.11 binding group
   is simply checked in the other order.  Both spellings ARE refused, measured separately
   in one-equation modules: the bare `(e : {..r} -> Int)` produces the identical diagnostic
   at its own position, so `Annot.close` (Annot.scala:15) skolemises the implicit `r` here
   exactly as the scala3 branch's `rename/TyLower.scala` does.  That was the one open
   question in BP-2's reading, and it is answered: CONFIRMED, by measurement.

   The warn-mode sweep records BOTH annotations (`ann:<annot>` at :99:19 and :100:19), and
   the oracle rejects the group; `error` stops at the first refusal, which is :100.

   For reference only -- the text measured on scala3-migration at 5162945, at the default
   `-Dermine.sigEntail=error`, through the `ann` site (`Subst.typeCheck`,
   `SigEntail.siteAt("ann", e.loc)`), on the FIRST spelling.  NOT a claim about this branch
   (ids vary per run; the positions are that file's, whose header is a different length
   from this one's):

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
   EXPRESSION and the site prints as `ann <annot>`.  Rule modes there: rejected under
   all / cut / nongen.

   ON THIS BRANCH (backport-2.11), checked by BP-2 by reading the grammar, not by building:
     * SYNTAX, both spellings parse.  `TypeParsers.annot` (:351-355) is an optional `some`
       quantifier followed by `typ`, and `typ` (:298) itself takes an optional `forall`
       (`uQuant`, :294).  So `(e : forall r. {..r} -> Int)` is accepted -- the EXPLICIT-
       FORALL annotation is NOT refused by this grammar; the stdlib already writes the
       richer `(cont : some a b . forall r . Field r a -> b)` at `Field.e:36`.  The bare
       `(e : {..r} -> Int)` is accepted too, with `r` resolved by `TypeParsers.typeVar`.
       Lambdas use `(r -> ...)`; no `\x ->` form exists in this grammar.
     * The scala3 branch closes a bare annotation into a Forall in `rename/TyLower.scala`
       (`TyLower.annot`), which does not exist here.  The 2.11 counterpart is
       `Annot.close` (Annot.scala:15, `body.closeWith(exists).nf`), reached through
       `Term.Sig.close` (Term.scala:78) and `Binding.close` from `Session.scala:931-932` at
       module load -- so `r` is quantified here as well, and the first spelling should
       skolemise as it does there.  BP-1 should confirm that on the measurement rather than
       assume it: it is the one place where the two pipelines close an annotation in
       different code.
     * sig03 (the let-bound sibling) is NOT the LET-1 case on this branch: the fused `let`
       production collects sig statements, so let signatures reach the same `sig` site as a
       top-level one and sig03 must be rejected by the entailment check like sig01, not at
       the call.
     * The seven stdlib signature corrections ARE applied on this branch
       (backport/CORRECTIONS.md); without them the boot dies in `DrilldownList.e` under
       `error` and no corpus module reaches its own diagnostic.
-}

import Prelude

field position : Double
field health   : Int

-- REPL: `crash` prints  <error: key not found: health>
crash  = ((r -> r ! health) : {..r} -> Int) { position = 2.0 }
crash2 = ((r -> r ! health) : forall r. {..r} -> Int) { position = 2.0 }
