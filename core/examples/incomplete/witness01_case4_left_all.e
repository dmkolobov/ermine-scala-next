module Incomplete.Witness01D where

{- CASE 4 OF 4 in the per-label case analysis that proves the constraint set of
   `unsound01_keyed_halves.e` unsatisfiable.  THIS FILE MUST FAIL.

   Same `shardable` property, but the split is pinned by a second argument
   `Row l`, so this file names one concrete choice of l (and hence of s):

       l = (|accountId, regionCode|), s = (| |) -- so accountId is in l, and lt <- ((|accountId|), l) repeats it

   OBSERVED 2026-09-01, -Dermine.useInterface=false, default genRules=all:
     witness01_case4_left_all.e:23:28: Fields appear twice in row: Incomplete.Witness01D.accountId

   All four ground splits of (|accountId, regionCode|) are refuted, one per
   witness file.  The flagship module states their disjunction and is ACCEPTED.
-}

import Prelude
import Relation.Row as Rw

field accountId, regionCode : Int

shardableAt : forall t l s lt rt.
              ( t  <- (l, s)
              , lt <- ((|accountId|), l)
              , rt <- ((|accountId|), s) )
           => Row l -> [..t] -> [..t]
shardableAt _ src = src

w : [accountId, regionCode]
w = shardableAt (append_Rw (single_Rw accountId) (single_Rw regionCode)) (relation [{ accountId = 1, regionCode = 2 }])
