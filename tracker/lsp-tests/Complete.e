module Complete where

import Bool
import CompleteSib

data Colour = Red | Green

type Pair a = (a, a)

topFn : Bool -> Bool
topFn arg = arg && True

whereFn b = helper b
  where helper h = h || False

letFn c =
  let inner = c && True
  in inner

useSib = sibValue

useTop = topFn True

ranked = let n1 = False in not n1

msg = "not a name"
