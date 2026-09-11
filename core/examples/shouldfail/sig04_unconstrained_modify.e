module ShouldFail.Sig04 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** CURRENTLY ACCEPTED ***

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
-}

import Prelude

field position : Double
field health   : Int

bump : forall r. {..r} -> {..r}
bump = modify health (h -> h + 1)

-- REPL: `crash` prints  {position = 2.0, health = <error: key not found: health>}
crash = bump { position = 2.0 }
