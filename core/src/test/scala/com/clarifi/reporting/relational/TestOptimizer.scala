package com.clarifi.reporting
package relational

import org.scalacheck.{Properties, Prop}
import Prop.{AnyOperators, forAll, propBoolean, secure}
import PrimT._
import Op._

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

  val lit = Literal(NonEmptyList(Map("colAA" -> IntExpr(false, 5), "colCC" -> IntExpr(false, 7))))

  property("optimize leaf literal") = secure {
    val r = LetR(ExtMem(lit), VarR(RTop))
    Optimizer.optimizeRel[Nothing, Nothing](r, (x:Nothing) => x, (x:Nothing) => x) match {
      case (h, SmallLit(rows)) =>
        (rows ?= lit.nel) &&
        (h ?= Map("colAA" -> IntT(), "colCC" -> IntT()))
      case _ => Prop.falsified
    }
  }
}
