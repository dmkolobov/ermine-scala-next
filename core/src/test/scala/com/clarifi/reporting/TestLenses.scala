package com.clarifi.reporting

import scalaz._
import org.scalacheck._
import Prop._
import Lens._
import scalaz.scalacheck.ScalazArbitrary._

object TestLenses extends Properties("Lenses") {
  class LensProperties[A: Arbitrary,B: Arbitrary](name: String, lens: Lens[A,B]) extends Properties(name) {
    property("law1") = forAll ((a: A) => lens.set(a, lens.get(a)) == a)
    property("law2") = forAll ((a: A) => forAll ((b: B) => lens.get(lens.set(a, b)) == b))
  }
  include(new Properties("Lens") {
    include(new LensProperties[(Int,Double),Int]("firstLens", firstLens[Int, Double]))
    include(new LensProperties[(Int,Double),Double]("secondLens",secondLens[Int, Double]))
    include(new LensProperties[Int, Unit]("trivial",trivialLens))
    include(new LensProperties[Int,Int]("lensId",lensId[Int]))
    include(new LensProperties[(Int,Double) \/ (Boolean,Int), Int]("firstLens|||secondLens", firstLens[Int, Double] ||| secondLens[Boolean, Int]))
  })

  class CompositionProperties[A: Arbitrary,B,C: Arbitrary](name: String, g: Lens[B,C], f: Lens[A,B]) extends LensProperties[A,C](name, g compose f)
  include(new Properties("Composition") {
    include(new CompositionProperties[(Int, (Double, String)), (Double, String), Double]("firstLens compose secondLens", firstLens[Double, String], secondLens[Int, (Double, String)]))
  })

  include(new Properties("Member") {
    property("map") = forAll ((key: Boolean) => new LensProperties[Map[Boolean, Int], Option[Int]](key.toString, lensId[Map[Boolean,Int]].member(key)))
    property("set") = forAll ((key: Char) => new LensProperties[Set[Char], Boolean](key.toString, lensId[Set[Char]].contains(key)))
  })
}
