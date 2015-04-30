package com.clarifi.reporting
package relational

import org.scalacheck.{Properties, Prop}
import Prop.{AnyOperators, forAll, propBoolean, secure}
import PrimT._
import Op._
import Predicate._

import scalaz._

object TestOptimizer extends Properties("SQL relation optimizer") {
  implicit val nothingEq: Equal[Nothing] = Equal.equalA

  val aabbTable = Table(Map("colAA" -> IntT(),
                            "colBB" -> IntT()),
                        TableName("someTbl"))

  /** combine args for aabbProjComb */
  def aaPlusBb = (Attribute("colCC", IntT()),
                  Op.Add(Op.ColumnValue("colAA", IntT()),
                         Op.ColumnValue("colBB", IntT())))

  val aabbProjComb: Relation[Nothing, Nothing] =
    Project(Combine(aabbTable, aaPlusBb._1, aaPlusBb._2),
            Map(Attribute("colAA", IntT()) -> ColumnValue("colAA", IntT()),
                Attribute("colCC", IntT()) -> ColumnValue("colCC", IntT())))

  def aabbRenComb: Relation[Nothing, Nothing] =
    RenameR(Combine(aabbTable, aaPlusBb._1, aaPlusBb._2), Attribute("colCC", IntT()), "colDD")

  property("combine followed by project sanity") = secure {
    Typer.closedRel(aabbProjComb) match {
      case Closed(_, h) => h ?= Map("colAA" -> IntT(), "colCC" -> IntT())
    }
  }

  property("combine followed by project optimized") = secure {
    Optimizer.optimizeRel[Nothing, Nothing](aabbProjComb, (x:Nothing) => x,
                                        (x:Nothing) => x) match {
      case (h, jh, SelectR(rs, prj, filt)) =>
        (rs ?= List(aabbTable)) &&
        (prj ?= Map(Attribute("colAA", IntT()) ->
                    ColumnValue("colAA", IntT()), aaPlusBb)) &&
        (filt ?= Atom(true)) &&
        (h ?= Map("colAA" -> IntT(),
                  "colCC" -> IntT())) &&
        (jh ?= Map("colAA" -> IntT(),
                   "colBB" -> IntT()))
    }
  }

  property("combine followed by rename optimized") = secure {
    Optimizer.optimizeRel[Nothing, Nothing](aabbRenComb, (x:Nothing) => x,
                                       (x:Nothing) => x) match {
      case (h, jh, SelectR(rs, prj, filt)) =>
        (rs ?= List(aabbTable)) &&
        (prj ?= Map(Attribute("colAA", IntT()) -> ColumnValue("colAA", IntT()),
                    Attribute("colBB", IntT()) -> ColumnValue("colBB", IntT()),
                    Attribute("colDD", IntT()) -> aaPlusBb._2)) &&
        (filt ?= Atom(true)) &&
        (h ?= Map("colAA" -> IntT(),
                  "colBB" -> IntT(),
                  "colDD" -> IntT())) &&
        (jh ?= Map("colAA" -> IntT(),
                   "colBB" -> IntT()))
    }
  }

  val lit = Literal(NonEmptyList(Map("colAA" -> IntExpr(false, 5), "colCC" -> IntExpr(false, 7)),
                                 Map("colAA" -> IntExpr(false, 4), "colCC" -> IntExpr(false, 8))))

  val caseLit = If(Eq(ColumnValue("colAA",IntT()),OpLiteral(IntExpr(false,5))),
                   OpLiteral(IntExpr(false,7)),
                   OpLiteral(IntExpr(false,8)))

  val filtLit = And(Atom(true),
                    Or(Eq(ColumnValue("colAA",IntT()),OpLiteral(IntExpr(false, 5))),
                       Eq(ColumnValue("colAA",IntT()),OpLiteral(IntExpr(false, 4)))))

  property("optimize leaf literal") = secure {
    val r = Join(aabbTable, LetR(ExtMem(lit), VarR(RTop)))
    Optimizer.optimizeRel[Nothing, Nothing](r, (x:Nothing) => x, (x:Nothing) => x) match {
      case (h, jh, SelectR(rs, prj, filt)) =>
        (rs ?= List(aabbTable)) &&
        (prj ?= Map(Attribute("colAA", IntT()) -> ColumnValue("colAA", IntT()),
                    Attribute("colBB", IntT()) -> ColumnValue("colBB", IntT()),
                    Attribute("colCC", IntT()) -> caseLit)) &&
        (filt ?= filtLit) &&
        (h ?= Map("colAA" -> IntT(), "colBB" -> IntT(), "colCC" -> IntT())) &&
        (jh ?= Map("colAA" -> IntT(), "colBB" -> IntT()))
    }
  }

  property("optimize inner literal") = secure {
    val r = LetR(ExtMem(lit), Join(VarR(RPop(aabbTable)), VarR(RTop)))
    Optimizer.optimizeRel[Nothing, Nothing](r, (x:Nothing) => x, (x:Nothing) => x) match {
      case (h, jh, SelectR(rs, prj, filt)) =>
        (rs ?= List(aabbTable)) &&
        (prj ?= Map(Attribute("colAA", IntT()) -> ColumnValue("colAA", IntT()),
                    Attribute("colBB", IntT()) -> ColumnValue("colBB", IntT()),
                    Attribute("colCC", IntT()) -> caseLit)) &&
        (filt ?= filtLit) &&
        (h ?= Map("colAA" -> IntT(), "colBB" -> IntT(), "colCC" -> IntT())) &&
        (jh ?= Map("colAA" -> IntT(), "colBB" -> IntT()))
    }
  }
}
