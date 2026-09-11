module UndefTy where

import Bool

-- THE CONTROL for ticket E7: no import failed here, so an undefined TYPE is a
-- real error and is reported.  The rule is conditional on a failed import, and
-- without this pin it could be a filter that drops the note outright.
paint : Shape -> Bool
paint s = True
