module Refs where

import Bool

shared : Bool -> Bool
shared b = b && True

localHome b =
  let mine = b || False
  in mine && (mine || mine)

quiet = shared True

onlyHere = True
