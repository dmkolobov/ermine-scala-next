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
  case class Median(v: Attribute) extends ProcessSymbol {
    def compile = sys.error("todo") /* toProcess {
      Numeric.composeFilterNaN(Numeric.median).
        map(r => Map(v.name -> toDoubleExpr(r, v.t.nullable))).
        comap((r: Record) => doubleFromPrimExpr(r(v.name)))
   } */
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }

  case class WeightedMean(weight: Attribute, v: Attribute) extends ProcessSymbol {
    def compile = sys.error("todo") //weightedCalc(weight, v, Numeric.weightedMean)
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }
  case class WeightedHarmonicMean(weight: Attribute, v: Attribute) extends ProcessSymbol {
    def compile = sys.error("todo") //weightedCalc(weight, v, Numeric.weightedHarmonicMean)
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }
/*
  def weightedCalc(weight: Attribute, v: Attribute,
                   f: Fold[NumTuple2,Option[Double]]): Process[Record,Record] =
    toProcess {
      Numeric.composeFilterNaNPairs(f).
        map { res => Map(v.name -> toDoubleExpr(res, v.t.nullable)) } .
        comap((r: Record) => NumTuple(
          doubleFromPrimExpr(r(weight.name)),
          doubleFromPrimExpr(r(v.name)))
        )
    }
 */
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
