module Present.Shouldfail.Box01 where

{- NEGATIVE. `styleBox`'s CELL COORDINATES included in its legend.

   `styleBox`'s two partitions are

       r <- (px, py, xv, yv, av, other)
       l <- (xv, yv, av, other)

   -- the legend `l` carries everything the fact row `r` does EXCEPT the two
   position columns, because those are the layout and not the content. Putting
   `xPos` in the legend makes the second partition demand a column the first
   partition has already given to `px`, and the two cannot both hold.

   This is the mistake the module header of `Present/StyleGridHeatmap.e`
   predicts a reader will make.

   EXPECTED (verbatim):

     Fields appear twice in row: Present.Shouldfail.Box01.xPos

   -- which is the clearest wording the solver has: `xPos` is claimed by the
   position part AND by the legend part of the same partition.
-}

import Prelude
import Layout
import Layout.Legend as Lg
import Layout.SortPriority
import Native.List
import Native.Pair
import Syntax.Relation
import Syntax.List

field xPos, yPos : Int
field probScore, impactScore, residualScore : Double

heatCells : [ xPos, yPos, probScore, impactScore, residualScore ]
heatCells = relation [ { xPos = 0, yPos = 0, probScore = 1.0, impactScore = 1.0,
                     residualScore = 1.0 } ]

-- The legend wrongly includes the x POSITION column.
wrongLegend : Legend_Lg (| xPos, probScore, impactScore, residualScore |)
wrongLegend = fromRow_Lg { xPos, probScore, impactScore, residualScore }

bins = toList# [ toPair# (0.5, 1.5), toPair# (1.5, 2.5) ]

-- REJECTED: `xPos` cannot be both a position column and a legend column.
bad = styleBox (wrongLegend, probScore, impactScore, residualScore)
               True ["a", "b"] ["c", "d"] bins bins xPos yPos heatCells
