module Ai.SalesByRegion where

{- Sales fact against three dimensions, rolled up through a geography
   hierarchy expressed with territoryId / parentTerritoryId.

   Fact:       orders  (orderId, productId, regionId, channelId, units, unitPrice)
   Dimensions: product (productId -> productName, productLine)
               region  (regionId  -> regionName, territoryId, parentTerritoryId)
               channel (channelId -> channelName, isDirect)

     >> :load core/examples/Ai/SalesByRegion.e
     >> render salesReport
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Ai.Common

field orderId, productId, regionId, channelId : Int
field territoryId, parentTerritoryId : Int
field productName, productLine, regionName, channelName : String
field displayName, isDirect, salesLabel : String
field units, unitPrice, revenue : Double
field value : Nullable Double

orders = relation [
  { orderId = 5001, productId = 1, regionId = 110, channelId = 1, units = 120.0, unitPrice = 24.99 },
  { orderId = 5002, productId = 2, regionId = 110, channelId = 2, units =  40.0, unitPrice = 149.00 },
  { orderId = 5003, productId = 1, regionId = 120, channelId = 1, units = 310.0, unitPrice = 22.50 },
  { orderId = 5004, productId = 3, regionId = 210, channelId = 2, units =  15.0, unitPrice = 899.00 },
  { orderId = 5005, productId = 2, regionId = 220, channelId = 1, units =  75.0, unitPrice = 139.00 }
]

productDim = relation [
  { productId = 1, productName = "Desk Lamp",     productLine = "Lighting" },
  { productId = 2, productName = "Office Chair",  productLine = "Seating" },
  { productId = 3, productName = "Standing Desk", productLine = "Surfaces" }
]

regionDim = relation [
  { regionId = 110, regionName = "Pacific Northwest" },
  { regionId = 120, regionName = "California" },
  { regionId = 210, regionName = "Ile-de-France" },
  { regionId = 220, regionName = "Bavaria" }
]

channelDim = relation [
  { channelId = 1, channelName = "Direct",  isDirect = "yes" },
  { channelId = 2, channelName = "Partner", isDirect = "no" }
]

-- Four-way star join.
sales : [ orderId, productId, regionId, channelId, units, unitPrice
        , productName, productLine, regionName, channelName, isDirect ]
sales = orders ** productDim ** regionDim ** channelDim

withRevenue = combine_Op (col_Op units *_Op col_Op unitPrice) revenue sales

-- Direct sales are shown by product; partner sales carry the channel name,
-- because a partner order for the same product is a different line item to a
-- reader. That is the conditional the display column encodes.
labelled =
  combine_Op
    (if_Op (col_Op isDirect ==_Pred prim_Op "yes")
           (col_Op productName)
           (col_Op productName ++_Op prim_Op " via " ++_Op col_Op channelName))
    displayName
    sales

-- Rename the source column so the rendered table does not repeat it.
renamed = rename productLine salesLabel labelled

-- Geography rollup: World -> continent -> country -> region.
geography = relation [
  { territoryId = 1,   parentTerritoryId = 0,  regionName = "Worldwide",         value = Some 100.0 },
  { territoryId = 10,  parentTerritoryId = 1,  regionName = "North America",     value = Some  62.0 },
  { territoryId = 110, parentTerritoryId = 10, regionName = "Pacific Northwest", value = Some  25.0 },
  { territoryId = 120, parentTerritoryId = 10, regionName = "California",        value = Some  37.0 },
  { territoryId = 20,  parentTerritoryId = 1,  regionName = "Europe",            value = Some  38.0 },
  { territoryId = 210, parentTerritoryId = 20, regionName = "Ile-de-France",     value = Some  22.0 },
  { territoryId = 220, parentTerritoryId = 20, regionName = "Bavaria",           value = Some  16.0 }
]

geographyTree = treeTable regionName parentTerritoryId territoryId geography

revenuePie =
  pieChart_K
    ([pieTitle_O := "Revenue Share by Geography",
      pieDrilldown_O := (parentTerritoryId, territoryId)]_Opt)
    regionName value geography

headline = grid [
  [atomShown "Orders",   atomShown "5"],
  [atomShown "Regions",  atomShown "4"],
  [atomShown "Channels", atomShown "Direct / Partner"]
]

salesReport = vflow [
  atomShown "## Sales by Region",
  headline,
  revenuePie,
  geographyTree,
  atomShown "### Order detail",
  tabular Nothing renamed
]
