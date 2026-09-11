module Burst where

import Prelude

burstA : Int -> Int
burstA x = x + 1

burstB y = burstA (y + 2)
