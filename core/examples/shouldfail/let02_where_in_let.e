module ShouldFail.Let02 where

{- SHOULD FAIL -- error class 7, LET SIGNATURE.
   Route: the SECOND drop site -- a `where` attached to an equation INSIDE a `let` block.

   Pinned 2026-09-11 (LET-1).  A `where` on a TOP-LEVEL equation was lowered by the
   module path, which pairs signatures; a `where` nested inside a `let` block went
   through the same signature-blind block helper as the `let` itself
   (`rename/Lower.scala:298-299` at a15a97e) and was dropped too.  AT a15a97e THIS
   MODULE LOADED.  The two drop sites share one implementation now, so this module and
   `let01` are refused by the same code.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/let02_where_in_let.e:25:6: error: failed to unify type Int with type String

   Rule modes: rejected under all / cut / nongen.
-}

import Prelude

badWhereInLet =
  let outer y = inner y
        where inner : Int -> Int
              inner q = q
  in outer "hello"
