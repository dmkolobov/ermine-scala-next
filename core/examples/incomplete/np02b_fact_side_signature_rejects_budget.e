module Incomplete.Np02b where

{- NO BEST TYPE (2/5), companion -- SHOULD FAIL.

   The Actuals reading of np02's `byRegion`, called with the Budget feed.  Under
   the other maximal typing (`dimSideMeasure` in np02) this exact call is fine.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false (rejected in
   0.03s):

     np02b_fact_side_signature_rejects_budget.e:31:1: error: failed to unify
     type (|orderId, regionId, amount|) with type (|orderId, regionId|)
-}

import Prelude
import Syntax.Relation

field orderId, regionId : Int
field amount : Double
field regionName : String

tradedRegions : [orderId, regionId]
tradedRegions = relation [{ orderId = 5001, regionId = 110 }]

regionBudget : [regionId, regionName, amount]
regionBudget = relation [
  { regionId = 110, regionName = "Pacific Northwest", amount = 3200.00 }]

factSideMeasure : [orderId, regionId, amount] -> [regionId, regionName]
               -> [regionName, amount]
factSideMeasure facts dims = (facts ** dims) # { regionName, amount }

bad = factSideMeasure tradedRegions regionBudget
