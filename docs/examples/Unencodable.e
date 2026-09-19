module Unencodable where

import Function
import Json
import Layout.Doc
import List using empty_Bracket; cons_Bracket

data P = P { who : String }

report : P -> Node
report p = vflow [rawWidget "text" "fine", rawWidget "broken" id]
