module MinReproUse where

{- Minimal reproducer for tracker/TICKET-signature-resolution-fragility.md.

   Distilled from Ai/HeadcountPlan.e's `withUnitCost`, one `combine_Op` adding a
   derived column to a relation with a concrete header.  `derived` MUST stay
   unannotated: inference is what produces the four-constraint shape.
-}

import Prelude
import Relation.Op as Op

field a, b, c : Double
field extra : Double

base : [ a, b, c ]
base = relation [{ a = 1.0, b = 2.0, c = 3.0 }]

derived = combine_Op (col_Op a /_Op col_Op b) extra base

-- a downstream use at a concrete header
use : [ a, b, c, extra ]
use = derived
