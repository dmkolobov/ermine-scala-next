module Incomplete.Gu08 where

{- INFERENCE GIVES UP WHERE CHECKING SUCCEEDS -- the library author's version,
   3 of 3: the control.

   THE SCENARIO.  Gu07's query with the abstraction removed: the conditional
   written out at the call site, exactly as core/examples/ai/SalesByRegion.e
   writes it.  Identical data, identical result, no helper.

   WHAT A COMPETENT USER EXPECTS.  The same thing as Gu07, since it is the same
   query.

   WHAT ACTUALLY HAPPENS.  This compiles.  See the family notes for the number.

   THE INCOMPLETENESS this establishes, jointly with Gu06 and Gu07: the cost is
   in neither the query nor the helper but in the ACT OF ABSTRACTING.  The rule
   core/examples/ai/Common.e follows -- "keep the conditional at the call site
   and let the helper take a ready-made Op" -- is this file, and it is a rule
   about working around the solver, not about designing a library.
-}

import Prelude
import Relation
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation

field orderId, productId, channelId : Int
field units : Double
field productName, channelName, isDirect, displayName : String

orderLine = relation [
  { orderId = 5001, productId = 1, channelId = 1, units = 120.0 },
  { orderId = 5002, productId = 2, channelId = 2, units =  40.0 } ]

productDim = relation [
  { productId = 1, productName = "Desk Lamp" },
  { productId = 2, productName = "Office Chair" } ]

channelDim = relation [
  { channelId = 1, channelName = "Direct",  isDirect = "yes" },
  { channelId = 2, channelName = "Partner", isDirect = "no" } ]

sales = orderLine ** productDim ** channelDim

labelled =
  combine_Op
    (if_Op (col_Op isDirect ==_Pred prim_Op "yes")
           (col_Op productName)
           (col_Op productName ++_Op prim_Op " via " ++_Op col_Op channelName))
    displayName
    sales
