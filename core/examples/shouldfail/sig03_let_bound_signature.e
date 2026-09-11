module ShouldFail.Sig03 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  REJECTED today, but at
   the CALL SITE and for a reason not yet explained.

   Pinned 2026-09-10.  sig01's shape on a LET-BOUND binding.  Let and top level share
   `inferBindingGroupTypes` -> `typeCheckExplicitBinding` (reached from `inferType`'s
   Let case and from `checkModule`), so the same discard happens -- yet this module IS
   refused, with the message on the call `local { position = 2.0 }` (line 20, col 12):

       Row partitions are unsatisfiable at field 'ShouldFail.Sig03.health':
       the whole contains it but no part does

   i.e. something in the let path keeps the body's obligation alive long enough for
   the call site's instantiation to contradict it, where the top-level path (sig01)
   loses it.  Explaining the difference is a deliverable of S1 in
   tracker/SIG-ENTAIL-PLAN.md: it may be the seed of the fix, or a coincidence of
   where the residual lands.  After S3 the blame should sit on the signature and the
   `!`, not on the call.

   Rule modes: rejected under all / cut / nongen (same message).
-}

import Prelude

field position : Double
field health   : Int

-- REPL: `crash` prints  <error: key not found: health>
crash = let local : forall r. {..r} -> Int
            local r = r ! health
        in local { position = 2.0 }
