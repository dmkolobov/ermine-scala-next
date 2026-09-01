module Incomplete.Unsound02 where

{- *** SOUNDNESS BUG (2 of 4): unsatisfiable, accepted.  This module LOADS. ***
   Default mode, -Dermine.genRules=all.

   ------------------------------------------------------------------ scenario

   Same sharding job as `unsound01_keyed_halves.e`, but the ledger is split
   THREE ways instead of two -- one shard per storage tier, each stamped with
   `accountId` so the three can be re-joined:

       t  <- (a, b, c)              -- columns split into three shards
       ka <- ((|accountId|), a)     -- shard a, plus the key, is a legal header
       kb <- ((|accountId|), b)
       kc <- ((|accountId|), c)

   Satisfiable whenever the ledger row does not already contain `accountId`;
   `good` below is the compiler-checked witness that it is.

   ---------------------------------------------------------- what a user expects

   `bad` applies it to a ledger that DOES carry `accountId`.  The key is one of
   the columns being split, so it lands in a, b or c, and that shard then gets
   `accountId` twice.  Rejection.

   ------------------------------------------------------------- what happens

   OBSERVED 2026-09-01, branch scala3-migration:
     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/unsound02_three_way_shard.e </dev/null
     -> "Importing module 'Incomplete.Unsound02'" -- it loads

   `bad`'s annotation is monomorphic and mentions none of a, b, c, ka, kb, kc,
   so the wanted set has to be discharged in place.  It is reported solved.

   ------------------------------------------------- proof, by per-label analysis

   `accountId` is in (|accountId, regionCode, amount|) = a (+) b (+) c, so it is
   in exactly one of a, b, c.  Each of the three cases contradicts one of
   ka/kb/kc, whose two parts must be disjoint.  Unsatisfiable.

   --------------------------------------------------------------- why it misses

   This case is strictly harder for the solver than the two-way one, and shows
   the miss is not an off-by-one at some rule's arity threshold.  In
   `unsound01` the remainder of the split was two variables, one short of
   nothing in particular; here it is three, so `cancellation`'s lone-variable
   test (Constraints.scala:1029, 1031) is even further from firing, and
   `splitConcrete` still declines because the split carries no concrete part
   (`concr.isEmpty`, Constraints.scala:817).  The rule that would close it,
   `Disjunction` (Constraints.scala:1122), is called from nowhere: its three
   call sites are commented out at Constraints.scala:843, 854, 856.
-}

import Prelude

field accountId, regionCode : Int
field amount : Double

-- | A ledger is shardable three ways on the account key when its columns split
-- into three groups that each form a legal header once `accountId` is stamped
-- on.  Records the property in the type and passes the ledger through.
shardable3 : forall t a b c ka kb kc.
             ( t  <- (a, b, c)
             , ka <- ((|accountId|), a)
             , kb <- ((|accountId|), b)
             , kc <- ((|accountId|), c) )
          => [..t] -> [..t]
shardable3 src = src

-- CONTROL: no `accountId` column, so the property really holds.  Accepted.
good : [regionCode, amount]
good = shardable3 (relation [{ regionCode = 1, amount = 2.0 }])

-- THE BUG: `accountId` is already a column, so no three-way split works.
-- Should be rejected.  Compiles.
bad : [accountId, regionCode, amount]
bad = shardable3 (relation [{ accountId = 1, regionCode = 2, amount = 3.0 }])
