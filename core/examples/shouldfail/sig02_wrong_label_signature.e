module ShouldFail.Sig02 where

{- SHOULD FAIL -- error class 6, SIGNATURE CONTEXT TOO WEAK.  *** CURRENTLY ACCEPTED ***

   Pinned 2026-09-10.  Sibling of sig01: the signature DOES carry a row constraint, but
   on the wrong label.  It promises `mana` and the body reads `health`.  Accepted under
   all / cut / nongen; `crash` evaluates to <error: key not found: health>.

   This rules out the reading "a signature with no context is treated specially": the
   skolem-mentioning wanted r <- ((|health|), t) is dropped whatever the givens say
   (Subst.scala:535-536, :553 -- see sig01's header for the mechanism).
-}

import Prelude

field position : Double
field health   : Int
field mana     : Nullable Int

wrongLabel : forall r t. r <- ((|mana|), t) => {..r} -> Int
wrongLabel r = r ! health

-- REPL: `crash` prints  <error: key not found: health>
crash = wrongLabel { position = 2.0, mana = Null Int }
