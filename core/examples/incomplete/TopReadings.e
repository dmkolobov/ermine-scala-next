module Incomplete.TopReadings where

{- SCENARIO -- show the whole row for the largest readings in a station log.

   One table:

     readings (logId, station, channel, peakValue)

   `topK` returns only the columns you sort by, so the standard idiom -- it is
   how `Relation.firstBy` and `Relation.lastBy` are written in the stdlib -- is
   to rank a projection and join the full rows back:

     topRowsBy h n r = join r (topK h n (r # h))

   WHAT A COMPETENT USER EXPECTS -- "the relation must contain the ranking
   columns". One constraint, which the stdlib even has an alias for:

       topRowsBy : (Has b h, RelationalComb rel) => Row h -> Int -> rel b -> rel b

   `Incomplete.Signatures.topRowsByDeduped` has that signature and it checks.

   WHAT USED TO HAPPEN, AND WHAT S3 FIXED. Reproduce with

     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/TopReadings.e
     >> :type topRowsBy

   BEFORE stage S3 (2026-09-07), identical on every run:

     forall (h: rho) (a: rho -> *) (b: rho).
       (exists (c: rho). b <- (h, c), h <- (h), b <- (c, h), RelationalComb a) =>
       Row h -> Int -> a b -> a b

   THREE row constraints, and TWO defects in them. `b <- (h, c)` IS `Has b h` --
   the alias is defined as `exists c. a <- (b, c)` in Constraint.e -- and it is
   the one constraint the user expected. `b <- (c, h)` is that same constraint
   printed a SECOND time with its two parts in the other order: the right-hand
   side of a partition is a SET, so the two are one constraint, and
   `Incomplete.Signatures.permA`/`permB`/`permC` are the proof. And `h <- (h)`
   says the row `h` is the disjoint union of the single row `h`, which holds for
   every row in the language: not a condition on anything, but the solver failing
   to notice that a partition with one part is an identity, and printing it in
   the user's face.

   `Incomplete.Signatures.tautIsFree` is the proof that it is vacuous: it uses a
   function whose only constraint is `r <- (r)` from a context with NO
   constraints whatsoever, and the solver discharges it.

   AFTER S3 the same command prints

     forall (h: rho) (a: rho -> *) (b: rho).
       (exists (c: rho). b <- (c, h), RelationalComb a) =>
       Row h -> Int -> a b -> a b

   ONE row constraint, and it is `Has b h`. That is exactly the signature at the
   top of this header, the one
   `Incomplete.Signatures.topRowsByDeduped` proves and the one "a competent user
   expects". BOTH defects were in `Subst.mkSimplified`, which had documented
   since it was written that its first job is to delete all but one permutation
   of a right-hand side: it never did, because `NormalPart` overrode `equals` and
   not `hashCode` and `List.distinct` buckets by hash; and its `normalPart` had a
   `None` case for the concrete identity `(|Foo|) <- (|Foo|)` and none for the
   variable identity. Thirteen lines in `Subst.scala` fixed both
   (`tracker/loopmodel/S3-SIMPLIFY.md`; this module is the reproduction the fix
   was built from).

   WHAT REMAINS INCOMPLETE. The simplifier still has NO entailment test between
   surviving partitions -- it deletes copies and tautologies and nothing else --
   so the fifteen-constraint residuals elsewhere in this directory lose their
   duplicates and their tautologies and keep every member that is merely IMPLIED
   by the others (`Signatures.valueAsOfFormA`, `shareOfGroupFull`). That is
   `tracker/ROSE-COMPARISON.md` rank 3 and a separate stage.
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation

field logId : Int
field station, channel : String
field peakValue : Double

readings = relation [
  { logId = 7701, station = "Eskdale",  channel = "MAG-H", peakValue = 4812000.0 },
  { logId = 7701, station = "Eskdale",  channel = "MAG-D", peakValue = 1240000.0 },
  { logId = 7702, station = "Hartland", channel = "MAG-H", peakValue =  930000.0 },
  { logId = 7702, station = "Hartland", channel = "MAG-Z", peakValue = 6105000.0 },
  { logId = 7703, station = "Eskdale",  channel = "MAG-Z", peakValue =  415000.0 }
]

-- | The complete rows carrying the `n` largest values of the columns in `h`.
topRowsBy h n r = join r (topK h n (r # h))

largest = topRowsBy {peakValue} 3 readings

largestReport = vflow [
  atomShown "## Three largest readings",
  tabular Nothing largest
]
