/*
package com.clarifi.reporting.ermine.session.foreign

import com.clarifi.analytics.util.control.{Fold => F}
import com.clarifi.analytics.util.math.{Numeric,NumTuple2}
import com.clarifi.analytics.util.control.Algebras.Numbers.DoubleField
import com.clarifi.reporting.ermine.{Data,Global,Prim,Runtime}
import com.clarifi.reporting.PrimT

object Folds {
  import Numeric.composeFilterNaN
  import Numeric.composeFilterNaNPairs
  import collection.immutable.Vector

  def some[A](a: A): Runtime =
    Data(Global("Builtin", "Some"), Array(Prim(a)))
  def none: Runtime =
    Data(Global("Builtin", "Null"), Array(Prim(PrimT.DoubleT)))
  def toNullable(a: Option[Double]): Runtime =
    a match {
      case None => none
      case Some(a) => some(a)
    }

  def sum: F[Double,Runtime] =
    composeFilterNaN(Numeric.sum[Double].toFold.map(some))
  def product: F[Double,Runtime] =
    composeFilterNaN(Numeric.product[Double].toFold.map(some))

  def min: F[Double,Runtime] =
    composeFilterNaN(Numeric.min[Double].toFold.map(toNullable))
  def max: F[Double,Runtime] =
    composeFilterNaN(Numeric.max[Double].toFold.map(toNullable))

  def mean: F[Double,Runtime] =
    composeFilterNaN(Numeric.mean.toFold.map(toNullable))
  def geometricMean: F[Double,Runtime] =
    composeFilterNaN(Numeric.geometricMean.toFold.map(toNullable))
  def weightedMean: F[NumTuple2,Runtime] =
    composeFilterNaNPairs(Numeric.weightedMean.map(toNullable))
  def weightedHarmonicMean: F[NumTuple2,Runtime] =
    composeFilterNaNPairs(Numeric.weightedHarmonicMean.map(toNullable))

  def median: F[Double,Runtime] =
    composeFilterNaN(Numeric.median.toFold.map(toNullable))
  def weightedMedian: F[NumTuple2,Runtime] =
    composeFilterNaNPairs(Numeric.weightedMedian.map(toNullable).toFold)

  def interquartileRange: F[Double,Runtime] =
    composeFilterNaN(Numeric.interquartileRange.toFold.map(toNullable))
  def standardDeviation: F[Double,Runtime] =
    composeFilterNaN(Numeric.populationStandardDeviation.toFold.map(toNullable))

  def unweighted[A](f: F[Double,A]): F[NumTuple2,A] = f.comap((n: NumTuple2) => n._2)
  def run[A,B](f: F[A,B], v: Vector[A]): B = f(v)

  def accumulate[Rec,R,Fld,Rel](f: F[Rec,R], field: Fld, leaves: Rel, hierarchy: Rel): Rel = {
    println((f, field, leaves, hierarchy))
    leaves
  }
}
*/