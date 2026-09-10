module Fix where

import Maybe using isJust
import Function hiding id
import FixTy using paint

-- Two unsigned groups whose inferred types this file CAN write: the
-- add-signature action offers both, and "add all missing signatures"
-- inserts exactly these two lines.
answer = 42

pairUp a = (a, a)

-- An unsigned group whose inferred type names `Colour` -- a type this
-- file does not import, since its FixTy list names only the term
-- `paint`.  No signature action: the inserted line would not parse.
peek = paint

-- A signed binding: no signature action for it.
signed : Int
signed = 7
