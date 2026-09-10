module CompleteSib where

import Bool
import Layout.Scan
import Syntax.Do

sibValue : Bool
sibValue = True

doFn f fa fb = do
  dx <- fa
  dy <- fb
  unit (f dx dy)
