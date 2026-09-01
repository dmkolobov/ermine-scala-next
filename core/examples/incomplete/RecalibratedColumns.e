module Incomplete.RecalibratedColumns where

{- SCENARIO -- apply a recalibration to a table of gauge readings.

   Two tables:

     monthly      (gaugeId, asOfDate, reportedVal)
     recalibration(gaugeId, asOfDate, revisedVal)

   Join them, then make the revised figure BE the reported figure: drop the
   old column and rename the new one onto its name. That two-step is common
   enough that the stdlib ships it as `Relation.rename'`, also without a
   signature:

     rename' f1 f2 = rename f1 f2 . except { f2 }

   WHAT A COMPETENT USER EXPECTS -- "the input has `f2`, and some other stuff,
   and `f1`; the output has the other stuff and `f2`":

       overwriteWith : (RelationalComb rel, r <- (a, e, c), d <- (e, c))
                    => Field a t -> Field c t -> rel r -> rel d

   `Incomplete.Signatures.overwriteWithDeduped` has that signature and checks.

   WHAT ACTUALLY HAPPENS. Reproduce with

     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/RecalibratedColumns.e
     >> :type overwriteWith

   Identical on every run:

     forall (a: rho) b (c: rho) (rel: rho -> *) (r: rho) (d: rho).
       (exists (e: rho) (r2: rho). r <- (a, e, c),
       r2 <- (e, a),
       d <- (e, c),
       RelationalComb rel) =>
       Field a b -> Field c b -> rel r -> rel d

   THE MIDDLE CONSTRAINT IS DEAD. `r2` is existentially quantified and occurs in
   no other constraint and nowhere in the type, so `exists r2. r2 <- (e, a)` says
   only "there is a row that is `e` and `a` together", i.e. that `e` and `a` are
   disjoint. The kept `r <- (a, e, c)` already says that. `r2` is a name the
   solver invented for a row nobody asked about, kept alive to hold a fact
   already recorded elsewhere.

   `Incomplete.Signatures.overwriteWithDeduped` is defined as
   `= overwriteWithFull`, where `overwriteWithFull` carries all three
   constraints. It checking means the two-constraint set entails the
   three-constraint set, so they are equivalent.

   This one is not hypothetical. `Relation.rename'` in the stdlib is
   `rename f1 f2 . except { f2 }` with no signature, and `:type rename'` in a
   bare REPL prints the same three constraints with the same dead variable:

     forall (a: rho) b (c: rho) (rel: rho -> *) (r: rho) (d: rho).
       (exists (r2: rho) (e: rho). d <- (e, c),
       r <- (c, a, e),
       r2 <- (e, a),
       RelationalComb rel) =>
       Field a b -> Field c b -> rel r -> rel d

   So this is a type the standard library ships to every caller.

   INCOMPLETENESS DEMONSTRATED -- THE RESIDUAL IS TRUE BUT USELESS. A third of a
   three-line type is an existential row variable that exists only to restate a
   disjointness the neighbouring constraint already implies.
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Date

field gaugeId : Int
field asOfDate : Date
field reportedVal, revisedVal : Double

monthly = relation [
  { gaugeId = 1, asOfDate = @2011/1/31, reportedVal = 10.00 },
  { gaugeId = 1, asOfDate = @2011/2/28, reportedVal = 10.42 },
  { gaugeId = 2, asOfDate = @2011/1/31, reportedVal = 25.00 }
]

recalibration = relation [
  { gaugeId = 1, asOfDate = @2011/2/28, revisedVal = 10.38 }
]

-- | Overwrite the column `f2` with the column `f1`, keeping the name `f2`.
overwriteWith f1 f2 r = rename f1 f2 (except {f2} r)

revised = overwriteWith revisedVal reportedVal (join monthly recalibration)

revisionReport = vflow [
  atomShown "## February readings, recalibrated",
  tabular Nothing revised
]
