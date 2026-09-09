module Tauto where

import Prelude
import Layout.Scan as LS

posSig : r <- (h, t) => Relation r -> Relation r
posSig x = x
pos = posSig
usePos = pos

concSig : r <- (h, (|foo|)) => Relation r -> Relation r
concSig x = x
conc = concSig
useConc = conc

tCount = count_LS
useCount = tCount
