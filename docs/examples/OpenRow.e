module OpenRow where

import Json
import Layout.Doc
import Record

report : {..r} -> Node
report r = widget "text" "hi"
