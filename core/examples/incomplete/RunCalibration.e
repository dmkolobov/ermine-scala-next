module Incomplete.RunCalibration where

{- SCENARIO -- calibrate an experiment-run log off a reference-value history.

   Two tables that any laboratory has:

     runLog    (runId, rigId, nSamples, operator, asOfDate)
     refValues (rigId, asOfDate, refValue)

   Reference values exist only on working days, and runs get logged on days
   with no reading (a weekend batch, a holiday, a stale feed). So the query
   everyone writes is a LOOKBACK JOIN: for each run take the most recent
   reference value at or before its date, looking back five days. `valueAsOf`
   below is that query, written the way the stdlib writes `lookbackJoin` --
   copy the date column, find the nearest earlier date, substitute it, join.

   WHAT A COMPETENT USER EXPECTS -- one partition constraint per join leg. The
   helper takes a date column, a relation containing it, a second relation
   containing it, and returns the two joined:

       valueAsOf : (r1 <- (k, s), r2 <- (k, t), r3 <- (k, s, t))
                => Field k Date -> Relation r1 -> Relation r2 -> Relation r3

   `Incomplete.Signatures.valueAsOfSimple` is this exact body under exactly that
   signature. It checks.

   WHAT ACTUALLY HAPPENS. Reproduce with

     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/RunCalibration.e
     >> :type valueAsOf

   The unchanged file gives one of TWO answers depending on the run. Six
   consecutive runs of the identical bytes gave Form A four times and Form B
   twice, each byte-for-byte as printed here:

   FORM A, fifteen constraints over thirteen existential rows --

     forall (r: rho) (r1: rho) (a: rho) (b: rho).
       (exists (c: rho) (d: rho) (e: rho) (f: rho) (g: rho) (h: rho) (c1: rho)
       (r2: rho) (i: rho) (o: rho) (j: rho) (k: rho) (l: rho). r <- (r),
       r1 <- (c1, r),
       r2 <- (d, r),
       f <- (r, c1, h),
       f <- (r, g, d),
       r1 <- (i, g),
       c <- (d, e),
       c <- (e, d),
       r2 <- (h, i),
       f <- (h, i, g),
       f <- (d, r, g),
       o <- (k, j),
       a <- (j, l),
       a <- (r, e),
       b <- (k, j, l)) =>
       Field r Date -> Relation r1 -> Relation a -> Relation b

   FORM B, ten --

     forall (r: rho) (r1: rho) (a: rho) (b: rho).
       (exists (c: rho) (d: rho) (e: rho) (t: rho) (f: rho) (g: rho) (h: rho)
       (c1: rho) (r2: rho) (i: rho) (r21: rho). a <- (i, r),
       r <- (r),
       r1 <- (h, g),
       t <- (h, g, f),
       r21 <- (e, d),
       a <- (d, c),
       b <- (e, d, c),
       r2 <- (g, f),
       r1 <- (r, c1),
       t <- (f, c1, r)) =>
       Field r Date -> Relation r1 -> Relation a -> Relation b

   THREE OF FORM A'S FIFTEEN ARE REDUNDANT BY INSPECTION.

     * `r <- (r)` says the row `r` is the disjoint union of the single row `r`.
       It holds for every row. `Incomplete.Signatures.tautIsFree` discharges it
       with no constraint at all in scope, which is the proof.
     * `c <- (e, d)` is `c <- (d, e)` with the right-hand side permuted. The
       right-hand side of a partition is a SET; `Signatures.perm2A/perm2B`
       derive the two-part swap from each other.
     * `f <- (d, r, g)` is likewise `f <- (r, g, d)` permuted;
       `Signatures.permA/permB/permC` derive the three-part rotations.

   AND FORM B, MINUS ITS OWN TAUTOLOGY, IS NINE CONSTRAINTS THAT SAY EXACTLY
   WHAT FORM A'S FIFTEEN SAY. `Incomplete.Signatures` carries both sets verbatim
   and derives each from the other (`valueAsOfFormB = valueAsOfFormA` and
   `valueAsOfFormAviaB = valueAsOfFormB`); that module compiling is the proof
   that the two are equivalent. So on a Form A run the compiler prints fifteen
   constraints where nine of its own output say the same thing -- and it cannot
   tell, because deciding that is exactly the coNP-complete entailment problem.

   This is the shape of `Relation.lookbackJoin` in the stdlib, which has no
   signature either. `:type lookbackJoin` in a bare REPL prints fifteen
   constraints on every run, among them the same tautology and the same permuted
   pairs:

     ... t <- (r, c, j), r <- (r), k <- (j, r), t <- (j, r, c), a <- (r, i),
     a <- (h, g), k <- (e, d), t <- (e, d, c), t <- (r, e, l), m <- (j, i),
     r1 <- (l, r), r2 <- (g, f), r1 <- (d, c), m <- (i, j), b <- (h, g, f)

   -- `r <- (r)`, `t <- (r, c, j)` beside `t <- (j, r, c)`, and `m <- (j, i)`
   beside `m <- (i, j)`.

   INCOMPLETENESS DEMONSTRATED -- THE RESIDUAL IS TRUE BUT USELESS. It is sound.
   It is also fifteen constraints where nine equivalent ones exist -- nine the
   same compiler emits for the same file on a different run -- it repeats itself
   under permuted right-hand sides, it carries a tautology, and it is not even a
   function of the program.
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Date

field runId, nSamples : Int
field rigId, operator : String
field asOfDate : Date
field refValue, scaledSum : Double

runLog = relation [
  { runId = 101, rigId = "RIG1", nSamples =  400, operator = "Okafor",    asOfDate = @2011/3/14 },
  { runId = 102, rigId = "RIG2", nSamples = 1200, operator = "Okafor",    asOfDate = @2011/3/14 },
  { runId = 103, rigId = "RIG1", nSamples =  250, operator = "Lindqvist", asOfDate = @2011/3/19 },
  { runId = 104, rigId = "RIG2", nSamples =  800, operator = "Lindqvist", asOfDate = @2011/3/20 }
]

-- no readings on 19 or 20 March -- that weekend is the whole point of the query
refValues = relation [
  { rigId = "RIG1", asOfDate = @2011/3/11, refValue = 351.99 },
  { rigId = "RIG1", asOfDate = @2011/3/14, refValue = 353.56 },
  { rigId = "RIG1", asOfDate = @2011/3/18, refValue = 330.67 },
  { rigId = "RIG2", asOfDate = @2011/3/11, refValue =  25.68 },
  { rigId = "RIG2", asOfDate = @2011/3/14, refValue =  25.49 },
  { rigId = "RIG2", asOfDate = @2011/3/18, refValue =  25.68 }
]

-- | For every row of `ts`, attach the row of `ps` carrying the most recent
-- date at or before its own, looking back at most five days. The date column
-- in the result is the CALIBRATION date, which is what a scaling run wants.
valueAsOf d ts ps = withFieldCopy d (d' ->
  let nearest = nearestDateWithin (f -> dateAdd_Op 5 days (col_Op f))
                                  d (ts # {d}) d' (rename d d' ps # {d'})
      ts' = except {d'} . [| d = d' |] ' join nearest ts
  in join ts' ps)

calibrated = valueAsOf asOfDate runLog refValues

scaledRuns = combine_Op (fromNumericOp_Op (col_Op nSamples) *_Op col_Op refValue)
                        scaledSum calibrated

calibrationReport = vflow [
  atomShown "## Run log scaled by the last available reference value",
  tabular Nothing scaledRuns
]
