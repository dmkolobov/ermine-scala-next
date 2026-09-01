module Incomplete.Np05b where

{- NO BEST TYPE (5/5), companion -- COMPILES, in 0.17s, and that is the point.

   The constrained signature that covers every typing of np05's label
   expression, written out by hand.  As a DEFINITION it checks immediately.

   Applying it does not.  np05c_helper_at_a_call_site.slow is this file plus a
   single application of the helper, and it takes 526.99 s to check.  So this is
   a type that exists, that the compiler verifies in a sixth of a second, and
   that costs nine minutes to use once.  That is the sense in which the complete
   set of typings for that expression has no affordable representative, and the
   sense in which the concrete header a report actually writes -- one of several
   incomparable maximal typings -- is forced rather than chosen.

   OBSERVED 2026-09-01, bin/ermine -Dermine.useInterface=false:
     Importing module 'Incomplete.Np05b' (0.17 seconds)
-}

import Prelude
import Constraint
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation

labelRow : forall v r s t c a rr tt rel opc opa.
           (exists o. RUnion3 v r s t, RUnion2 tt rr c, rr <- (v, o),
            AsOp opc, AsOp opa, RelationalComb rel)
        => Predicate r -> opc s a -> opa t a -> Field c a -> rel rr -> rel tt
labelRow cond yes no fld rel = combine_Op (if_Op cond yes no) fld rel
