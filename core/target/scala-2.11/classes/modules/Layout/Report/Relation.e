module Layout.Report.Relation where

import Layout.Report
import Relation
import List
import Field
import Function
import Pair
import Double
import Num
import Eq
import Record as R
import Relation.Row hiding empty_Bracket; cons_Bracket
import Vector as V
import Map as M
import Nullable hiding map
import Control.Functor
import Syntax.List
import Ord
import Native.Object using toString
import String as Str
import Bool
import Relation.Op as Op
import Relation.Predicate as P
import Syntax.Relation
import Relation.Aggregate as Agg

private
  sumVals valueFld = sum' . map (abs . getOrElse 0.0 . getF valueFld)
  numOrZero test x = if (test x 0.0) x 0.0
  sumPosVals valueFld = sum' . map (numOrZero (>) . getOrElse 0.0 . getF valueFld)
  sumNegVals valueFld = sum' . map (numOrZero (<) . getOrElse 0.0 . getF valueFld)
private field cutoff: Nullable Double

-- separate a relation into positive and negative halves
-- and aggregate small positive values into 'Other'
-- and small negative values (i.e. those near zero) into "Other (Negative)"
cutoffGroupedFldsPosNegRel' valueFld nameFld flds cutoffAgg rel =
  let f rel' = let zero = prim_Op $ Some 0.0
                   cutoffPredicate = valueFld >_P cutoff ||_P valueFld <_P (negate_Op cutoff)
                   largeEnough = filter_P cutoffPredicate rel'
                   tooSmall = filter_P (valueFld <_P cutoff &&_P valueFld >_P zero) rel'
                   tooSmallNeg = filter_P (valueFld >_P (negate_Op cutoff) &&_P valueFld <_P zero) rel'
                   tooSmallRel = tooSmall ** mem [{ nameFld = "Other" }]
                   tooSmallNegRel = tooSmallNeg ** mem [{ nameFld = "Other (Negative)" }]
               in except {cutoff} . union tooSmallRel . union tooSmallNegRel $ largeEnough
      relWithCutoff = rel ** aggregate_Agg (cutoffAgg valueFld) cutoff rel
  in groupBy flds f $ relWithCutoff

private field cutoffCount : Int
private field cutoffChild : Int
private field cutoffGroup : String

-- At each level of the drilldown, aggregate small slivers into an "Other" row.
cutoffDrilldownRel
   : forall v p pt c ct d s.
   ( exists l
   . s <- (d, c, p, v)
   , l <- ((|cutoff,cutoffCount,cutoffChild,cutoffGroup|), s))
  => Field v (Nullable Double)
  -> Field p pt
  -> Field c Int
  -> Double
  -> Field d String
  -> Relation s
  -> Relation s
cutoffDrilldownRel valueFld parentFld childFld (cutoffPct : Double) groupFld rel =
  union (largers valueFld parentFld cutoffPct rel)
        (others valueFld parentFld groupFld childFld cutoffPct rel)

private 
  largers
     : forall v p pt s.
     ( exists l e
     . s <- (e, p, v)
     , l <- ((|cutoff|), s))
    => Field v (Nullable Double)
    -> Field p pt
    -> Double
    -> Relation s
    -> Relation s
  largers valueFld parentFld cutoffPct rel =
    rel ** cutoffs valueFld parentFld cutoffPct rel
      |> filter_P (abs_Op valueFld >_P cutoff)
      |> except {cutoff}

  cutoffs
     : forall v p pt s r.
     ( exists l e
     . s <- (e, p, v)
     , l <- ((|cutoff|), s)
     , r <- (p, (|cutoff|)))
    => Field v (Nullable Double)
    -> Field p pt
    -> Double
    -> Relation s
    -> Relation r
  cutoffs valueFld parentFld (cutoffPct : Double) rel =
    aggregateByGroup_Agg (sum_Agg . abs_Op $ valueFld) {parentFld} valueFld rel
      |> [| cutoff = prim_Op (Some cutoffPct) *_Op valueFld |]
      |> except {valueFld}

  small
     : forall v p pt s.
     ( exists l e
     . s <- (e, p, v)
     , l <- ((|cutoff|), s))
    => Field v (Nullable Double)
    -> Field p pt
    -> Double
    -> Relation s
    -> Relation s
  small valueFld parentFld cutoffPct rel =
    rel ** cutoffs valueFld parentFld cutoffPct rel
      |> filter_P (abs_Op valueFld <=_P cutoff)
      |> except {cutoff}

  smallsum
     : forall v p pt s r.
     ( exists l e
     . r <- (p, v)
     , s <- (p, v, e)
     , l <- ((|cutoff|), s))
    => Field v (Nullable Double)
    -> Field p pt
    -> Double
    -> Relation s
    -> Relation r
  smallsum valueFld parentFld cutoffPct rel =
    aggregateByGroup_Agg (sum_Agg . abs_Op $ valueFld) {parentFld} valueFld
      (small valueFld parentFld cutoffPct rel)

  smallcount
     : forall v p pt s r.
     ( exists l e
     . r <- (p, (|cutoffCount|))
     , s <- (p, v, e)
     , l <- ((|cutoff|), s))
    => Field v (Nullable Double)
    -> Field p pt
    -> Double
    -> Relation s
    -> Relation r
  smallcount valueFld parentFld cutoffPct rel =
    aggregateByGroup_Agg countAgg_Agg {parentFld} cutoffCount (small valueFld parentFld cutoffPct rel)

  smallid
     : forall v p pt s r.
     ( exists l e
     . r <- (p, (|cutoffChild|))
     , s <- (p, v, c, e)
     , l <- ((|cutoff|), s))
    => Field v (Nullable Double)
    -> Field p pt
    -> Field c Int
    -> Double
    -> Relation s
    -> Relation r
  smallid valueFld parentFld childFld cutoffPct rel =
    aggregateByGroup_Agg (max_Agg childFld) {parentFld} cutoffChild (small valueFld parentFld cutoffPct rel)

  smallgroup
     : forall v p pt s r d.
     ( exists l e
     . r <- (p, (|cutoffGroup|))
     , s <- (p, v, d, e)
     , l <- ((|cutoff|), s))
    => Field v (Nullable Double)
    -> Field p pt
    -> Field d String
    -> Double
    -> Relation s
    -> Relation r
  smallgroup valueFld parentFld groupFld cutoffPct rel =
    aggregateByGroup_Agg (max_Agg groupFld) {parentFld} cutoffGroup (small valueFld parentFld cutoffPct rel)

  others
     : forall v p pt s d c.
     ( exists l
     . s <- (p, v, d, c)
     , l <- ((|cutoff,cutoffCount,cutoffChild,cutoffGroup|), s))
    => Field v (Nullable Double)
    -> Field p pt
    -> Field d String
    -> Field c Int
    -> Double
    -> Relation s
    -> Relation s
  others valueFld parentFld groupFld childFld cutoffPct rel =
      smallsum valueFld parentFld cutoffPct rel
        ** smallcount valueFld parentFld cutoffPct rel 
        ** smallid valueFld parentFld childFld cutoffPct rel
        ** smallgroup valueFld parentFld groupFld cutoffPct rel
         |> [| cutoffCount > 0
             , groupFld = if_Op (cutoffCount ==_P 1) cutoffGroup "Other"
             , childFld = if_Op (cutoffCount ==_P 1) cutoffChild (0 -_Op 1)
            |]
         |> except {cutoffCount, cutoffGroup, cutoffChild}

