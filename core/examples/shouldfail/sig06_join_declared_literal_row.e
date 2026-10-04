module ShouldFail.Sig06 where

{- SHOULD FAIL -- the signature's context is too weak (error class 6).

   The signature promises a relation over exactly (|a, b|) from any two
   relations.  The body's join only gives that when the operands' columns are
   a and b; the signature says nothing about them.

   What refutes it is `(|a, b|) <- (k, t1, t2)`, a partition with a literal
   column set on its left.  Until 2026-10 the check could not read that shape:
   it warned "NO VERDICT" and accepted.  The value then lies about its type:

       bad = joinLit (relation [{c = 1}]) (relation [{d = 2}])
       :type bad            Relation (|a, b|)
       bad                  a relation with columns c and d
       project {a} bad      Operation refers to nonexistent column (a) in header.

   The honest version is Lang/LiteralRowContext.e, `joinInto`.
-}

import Prelude

field a : Int
field b : Int

joinLit : Relation r1 -> Relation r2 -> Relation (|a, b|)
joinLit x y = join x y
