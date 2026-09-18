module FetchData where

-- The two relations the `Fetch*` example reports share (stage J3f,
-- `Layout.Fetch`): literal rows, so the reports run on the in-memory SQLite
-- connection the runner opens per request, and every scan of them is a
-- SQL scan of a `VALUES` literal -- the same path a database table takes.

import Date
import List using empty_Bracket; cons_Bracket
import Relation

field region : String
field day    : Date
field amount : Double
field units  : Int
field target : Double

-- eight sales in four regions; north 4350.75, south 2605.75, east 4175.5,
-- west 1550.0, all 12682.0
sales : [region, day, amount, units]
sales = relation
  [ { region = "north", day = @2026/1/5,  amount = 1200.5,  units = 3 }
  , { region = "north", day = @2026/1/19, amount = 840.0,   units = 2 }
  , { region = "north", day = @2026/2/14, amount = 2310.25, units = 7 }
  , { region = "south", day = @2026/1/9,  amount = 615.75,  units = 1 }
  , { region = "south", day = @2026/2/2,  amount = 1990.0,  units = 5 }
  , { region = "east",  day = @2026/2/20, amount = 75.5,    units = 1 }
  , { region = "east",  day = @2026/3/3,  amount = 4100.0,  units = 11 }
  , { region = "west",  day = @2026/3/17, amount = 1550.0,  units = 4 }
  ]

-- a target per region: north and east meet theirs, south and west do not
targets : [region, target]
targets = relation
  [ { region = "north", target = 4000.0 }
  , { region = "south", target = 3000.0 }
  , { region = "east",  target = 2000.0 }
  , { region = "west",  target = 2500.0 }
  ]
