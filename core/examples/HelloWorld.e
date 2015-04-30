module HelloWorld where

import Prelude
import Layout

report : Int -> Report f z
report reportId = vspan [ atomShown "Important heading!", atomShown reportId ]
