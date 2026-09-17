package com.clarifi.reporting
package writers

import collection.immutable.IndexedSeq

import scalaz._
import scalaz.scalacheck.ScalaCheckBinding._
import scalaz.scalacheck.ScalazProperties._
import scalaz.scalacheck.ScalazArbitrary.NonEmptyListArbitrary
import scalaz.syntax.monad._
import scalaz.syntax.traverse.{ToFunctorOps => _, _}
import scalaz.std.AllInstances._
import scalaz.syntax.monoid._

import org.scalacheck.{Arbitrary, Gen, Prop, Properties}
import Arbitrary.arbitrary
import Prop._

import com.clarifi.reporting.{Op, DoubleExpr, PrimExpr, SortOrder, StringExpr, ColumnName}
import com.clarifi.reporting.PrimT.{StringT, DoubleT}
import com.clarifi.reporting.{RelationGens => RG}

object LegendGens {
  import com.clarifi.reporting.OpGens.genOpAny

  val underlyingOps: Gen[Op] =
    (RG.genPrimTypeForCombine |@| arbitrary[String] |@| arbitrary[String])(genOpAny).join

  val directions: Gen[SortDirection] =
    Gen.oneOf(Seq(SortDirection.Forward, SortDirection.Reverse))

  val truncateSamples: Gen[(Format.Truncate, Gen[NonEmptyList[PrimExpr]])] =
    Gen.choose(0, 10) map (plc => Format.Truncate(plc)
                               -> (RG.genPrimExpr map (NonEmptyList(_))))

  /** Formats and domains of interest for them.  All formats must, of
    * course, operate on all primexpr nels, but these ones in
    * particular should be studied. */
  val formatSamples: Gen[(Format, Gen[NonEmptyList[PrimExpr]])] =
    Gen.oneOf(Gen.const(Format.Default -> (RG.genPrimExpr map (NonEmptyList(_)))),
              Gen.const(Format.Percentage(false, false, 2, false) -> (RG.genNumExpr map (NonEmptyList(_)))),
              Gen.oneOf("USD", "GBP", "INR") map (cc => Format.Currency(false, false, cc) -> (RG.genNumExpr map (NonEmptyList(_)))),
              Gen.const(Format.DateRange
                        -> (^(RG.genDateExpr, RG.genDateExpr) (NonEmptyList(_,_)))),
              Gen.choose(0, 10) map (plc => Format.Round(false, false, plc) -> (RG.genNumExpr map (NonEmptyList(_)))),
              Gen.choose(0, 10) map (plc => Format.IntegralRound(false, false, plc) -> (RG.genNumExpr map (NonEmptyList(_)))),
              truncateSamples
    )

  val presentations: Gen[Presentation] = for {
    opCount <- Gen.choose(1, 2)
    ops <- Gen.listOfN(opCount, underlyingOps)
  } yield Presentation(Format.Default,
                       NonEmptyList.nel(ops.head, scalaz.IList.fromList(ops.tail)))

  def legends[Lbl](lbls: Gen[Lbl]): Gen[Legend.U[Lbl]] = {
    implicit val pd = Arbitrary(for {
      p <- presentations
      cols = p.columnReferences
      dirs <- Gen.listOfN(cols.size, directions)
    } yield (p, SortStrategy(cols.toSeq zip dirs)))
    implicit val l = Arbitrary(lbls)
    arbitrary[List[((Presentation, SortStrategy), Lbl)]] map {
        curried => Legend(LegendColumns flat (curried map {case ((p, d), lbl) => (p, d, lbl)}
                                               toIndexedSeq)
                         , IndexedSeq.empty, None)
    }
  }
}

object TestLegend extends Properties("Legends & presentations") {
  import LegendGens._

  implicit def impLegends[Lbl: Arbitrary]: Arbitrary[Legend.U[Lbl]] =
    Arbitrary(legends(arbitrary[Lbl]))

  implicit val formats: Arbitrary[Format] = Arbitrary(formatSamples map (_._1))

  implicit val primExprs: Arbitrary[PrimExpr] = Arbitrary(RG.genPrimExpr)

  sealed trait Interesting
  val Interesting = Tag.of[Interesting]
  def uninteresting[A,B](ab: (A,B) @@ Interesting): (A,B) = Tag.unwrap(ab)
  type InterestingFormat = (Format, NonEmptyList[PrimExpr]) @@ Interesting

  implicit val formatsWithArgs: Arbitrary[InterestingFormat] =
    Arbitrary(Interesting subst (formatSamples flatMap (_.sequence)))

  implicit val truncatesWithArgs: Arbitrary[(Format.Truncate, NonEmptyList[PrimExpr])
                                            @@ Interesting] =
    Arbitrary(Interesting subst (truncateSamples flatMap (_.sequence)))

  implicit val numExpr: Arbitrary[PrimExpr @@ Number] =
    Tag subst (Arbitrary(RG.genNumExpr))

  /** Span each label across the underlying columns in sort-order. */
  private def orderedLabels[Lbl](leg: Legend.U[Lbl]): Seq[(ColumnName, Lbl)] = for {
    labeledPtion <- leg.leavesInOrder
    (ption, SortStrategy(sortBy), label) = labeledPtion
    col <- sortBy.map(_._1)
  } yield col -> label

  property("sorting left-to-right yields std columnname ordering") = forAll {
    (l: Legend.U[String]) =>
      (l.deriveSort(l.leftToRightSort)
       map (_._1)).toSeq.distinct ?= orderedLabels(l).map(_._1).toIndexedSeq.distinct
  }

  property("empty sort begets empty sort") = forAll {
    (l: Legend.U[String]) => l.deriveSort(Seq.empty).isEmpty
  }

  property("nonsense labels are harmless") = forAll {
    (l: Legend.U[Int], nonsense: Int) =>
      (!l.orderedPresentations.find(_._2 == nonsense).isDefined) ==>
        (l.deriveSort(Seq(nonsense -> SortOrder.Asc)) ?= IndexedSeq.empty)
  }

  property("nonsense labels filter out") = forAll {
    (l: Legend.U[Int], nonsense: Int) =>
      (!l.orderedPresentations.find(_._2 == nonsense).isDefined) ==>
        (l.filterSort(Seq(nonsense -> SortOrder.Asc)) ?= IndexedSeq.empty)
  }

  property("overflow labels are harmless") = forAll {
    (l: Legend.U[String]) =>
      val stdsort = (l.orderedPresentations.view map (_._2 -> SortOrder.Asc)).toSeq
      l.deriveSort(stdsort) ?= l.deriveSort(stdsort ++ stdsort)
  }

  property("overflow labels filter out") = forAll {
    (l: Legend.U[String]) =>
      val stdsort: Seq[(String, SortOrder)] =
        (l.orderedPresentations.view map (p => (p._2, SortOrder.Asc: SortOrder))).toSeq
      l.filterSort(stdsort) ?= l.filterSort(stdsort ++ stdsort)
  }

  val crazyLegend: Legend.U[String] =
    Legend(LegendColumns flat (
             Seq((Presentation(Format.Default,
                               NonEmptyList(Op.ColumnValue("fname", StringT(0)))),
                  SortStrategy allForward Seq("fname"), "Name!"),
                 (Presentation(Format.Default,
                               NonEmptyList(Op.ColumnValue("lname", StringT(0)))),
                  SortStrategy allForward Seq("lname"), "Name!"),
                 (Presentation(Format.Percentage(false, false, 2, false),
                               NonEmptyList(Op.Sub(Op.Sub(Op.OpLiteral(DoubleExpr(false, 0)),
                                                          Op.ColumnValue("qbranch", DoubleT())),
                                                   Op.ColumnValue("rbranch", DoubleT())))),
                  SortStrategy(Seq("qbranch" -> SortDirection.Reverse,
                                   "rbranch" -> SortDirection.Reverse)),
                  "What's left?"))), IndexedSeq.empty, None)

  property("sorting a Lbl once chooses the leftmost") = secure {
    crazyLegend.deriveSort(Seq("Name!" -> SortOrder.Desc)) ?=
    IndexedSeq("fname" -> SortOrder.Desc)
  }

  property("sorting a Lbl twice chooses the left, 2nd left") = secure {
    crazyLegend.deriveSort(Seq("Name!" -> SortOrder.Desc,
                               "Name!" -> SortOrder.Desc)) ?=
    IndexedSeq("fname" -> SortOrder.Desc, "lname" -> SortOrder.Desc)
  }

  property("sorting a dual preserves underlying order, flips if needed") = secure {
    crazyLegend.deriveSort(Seq("What's left?" -> SortOrder.Asc,
                               "Name!" -> SortOrder.Asc)) ?=
    IndexedSeq("qbranch" -> SortOrder.Desc, "rbranch" -> SortOrder.Desc,
               "fname" -> SortOrder.Asc)
  }

  property("format basicEvals are homs") = forAll {
    (fmt: Format, pe: NonEmptyList[PrimExpr]) =>
      fmt.basicEval(pe) match {
        case x if x eq pe.head => true :| "identity, sort of"
        case StringExpr(_, shown) => true :| shown
        case x => false :| ("nonsense resulted: " + x)
      }
  }

  private def wellTyped(op: Op) =
    op.guessType.fold(_.foldLeft(falsified :| ("ill-typed " + op))
                                (_ :| _), _ => proved)

  property("format devolves are homs") = forAll {
    (fmt: Format, pe: NonEmptyList[PrimExpr]) =>
      val devolved = fmt.devolve(pe map Op.OpLiteral)
      (wellTyped(devolved) && {devolved.eval(Map.empty); proved})
  }

  // FLAKY (docs/gate-policy.md §1): a gate never re-runs, so a property that gives both answers on
  // the same content is registered only under -Dermine.test.flaky=true until its ticket is fixed.
  // Ticket E13 (TICKET-stdlib-findings.md): seed-dependent date-range formatting.
  if (sys.props.contains("ermine.test.flaky"))
  property("extra args are ignored") = forAll {
    (trial: InterestingFormat) =>
      val (fmt, pe) = uninteresting(trial)
      fmt.basicEval(pe) ?= fmt.basicEval(pe |+| pe)
  }

  property("formatting interesting things makes strings") = forAll {
    (trial: InterestingFormat) =>
      val (fmt, pe) = uninteresting(trial)
      ((fmt ne Format.Default) && ! fmt.isInstanceOf[Format.Truncate]) ==> (fmt.basicEval(pe) match {
        case StringExpr(_, shown) => true :| shown
        case x => false :| ("evalled to " + x)
      })
  }

  property("devolved round rounds") = forAll {
    (pe: PrimExpr @@ Number) =>
    math.abs(Tag.unwrap(pe).extractDouble) < 1e13 ==>
      (Format.Round(false, false, 2).devolve(NonEmptyList(Op.OpLiteral(Tag.unwrap(pe))))
         .eval(Map.empty).extractDouble
         ?= (math.round(Tag.unwrap(pe).extractDouble * 100) / 100.0))
  }

  property("truncate truncates") = forAll {
    (trial: (Format.Truncate, NonEmptyList[PrimExpr]) @@ Interesting) =>
      val (fmt, pe) = uninteresting(trial)
      fmt match {
        case Format.Truncate(n) => (fmt.basicEval(pe) match {
          case StringExpr(_, shown) => (shown.length <= (n max 3)) :| shown
          case x => true :| ("vacuously ok")
        })
        case _ => false :| ("impossible: " + fmt)
      }
  }

  property("basic eval does sort of what I think") = secure {
    type IS = IndexedSeq[PrimExpr]
    (IndexedSeq(StringExpr(false, "Mr."), StringExpr(false, "Bill"),
                StringExpr(false, "-75%")): IS) =?
    (crazyLegend.basicEval(Map("fname" -> StringExpr(false, "Mr."),
                               "lname" -> StringExpr(false, "Bill"),
                               "qbranch" -> DoubleExpr(false, 0.25),
                               "rbranch" -> DoubleExpr(false, 0.5))): IS)
  }

  property("natural equality") = secure {
    (Equal[Format].equalIsNatural: Prop) &&
    (Equal[Presentation].equalIsNatural: Prop) &&
    (Equal[SortDirection].equalIsNatural: Prop)
  }

  include(monoid.laws[Legend.U[String]], "legend monoid.")

  implicit val arbPres: Arbitrary[Presentation] = Arbitrary(presentations)
  implicit val arbSD: Arbitrary[SortDirection] = Arbitrary(directions)
  implicit val arbSS: Arbitrary[SortStrategy] =
    implicitly[Arbitrary[List[(ColumnName, SortDirection)]]] map SortStrategy.apply

  include(equal.laws[Format], "format equal.")
  include(equal.laws[Presentation], "presentation equal.")
  include(order.laws[SortStrategy], "sortstrategy order.")
  include(order.laws[SortDirection], "sortdirection order.")
  include(equal.laws[Legend.U[String]], "legend equal.")
}

object TestErmineLegends extends Properties("Ermine legends") {
  import com.clarifi.reporting.ermine.Prim
  private val ermineFixture = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import ermineFixture._

  property("presentation coercion") = secure {
    eval("primAsPreses", Map("Layout.PresentationTest" -> all)).whnf iff {
      case Prim(xs: List[_]) if xs nonEmpty => Prop.all((xs map (_ iff {
        case _: Presentation => true: Prop
      })): _*)
    }
  }
}
