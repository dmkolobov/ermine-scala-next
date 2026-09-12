module Splice where

import Prelude

infixl 6 <^^>

spliceA : Int -> Int
spliceA x =
  let flag = x + 1
  in flag

spliceB b = keep
  where keep = b + 2

spliceC b = spliceA b

private
  spliceP : Int -> Int
  spliceP n = n + 3

(<^^>) x y = x + y

spliceD x = x <^^> 4
