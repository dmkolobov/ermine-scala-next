module LocalsDo where

import Bool
import Syntax.Do

doLocal ma = do
  dres <- ma
  unit (dres && True)
