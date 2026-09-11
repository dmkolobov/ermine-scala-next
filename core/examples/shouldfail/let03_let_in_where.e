module ShouldFail.Let03 where

{- SHOULD FAIL -- error class 7, LET SIGNATURE.
   Route: a signed `let` inside a `where` BODY.

   Pinned 2026-09-11 (LET-1).  The `where` block itself was lowered by the module path,
   but the `let` in its right-hand side is lowered by `Lower.term`, which is where the
   signature was dropped -- so nesting a `let` inside a healthy `where` lost the
   signature again.  AT a15a97e THIS MODULE LOADED.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/let03_let_in_where.e:19:17: error: failed to unify type Int with type String

   Rule modes: rejected under all / cut / nongen.
-}

import Prelude

badLetInWhere = outer "hello"
  where outer y =
          let inner : Int -> Int
              inner q = q
          in inner y
