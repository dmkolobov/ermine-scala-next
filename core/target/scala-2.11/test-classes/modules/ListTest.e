module ListTest where

import Eq
import Function
import Control.Monad.Id
import Native.Bool
import Native.List
import Pair using mapSnd
import Syntax.List using map
import List

-- Test that spanM is reasonably nonstrict.
spanMNonStrict =
  mapSnd (take 5) (runIdentity $ spanM idMonad (const $ Id False) (repeat 42))
   == ([], [42, 42, 42, 42, 42])

testMain = [spanMNonStrict]

testMainNative# = toList# (map toBool# testMain)
