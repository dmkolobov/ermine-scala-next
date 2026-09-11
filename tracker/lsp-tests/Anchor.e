module Anchor where

import Bool

data Shade = Light Bool | Dark Bool

anchorLet : Bool -> Bool
anchorLet x =
  let flag = x && True
  in flag

anchorWhere b = keep
  where keep = b || False

anchorUse b = anchorLet b

noSig b = b && True

anchorPlain b = (let inner = b || True in inner)
