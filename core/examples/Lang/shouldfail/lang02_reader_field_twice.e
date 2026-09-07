module Lang.Shouldfail.Lang02 where

{- NEGATIVE: a CSV row reader that reads the same column into the same field twice.

   `Helpers.consRow`'s `t <- (r, s)` is a DISJOINT union, so the field being added may
   not already be in the rest of the reader's row. A CSV whose header repeats a name is
   a real mistake, and this is where it is caught -- at compile time, in the reader,
   rather than at run time in the relation.

   EXPECTED:

     Fields appear twice in row: Lang.Shouldfail.Lang02.assetRef

   (this one carries no `error:` prefix -- it is raised during row CONSTRUCTION, before
   the solver is reached at all)
-}

import Prelude
import Lang.Helpers

field assetRef : String
field assetQty : Int

badReader = consRow (assetRef, 0, cellString)
              (consRow (assetQty, 1, cellInt)
                (consRow (assetRef, 2, cellString) nilRow))
