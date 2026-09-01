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

   WHAT ACTUALLY HAPPENS. Reproduce with

     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/TopReadings.e
     >> :type topRowsBy

   Identical on every run:

     forall (h: rho) (a: rho -> *) (b: rho).
       (exists (c: rho). h <- (h), b <- (h, c), RelationalComb a) =>
       Row h -> Int -> a b -> a b

   `b <- (h, c)` IS `Has b h` -- the alias is defined as `exists c. a <- (b, c)`
   in Constraint.e. So the whole content of the type is the one constraint the
   user expected, PLUS `h <- (h)`: the row `h` is the disjoint union of the
   single row `h`. That holds for every row in the language. It is not a
   condition on anything; it is the solver failing to notice that a partition
   with one part is an identity, and printing it in the user's face.

   `Incomplete.Signatures.tautIsFree` is the proof that it is vacuous: it uses a
   function whose only constraint is `r <- (r)` from a context with NO
   constraints whatsoever, and the solver discharges it.

   INCOMPLETENESS DEMONSTRATED -- THE RESIDUAL IS TRUE BUT USELESS. This is the
   smallest possible instance: a two-constraint type where one constraint is a
   tautology. If the solver cannot simplify THIS, the fifteen-constraint cases
   in this directory are not surprising.
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
