package com.clarifi.reporting

import scalaz.{@@, Equal, NonEmptyList, Tag}
import scalaz.Id._
import scalaz.syntax.order._
import scalaz.std.option._
import scalaz.std.set._
import scalaz.std.string._
import scalaz.scalacheck.ScalaCheckBinding._
import scalaz.scalacheck.ScalazProperties._
import scalaz.scalacheck.ScalazArbitrary.OrderingArbitrary

import org.scalacheck._
import Prop.{extendedAny => _, _}
import Arbitrary.arbitrary

import com.clarifi.reporting.util.PartitionedSet

import Reporting._
import PrimT.IntT

/*
/** Some sample tagged relations.  Prefer adding new samples to
  * altering longstanding ones, as tests may dig into their peculiar
  * corners. */
object TaggedRelations {
  /** table someTbl [colAA Int, colBB Int] */
  def aabbTable[H](implicit tag: RTag[H]) = {
    import tag._
    Ref(RefID("someTbl"),
        Map("colAA" -> IntT(), "colBB" -> IntT()),
        Source("someDB"))
  }

  /** combine args for aabbProjComb */
  def aaPlusBb = (Attribute("colCC", IntT()),
                  Op.Add(Op.ColumnValue("colAA", IntT()),
                         Op.ColumnValue("colBB", IntT())))

  /** `project {colAA, colCC} . {colAA colBB => colCC = colAA + colBB}` */
  def aabbProjComb[H](implicit tag: RTag[H]) = {
    import tag._
    Project(Combine(aabbTable, aaPlusBb._1, aaPlusBb._2),
            Set("colAA", "colCC"))
  }

  def aabbRenComb[H](implicit tag: RTag[H]) = {
    import tag._
    Rename(Combine(aabbTable, aaPlusBb._1, aaPlusBb._2),
           "colCC", "colDD")
  }

  def lit42[H](colname: ColumnName)(implicit tag: RTag[H]) =
    tag.Literal(NonEmptyList(Map(colname -> IntExpr(false, 42))))

  def aaeq42[H](r: Relation[H])(implicit tag: RTag[H]) =
    tag.Filter(r, Predicate.Eq(Op.ColumnValue("colAA", IntT()),
                               Op.OpLiteral(IntExpr(false, 42))))
}
*/

object RTagGens {
  implicit val arbExpr = Arbitrary(RelationGens.genPrimExpr)

  /** @todo S11 perhaps include equivalence tests */
  implicit def arbReflexivity[K: Arbitrary: Equal]: Arbitrary[Reflexivity[K]] =
    Arbitrary(arbitrary[Map[K, Option[PrimExpr]]]
              map (ForallTups(_, PartitionedSet.zero)))
}

object TestRTag extends Properties("PrimTs, PrimExprs, Reflexivity") {
  import com.clarifi.reporting.{TypeTag => H}
  import RTagGens._
  implicit val arbPrimt = Arbitrary(RelationGens.primT)
  implicit val arbHeader = Arbitrary(RelationGens.genVariableHeader)

  property("type reflexivity") = forAll { h: Header =>
    sup(h, h) ?= Some(h)
  }

  property("type symmetry") = forAll {(h1: Header, h2: Header) =>
    sup(h1, h2) ?= sup(h2, h1)
  }

  property("type associativity") = forAll {(t1: PrimT, t2: PrimT, t3: PrimT) =>
    (t1 sup t2 flatMap (_ sup t3)) ?= (t2 sup t3 flatMap (t1 sup _))
  }

  property("type order") = order.laws[PrimT]

  property("column equivalence required") = forAll {(h1: Header, h2: Header) =>
    (h1.keySet /== h2.keySet) ==> (sup(h1, h2) ?= None)
  }

  property("nullable variants unify up") = forAll {h: Header =>
    val nulled = h.mapValues(_.withNull)
    sup(h, nulled) ?= Some(nulled)
  }

  property("0-len string is root string type") = forAll {h: Header =>
    val zerostringed =
      h.mapValues{case PrimT.StringT(l, n) => PrimT.StringT(0, n)
                  case x => x}
    sup(h, zerostringed) ?= Some(zerostringed)
  }

  property("only equal IntTs are equal") = secure {
    ((IntT(false): PrimT) ?= (IntT(false): PrimT)) &&
      ((IntT(true): PrimT) != (IntT(false): PrimT))
  }

  property("IntT matches IntT, not LongT") = secure {
    (IntT(false): PrimT) match {
      case PrimT.LongT(_) => false
      case IntT(n) => !n
    }
  }

  property("StringT equal is total") = secure {
    (PrimT.StringT(0): PrimT) != (IntT(): PrimT)
  }

  trait FortyTwoExprT
  type FortyTwoExpr = PrimExpr @@ FortyTwoExprT

  private implicit val fortytwos: Arbitrary[FortyTwoExpr] =
    Arbitrary(Gen.oneOf(Seq(ByteExpr(false, 42), ShortExpr(false, 42),
                            IntExpr(false, 42), LongExpr(false, 42),
                            DoubleExpr(false, 42))) map (Tag.subst[PrimExpr, Id, FortyTwoExprT](_)))

  property("42-value equivalence is just type unification") = forAll {
    (x: FortyTwoExpr, y: FortyTwoExpr) =>
      (x ?= y) == ((x.typ sup y.typ).isDefined: Prop)
  }

  property("value equivalence presupposes type unification") = forAll {
    (x: PrimExpr, y: PrimExpr) =>
      // ==> discards too many cases, and I'm not that interested,
      // since the 42 test is the really interesting one
      if (x == y) (x.typ sup y.typ).isDefined else true
  }

  property("primexpr order") = order.laws[PrimExpr]

  property("reflexivity union (AND) is reflexive") = forAll {
    (rx: Reflexivity[ColumnName]) =>
      (rx && rx) ?= rx
  }

  property("reflexivity intersection (OR) keeps like Somes, drops Nones") = forAll {
    (rx: Reflexivity[ColumnName]) =>
      (rx || rx) ?= rx.varyConsts(_ filter (_._2.isDefined))
  }

  property("reflexivity union prefers known values") = forAll {
    (rx: Reflexivity[ColumnName]) =>
      (rx && rx.varyConsts(_ mapValues (Function const None))) ?= rx
  }

  property("reflexivity value disagreement is erased in intersections") = forAll {
    (rx: Reflexivity[ColumnName], uniq: Option[PrimExpr]) =>
      (!rx.consts.values.exists(_ === uniq)) ==> {
        val disagreed = rx.varyConsts(_ mapValues (Function const uniq))
        (rx || disagreed) ?= Reflexivity.zero[ColumnName]
      }
  }

  private def stringTup(tup: Map[ColumnName, String]): Record =
    tup mapValues (StringExpr(false, _))

/*
  private def litrel[H](tups: NonEmptyList[Map[ColumnName, String]]
                      )(implicit tag: RTag[H]): Relation[H] =
    tag Literal (tups map stringTup)

  private def stringHeader(cols: ColumnName*): Header =
    (cols.view map (_ -> PrimT.StringT(0)) toMap)

  private def litrelProp(rel: Relation[_], expectedTups: Set[Map[ColumnName, String]]): Prop =
    rel iff {case Relation.Relation(_, RelationImplF.Literal(tups)) =>
      tups.list.toSet ?= expectedTups.map(stringTup)}

  private val magicWords =
    litrel[H](NonEmptyList(Map("hd" -> "abra", "tl" -> "cadabra"),
                           Map("hd" -> "ala", "tl" -> "kazaam")))

  private val magicHead =
    litrel[H](NonEmptyList(Map("hd" -> "abra", "magic" -> "yes"),
                           Map("hd" -> "ala", "magic" -> "yes"),
                           Map("hd" -> "ala", "magic" -> "sure"),
                           Map("hd" -> "co", "magic" -> "no")))

  property("literal joins empty") = secure {
    val h: Header = Map("hd" -> PrimT.StringT(4), "tl" -> PrimT.StringT(7),
                        "magic" -> PrimT.StringT(0))
    (("one" |: (Join(magicWords, Empty(stringHeader("magic")))
                ?= Empty(h)))
     && ("other" |: (Join(Empty(stringHeader("magic")), magicWords)
                     ?= Empty(h))))
  }

  property("literal join cartesian") = secure {
    litrelProp(Join(magicWords,
                    litrel[H](NonEmptyList(Map("magic" -> "probably")))),
               Set(Map("hd" -> "abra", "tl" -> "cadabra",
                       "magic" -> "probably"),
                   Map("hd" -> "ala", "tl" -> "kazaam",
                       "magic" -> "probably")))
  }

  property("literal joins on data") = secure {
    val magicJoined =
      Set(Map("hd" -> "abra", "tl" -> "cadabra", "magic" -> "yes"),
          Map("hd" -> "ala", "tl" -> "kazaam", "magic" -> "yes"),
          Map("hd" -> "ala", "tl" -> "kazaam", "magic" -> "sure"))
    (("one way" |: litrelProp(Join(magicWords, magicHead), magicJoined))
     && ("other way" |: litrelProp(Join(magicHead, magicWords), magicJoined)))
  }
*/
}
