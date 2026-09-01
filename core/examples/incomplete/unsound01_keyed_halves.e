module Incomplete.Unsound01 where

{- *** SOUNDNESS BUG: THE SHIPPED SOLVER ACCEPTS AN UNSATISFIABLE PROGRAM ***
   Default mode, -Dermine.genRules=all.  This module LOADS.

   ------------------------------------------------------------------ scenario

   A general ledger is too wide for one table, so it gets sharded vertically:
   the columns are split into two groups and each group is written to its own
   table with the account key stamped on, so the two shards can be re-joined on
   `accountId` later.  "Splittable this way" is a property of the ledger's row,
   and Ermine lets you say it in a signature:

       t  <- (l, s)                 -- the columns split into two groups
       lt <- ((|accountId|), l)     -- group l, plus the key, is a legal header
       rt <- ((|accountId|), s)     -- group s, plus the key, is a legal header

   That is `shardable` below.  The constraint set is SATISFIABLE -- it holds of
   any ledger row that does not already contain `accountId` -- and the call
   `good` below proves it by exhibiting an instance the compiler accepts.

   ---------------------------------------------------------- what a user expects

   Apply `shardable` to a ledger that DOES already carry `accountId` and the
   property is false: the key is one of the columns being split, so it lands in
   l or in s, and then the corresponding half gets `accountId` twice.  This is
   the everyday version of the mistake -- you forgot to drop the key before
   splitting.  Ermine's whole pitch is that row types catch exactly this, and
   `core/examples/shouldfail/` has 40 cases showing it usually does.

   ------------------------------------------------------------- what happens

   OBSERVED 2026-09-01, branch scala3-migration:
     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/unsound01_keyed_halves.e </dev/null
     -> "Importing module 'Incomplete.Unsound01'" -- it loads

   `bad` is accepted.  Note its ANNOTATION: `[accountId, regionCode]` is
   monomorphic and mentions none of l, s, lt, rt, so nothing can be deferred
   into a residual -- the solver has to discharge the whole wanted set here and
   now.  `:browse` confirms it believes it did:

       bad : Relation (|accountId, regionCode|)

   No constraint context.  The solver reports "solved" on

       (|accountId, regionCode|) <- (l, s)
       lt <- ((|accountId|), l)
       rt <- ((|accountId|), s)

   which has no solution at all.

   ------------------------------------------------- proof, by per-label analysis

   Only the label `accountId` matters.  `accountId` is in
   (|accountId, regionCode|) = l (+) s, so it is in l or in s.
     * accountId in l  contradicts  lt <- ((|accountId|), l)  (parts are disjoint)
     * accountId in s  contradicts  rt <- ((|accountId|), s)
   Unsatisfiable.  The four ground splits of (|accountId, regionCode|) are the
   four `witness01_*.e` files in this directory; the compiler REJECTS every one
   of them with "Fields appear twice in row: ... accountId".  It refutes each
   case and accepts their disjunction.

   --------------------------------------------------------------- why it misses

   The needed step is elimination: `accountId` is somewhere in l (+) s, it is
   not in l, so it is in s -- contradiction.  Ermine documents that rule
   (`Disjunction`, Constraints.scala:1114-1121) and implements it
   (Constraints.scala:1122), but ALL THREE of its call sites are commented out
   (Constraints.scala:843, 854, 856), so the shipped solver never fires it.

   Nothing else reaches the contradiction, because the partition
   `(|accountId, regionCode|) <- (l, s)` is a dead end for every remaining rule:
     * `cancellation` (Constraints.scala:1017) needs a LONE variable remainder
       (`xs.size == 1` / `ys.size == 1`, lines 1029/1031); here both remainders
       are two variables wide.
     * `splitConcrete` (Constraints.scala:816) refuses on `concr.isEmpty`
       (line 817), so it never mints a name for `l (+) s`.
     * `commonSubexpression` (Constraints.scala:1089) refuses on `int.size < 2`
       (line 1094); this partition shares only one variable with `lt`'s and only
       one with `rt`'s.
     * `resolution` (Constraints.scala:1047) matches only `RHS(Single(x), _)`.
   So the facts "accountId is not in l" and "accountId is not in s" live in the
   partitions of lt and rt and are never brought into contact with the split.
   This is NOT the `-Dermine.genRules=nongen` regression documented in
   `core/examples/shouldfail/RESULTS.md`: minting is ON here and does not help,
   because there is nothing with a concrete part to mint from.

   Contrast `control01_same_route_refuted.e`: an unsatisfiable signature
   discharged through the identical `f (relation [...])` route IS refuted.  So
   "signature constraints are only assumptions" does not explain this one.
-}

import Prelude

field accountId, regionCode : Int
field amount : Double

-- | A ledger is shardable on the account key when its columns split into two
-- groups (l and s) that each form a legal header once `accountId` is stamped
-- on.  That is the precondition for writing it to two tables that re-join on
-- `accountId`.  Records the property in the type and passes the ledger through.
shardable : forall t l s lt rt.
            ( t  <- (l, s)
            , lt <- ((|accountId|), l)
            , rt <- ((|accountId|), s) )
         => [..t] -> [..t]
shardable src = src

-- CONTROL.  This ledger has no `accountId` column, so it really is shardable:
-- take l = (|regionCode|), s = (|amount|), lt = (|accountId, regionCode|),
-- rt = (|accountId, amount|).  Accepted, as it should be -- and this is the
-- constructive witness that `shardable`'s own constraint set is satisfiable.
good : [regionCode, amount]
good = shardable (relation [{ regionCode = 1, amount = 2.0 }])

-- THE BUG.  This ledger ALREADY carries `accountId`, so it is not shardable
-- on that key by any split.  Should be rejected.  Compiles.
bad : [accountId, regionCode]
bad = shardable (relation [{ accountId = 1, regionCode = 2 }])
