module Holes where

import Prelude
import Syntax.List
import Type.Remember

f x = x + 1 + _

f2 = map _ [1,2,3,4]

f3 = unify _ ([1,2,3,4] ++ [5,6,7,8])
