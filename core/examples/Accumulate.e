module Accumulate where

import Prelude
import Relation.Aggregate as A
import Nullable
import Num

field parentId : Int
field nodeId : Int
field name : String
field value : Nullable Double

hierarchy = mem [
  {parentId = 0, nodeId = 1, name = "Total"},
    {parentId = 1, nodeId = 2, name = "Tech"},
      {parentId = 2, nodeId = 3, name = "Google"},
      {parentId = 2, nodeId = 4, name = "Microsoft"},
      {parentId = 2, nodeId = 5, name = "Apple"},
    {parentId = 1, nodeId = 6, name = "Financial"},
      {parentId = 6, nodeId = 7, name = "Wells Fargo"},
      {parentId = 6, nodeId = 8, name = "Citibank"},
      {parentId = 6, nodeId = 9, name = "Bank Of America"}
  ]

metric = mem [
  {name = "Google", value = Some 1.0},
  {name = "Microsoft", value = Some 0.5},
  {name = "Apple", value = Some 0.75},
  {name = "Wells Fargo", value = Some 0.8},
  {name = "Citibank", value = Some 0.9},
  {name = "Bank Of America", value = Some 0.4}
] |> join hierarchy |> except {name}

report = let f = aggregate_A (sum_A value) value
         in accumulate parentId nodeId f metric hierarchy
            |> join hierarchy
            |> drilldownTable Nothing name parentId nodeId

