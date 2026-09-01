module Shouldfail.Der08 where

{- SHOULD FAIL -- error class 1, DUPLICATED FIELD, derived, generativity-
   sensitive.  der06 expressed over RELATIONS (`[..r]`) rather than row
   headers, so the case does not depend on the `Row` type constructor.

   *** GENERATIVITY-SENSITIVE. ***
   Observed:  -Dermine.genRules=all     -> REJECTED
              -Dermine.genRules=cut     -> REJECTED
              -Dermine.genRules=nongen  -> LOADS.

   This is the shape a real row-polymorphic reporting helper has: it names the
   columns it needs and carries an anonymous remainder.  Two such helpers
   sharing a remainder of more than one variable is exactly the situation
   `commonSubexpression` was written for, and it is the situation whose
   refutation the fully non-generative calculus drops.

       t <- ((|a|), x, y)      with t = (|a, b, c|)   so  x + y = (|b, c|)
       u <- ((|b|), x, y)      with u = (|b, c|)      so  `b` twice

   Expected message (verbatim, default -Dermine.genRules=all):
     core/examples/shouldfail/der08_shared_remainder_relations.e:40:1: Fields appear twice in row: Set(Shouldfail.Der08.b)

   Raised by: Constraints.scala:329, `RHS.merge`
     else tml.die("Fields appear twice in row: " + cint)
-}

import Prelude

field a, b, c : Int

abc : [a, b, c]
abc = relation [{ a = 1, b = 2, c = 3 }]

bc : [b, c]
bc = relation [{ b = 2, c = 3 }]

pairR : forall t u x y. (t <- ((|a|), x, y), u <- ((|b|), x, y))
     => [..t] -> [..u] -> Int
pairR _ _ = 0

bad = pairR abc bc
