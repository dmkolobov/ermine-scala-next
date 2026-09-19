module Nulls where

import Date
import Json
import Layout.Doc
import List using empty_Bracket; cons_Bracket
import Nullable
import Prim
import Relation

field city : String
field score : Nullable Double
field ident : Long
field stamp : Timestamp

data P = P { who : Maybe String }

report : P -> Node
report p = rawWidget "table" (relation
  [ { city = "a", score = Some 1.5, ident = 9007199254740993L, stamp = timestampFromLong 1767625445123L }
  , { city = "b", score = Null Double, ident = 0L, stamp = timestampFromLong 0L } ])
