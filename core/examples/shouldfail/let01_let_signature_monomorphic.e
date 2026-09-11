module ShouldFail.Let01 where

{- SHOULD FAIL -- error class 7, LET SIGNATURE.
   Route: a MONOMORPHIC signature on a `let`-bound binding, applied at another type.

   Pinned 2026-09-11 (LET-1, tracker/loopmodel/LET-1-FIX.md).  This is the minimal
   witness of the regression the new pipeline shipped on 2026-08-31: `rename/Lower.scala`
   lowered a `let` block to `Let(pos, implicits, Nil, body)` and never built an explicit
   binding for a signature, so `sameInt`'s declaration reached neither the checker nor
   the editor.  AT a15a97e THIS MODULE LOADED, and `badLet` evaluated to `"hello"` --
   the signature was not merely unenforced, it was never consulted.  The `where`
   spelling of the same program was rejected all along, because a top-level `where` goes
   through the module path's own signature pairing.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/let01_let_signature_monomorphic.e:34:6: error: failed to unify type Int with type String

   Raised by: Subst.scala's `typeCheckExplicitBinding`/`subsumeType` path, reached
   because the block machinery now pairs the signature with its equation
   (`Lower.pairSigs`, shared with the top level and with `where`).

   Rule modes: rejected under all / cut / nongen (this is ordinary unification, not a
   row rule).

   Control: core/examples/shouldfail-controls/control09_let_signatures.e, the same five
   shapes with signatures the bodies satisfy.
-}

import Prelude

badLet =
  let sameInt : Int -> Int
      sameInt q = q
  in sameInt "hello"
