module Shouldfail.Control10 where

{- A literal row on the left of a constraint in the signature's own context.

   A signature may say that a written-out row is partitioned by its variables:

       ((|a, b|) <- (k, t1, t2)) => ..

   Until 2026-10 the signature check dropped such a given, so it could never
   use it.  An honest body that needed the given got "NO VERDICT" and was
   accepted on trust.  Both bindings below need theirs, and now load without
   the warning.

   The dishonest counterparts are shouldfail/sig09 and sig10.
-}

import Prelude

field a : Int
field b : Int

-- `join`'s own context, with the result row written out.
joinInto : (r1 <- (k, t1), r2 <- (k, t2), (|a, b|) <- (k, t1, t2))
        => Relation r1 -> Relation r2 -> Relation (|a, b|)
joinInto x y = join x y

-- The given leaves `t` one value, (|b|), so projecting `b` out of it is safe.
hasB : ((|a, b|) <- ((|a|), t)) => Relation t -> Relation t
hasB x = join x (project {b} x)
