module Incomplete.Unsound04 where

{- *** SOUNDNESS BUG (4 of 4): unsatisfiable, accepted.  This module LOADS. ***
   Default mode, -Dermine.genRules=all.

   ------------------------------------------------------------------ scenario

   A statement table carries an `amount` measure plus whatever else.  You write
   a helper for the "report each column block next to the amount" pattern and
   spell the precondition out in the signature:

       t  <- (m, (|amount|))        -- the table has an amount column
       t  <- (l, s)                 -- its columns split into two blocks
       lt <- ((|amount|), l)        -- block l reported with the amount
       rt <- ((|amount|), s)        -- block s reported with the amount

   Unlike `unsound01`/`unsound02`, this constraint set is unsatisfiable BY
   ITSELF, for every t: line 1 puts `amount` in t, line 2 puts it in l or in s,
   and lines 3 and 4 say it is in neither.  `withAmountBlocks` can therefore
   never be called at any instance -- it is dead code with a type.

   ---------------------------------------------------------- what a user expects

   A signature no instance can satisfy is a mistake worth reporting, and Ermine
   does report the ones it can see: `core/examples/shouldfail/dup01` and
   `inf01` are exactly this shape (a bad signature plus a `use` that forces the
   solver to discharge it) and both are rejected.

   ------------------------------------------------------------- what happens

   OBSERVED 2026-09-01, branch scala3-migration:
     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/unsound04_dead_helper.e </dev/null
     -> "Importing module 'Incomplete.Unsound04'" -- it loads

   Both the definition and the call site are accepted, and `:browse` gives

     use : Relation (|regionCode, amount|)

   -- monomorphic, no constraint context, so the solver considers the whole
   instantiated set discharged:

       (|regionCode, amount|) <- (m, (|amount|))     -- forces m = (|regionCode|)
       (|regionCode, amount|) <- (l, s)
       lt <- ((|amount|), l)
       rt <- ((|amount|), s)

   `amount` is in l (+) s and in neither l nor s.  No solution.

   ------------------------------------------------------------- the calibration

   `control01_same_route_refuted.e` is the same file with the same `use` shape
   and an unsatisfiable signature the solver DOES see; it is rejected.  So this
   is not the "signature constraints are only assumptions" rule at work -- the
   assumptions become wanted constraints at `use` in both files.  The
   difference is only whether some rule fires, and here none does: the split
   `(|regionCode, amount|) <- (l, s)` carries no concrete part for
   `splitConcrete` (Constraints.scala:817), leaves a two-variable remainder
   that `cancellation` cannot use (Constraints.scala:1029, 1031), and shares
   one variable at a time with the partitions of lt and rt, below
   `commonSubexpression`'s threshold (Constraints.scala:1094).  `Disjunction`
   would close it and is never called (Constraints.scala:843, 854, 856).
-}

import Prelude

field regionCode : Int
field amount : Double

-- | Report the two halves of a statement's columns, each carrying the amount.
withAmountBlocks : forall t m l s lt rt.
                   ( t  <- (m, (|amount|))
                   , t  <- (l, s)
                   , lt <- ((|amount|), l)
                   , rt <- ((|amount|), s) )
                => [..t] -> [..t]
withAmountBlocks src = src

use : [regionCode, amount]
use = withAmountBlocks (relation [{ regionCode = 1, amount = 2.0 }])
