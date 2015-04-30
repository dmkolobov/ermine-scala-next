module LetAndPatternMatching where

import Prelude hiding product
import Int

-- a function for summing a list
product xs = 
  let go []     acc = acc
      go (h::t) acc = go t (h * acc)
  in go xs 1
