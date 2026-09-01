module Lab.AnnConc4 where

{- INFERENCE GIVES UP WHERE CHECKING SUCCEEDS -- and so, sometimes, does
   checking.  The escape hatch of Gu04, written the way a report author would
   actually write it.

   THE SCENARIO.  Gu01's star join, cut down to FOUR dimensions, with the type
   signature a person actually writes.  Nobody hand-derives a 24-constraint
   partition system; what they write is the column list, because they know the
   columns -- that is the whole point of a warehouse schema.  It is also exactly
   what core/examples/ai/SalesByRegion.e does:

       sales : [ orderId, productId, regionId, channelId, units, unitPrice
               , productName, productLine, regionName, channelName, isDirect ]

   So the same thing, one table wider and with the inputs named:

       wideOrderLines : [ orderId, productId, ... ] -> [ productId, productName ]
                     -> ... -> [ every column ]

   WHAT A COMPETENT USER EXPECTS.  Fully concrete rows on every arrow and no
   variables anywhere.  There is nothing left to infer: the checker can read the
   header off each argument, take the union, and compare.  This should be the
   FASTEST form of the query, not the slowest.

   WHAT ACTUALLY HAPPENS.  The same definition with NO signature at four
   dimensions takes 0.14s (the 4-dimension rung of Gu01's ladder).  With the
   signature it does not come back.  Measured on this shape, one JVM per file:

       dimensions   no signature   concrete-column signature
       2            0.03s          0.10s
       3            0.05s          0.23s
       4            0.14s          (see family notes -- does not return)

   THE INCOMPLETENESS.  Gu04 says the way out of the inference blow-up is to
   write the signature down.  This file says: only if you write down the
   signature the SOLVER wanted, not the one that describes your data.  Concrete
   labels are what turn partition solving from the (trivially satisfiable)
   homogeneous case into the NP-hard one -- the solver has to decide which of
   the named columns lands in which part of each partition, and at four
   dimensions there are enough parts for that to matter.  A user who follows the
   advice "add a type signature" with the signature they can actually write ends
   up worse off than before.
-}

import Prelude
import Relation
import Syntax.Relation

field orderId, productId, regionId, channelId, dayId : Int
field units : Double
field productName, regionName, channelName, monthName : String

wideOrderLines :
     [ orderId, productId, regionId, channelId, dayId, units ]
  -> [ productId, productName ]
  -> [ regionId, regionName ]
  -> [ channelId, channelName ]
  -> [ dayId, monthName ]
  -> [ orderId, productId, regionId, channelId, dayId, units
     , productName, regionName, channelName, monthName ]
wideOrderLines orderLine productDim regionDim channelDim calendarDim =
  orderLine ** productDim ** regionDim ** channelDim ** calendarDim
