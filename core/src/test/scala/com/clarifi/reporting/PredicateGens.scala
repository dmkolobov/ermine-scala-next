package com.clarifi.reporting
import org.scalacheck._
import org.scalacheck.Gen._

import scalaz._
import scalaz.Scalaz._
import scalaz.scalacheck.ScalaCheckBinding._

import com.clarifi.reporting.Predicate._

/**
 * Generators for the different kinds of predicates.
 */
object PredicateGens {
  /**
   * The maximum number of permitted nested predicates.
   */
  private val MaxPredicateLevel = 5

  //
  // Below are the generators for the different types of predicates. The
  // header strings are only strictly required for Lt, Gt, and Eq; however,
  // other predicates can include these predicates, so they all need
  // these two parameters (except for Atom).
  //
  def genPredicateAtom: Gen[Predicate] = for { b <- Gen.oneOf(Gen.value(true), Gen.value(false)) } yield Atom(b)

  private def genPredicateBin(h0: String, h1: String) = {
    val op = OpGens.genOpAny(PrimT.IntT(), h0, h1)
    (oneOf(Seq[(Op, Op) => Predicate](Lt, Gt, Eq))
     |@| op |@| op) {(f, a, b) => f(a, b)}
  }

  private def genPredicateNot(h: (String, String), level: Int): Gen[Predicate] = {
    for {
      p <- _genPredicateAny(h, level - 1)
    } yield Not(p)
  }
  private def genPredicateOr(h: (String, String), level: Int): Gen[Predicate] = genPredicateOr_or_And(Or(_, _), h, level)
  private def genPredicateAnd(h: (String, String), level: Int): Gen[Predicate] = genPredicateOr_or_And(And(_, _), h, level)

  /**
   * Generator for a Or or And, depending on the given flag.
   */
  private def genPredicateOr_or_And(p: (Predicate, Predicate) => Predicate, h: (String, String), level: Int): Gen[Predicate] = {
    for {
      p0 <- _genPredicateAny(h, level - 1)
      p1 <- _genPredicateAny(h, level - 1)
    } yield p(p0, p1)
  }

  /**
   * A generator for predicates that do not recurse into other predicates,
   * such as Atom or Lt. If the given pair does not contain two Strings,
   * then the only predicate that can be created is an Atom.
   */
  private def genPredicateTerminating(h: (String, String)): Gen[Predicate] = {
    Gen.oneOf(genPredicateAtom, genPredicateBin(h._1, h._2))
  }

  /**
   * Generates any kind of predicate. The given Strings are the relation
   * headers that are needed when creating a predicate over two columns
   * (i.e. less than, equal, etc)
   */
  def genPredicateAny(h: (String, String)): Gen[Predicate] =
    _genPredicateAny(h, MaxPredicateLevel)

  /**
   * Generates any predicate depending on the level; if the level is zero,
   * then a terminating predicate is generated (atom or less than); otherwise
   * a non-terminating predicate is generated
   */
  private def _genPredicateAny(h: (String, String), level: Int): Gen[Predicate] = {
    level match {
      case 0 => genPredicateTerminating(h)
      case l => Gen.oneOf(genPredicateAtom,
                         genPredicateBin(h._1, h._2),
                          genPredicateNot(h, l),
                          genPredicateOr(h, l),
                          genPredicateAnd(h, l))
    }
  }
}
