module Shouldfail.Control08 where

-- MUST LOAD. Control for sig01 / sig02 / sig03 / sig04: the same bodies under HONEST
-- signatures, in the four spellings a fix must keep accepting -- explicit partition,
-- `Has`, a let-bound signature, and a two-row library helper (the consRow shape,
-- Lang/Helpers.e) whose wanted mentions BOTH signature variables.  If a control stops
-- loading, the corresponding should-fail case is no longer evidence of anything.

import Prelude

field position : Double
field health   : Int
field mana     : Nullable Int

healthWith : forall r t. r <- ((|health|), t) => {..r} -> Int
healthWith r = r ! health

healthHas : forall r. Has r (|health|) => {..r} -> Int
healthHas r = r ! health

bumpWith : forall r t. r <- ((|health|), t) => {..r} -> {..r}
bumpWith = modify health (h -> h + 1)

localWith = let f : forall r t. r <- ((|health|), t) => {..r} -> Int
                f r = r ! health
            in f { position = 1.0, health = 10 }

tagged : forall t r. t <- ((|health|), r) => Int -> {..r} -> {..t}
tagged h rec = cons health h rec

ok1 = healthWith { position = 1.0, health = 10, mana = Some 3 }
ok2 = healthHas  { position = 1.0, health = 10 }
ok3 = bumpWith   { position = 1.0, health = 10 }
ok4 = tagged 3   { position = 1.0 }
