module Lang.Shouldfail.Lang04 where

{- NEGATIVE: a `do` block applied to the wrong dictionary.

   `Syntax.Do` desugars a block to `Monad f -> f a`, so the dictionary is an ORDINARY
   ARGUMENT and supplying the wrong one is an ordinary type error -- not a missing
   instance, because there are no instances. The block below is built from `Maybe`
   actions and handed `listMonad`.

   This is the whole difference between Ermine's `do` and a class-based one: the monad
   is chosen at the APPLICATION, and choosing wrong is caught by unification.

   EXPECTED:

     error: failed to unify type Maybe with type List
-}

import Prelude
import Control.Monad as M
import Syntax.List
import Lang.Helpers

badDo : List Int
badDo = (do a <- liftDo (Just 1)
            b <- liftDo (Just 2)
            unit (a + b)) ' listMonad
