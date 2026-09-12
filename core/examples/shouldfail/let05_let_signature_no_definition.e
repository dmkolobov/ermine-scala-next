module ShouldFail.Let05 where

{- SHOULD FAIL -- error class 7, LET SIGNATURE.
   Route: a signature with NO equation in the same `let` block.

   Pinned 2026-09-11 (LET-1).  At the top level and in a `where` block this has always
   been a refusal -- `missing definition`, at the signature's own span -- because the
   module path pairs each signature with a binding of the same binder and refuses one
   that has none.  In a `let` block the signature was dropped, so the block simply had
   no `orphan` at all and the module LOADED at a15a97e.  The refusal is now the same
   message at the same kind of position, through the `Ctx` diagnostic sink rather than
   the assemble refusal (`Lower.ctxEnv`), which the batch reader renders identically and
   the editor shows as a squiggle on the signature.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/let05_let_signature_no_definition.e:27:7: missing definition

   Note: no `error:` prefix, because this is `pairSigs`' own message, kept verbatim so
   that the `let` and `where` spellings read the same.

   Rule modes: rejected under all / cut / nongen (it is a lowering refusal; no rule runs).
-}

import Prelude

badOrphan =
  let orphan : Int -> Int
  in 1
