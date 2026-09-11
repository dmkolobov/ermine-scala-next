module BadTy where

import NoSuchTypeModule

-- TICKET E7.  `Shape` would have come from the module that did not load, so
-- "undefined type" here is a CONSEQUENCE, not a diagnostic: the import failure
-- above is the thing to act on, and it is the only thing reported.
paint : Shape -> Int
paint s = 1
