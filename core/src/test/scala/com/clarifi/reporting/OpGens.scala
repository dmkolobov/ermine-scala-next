package com.clarifi.reporting

import org.scalacheck.Gen
import org.scalacheck.Gen._

import scalaz._
import scalaz.scalacheck.ScalaCheckBinding._
import syntax.applicative._

import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.Op._
import com.clarifi.reporting.Predicate.Atom

/**
 * Generators for the different kinds of operations for the combine relation.
 */
object OpGens {
  import PredicateGens.genPredicateAny

  def genOpLiteral(t: PrimT): Gen[Op] =
    RelationGens.simplePrimExpr(t) map OpLiteral

  /**
   * Creates an operation based on the given type and column names.
   */
  def genOpAny(t: Type, h1: String, h2: String): Gen[Op] = {
    val rec = lzy(genOpAny(t, h1, h2))
    def oneBinOp(fs: ((Op, Op) => Op)*) =
      (rec |@| rec |@| oneOf(fs)) {(l, r, ct) => ct(l, r)}
    oneOf(genOpLiteral(t), oneOf(Seq(h1, h2)) map (ColumnValue(_, t)),
          t match {
            case StringT(_,_) => oneBinOp({(l, r) => Concat(List(l, r))})
            case IntT(_) => oneBinOp(Add, Sub, Mul, FloorDiv,
                                    If(Atom(true), _, _), If(Atom(false), _, _))
            case DoubleT(_) => oneBinOp(Add, Sub, Mul, DoubleDiv, Pow)
            case DateT(_) => oneBinOp(Add, Sub)
            case BooleanT(_) => sys.error("Booleans do not support any ops")
            case _ => sys.error("Unrecognized type: " + t)
          })
  }
}
