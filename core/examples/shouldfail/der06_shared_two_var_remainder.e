module Shouldfail.Der06 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD, reached only through a
   DERIVED constraint, and ONLY WHEN A RULE IS ALLOWED TO MINT A FRESH NAME.

   *** THIS IS A GENERATIVITY-SENSITIVE CASE. ***
   Observed:  -Dermine.genRules=all     -> REJECTED (message below)
              -Dermine.genRules=cut     -> REJECTED (same message)
              -Dermine.genRules=nongen  -> LOADS.  The program compiles.

   `pair`'s two givens share a TWO-VARIABLE remainder `x, y`:

       t <- ((|a|), x, y)
       u <- ((|b|), x, y)

   satisfiable in general (control:
   core/examples/shouldfail-controls/control07_pair.e).  Instantiated at
   `pair abc bc` it becomes

       (|a, b, c|) <- ((|a|), x, y)      so  x + y = (|b, c|)
       (|b, c|)    <- ((|b|), x, y)      so  u would contain `b` twice

   Nothing in that set names `x + y`, and no row in it mentions a field twice.
   The solver can only see the contradiction after the remainder gets a NAME:

     * `commonSubexpression` (Constraints.scala:1089) sees the two partitions
       sharing {x, y}; neither right-hand side IS that set and no existing
       variable denotes it, so it reaches its minting branch -- the one guarded
       by `GenRules.cseMints` at Constraints.scala:1104 -- and creates
       `z <- (x, y)`, rewriting both rules over `z`.
     * `splitConcrete` (Constraints.scala:816) mints the same name on its own
       from `(|a,b,c|) <- ((|a|), x, y)`; that branch is guarded by
       `GenRules.splitMints` at Constraints.scala:821.

   Once the remainder is a single variable, cancellation applies (it requires a
   LONE variable, `xs.size == 1`, Constraints.scala:1029) and yields
   `z <- (|b, c|)`; substituting that into `u <- ((|b|), z)` merges (|b|) with
   (|b, c|) and `b` appears twice.

   Under `nongen` neither rule mints, the remainder is never named, cancellation
   never fires (two variables, not one), and the module type-checks.  `cut`
   keeps `splitConcrete`'s mint, which is enough.

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/der06_shared_two_var_remainder.e:64:1: Fields appear twice in row: Set(Shouldfail.Der06.b)

   Raised by: Constraints.scala:329, `RHS.merge`
     else tml.die("Fields appear twice in row: " + cint)
-}

import Prelude
import Relation.Row as Rw

field a, b, c : Int

abc : Row (|a, b, c|)
abc = append_Rw (single_Rw a) (append_Rw (single_Rw b) (single_Rw c))

bc : Row (|b, c|)
bc = append_Rw (single_Rw b) (single_Rw c)

pair : forall t u x y. (t <- ((|a|), x, y), u <- ((|b|), x, y))
    => Row t -> Row u -> Int
pair _ _ = 0

bad = pair abc bc
