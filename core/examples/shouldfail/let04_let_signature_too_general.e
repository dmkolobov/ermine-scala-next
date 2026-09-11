module ShouldFail.Let04 where

{- SHOULD FAIL -- error class 7, LET SIGNATURE.
   Route: a `let` signature MORE GENERAL than its body can deliver.

   Pinned 2026-09-11 (LET-1).  `tooGeneral`'s declared type promises to work at EVERY
   type; the body adds one to its argument, which needs `Int` (`Num`'s `+` at
   `Primitive`).  Checking the declaration skolemises the quantified variable, and the
   body cannot unify the skolem with `Int`.  AT a15a97e THIS MODULE LOADED -- a dropped
   signature can neither restrict a binding nor widen it, and this is the widening half.

   Expected message (verbatim, default -Dermine.genRules=all; `!a` is how `Pretty`
   renders a SKOLEM):
     core/examples/shouldfail/let04_let_signature_too_general.e:23:7: error: failed to unify type !a with type Int

   Rule modes: rejected under all / cut / nongen.
-}

import Prelude

badTooGeneral =
  let tooGeneral : forall a. a -> Int
      tooGeneral x = x + 1
  in tooGeneral 2
