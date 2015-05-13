package com.clarifi.reporting
package relational

import collection.immutable.LinearSeq

import org.scalacheck.{Gen, Prop, Properties}
import Prop.{extendedAny => _, _}
import com.clarifi.machines._

object TestProcessSymbols extends Properties("process symbol processes") {
  /** Run [[com.clarifi.machines.Process]] like a reducer that emits one
    * result when the input is exhausted.
    */
  private[this]
  def iffReduced[A, B](p: Process[A, B], l: LinearSeq[A])
                      (f: B PartialFunction Prop): Prop =
    Process.transduce(l)(p) iff {
      case IndexedSeq(e) => f(e)
    }

  property("median") = {
    import ProcessSymbols.medianProcess
    forAll(Gen.listOf1(Gen.choose(-1000.0,1000.0)))(
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
    forAll(Gen.listOf1(Gen.choose(-1000.0,1000.0)))(
      ns => {
        iffReduced(medianProcess, ns){
          case Some(nsmg) =>
            if (ns.size % 2 == 0)
              !(ns.contains(nsmg))
            else
              ns.contains(nsmg)
        }}) &&
    forAll(Gen.listOf1(Gen.choose(-1000.0,1000.0)))(
      ns => {
        iffReduced(medianProcess, ns){
          case Some(m) =>
            ns.count(_ >= m) =? ns.count(_ <= m)
      }})
  }
}
