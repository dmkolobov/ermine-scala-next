module Ai.SupplyChainInventory where

{- Warehouse inventory where the LEAVES OF THE HIERARCHY ARE HETEROGENEOUS:
   a bin holds loose units, a pallet holds cases, and a container holds
   pallets. They are all "inventory items", but the sensible label for each
   is different, so `displayName` is computed from the unit kind with nested
   conditional Ops rather than read from a column.

   Fact:       stock    (itemId, locationId, unitKind, unitCount, unitWeightKg)
   Dimensions: item     (itemId -> sku, itemDesc, hazmat)
               location (locationId -> locationName, siteId, parentSiteId)

     >> :load core/examples/Ai/SupplyChainInventory.e
     >> render inventoryReport
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

field itemId, locationId : Int
field siteId, parentSiteId : Int
field sku, itemDesc, hazmat, unitKind, locationName : String
field displayName, storageLabel : String
field unitCount, unitWeightKg, totalWeightKg : Double
field value : Nullable Double

stock = relation [
  { itemId = 1, locationId = 1101, unitKind = "unit",      unitCount = 480.0, unitWeightKg =  0.4 },
  { itemId = 2, locationId = 1102, unitKind = "case",      unitCount =  36.0, unitWeightKg = 12.0 },
  { itemId = 3, locationId = 1201, unitKind = "pallet",    unitCount =   8.0, unitWeightKg = 410.0 },
  { itemId = 4, locationId = 2101, unitKind = "container", unitCount =   2.0, unitWeightKg = 9800.0 },
  { itemId = 5, locationId = 2102, unitKind = "unit",      unitCount = 1150.0, unitWeightKg = 0.1 }
]

itemDim = relation [
  { itemId = 1, sku = "LMP-0041", itemDesc = "Desk lamp, 12W LED",     hazmat = "no" },
  { itemId = 2, sku = "CHR-2210", itemDesc = "Task chair, mesh back",  hazmat = "no" },
  { itemId = 3, sku = "BAT-9001", itemDesc = "Lithium cell, 18650",    hazmat = "yes" },
  { itemId = 4, sku = "STL-0500", itemDesc = "Steel sheet, 0.5mm",     hazmat = "no" },
  { itemId = 5, sku = "INK-3300", itemDesc = "Solvent ink cartridge",  hazmat = "yes" }
]

locationDim = relation [
  { locationId = 1101, locationName = "Tacoma / Zone A / Bin 01" },
  { locationId = 1102, locationName = "Tacoma / Zone A / Bin 02" },
  { locationId = 1201, locationName = "Tacoma / Zone B / Rack 11" },
  { locationId = 2101, locationName = "Rotterdam / Yard / Slot 3" },
  { locationId = 2102, locationName = "Rotterdam / Zone C / Bin 07" }
]

inventory : [ itemId, locationId, unitKind, unitCount, unitWeightKg
            , sku, itemDesc, hazmat, locationName ]
inventory = stock ** itemDim ** locationDim

withWeight = combine_Op (col_Op unitCount *_Op col_Op unitWeightKg) totalWeightKg inventory

-- Three-way conditional: the noun that makes sense depends on the unit kind,
-- and hazmat items are flagged in the label regardless of kind.
labelled =
  combine_Op
    (if_Op (col_Op hazmat ==_Pred prim_Op "yes")
           (prim_Op "[HAZMAT] " ++_Op col_Op sku ++_Op prim_Op " - " ++_Op col_Op itemDesc)
           (if_Op (col_Op unitKind ==_Pred prim_Op "container")
                  (col_Op sku ++_Op prim_Op " (full container)")
                  (if_Op (col_Op unitKind ==_Pred prim_Op "pallet")
                         (col_Op sku ++_Op prim_Op " (palletised)")
                         (col_Op itemDesc))))
    displayName
    inventory

renamed = rename itemDesc storageLabel labelled

-- Network -> site -> zone -> location.
network = relation [
  { siteId = 1,    parentSiteId = 0,    locationName = "Network",                      value = Some 100.0 },
  { siteId = 10,   parentSiteId = 1,    locationName = "Tacoma",                       value = Some  45.0 },
  { siteId = 110,  parentSiteId = 10,   locationName = "Zone A",                       value = Some  25.0 },
  { siteId = 1101, parentSiteId = 110,  locationName = "Tacoma / Zone A / Bin 01",     value = Some  12.0 },
  { siteId = 1102, parentSiteId = 110,  locationName = "Tacoma / Zone A / Bin 02",     value = Some  13.0 },
  { siteId = 120,  parentSiteId = 10,   locationName = "Zone B",                       value = Some  20.0 },
  { siteId = 1201, parentSiteId = 120,  locationName = "Tacoma / Zone B / Rack 11",    value = Some  20.0 },
  { siteId = 20,   parentSiteId = 1,    locationName = "Rotterdam",                    value = Some  55.0 },
  { siteId = 2101, parentSiteId = 20,   locationName = "Rotterdam / Yard / Slot 3",    value = Some  40.0 },
  { siteId = 2102, parentSiteId = 20,   locationName = "Rotterdam / Zone C / Bin 07",  value = Some  15.0 }
]

networkTree = treeTable locationName parentSiteId siteId network

occupancyPie =
  pieChart_K
    ([pieTitle_O := "Capacity Used by Site",
      pieDrilldown_O := (parentSiteId, siteId)]_Opt)
    locationName value network

inventoryReport = vflow [
  atomShown "## Warehouse Inventory",
  occupancyPie,
  networkTree,
  atomShown "### Item detail (heterogeneous units)",
  tabular Nothing renamed
]
