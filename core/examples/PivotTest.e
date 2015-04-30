
module PivotTest where

import Prelude
import Relation.Pivot hiding single_Brace; snoc_Brace
import Relation.Op using col

field Issue : String
field Key, Value : String
field Sector, Price, MarketCap : String

myData : Mem (| Issue, Key, Value |)
myData = mem
  [ { Issue = "MSFT", Key = "Sector", Value = "Technology" }
  , { Issue = "MSFT", Key = "Price", Value = "33.72" }
  , { Issue = "MSFT", Key = "MarketCap", Value = "282B" }
  , { Issue = "GOOG", Key = "Sector", Value = "Technology" }
  , { Issue = "GOOG", Key = "Price", Value = "1025" }
  , { Issue = "GOOG", Key = "MarketCap", Value = "342B" }
  , { Issue = "MHFI", Key = "Sector", Value = "Finance" }
  , { Issue = "MHFI", Key = "Price", Value = "9000" }
  , { Issue = "MHFI", Key = "MarketCap", Value = "9000B" }
  , { Issue = "MCO",  Key = "Sector", Value = "Finance" }
  , { Issue = "MCO",  Key = "Price", Value = "1" }
  , { Issue = "MCO",  Key = "MarketCap", Value = "12" }
  , { Issue = "PCLN", Key = "Sector", Value = "Shatner" }
  , { Issue = "PCLN", Key = "Price", Value = "10000" }
  , { Issue = "PCLN", Key = "MarketCap", Value = "Unlimited" }
  ]

f0 = nilFulcrum {Key} {Value}
f1 = consFulcrum Sector (col Value) { Key = "Sector" } f0
f2 = consFulcrum Price (col Value) { Key = "Price" } f1
f3 = consFulcrum MarketCap (col Value) { Key = "MarketCap" } f2

pivotData = pivot f3 myData

myData2 : Mem (| Issue, Key, Value |)
myData2 = mem
  [ { Issue = "MSFT", Key = "Sector", Value = "Technology" }
  , { Issue = "MSFT", Key = "Price", Value = "33.72" }
  , { Issue = "MSFT", Key = "MarketCap", Value = "282B" }
  , { Issue = "GOOG", Key = "Sector", Value = "Technology" }
  , { Issue = "GOOG", Key = "Price", Value = "1025" }
  , { Issue = "GOOG", Key = "MarketCap", Value = "342B" }
  , { Issue = "MHFI", Key = "Sector", Value = "Finance" }
  , { Issue = "MHFI", Key = "Price", Value = "9000" }
  , { Issue = "MHFI", Key = "MarketCap", Value = "9000B" }
  , { Issue = "MCO",  Key = "Sector", Value = "Finance" }
  , { Issue = "MCO",  Key = "Price", Value = "1" }
  , { Issue = "MCO",  Key = "MarketCap", Value = "12" }
  , { Issue = "PCLN", Key = "Sector", Value = "Shatner" }
  , { Issue = "PCLN", Key = "Price", Value = "10000" }
  -- , { Issue = "PCLN", Key = "MarketCap", Value = "Unlimited" }
  ]

pivotData2 = pivot f3 myData2
