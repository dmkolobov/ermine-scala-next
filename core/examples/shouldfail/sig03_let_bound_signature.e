module ShouldFail.Sig03 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  MEASURED on 2.11, 2026-09-12.

   Back-ported to branch `backport-2.11` by BP-2 from scala3-migration 5162945 (pinned
   there 2026-09-10, explained 2026-09-11 in tracker/loopmodel/SIG-1-SURVEY.md and
   SIG-1-REVIEW.md; rejected there since S3).  sig01's shape on a LET-BOUND binding.

   *** ON THIS BRANCH sig03 IS NOT THE LET-1 CASE. ***

   On the scala3-migration branch this module had a SECOND, unrelated bug in front of it
   until LET-1 (cff6c42): that pipeline's renamer DROPPED explicit (signed) let bindings --
   `rename/Lower.scala` SLet case did `val (implicits, _) = bindings(ss, c); Let(pos,
   implicits, Nil, ...)`, with `Lower.bindings` typed `(List[ImplicitBinding],
   List[Nothing])` and `case _: SSigStatement => ()`.  So `local`'s signature never reached
   the checker, `local` was INFERRED (`forall r t. r <- ((|health|), t) => {..r} -> Int`),
   and the module was refused at the CALL `local { position = 2.0 }` with

       Row partitions are unsatisfiable at field 'ShouldFail.Sig03.health':
       the whole contains it but no part does

   -- ordinary inference, not the entailment hole.  LET-1 fixed that drop and the blame
   moved to the signature.  NONE OF THAT APPLIES HERE.  `rename/Lower.scala` does not exist
   on this branch; the FUSED Scala-2 grammar builds both halves of `Let` directly:
   `TermParsers.let` (:224-243) does `bs <- laidout("let binding", bindingStatement)`,
   `(is, ss) = gatherBindings(bs)`, `checkBindings[Parser](bgLoc, is, ss)`, and
   `StatementParsers.bindingStatement` is `sigStatement | termStatement`
   (:332-334, and `sigs` at :31 backtracks up to the `:`) -- so a let-bound signature becomes an `ExplicitBinding`
   (`Statement.checkBindings` :306, `ExplicitBinding(i.loc, i.v, Annot.plain(i.loc, s.ty),
   i.alts)`) exactly as a top-level or `where` one does.  This branch never had the let
   drop: the fused production is the code LET-1 restored on the other side.

   Consequently, on this branch sig03 is simply sig01 inside a `let`, and it must be
   rejected by the ENTAILMENT CHECK at the signature, like sig01 -- not at the call.  The
   old inference message above should NOT be what BP-1 measures (and if it is, the let
   pipeline here is not what BP-2 read).

   Mechanism, at THIS branch's `Subst.scala` (HEAD 4fefc51): the site is `sig`
   (`typeCheckExplicitBinding` :647, reached through `inferBindingGroupTypes`), the same one
   a top-level binding uses; `subsumeType` (:527-553) partitions the residual at :534 and
   discards the skolem-mentioning half at :535-536.  See sig01's header for the full
   description.

   MEASURED ON THIS BRANCH, 2026-09-12 (BP-1, `backport/SIG-ENTAIL-2.11.md`): sbt 0.13.5 /
   Scala 2.11.5 / JDK 8, `-Dermine.typeCheck=true -Dermine.useInterface=false` at the
   DEFAULT `-Dermine.sigEntail=error`, `:load`ed into the 2.11 REPL
   (`com.clarifi.reporting.ermine.session.Console`).  The module is REFUSED; the `^N` ids
   below are this run's and vary per run, nothing else does.

       core/examples/shouldfail/sig03_let_bound_signature.e:109:25: the signature does not
       entail this row constraint
                   local r = r ! health
                               ^
           wanted   r^521120S <- ((|ShouldFail.Sig03.health|), _^521122A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig03.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig03_let_bound_signature.e:108:21 (sig local)
       Unable to load module

   CONFIRMED: the site is `sig local`, i.e. the ENTAILMENT CHECK at the let-bound
   signature, NOT the older refusal at the CALL.  BP-2's reading of the fused `let`
   production is right -- this branch never had the LET-1 defect, so sig03 is sig01's shape
   in a `let` and nothing else.

   For reference only -- the text measured on scala3-migration at 5162945 AFTER both fixes
   (LET-1 plus S3's check), at the default `-Dermine.sigEntail=error`.  NOT a claim about
   this branch (ids vary per run; the positions are that file's, whose header is a
   different length from this one's):

       core/examples/shouldfail/sig03_let_bound_signature.e:70:25: the signature does not
       entail this row constraint
           wanted   r^579378S <- ((|ShouldFail.Sig03.health|), _^579380A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig03.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of _1 (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig03_let_bound_signature.e:69:21 (sig local)

   There 70:25 is the `!` inside the let body and 69:21 the DECLARED TYPE on the let's
   signature line, which is what makes a let-bound signature's diagnostic readable.  Rule
   modes there: rejected under all / cut / nongen, same message.  Under
   `-Dermine.sigEntail=off` that tree refused the module again by ordinary inference, at
   the CALL.

   ON THIS BRANCH (backport-2.11), checked by BP-2 by reading the grammar, not by building:
     * SYNTAX: the laid-out `let` with a signature line parses -- `bindingStatement` is
       `sigStatement | termStatement` and `sigStatement` backtracks up to the `:`
       (`sigs` is `(termDef.sepBy(comma) << keyOp(":")).attempt ++ typ`).  No `\x ->`
       lambda is used.
     * The let's ExplicitBinding is closed at module load like any other:
       `Term.Let.close` (Term.scala:104) -> `ExplicitBinding.close` (Binding.scala:68) ->
       `Annot.close` (Annot.scala:15), reached from `Session.scala:931-932`.
     * The seven stdlib signature corrections ARE applied on this branch
       (backport/CORRECTIONS.md); without them the boot dies in `DrilldownList.e` under
       `error` and no corpus module reaches its own diagnostic.
-}

import Prelude

field position : Double
field health   : Int

-- REPL: `crash` prints  <error: key not found: health>
crash = let local : forall r. {..r} -> Int
            local r = r ! health
        in local { position = 2.0 }
