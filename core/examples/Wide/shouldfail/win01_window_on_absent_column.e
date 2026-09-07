module Wide.Shouldfail.Win01 where

{- SHOULD FAIL -- a window partitioned by a column the relation does not have.

   `rankWithin`'s signature carries
       w <- (k, s)        -- the window row is the partition plus the sort
       r <- (w, o)        -- the relation contains the window row, plus a rest
   so partitioning by `divisionName` a relation that has no `divisionName`
   asks the solver to split a concrete row on a field that is not in it.

   This is the ordinary typo -- a column renamed upstream, a window left
   pointing at the old name -- and it is the failure a reporting language has
   to catch, because at runtime it would silently rank the whole table as one
   partition.

   Expected message: see Wide/shouldfail/RESULTS.md.
-}

import Prelude
import Syntax.Relation
import Wide.Helpers

field teamName : String
field points : Double
field divisionName : String
field seed : Int

scores : [ teamName, points ]
scores = relation [{ teamName = "Meridian", points = 41.0 }]

-- `divisionName` is not a column of `scores`.
bad = rankWithin {divisionName} (desc points) seed scores
