module ShouldFail.Sig04 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** REJECTED (S3) ***

   Pinned 2026-09-10.  sig01's shape for a WRITE: `modify` (Field.e) needs
   r <- ((|health|), t) and the signature promises every row.  Accepted under
   all / cut / nongen; `crash` evaluates to a record whose `health` field is the
   error, printed as
       Record (|position|) = {position = 2.0, health = <error: key not found: health>}
   -- note the printed TYPE has no `health` and the VALUE has one: the runtime built
   a record outside its own type.

   Why a separate pin: a record-to-record signature is the shape a caller would read as
   an access set (which fields a function touches).  With the hole open, the declared
   set can be narrower than the body's, which is the case any consumer of signatures as
   access sets must not trust.

   REJECTED since S3 (2026-09-11), at the default `-Dermine.sigEntail=error`.  Measured:

       core/examples/shouldfail/sig04_unconstrained_modify.e:48:8: the signature does not
       entail this row constraint
           wanted   r^579415S <- ((|ShouldFail.Sig04.health|), t^579417A)
           given    (none)
         no rows satisfying the givens satisfy it: take the column
           `ShouldFail.Sig04.health` to be in none of the signature's rows (r) -- the
           givens allow that, and no choice of t' (the solver's own, which may be any rows)
           then satisfies the wanted
         declared at core/examples/shouldfail/sig04_unconstrained_modify.e:47:8 (sig bump)

   48:8 is `modify`'s occurrence -- the term that generated the wanted -- and 47:8 is the
   declared type.  The minted remainder keeps the name `t` it was refreshed from, so the
   message prints it as `t'`: a PRIME marks the solver's own copy of a source name, and no
   id and no position appears in that sentence, which is what makes it reproducible.
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

bump : forall r. {..r} -> {..r}
bump = modify health (h -> h + 1)

-- REPL: `crash` prints  {position = 2.0, health = <error: key not found: health>}
crash = bump { position = 2.0 }
