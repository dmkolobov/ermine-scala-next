module Incomplete.Witness01C where

{- CASE 3 OF 4 in the per-label case analysis that proves the constraint set of
   `unsound01_keyed_halves.e` unsatisfiable.  THIS FILE MUST FAIL.

   Same `shardable` property, but the split is pinned by a second argument
   `Row l`, so this file names one concrete choice of l (and hence of s):

       l = (|regionCode|), s = (|accountId|) -- so accountId is in s, and rt <- ((|accountId|), s) repeats it

   OBSERVED 2026-09-01, -Dermine.useInterface=false, default genRules=all:
     witness01_case3_right_key.e:28:1: Fields appear twice in row: Set(Incomplete.Witness01C.accountId)

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
w = shardableAt (single_Rw regionCode) (relation [{ accountId = 1, regionCode = 2 }])
