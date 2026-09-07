module Present.Shouldfail.Box02 where

{- NEGATIVE. A treemap whose INTENSITY and SIZE are the same column.

   `treemapChart`'s constraint is

       r <- (labels, ivalue, svalue, r1, r2, o)

   -- a partition, hence disjoint, so the colour measure and the area measure
   must be DIFFERENT columns. Passing the same field twice asks the solver to
   put one field in two parts of one partition.

   The mistake is natural: "colour it and size it by impact" is a sentence a
   person would say. The answer is to combine the column with itself under a
   second name first (`combine_Op (col_Op impact) intensity`), which is
   honest about the fact that the treemap is reading it twice.

   EXPECTED (verbatim):

     Fields appear twice in row: Present.Shouldfail.Box02.nodeImpact
-}

import Prelude
import Layout
import Layout.Presentation as Pres
import Syntax.Relation

field nodeKey, parentKey : Int
field nodeName : String
field nodeImpact : Double

nodes : [ nodeKey, parentKey, nodeName, nodeImpact ]
nodes = relation [ { nodeKey = 1, parentKey = 0, nodeName = "All",
                     nodeImpact = 100.0 } ]

-- REJECTED: intensity and size are the same column.
bad = treemapChart parentKey nodeKey nodeName
                   (basic_Pres nodeImpact) (basic_Pres nodeImpact) nodes
