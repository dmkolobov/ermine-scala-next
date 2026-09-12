module ShouldFail.Sig04 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  MEASURED on 2.11, 2026-09-12.

   Back-ported to branch `backport-2.11` by BP-2 from scala3-migration 5162945 (pinned
   there 2026-09-10; rejected there since S3, 2026-09-11).  sig01's shape for a WRITE:
   `modify` (Field.e:39, `r <- (h, t) => Field h a -> (a -> a) -> {..r} -> {..r}`) needs
   r <- ((|health|), t) and the signature promises every row.  On an UNPORTED tree it is
   accepted under all / cut / nongen, and `crash` evaluates to a record whose `health`
   field is the error, printed as
       Record (|position|) = {position = 2.0, health = <error: key not found: health>}
   -- note the printed TYPE has no `health` and the VALUE has one: the runtime built
   a record outside its own type.

   Why a separate pin: a record-to-record signature is the shape a caller would read as
   an access set (which fields a function touches).  With the hole open, the declared
   set can be narrower than the body's, which is the case any consumer of signatures as
   access sets must not trust.

   Mechanism: this branch's `Subst.scala` at HEAD 4fefc51, :534 / :535-536 / :553 --
   see sig01's header.

   MEASURED ON THIS BRANCH, 2026-09-12 (BP-1, `backport/SIG-ENTAIL-2.11.md`): sbt 0.13.5 /
   Scala 2.11.5 / JDK 8, `-Dermine.typeCheck=true -Dermine.useInterface=false` at the
   DEFAULT `-Dermine.sigEntail=error`, `:load`ed into the 2.11 REPL
   (`com.clarifi.reporting.ermine.session.Console`).  The module is REFUSED; the `^N` ids
   below are this run's and vary per run, nothing else does.

       core/examples/shouldfail/sig04_unconstrained_modify.e:87:8: the signature does not
       entail this row constraint
       bump = modify health (h -> h + 1)
              ^
           wanted   r^521157S <- ((|ShouldFail.Sig04.health|), t^521159A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig04.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of t' (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig04_unconstrained_modify.e:86:8 (sig bump)
       Unable to load module

   The minted variable prints as `t'` -- a PRIME, not an id: it was refreshed from
   `Field.modify`'s own `t`, and `SigEntail.displayNames` primes a copied name so one
   sentence cannot mention two different `t`s.  The primary position is the whole equation
   (`bump` is point-free, so the obligation's position is the `modify` application), which
   is why the secondary `declared at` line is what identifies the signature here.

   For reference only -- the text measured on scala3-migration at 5162945, at the default
   `-Dermine.sigEntail=error`.  NOT a claim about this branch (ids vary per run; the
   positions are that file's, whose header is a different length from this one's):

       core/examples/shouldfail/sig04_unconstrained_modify.e:48:8: the signature does not
       entail this row constraint
           wanted   r^579415S <- ((|ShouldFail.Sig04.health|), t^579417A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig04.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of t' (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig04_unconstrained_modify.e:47:8 (sig bump)

   There 48:8 is `modify`'s occurrence -- the term that generated the wanted -- and 47:8 is
   the declared type.  The minted remainder keeps the name `t` it was refreshed from, so
   the message prints it as `t'`: a PRIME marks the solver's own copy of a source name, and
   no id and no position appears in that sentence, which is what makes it reproducible.

   ON THIS BRANCH (backport-2.11), checked by BP-2 by reading the grammar, not by building:
     * SYNTAX: `modify`, `!` and the record literal are all in this branch's Prelude, whose
       module text is byte-identical to the scala3 branch's (`export Field`, `export
       Constraint`), and `Field.e` here is byte-identical too.  The lambda is written
       `(h -> h + 1)`; no `\x ->` form is used.
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

bump : forall r. {..r} -> {..r}
bump = modify health (h -> h + 1)

-- REPL: `crash` prints  {position = 2.0, health = <error: key not found: health>}
crash = bump { position = 2.0 }
