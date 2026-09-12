module ShouldFail.Sig02 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  MEASURED on 2.11, 2026-09-12.

   Back-ported to branch `backport-2.11` by BP-2 from scala3-migration 5162945 (pinned
   there 2026-09-10; rejected there since S3, 2026-09-11).  Sibling of sig01: the signature
   DOES carry a row constraint, but on the wrong label.  It promises `mana` and the body
   reads `health`.  On an UNPORTED tree it is accepted under all / cut / nongen, and
   `crash` evaluates to <error: key not found: health>.

   This rules out the reading "a signature with no context is treated specially": the
   skolem-mentioning wanted r <- ((|health|), t) was dropped whatever the givens said
   (this branch's `Subst.scala` at HEAD 4fefc51, :535-536 and :553 -- see sig01's header
   for the mechanism).

   MEASURED ON THIS BRANCH, 2026-09-12 (BP-1, `backport/SIG-ENTAIL-2.11.md`): sbt 0.13.5 /
   Scala 2.11.5 / JDK 8, `-Dermine.typeCheck=true -Dermine.useInterface=false` at the
   DEFAULT `-Dermine.sigEntail=error`, `:load`ed into the 2.11 REPL
   (`com.clarifi.reporting.ermine.session.Console`).  The module is REFUSED; the `^N` ids
   below are this run's and vary per run, nothing else does.

       core/examples/shouldfail/sig02_wrong_label_signature.e:81:18: the signature does not
       entail this row constraint
       wrongLabel r = r ! health
                        ^
           wanted   r^521188S <- ((|ShouldFail.Sig02.health|), _^521190A)
           given    r^521188S <- ((|ShouldFail.Sig02.mana|), t^520974B)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig02.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig02_wrong_label_signature.e:80:14
           (sig wrongLabel)
       Unable to load module

   The `given` line is the point of this pin: the signature DOES carry a row constraint and
   it is printed, on the WRONG label, and the refusal is still at the `health` class.  The
   `t^...B` is the signature's own `t`, a dangling `Bound` the 2.11 pipeline leaves in the
   given (rigid, and not part of the witness because no obligation mentions it).

   For reference only -- the text measured on scala3-migration at 5162945, at the default
   `-Dermine.sigEntail=error`.  NOT a claim about this branch (ids vary per run; the
   positions are that file's, whose header is a different length from this one's):

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

   ON THIS BRANCH (backport-2.11), checked by BP-2 by reading the grammar, not by building:
     * SYNTAX: `forall r t. r <- ((|mana|), t) => {..r} -> Int` uses `TypeParsers.uQuant`
       plus the `(| ... |)` row literal, both in this branch's grammar (the stdlib's
       `Layout/Report/Relation.e` writes `(|cutoff|)` the same way).  No `\x ->` lambda.
     * sig03 (the let-bound sibling) is NOT the LET-1 case on this branch: the fused `let`
       production collects sig statements (`TermParsers.let` -> `Statement.gatherBindings`
       -> `checkBindings`), so let signatures reach the same `sig` site as a top-level one
       and sig03 must be rejected by the entailment check like sig01, not at the call.
     * The seven stdlib signature corrections ARE applied on this branch
       (backport/CORRECTIONS.md); without them the boot dies in `DrilldownList.e` under
       `error` and no corpus module reaches its own diagnostic.
-}

import Prelude

field position : Double
field health   : Int
field mana     : Nullable Int

wrongLabel : forall r t. r <- ((|mana|), t) => {..r} -> Int
wrongLabel r = r ! health

-- REPL: `crash` prints  <error: key not found: health>
crash = wrongLabel { position = 2.0, mana = Null Int }
