module ShouldFail.Sig10 where

{- SHOULD FAIL -- the signature's context is too weak (error class 6).

   The given constrains s and t.  The body projects zz out of r, a row the
   given does not mention.

   The control for sig09: here the given is irrelevant, and reading it must
   not make the check accept.
-}

import Prelude

field a : Int
field b : Int
field zz : Int

needZz : ((|a, b|) <- (s, t)) => Relation r -> Relation s -> Relation r
needZz x y = join x (project {zz} x)
