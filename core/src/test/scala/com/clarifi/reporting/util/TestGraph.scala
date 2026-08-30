package com.clarifi.reporting.util

import scalaz.Scalaz.mzero
import scalaz.std.anyVal._
import scalaz.scalacheck.ScalazProperties._
import scalaz.scalacheck.ScalazArbitrary.OrderingArbitrary

import org.scalacheck.{Arbitrary, Gen, Prop, Properties}
import Prop.{exists, AnyOperators, forAll}
import Arbitrary.arbitrary

object GraphGens {
  def cliques[A](as: Gen[A]): Gen[Clique[A]] = {
    implicit val asarb = Arbitrary(as)
    arbitrary[Set[A]] map Clique.apply
  }

  def disjointCliques[A](as: Gen[A]): Gen[List[Clique[A]]] = {
    implicit val carb = Arbitrary(cliques(as))
    arbitrary[List[Clique[A]]] map {
      case Nil => Nil
      case hd :: tl =>
        tl.scanLeft((hd: Set[A], hd)){(st, cq) =>
          (st._1 | cq) -> Clique(cq &~ st._1)
        } collect {case (_, cq) if cq.nonEmpty => cq}
    }
  }

  def partitionedSets[A](as: Gen[A]): Gen[PartitionedSet[A]] =
    disjointCliques(as) map PartitionedSet.apply
}

object TestGraph extends Properties("graph types") {
  import GraphGens._

  private type PSS = PartitionedSet[Short]

  implicit def cliqueArb[A: Arbitrary]: Arbitrary[Clique[A]] = Arbitrary(cliques(arbitrary[A]))
  implicit def partitionedSetArb[A: Arbitrary]: Arbitrary[PartitionedSet[A]] =
    Arbitrary(partitionedSets(arbitrary[A]))

  include(order.laws[Clique[Short]], "clique order.")
  include(monoid.laws[Clique[Short]], "clique monoid.")

  include(equal.laws[PSS], "PS equal.")
  include(monoid.laws[PSS], "PS monoid.")

  property("PS== reflexive") = forAll {(a: PSS) =>
    (a ?= a)
  }

  property("PS== not vacuous") = exists {(ab: (PSS, PSS)) =>
    ab._1 != ab._2
  }

  property("PS#hashCode not vacuous") = exists {(ab: (PSS, PSS)) =>
    ab._1.## != ab._2.##
  }

  property("PS#cliques round-trips") = forAll {(a: PSS) =>
    (a.## ?= PartitionedSet(a.cliques).##) &&
    (a ?= PartitionedSet(a.cliques))
  }

  property("PS#require reflexivity") = forAll {(a: PSS) =>
    a ?= (a require a)
  }

  property("PS#allow reflexivity") = forAll {(a: PSS) =>
    a ?= (a allow a)
  }

  property("PS#left identity") = forAll {(a: PSS) =>
    a ?= (PartitionedSet.zero[Short] allow a)
  }

  property("PS#right identity") = forAll {(a: PSS) =>
    a ?= (a allow PartitionedSet.zero)
  }

  property("PS#invite vacuous") = forAll {(a: PSS) =>
    a ?= (a invite mzero[Clique[Short]])
  }

  property("PS#invite absorbs own cliques") = forAll {(a: PSS) =>
    Prop.all(a.cliques.toSeq.map(cq => a ?= (a invite cq)): _*)
  }

  property("PS#invite all unifies the set") = forAll {(a: PSS) =>
    PartitionedSet(Iterable(Clique(a.elements))) ?=
      (a invite Clique(a.cliques.flatMap(_.value).toSet))
  }

  property("PS#invite one from each unifies the set") = forAll {(a: PSS) =>
    PartitionedSet(Iterable(Clique(a.elements))) ?=
      (a invite Clique(a.cliques.map(_.value.head).toSet))
  }

  property("PS#allow disjoint contains all cliques") = forAll {(a: PSS) =>
    val (pl, pr) = a.cliques splitAt (a.cliques.size / 2)
    (pl ++ pr).toSet ?=
      (PartitionedSet(pl) allow PartitionedSet(pr)).cliques.toSet
  }

  property("PS#allow symmetric") = forAll {(a: PSS, b: PSS) =>
    (a allow b) ?= (b allow a)
  }

  property("PS#allow associative") = forAll {(a: PSS, b: PSS, c: PSS) =>
    (a allow (b allow c)) ?= ((a allow b) allow c)
  }

  property("PS#allow distributive") = forAll {(a: PSS, b: PSS, c: PSS) =>
    (a allow b allow c) ?= ((a allow c) allow (b allow c))
  }

  property("PS#require symmetric") = forAll {(a: PSS, b: PSS) =>
    (a require b) ?= (b require a)
  }

  property("PS#require disjoint yields nothing") = forAll {(a: PSS) =>
    val (pl, pr) = a.cliques splitAt (a.cliques.size / 2)
    PartitionedSet.zero[Short] ?=
      (PartitionedSet(pl) require PartitionedSet(pr))
  }

  property("PS#invite is a step of #allow's fold") = forAll {
    (a: PSS, cq: Clique[Short]) =>
      (a invite cq) ?= (a allow PartitionedSet(Iterable(cq)))
  }

  property("PS#invite contains PS#exclusive") = forAll {
    (a: PSS, cq: Clique[Short]) => (cq.nonEmpty: Prop) ==> {
        val excl = a exclusive cq
        ((a invite cq).cliques exists (excl ==))
  }}

  property("PS#sparse disjoint contains all elements, no edges") = forAll {(a: PSS) =>
    val (pl, pr) = a.cliques splitAt (a.cliques.size / 2)
    (a.elements =?
      (PartitionedSet(pl) sparse PartitionedSet(pr)).elements) &&
    ((PartitionedSet(pl) sparse PartitionedSet(pr)).cliques.toSet ?=
      a.elements.map(el => Clique(Set(el))))
  }

  property("PS#sparse reflexive") = forAll {(a: PSS) =>
    (a sparse a) ?= a
  }

  property("PS#sparse symmetric") = forAll {(a: PSS, b: PSS) =>
    (a sparse b) ?= (b sparse a)
  }

  property("PS#sparse transitive") = forAll {(a: PSS, b: PSS, c: PSS) =>
    (a sparse (b sparse c)) ?= ((a sparse b) sparse c)
  }
}
