package com.clarifi.reporting
/*
import scalaz.Show
import scalaz.std.string._
import scalaz.std.tuple._
import scalaz.syntax.show._

import org.scalacheck.{Arbitrary, Gen, Properties, Prop}
import Arbitrary.arbitrary
import Prop.{AnyOperators, exists, forAll, propBoolean, secure}

import com.clarifi.reporting.relational._
import com.clarifi.reporting.ReportingUtils.MapElts
import com.clarifi.reporting.util.{Clique, PartitionedSet}

import Provenance.RefUsage
import Reporting._
import PrimT.IntT
import TaggedRelations._

object AccessGens {
  import RTagGens._

  val untypedRef: Gen[UntypedRef] =
    arbitrary[(String, String)] map {
      case (r, s) => UntypedRef(RefID(r), Source(s))}

  val refUsage: Gen[RefUsage] = {
    implicit val ur = Arbitrary(untypedRef)
    (arbitrary[Map[UntypedRef, (Set[ColumnName], Reflexivity[ColumnName])]]
     map (_ mapValues {case (cn, rx) => (cn | rx.consts.keySet, rx)}))
  }
}

object TestAccess extends Properties("relational capability testing") {
  import AccessGens._
  implicit val arbRefUsage = Arbitrary(refUsage)

  type RT = (Provenance[BackedColumn], TypeTag)
  lazy val tag: RTag[RT] = implicitly
  import tag._

  /** Like [[org.scalacheck.Prop]].iff, but use Show, and curry for
    * better inference. */
  def iffS[A: Show](a: A)(p: PartialFunction[A, Prop]): Prop =
    (p.orElse[A, Prop]{case x =>
      false :| ("unmatched value: " + x.shows)})(a)

  val someTbl = UntypedRef(RefID("someTbl"), Source("someDB"))
  val aabb = Set("colAA", "colBB")
  val justAA = Set("colAA")

  val projEq = PartitionedSet[BackedColumn](Iterable(
    Clique(Set(RelCol("colAA"), AbsCol(someTbl, "colAA"))),
    Clique(Set(AbsCol(someTbl, "colBB"))))) // vacuous
  val projGraph = PartitionedSet.single[BackedColumn](
    RelCol("colAA"), AbsCol(someTbl, "colAA"),
    AbsCol(someTbl, "colBB"), RelCol("colCC"))

  property("combine followed by project") = secure {
    iffS(aabbProjComb[RT] map (_._1)) {
      case RelF(projTag, RI.Project(
        RelF(combTag, RI.Combine(RelF(refTag, RI.Ref(_, myHead, _)),
                                 _, _)), _)) =>
          val refEq = PartitionedSet[BackedColumn](Iterable(
            Clique(Set(RelCol("colAA"), AbsCol(someTbl, "colAA"))),
            Clique(Set(RelCol("colBB"), AbsCol(someTbl, "colBB")))))
          val combGraph = PartitionedSet[BackedColumn](Iterable(Clique(Set(
            RelCol("colAA"), AbsCol(someTbl, "colAA"),
            RelCol("colBB"), AbsCol(someTbl, "colBB"),
            RelCol("colCC")))))
          (refTag ?= Provenance(ForallTups(Map.empty, refEq),
                                refEq)) &&
          (combTag ?= Provenance(ForallTups(Map.empty, refEq),
                                 combGraph)) &&
          (projTag ?= Provenance(ForallTups(Map.empty, projEq),
                                 projGraph)) &&
          iffS(projTag.references(Map("colAA" -> IntT()))){
            case MapElts((`someTbl`, (`aabb`, ForallTups(MapElts(), _)))) =>
              true
          }
    }
  }

  property("combine followed by project optimized") = secure {
    iffS(optimizeRelation(aabbProjComb[RT]) map (_._1)) {
      case RelF(amaTag, RI.Amalgamation(
        List(RelF(refTag, RI.Ref(sometbl, myHead, _))),
        prj, ren, cmb, Predicate.Atom(true))) =>
          (sometbl ?= RefID("someTbl")) &&
          (amaTag ?= Provenance(ForallTups(Map.empty, projEq),
                                projGraph))
    }
  }

  property("join constant is filter = constant") = secure {
    val joining = Join(aabbProjComb, lit42("colAA")).extract._1
    val filtering = aaeq42[RT](aabbProjComb).extract._1
    (joining ?= filtering) &&
    iffS(joining.references(Map("colAA" -> IntT(), "colCC" -> IntT()))) {
      case MapElts((`someTbl`, (`aabb`, rx))) =>
        rx.consts ?= Map("colAA" -> Some(IntExpr(false, 42)))
    }
  }

  property("concrete phantoms keep constancy") = secure {
    val bbsFromAA42 = Project(aaeq42(aabbTable), Set("colBB"))
    val refs = Map("colBB" -> IntT())
    def forBB(r: Relation[RT]) = r.extract._1 references refs
    ("join" |: iffS(forBB(Join(bbsFromAA42, bbsFromAA42))) {
      case MapElts((`someTbl`, (`aabb`, rx))) =>
        rx.consts ?= Map("colAA" -> Some(IntExpr(false, 42)))
    }) &&
    ("union" |: iffS(forBB(Union(bbsFromAA42, bbsFromAA42))) {
      case MapElts((`someTbl`, (`aabb`, rx))) =>
        rx.consts ?= Map("colAA" -> Some(IntExpr(false, 42)))
    })
  }

  property("contradictory concrete phantoms lose constancy") = secure {
    val bbsFromAA42 = Project(aaeq42[RT](aabbTable), Set("colBB"))
    val bbsFromAA84 =
      Project(Filter(
        aabbTable, Predicate.Eq(Op.ColumnValue("colAA", IntT()),
                                Op.OpLiteral(IntExpr(false, 84)))),
              Set("colBB"))
    val refs = Map("colBB" -> IntT())
    def forBB(r: Relation[RT]) = r.extract._1 references refs
    ("join" |: iffS(forBB(Join(bbsFromAA42, bbsFromAA84))) {
      case MapElts((`someTbl`, (`aabb`, rx))) =>
        rx.consts ?= Map.empty
    }) &&
    ("union" |: iffS(forBB(Union(bbsFromAA42, bbsFromAA84))) {
      case MapElts((`someTbl`, (`aabb`, rx))) =>
        rx.consts ?= Map.empty
    })
  }

  property("top-level transitive constancy success") = secure {
    val rewrittenToD = Project(Combine(aabbTable,
                                       Attribute("colDD", IntT()),
                                       Op.ColumnValue("colAA", IntT())),
                               Set("colDD"))
    val filt = Filter(Join(rewrittenToD, rewrittenToD),
                      Predicate.Eq(Op.ColumnValue("colDD", IntT()),
                                   Op.OpLiteral(IntExpr(false, 55))))
    iffS(filt.extract._1 references Map("colDD" -> IntT())) {
      case MapElts((`someTbl`, (`justAA`, rx))) =>
        rx.consts ?= Map("colAA" -> Some(IntExpr(false, 55)))
    }
  }

  property("top-level transitive constancy failure") = secure {
    val filt = Filter(Join(Rename(aabbTable, "colAA", "colEE"),
                           Rename(aabbTable, "colAA", "colFF")),
                      Predicate.Eq(Op.ColumnValue("colDD", IntT()),
                                   Op.OpLiteral(IntExpr(false, 66))))
    iffS(filt.extract._1 references Map("colEE" -> IntT(), "colFF" -> IntT())) {
      case MapElts((`someTbl`, (`aabb`, rx))) =>
        rx.consts ?= Map.empty
    }
  }

  property("transitive union failure") = secure {
    val un = Union(Combine(Rename(aabbTable, "colAA", "colEE"),
                           Attribute("colFF", IntT()),
                           Op.OpLiteral(IntExpr(false, 77))),
                   Combine(Rename(aabbTable, "colAA", "colFF"),
                           Attribute("colEE", IntT()),
                           Op.OpLiteral(IntExpr(false, 88))))
    iffS(un.extract._1 references Map("colEE" -> IntT(), "colFF" -> IntT())) {
      case MapElts((`someTbl`, (`justAA`, rx))) =>
        rx.consts ?= Map.empty
    }
  }

  property("capability identity") = forAll {(cap: RefUsage) =>
    RefUsage permitted (cap, cap): Prop
  }

  property("capability non-vacuous") = exists {(xs: (RefUsage, RefUsage)) =>
    !RefUsage.permitted(xs._1, xs._2): Prop
  }
}*/
