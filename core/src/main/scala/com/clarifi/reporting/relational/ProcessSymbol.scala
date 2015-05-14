package com.clarifi.reporting.relational


import com.clarifi.machines._

import com.clarifi.reporting._
import com.clarifi.reporting.PrimT.DoubleT

/** Defunctionalized representation of folds and stream transducers. */
trait ProcessSymbol {
  def compile: Process[Record,Record]
  def outputType(h: Header): Header
}

object ProcessSymbols {
  /** @todo Maybe special double-pair class? */
  private[relational]
  type NumTuple2 = (Double, Double)

  case class Median(v: Attribute) extends ProcessSymbol {
    def compile =
      composeFilterNaN(medianProcess).
        outmap(r => Map(v.name -> toDoubleExpr(r, v.t.nullable))).
        comap((r: Record) => doubleFromPrimExpr(r(v.name)))
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }

  private[relational]
  def medianProcess: Process[Double, Option[Double]] =
    sys.error("todo") // toProcess(Numeric.median)

  case class WeightedMean(weight: Attribute, v: Attribute) extends ProcessSymbol {
    def compile = weightedCalc(weight, v, weightedMeanProcess)
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }

  private[relational]
  def weightedMeanProcess: Process[NumTuple2, Option[Double]] =
    sys.error("todo") // toProcess(Numeric.weightedMean)

  case class WeightedHarmonicMean(weight: Attribute, v: Attribute) extends ProcessSymbol {
    def compile = weightedCalc(weight, v, weightedHarmonicMeanProcess)
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }

  private[relational]
  def weightedHarmonicMeanProcess: Process[NumTuple2, Option[Double]] =
    sys.error("todo") // toProcess(Numeric.weightedHarmonicMean)

  private[this]
  def weightedCalc(weight: Attribute, v: Attribute,
                   f: Process[NumTuple2,Option[Double]]): Process[Record,Record] =
    composeFilterNaNPairs(f).
      outmap { res => Map(v.name -> toDoubleExpr(res, v.t.nullable)) } .
      comap((r: Record) => (
        doubleFromPrimExpr(r(weight.name)),
        doubleFromPrimExpr(r(v.name)))
      )

  /** Removes NaN values from the input. */
  private[this]
  def composeFilterNaN[A](f: Process[Double, A]): Process[Double, A] =
    sys.error("todo")

  /** Removes tuples whose second element is NaN. */
  private[this]
  def composeFilterNaNPairs[A](f: Process[NumTuple2, A]): Process[NumTuple2, A] =
    sys.error("todo")

  // NB: there is not really a good way to handle the case that we are storing
  // the (None) result of a partial function in a non-nullable field
  private[this]
  def toDoubleExpr(o: Option[Double], nullable: Boolean): PrimExpr = o match {
    case None => if (nullable) NullExpr(DoubleT(nullable))
                 else DoubleExpr(nullable, Double.NaN)
    case Some(d) => DoubleExpr(nullable, d)
  }
  // returns NaN if PrimExpr is null
  private[this]
  def doubleFromPrimExpr(p: PrimExpr): Double =
    p match {
      case NullExpr(_) => Double.NaN
      case _ => p.extractDouble
    }

  private[this]
  implicit final class processComap[A, B](val _fa: Process[A, B]) extends AnyVal {
    def comap[C](f: C => A): Process[C, B] =
      _fa.inmap(_ compose f)
  }

/*
  def toProcess[A,B](f: Fold[A,B]): Process[A,B] =
    f.unbind match {
      case Left(r) => toProcess(r)
      case _ => sys.error("cannot convert multipass Fold to a Process")
    }
  def toProcess[A,B,C](r: ReducerTo[A,B,C]): Process[A,C] =
    Plan.await[A].flatMap(a => toProcess(r, r.reducer.snoc(r.empty, a)))

  def toProcess[A,B,C](r: ReducerTo[A,B,C], acc: B): Process[A,C] =
    Plan.await[A].flatMap(a => toProcess(r, r.reducer.snoc(acc, a))).
                  orElse(Plan.emit(r.counit(acc)).compile)
*/

  def median(v: Attribute) = Median(v)
  def weightedMean(weight: Attribute, v: Attribute) = WeightedMean(weight, v)
  def weightedHarmonicMean(weight: Attribute, v: Attribute) = WeightedHarmonicMean(weight, v)
}
