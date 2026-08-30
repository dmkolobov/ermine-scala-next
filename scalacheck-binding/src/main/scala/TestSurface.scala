package com.clarifi.reporting

import com.clarifi.reporting.ermine.{ Fixity, Idfix, InfixL }
import com.clarifi.reporting.ermine.surface._

import org.scalacheck._
import Prop._

/** Structural sanity for the surface AST (roadmap 2.1): the shapes
  * compose into the trees 2.3's parser will build, and Span's hit-test
  * arithmetic behaves.  The real exercise arrives with the parser. */
object TestSurface extends Properties("Surface AST") {

  def sp(l1: Int, c1: Int, l2: Int, c2: Int) = Span(l1, c1, l2, c2)
  def nm(s: String, l: Int, c: Int, fix: Fixity = Idfix) =
    SName(s, Plain, fix, sp(l, c, l, c + s.length))

  property("span containment is half-open and multi-line aware") = {
    val s = sp(2, 5, 4, 1)
    (s.contains(2, 5) :| "start in") &&
    (!s.contains(4, 1) :| "end out") &&
    (s.contains(3, 999) :| "middle line in") &&
    (!s.contains(2, 4) :| "before start out") &&
    ((sp(1, 1, 1, 3) to sp(1, 8, 1, 9)) ?= sp(1, 1, 1, 9))
  }

  property("a flat chain with occurrences composes and keeps spellings") = {
    // 1 + !! x  — infix + at post-operand, !! at operand position
    val chain = Chain[STerm](Real(sp(1, 5, 1, 13)), List(
      Left(SLitInt(Real(sp(1, 5, 1, 6)), 1)),
      Right(OpOcc(nm("+", 1, 7, InfixL(6)), PostOperandPos)),
      Right(OpOcc(nm("!!", 1, 9, Idfix), OperandPos)),
      Left(SVar(nm("x", 1, 12)))))
    val ops = chain.items.collect { case Right(o) => (o.name.spelling, o.posClass) }
    (ops ?= List(("+", PostOperandPos), ("!!", OperandPos))) &&
    (chain.items.length ?= 4)
  }

  property("a module with an aliased import and a where equation builds") = {
    val m = SModule("Nav.e",
      SHeader(Real(sp(1, 1, 1, 17)), "Nav", Some(sp(1, 8, 1, 11)), explicitLayout = false,
        List(SImport(Real(sp(2, 1, 2, 22)), isExport = false, "Function", sp(2, 8, 2, 16),
          as = Some(nm("F", 2, 20, Idfix)), items = None))),
      List(
        SFixity(Real(sp(3, 1, 3, 12)), InfixL(5), typeLevel = false, List(nm(":%:", 3, 10, InfixL(5)))),
        SEquation(Real(sp(4, 1, 5, 12)), nm("f", 4, 1), List(SPVar(nm("w", 4, 3))),
          SVar(nm("id_F", 4, 7)),
          Some(SWhere(Real(sp(5, 3, 5, 12)), List(
            SEquation(Real(sp(5, 9, 5, 12)), nm("w", 5, 9), Nil,
              SLitInt(Real(sp(5, 11, 5, 12)), 5), None)))))))
    // the fixity statement is IN the tree, and the alias affix spelling survives
    (m.statements.collectFirst { case f: SFixity => f.ops.head.spelling } ?= Some(":%:")) &&
    (m.statements.collectFirst { case e: SEquation => e.body } match {
      case Some(SVar(n)) => (n.spelling ?= "id_F") :| "affix kept as written"
      case other         => falsified :| ("unexpected body: " + other)
    })
  }
}
