module Headerless where

import Json
import Layout.Doc
import List using empty_Bracket; cons_Bracket
import Native.List
import Native.Relation

data P = P { who : String }

report : P -> Node
report p = widget "table" (mkRelation# (toList# []))
