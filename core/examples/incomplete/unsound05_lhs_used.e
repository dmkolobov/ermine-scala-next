module Incomplete.Unsound05 where

{- Does requiring every partition LHS to be USED close the hole?  No.

   `unsound01_keyed_halves.e` has `lt` and `rt` appearing only as partition
   left-hand sides and nowhere else in the type -- which looks like the defect.
   This module removes that property: `shardable` RETURNS the two shards, so
   `lt` and `rt` are both used, in the result type, as ordinary rows.

   The constraint set is character-for-character the one in unsound01, and it
   is unsatisfiable for the same reason: `accountId` is in t = l (+) s, so it
   is in l or in s, and either way the corresponding shard header repeats it.

   Expected if a use-requirement were the fix: rejected.
-}

import Prelude

field accountId, regionCode : Int
field amount : Double

-- Every quantified row variable now occurs in the type, not just as a
-- partition LHS: t in the argument, lt and rt in the result.
shardTo : forall t l s lt rt.
          ( t  <- (l, s)
          , lt <- ((|accountId|), l)
          , rt <- ((|accountId|), s) )
       => [..t] -> ([..lt], [..rt])
shardTo src = (relation [], relation [])

-- CONTROL: ledger without the key.  Genuinely shardable.
good05 : ([accountId, regionCode], [accountId, amount])
good05 = shardTo (relation [{ regionCode = 1, amount = 2.0 }])

-- THE BUG, with every LHS used.  Should be rejected.
bad05 : ([accountId, regionCode], [accountId])
bad05 = shardTo (relation [{ accountId = 1, regionCode = 2 }])
