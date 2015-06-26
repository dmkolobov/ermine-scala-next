package com.clarifi.reporting.relational

import scalaz.{Contravariant, Monoid, Reducer}
import scalaz.syntax.contravariant._
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
  lazy val medianProcess: Process[Double, Option[Double]] =
    Process.wrapping[Double] outmap median_

  private[this]
  def median_(vs: Iterable[Double]): Option[Double] = {
    import scala.util.Sorting.quickSort
    val a = vs.toStream.toArray
    quickSort(a)
    val i = a.size / 2
    if(a.size % 2 > 0)
      Some(a(i))
    else if(a.size > 0)
      Some((a(i) + a(i-1)) / 2)
    else
      None
  }

  case class WeightedMean(weight: Attribute, v: Attribute) extends ProcessSymbol {
    def compile = weightedCalc(weight, v, weightedMeanProcess)
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }

  private[relational]
  lazy val weightedMeanProcess: Process[NumTuple2, Option[Double]] =
    Process.reducer(
      dot.contramap[NumTuple2](ensureNonnegativeWeight)
        .compose(sum.contramap[NumTuple2](_._1.abs)))
      .outmap(t => if (t._2 != 0.0) Some(t._1/t._2) else None)

  case class WeightedHarmonicMean(weight: Attribute, v: Attribute) extends ProcessSymbol {
    def compile = weightedCalc(weight, v, weightedHarmonicMeanProcess)
    def outputType(h: Header): Header = Map(v.name -> v.t)
  }

  private[relational]
  lazy val weightedHarmonicMeanProcess: Process[NumTuple2, Option[Double]] = {
    val sumAbs = sum.contramap[Double](_.abs)
    val sumQuotients = sum.contramap[(Double,Double)](p => p._1 / p._2)
    val hm = Process.reducer(
      (sumAbs *** sumQuotients).contramap[NumTuple2](
        (ensureNonnegativeWeight(_)).
          andThen(p => (p._1, (p._1,p._2)))))
      .outmap(p => if (p._2 != 0.0) Some((p._1/p._2)) else None)
    Process.filtered{wv: NumTuple2 => wv._2 != 0.0} andThen hm
  }

  private[this]
  def weightedCalc(weight: Attribute, v: Attribute,
                   f: Process[NumTuple2,Option[Double]]): Process[Record,Record] =
    composeFilterNaNPairs(f).
      outmap { res => Map(v.name -> toDoubleExpr(res, v.t.nullable)) } .
      comap((r: Record) => (
        doubleFromPrimExpr(r(weight.name)),
        doubleFromPrimExpr(r(v.name)))
      )

  private[this]
  val sum: Reducer[Double, Double] = {
    val plus = (m:Double) => (m + (_: Double))
    // NB: This monoid is illegal. -SMRC
    Reducer(identity[Double], plus, plus
          )(Monoid.instance(_ + _, 0))
  }

  private[this]
  val dot: Reducer[NumTuple2, Double] =
    // NB: This monoid is illegal. -SMRC
    Reducer.unitReducer[NumTuple2, Double]
      {case (a, b) => a * b
      }(Monoid.instance(_ + _, 0))

  /** Removes NaN values from the input. */
  private[this]
  def composeFilterNaN[A](f: Process[Double, A]): Process[Double, A] =
    Process.filtered((_:Double).isNaN) andThen f

  /** Removes tuples whose second element is NaN. */
  private[this]
  def composeFilterNaNPairs[A](f: Process[NumTuple2, A]): Process[NumTuple2, A] =
    Process.filtered((_:NumTuple2)._2.isNaN) andThen f

  private[relational]
  def ensureNonnegativeWeight(v: NumTuple2) =
    if (v._1 < 0) (-v._1, -v._2) else v

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
  final class processComap[A, B](val _fa: Process[A, B]) {
    def comap[C](f: C => A): Process[C, B] =
      _fa.inmap(_ compose f)
  }

  private[this]
  implicit def processComap[A, B](_fa: Process[A, B]): processComap[A, B] =
    new processComap(_fa)

  private[this]
  final class `reducer ***`[C, M](private val _self: Reducer[C, M]) {
    @inline def ***[D, N](r: Reducer[D, N]): Reducer[(C, D), (M, N)] = {
      import scalaz.std.tuple._
      implicit val mm = _self.monoid
      implicit val mn = r.monoid
      Reducer.reducer[(C, D), (M, N)](
        {case (c, d) => (_self.unit(c), r.unit(d))},
        {case (c, d) => {case (m, n) => (_self.cons(c, m), r.cons(d, n))}},
        {case (m, n) => {case (c, d) => (_self.snoc(m, c), r.snoc(n, d))}})
    }
  }

  @inline private[this]
  implicit def `reducer ***`[C, M](_self: Reducer[C, M])
    : `reducer ***`[C, M] = new `reducer ***`(_self)

  private[this]
  implicit def `contravariant Reducer`[M]: Contravariant[({type λ[α] = Reducer[α, M]})#λ] =
    new Contravariant[({type λ[α] = Reducer[α, M]})#λ] {
      def contramap[A, B](fa: Reducer[A, M])(f: B => A): Reducer[B, M] =
        Reducer.reducer[B, M](f andThen fa.unit, b => m => fa.cons(f(b), m),
                              m => b => fa.snoc(m, f(b)))(fa.monoid)
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
