module Params where

import Json
import Layout.Doc
import List using empty_Bracket; cons_Bracket

data Scope = Everything | OneRegion { regionName : String }

data Filters = Filters { minAmount : Double, tags : List String }

data P = P { scope : Scope, filters : Filters, limit : Maybe Int }

report : P -> Node
report p = widget "echo" p
