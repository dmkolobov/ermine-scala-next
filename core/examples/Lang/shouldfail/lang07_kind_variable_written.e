module Lang.Shouldfail.Lang07 where

{- NEGATIVE: the inferred signature the interface printer emits, written back.

   `-Dermine.useInterface=true` over an eta-delegating wrapper such as

       iAskField f = askField f

   writes the scheme

       forall {a} (h: rho) (a1: a) (e: rho). (exists (c: rho). e <- (h, c))
         => Field h a1 -> Record e -> a1

   with the value type generalised at an inferred KIND variable. That scheme cannot be
   written back: `->` demands kind `*` on both sides. The minimal case is below, and it
   needs no rows, no records and no library at all.

   This is a `.ei` that does not round-trip through the surface syntax. See
   `tracker/loopmodel/E5-EXAMPLES.md` section 6.

   EXPECTED:

     error: failed to unify kind * with kind !k
-}

import Prelude

atAnyKind : forall {k} (a: k). a -> Int
atAnyKind x = 1
