module Incomplete.Np04b where

{- NO BEST TYPE (4/5), companion -- SHOULD FAIL.

   np04's summary line with the cut written down at { asOfDate, regionName } |
   { orderCount, revenue }, called from the page where the caption is the date
   alone.  Under `captionIsDateOnly` -- an equally maximal typing of the same
   expression -- this call is fine.

   Fifteen of the sixteen valid splits are unreachable once the sixteenth is
   written; which fifteen depends on which one the author happened to need
   first.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false (rejected in
   0.05s):

     np04b_one_split_rejects_the_others.e:30:1: error: failed to unify type
     (|asOfDate, regionName|) with type (|asOfDate|)
-}

import Prelude
import Record using appendR

field asOfDate, regionName : String
field orderCount : Int
field revenue : Double

summaryLine : {asOfDate, regionName} -> {orderCount, revenue}
           -> {asOfDate, regionName, orderCount, revenue}
summaryLine caption figures = appendR caption figures

bad = summaryLine { asOfDate = "2026-08-31" }
                  { regionName = "California", orderCount = 63, revenue = 6975.00 }
