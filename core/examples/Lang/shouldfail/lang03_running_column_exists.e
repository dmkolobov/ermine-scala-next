module Lang.Shouldfail.Lang03 where

{- NEGATIVE: a running-total column whose name the input row already has.

   `Helpers.withRunning`'s `t <- (r, c)` says the output row is the input row plus
   EXACTLY the new column, disjointly. Adding `runningSum` to rows that already carry
   `runningSum` would be a silent overwrite in a language with subtyping; here it is a
   compile error.

   EXPECTED:

     Fields appear twice in row: Lang.Shouldfail.Lang03.runningSum
-}

import Prelude
import List as L
import Lang.Helpers

field postRef    : String
field postAmount : Double
field runningSum : Double

alreadyRunning : List {postRef, postAmount, runningSum}
alreadyRunning = [ {postRef = "P-1", postAmount = 10.0, runningSum = 0.0}
                 , {postRef = "P-2", postAmount = 20.0, runningSum = 0.0} ]_L

badRunning = withRunning runningSum (s t -> s + (t ! postAmount)) 0.0 alreadyRunning
