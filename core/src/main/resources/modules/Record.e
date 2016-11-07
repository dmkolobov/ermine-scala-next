module Record where

import Native.Record
import Native.Pair using fromPair#
import Native.List using fromList#
import Native.Ord
import Function
import Ord
import List using map_List as map
import Relation.Row

appendR : c <- (a,b) => {..a} -> {..b} -> {..c}
appendR = appendRec#

infixr 5 ++
(++) = appendR

-- | Unlike recordOrd in Relation.Sort, this just picks an arbitrary
-- sort.
anyRecordOrd : Ord {..r}
anyRecordOrd = contramap (scalaRecord# . record#) anyRecordOrd#

header : {..r} -> Row r
header = Row . map fromPair# . fromList# . header# . record#
