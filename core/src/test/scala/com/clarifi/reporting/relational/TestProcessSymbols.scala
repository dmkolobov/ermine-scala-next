package com.clarifi.reporting
package relational

import collection.immutable.LinearSeq

import org.scalacheck.{Arbitrary, Gen, Prop, Properties}
import org.scalacheck.util.Pretty
import Prop._
import com.clarifi.machines._

private[relational]
object ProcessSymbolAux {
  import collection.generic.{CanBuildFrom, FilterMonadic}
  import ProcessSymbols.{NumTuple2, ensureNonnegativeWeight}

  /** Run [[com.clarifi.machines.Process]] like a reducer that emits one
    * result when the input is exhausted.
    */
  def iffReduced[A, B](p: Process[A, B], l: LinearSeq[A])
                      (f: B PartialFunction Prop): Prop =
    Process.transduce(l)(p) iff {
      case IndexedSeq(e) => e iff f
    }

  implicit final class FuzzyDouble(val v: Double) extends AnyVal {
    def epsilon = .00001
    def epsilonEquals(d: Double): Boolean = { 
      if (this.v.isNaN && d.isNaN) true 
      else if ((this.v - d).abs < epsilon) true
      else printLeftRight(d)
    }
    def ~(d: Double) = this.epsilonEquals(d)
    def >~(d: Double) = (this.v - d) > -epsilon || printLeftRight(d)

    def ?~(d: Double): Prop =
      if(this.v ~ d) proved else falsified :| {
        val exp = Pretty.pretty(d, Pretty.Params(0))
        val act = Pretty.pretty(v, Pretty.Params(0))
        "Expected "+exp+" but got "+act
      }

    def ~?(d: Double): Prop = d ?~ this.v

    def printLeftRight(d: Double): Boolean = {
      //println("left: "+this.v); println("right: "+d.v)
      false 
    }
  }

  def mean(xs: Seq[Double]): Option[Double] =
    if (xs.isEmpty) None else Some(xs.sum / xs.length)

  def ensureNonnegativeWeights[This, That]
                              (vs: FilterMonadic[NumTuple2, This])
                              (implicit cbf: CanBuildFrom[This, NumTuple2, That])
      : That =
    vs.map(ensureNonnegativeWeight)
}

object TestProcessSymbols extends Properties("process symbol processes") {
  import ProcessSymbolAux._

  implicit val doubles: Arbitrary[Double] = Arbitrary(Gen.choose(-1000.0,1000.0))
  implicit val smallishInt: Arbitrary[Int] = Arbitrary(Gen.choose(-500,500))

  property("median") = {
    import ProcessSymbols.medianProcess
    forAll(Gen.nonEmptyListOf(Gen.choose(-1000.0,1000.0)))(
      ns => iffReduced(medianProcess, ns){
        case Some(m) =>
          val sorted = ns.sortWith(_ < _)
          val expected = if(ns.size % 2 > 0)
                           sorted(ns.size/2)
                         else if(ns.size > 0)
                           (sorted(ns.size/2) + sorted(ns.size/2 - 1))/2
                         else
                           Double.NaN
          ?=(m, expected)
      }) &&
    forAll(Gen.nonEmptyListOf(Gen.choose(-1000.0,1000.0)))(
      ns => {
        iffReduced(medianProcess, ns){
          case Some(nsmg) =>
            if (ns.size % 2 == 0)
              !(ns.contains(nsmg))
            else
              ns.contains(nsmg)
        }}) &&
    forAll(Gen.nonEmptyListOf(Gen.choose(-1000.0,1000.0)))(
      ns => {
        iffReduced(medianProcess, ns){
          case Some(m) =>
            ns.count(_ >= m) =? ns.count(_ <= m)
      }})
  }

  include{new Properties("weightedMean") {
    import ProcessSymbols.weightedMeanProcess
    val doubleGen = Gen.choose(-10000.0,10000.0) // arbitrary range here
    val pairs = for {
      d <- Gen.nonEmptyListOf(doubleGen)
      w <- doubleGen
    } yield d.map((w, _))

    property("weighted mean = mean when the weights are all any positive constant") =
      forAll(pairs.map(ensureNonnegativeWeights(_))){a =>
        iffReduced(weightedMeanProcess, a){
          case Some(wm) =>
            mean(a.map(_._2)).get ~? wm}}

    property("weighted mean = -mean when the weights are all any negative constant") =
      forAll(pairs.map(_.map(t => (-t._1.abs, t._2)))){a =>
        iffReduced(weightedMeanProcess, a){
          case Some(wm) =>
            -mean(a.map(_._2).toSeq).get ~? wm}}

    property("weighted mean is associative - wm(a ++ b) == wm(wm(a) ++ wm(b))") =
      forAll((a: List[(Double,Double)], b: List[(Double,Double)]) =>
        (!a.isEmpty && !b.isEmpty) ==> {
          val posA = a.map(p => (p._1.abs,p._2))
          val posB = b.map(p => (p._1.abs,p._2))
          val weightA = posA.map(_._1).sum
          val weightB = posB.map(_._1).sum
          iffReduced(weightedMeanProcess, posA ++ posB){
            case Some(unionWM) => iffReduced(weightedMeanProcess, posA){
              case Some(wa) => iffReduced(weightedMeanProcess, posB){
                case Some(wb) => iffReduced(weightedMeanProcess, List(
                                             (weightA, wa), (weightB, wb))){
                  case Some(separateWM) => unionWM ~? separateWM
        }}}}}
      )
  }}

  include{new Properties("weightedHarmonicMean") {
    import ProcessSymbols.{weightedMeanProcess, weightedHarmonicMeanProcess}
    val posDoubleGen = Gen.choose(0.00000001,1000.0) // arbitrary positive
    val negDoubleGen = posDoubleGen.map(d => -d)
    val negWeightedValue = for { w <- negDoubleGen; v <- posDoubleGen } yield (w,v)

    property("""a constant-weighted weighted harmonic mean is the same as a
       weighted mean whose weights are the reciprocals of the values
       http://en.wikipedia.org/wiki/Harmonic_mean#Relationship_with_other_means""") =
      forAll(Gen.nonEmptyListOf(posDoubleGen)){a =>
        iffReduced(weightedMeanProcess, a.map(v => (1/v,v))){
          case Some(wm) => iffReduced(weightedHarmonicMeanProcess,
                                     a.map(v => (1.0,v))){
            case Some(whm) => wm ~? whm}}}

    property("""Verify that the arithmetic mean is always greater or equal than the
        harmonic mean
        http://en.wikipedia.org/wiki/Pythagorean_means""") =
      forAll(Gen.nonEmptyListOf(posDoubleGen)){a =>
        iffReduced(weightedMeanProcess, a.map(v => (1.0,v))){
          case Some(wm) => iffReduced(weightedHarmonicMeanProcess, a.map(v => (1.0,v))){
            case Some(whm) => wm >~ whm}}}

    property("verify that harmonic mean is negative if all weights are negative") =
      forAll(Gen.nonEmptyListOf(negWeightedValue)){a =>
        iffReduced(weightedHarmonicMeanProcess, a){
          case Some(whm) => 0.0 >~ whm}}
  }}
}
