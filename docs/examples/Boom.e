module Boom where

import Error
import Json
import Layout.Doc

data P = P { who : String }

report : P -> Node
report p = rawWidget "text" (error "no sales for that region")
