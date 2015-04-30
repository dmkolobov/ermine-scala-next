/*package com.clarifi.reporting

import scalaz.Id._
import scalaz.std.list._
import scalaz.WriterT
import scalaz.WriterT.writer

import org.scalacheck._
import Prop.{extendedAny => _, _}
import Arbitrary.arbitrary

import PrimT.IntT
import Reporting._

object TestRelations extends Properties("relation ADTs") {
  implicit val genop = Arbitrary(OpGens.genOpAny(PrimT.IntT(), "xxx", "yyy"))
  implicit val genpred = Arbitrary(PredicateGens.genPredicateAny("xxx", "yyy"))

  property("simple eval") = forAll {(x: Short) =>
    import Op._
    implicit def litint(i: Int) = OpLiteral(IntExpr(false, i))
    (x > 0) ==>
      (Sub(FloorDiv(Mul(Add(Mul(ColumnValue("eee", IntT()), 2), 10), 10), 2),
           100).eval(Map("eee" -> IntExpr(false, x)))
       ?= IntExpr(false, (((x:Int) - 5) * 10)))
  }

  property("replacement-style eval") = forAll {(x: Short) =>
    import Op._
    implicit def litint(i: Int) = OpLiteral(IntExpr(false, i))
    (x > 0) ==>
      (Sub(FloorDiv(Mul(Add(Mul(ColumnValue("eee", IntT()), 2), 10), 10), 2),
           100).postReplace[Id]{case ColumnValue("eee", _) => OpLiteral(IntExpr(false, x))
                                case x => x}.eval(Map())
       ?= IntExpr(false, (((x:Int) - 5) * 10)))
  }

  property("finds columns") = exists {(op: Op) =>
    Set("xxx", "yyy") ?= op.columnReferences
  }

  property("finds only true columns") = forAll {(op: Op) =>
    op.columnReferences subsetOf Set("xxx", "yyy")
  }

  property("op replace reflexivity") = forAll {(op: Op) =>
    op ?= op.postReplace[Id](identity)
  }

  property("op replace reflexivity in predicate") = forAll {(p: Predicate) =>
    p ?= p.postReplaceOp[Id](identity)
  }

  property("predicate eval") = forAll {(x: Short) =>
    import Predicate._
    import Op._
    implicit def litint(i: Int) = OpLiteral(IntExpr(false, i))
    (Lt(Sub(ColumnValue("aaa", IntT()), 1), Add(ColumnValue("aaa", IntT()), 1))
     .eval(Map("aaa" -> IntExpr(false, x)))) &&
    !(Gt(Sub(ColumnValue("aaa", IntT()), 1), Add(ColumnValue("aaa", IntT()), 1))
      .eval(Map("aaa" -> IntExpr(false, x))))
  }

  property("if simplifies") = secure {
    import Predicate._
    import Op._
    val x = ColumnValue("x", IntT())
    def ie(n: Int): PrimExpr = IntExpr(false, n)
    def num(n: Int): Op = OpLiteral(ie(n))
    def eqx(n: Int) = Eq(x, num(n))
    val branches = If(Not(eqx(0)),
                      If(eqx(2), num(2),
                         If(eqx(3), num(3), FloorDiv(x, num(3)))),
                      num(0))
    ((ie(0) =? (branches eval Map("x" -> ie(0))))
     && (ie(2) =? (branches eval Map("x" -> ie(2))))
     && (ie(4) =? (branches eval Map("x" -> ie(12)))))
/* TODO SMRC XFAIL    ((num(0) =? (branches simplify Map("x" -> num(0))))
     && (num(2) =? (branches simplify Map("x" -> num(2))))
     && (num(4) =? (branches simplify Map("x" -> num(12))))) */
  }

  property("primt name round-trip") = {
    implicit val nonNullable =
      Arbitrary(RelationGens.simplePrimT map {case PrimT.StringT(_, _) => PrimT.StringT(0)
                                              case x => x})
    forAll {(ty: PrimT) =>
      PrimT.withName(ty.name) ?= ty
    }
  }
}

object TestErmineRelations extends Properties("Ermine relations") {
  import com.clarifi.reporting.ermine._
  import Type.{ int, subType, conMap, typeVars, True }
  import session.{ Lib, Session, SessionEnv }
  import session.Session.{all => _, eval => _, _}
  import syntax.Single

  val ermineFixture = ErmineFixture()
  import ermineFixture._

  def fumports(mod: String, names: String*): (String, ImportSpec) =
    (mod, (None, names map {n => Single(Global(mod, n), false)} toList, true))

  property("combine") = secure {
    val defns = """field x: Int
                  |field y: Int
                  |field z: Int
                  |field w: Int
                  |x2 = let qqq = x in qqq
                  |int4 = prim 4
                  |long4 = prim 4L
                  |myrel = relation [{y = 2, z = 3}]""".stripMargin
    val imps = Map("Field" -> all, fumports("Relation.Op", "col", "prim", "combine"),
                   "Relation" -> all,
                   "List" -> all, "Builtin" -> all, "Prim" -> all,
                   "Test" -> all)
    typeChecks(defns, "42", imps) &&
    typeChecks(defns, "myrel", imps) &&
    typeChecks(defns, "combine int4 x", imps) &&
    no(typeChecks(defns, "combine long4 x", imps)) &&
    typeChecks(defns, "combine int4 x myrel", imps) &&
    typeChecks(defns, "combine (col y) x myrel", imps) &&
    no(typeChecks(defns, "combine (col x) x", imps)) &&
    no(typeChecks(defns, "combine (col w) x myrel", imps)) &&
    no(typeChecks(defns, "combine (col x) w myrel", imps)) &&
    no(typeChecks(defns, "combine int4 y myrel", imps)) &&
    typeChecks(defns, "[x, x2]", imps) &&
    typeChecks(defns, """[relation [{x = 1, y = 2, z = 3}], combine int4 x2 myrel]""", imps) &&
    unexceptional { defAndEval(defns, "combine int4 x myrel", imps).extract[Any]; true }
  }

  property("newer combines") = secure {
    eval("testMain", Map("Relation.OpTest" -> all)) ?= True
  }

  property("op coercion") = secure {
    eval("primAsOps", Map("Relation.OpTest" -> all)).whnf iff {
      case Prim(xs: List[_]) if xs nonEmpty => Prop.all((xs map (_ iff {
        case _: Op => true: Prop
      })): _*)
    }
  }

  property("aggregate") = secure {
    import com.clarifi.reporting.Relation.Relation
    import RelationImpl._
    import AggFunc._
    val imps = Map(fumports("Relation.Op", "col", "prim"),
                   "Relation" -> all, "Relation.Aggregate" -> all,
                   "Relation.AggregateTest" -> all,
                   "List" -> all, "Builtin" -> all, "Prim" -> all,
                   "Test" -> all)
    (eval("testMain", Map("Relation.AggregateTest" -> all)) ?= True) &&
    no(sessionProp(implicit s =>
      typeOf("aggregate (avg (col x)) y myrel", imps))) &&
    // TODO ddoel XFAIL
    // no(sessionProp(implicit s =>
    //   typeOf("aggregate (avg (col y)) : TooWideForSumYs", imps))) &&
    no(sessionProp(implicit s => typeOf("aggregate (avg (col x)) ll", imps))) &&
    (eval("nativeCountIntoX", Map("Relation.AggregateTest" -> all)).extract[Any] match {
      case Relation(_, Aggregate(Relation(_, Literal(_)),
                                 Attribute("x", PrimT.IntT(_)),
                                 Count)) => true
      case x => false :| ("bad structure " + x)
     })
  }

  property("limit") = secure {
    import com.clarifi.reporting.Relation.Relation
    import RelationImpl._
    eval("someLimit36", Map("Relation.SortTest" -> all)).extract[Any] match {
      case Relation(_, Limit(Relation(_, Ref(xtable, _, _)),
                             Some(3), Some(6),
                             List(("x", SortOrder.Asc)))) =>
        xtable ?= RefID("xtable")
      case x => false :| "unexpected " + x.toString
    }
  }

  property("variants of relation sugar compile") = secure {
    eval("testMain", Map("Syntax.RelationTest" -> all)).whnf ?= True
  }

  property("relation sugar desugars predictably") = secure {
    import parsing.phrase
    import parsing.TermParsers.term
    val imps = Map("Syntax.RelationTest" -> all,
                   "Relation.Op" -> all, // col, prim, combine, (+)
                   "Syntax.Relation" -> all,
                   "Relation.Predicate" -> all,
                   "Function" -> all,
                   fumports("Relation", "rename"),
                   "List" -> all, "Builtin" -> all, "Prim" -> all,
                   "Test" -> all)
    val desugared = """rename x y
                     . filter (col x > prim 100)
                     . combine (col z + prim 50) x"""
    val sugary = "[| x = z + 50, x > 100, y <- x |]"
    val reloc: Relocatable[Term] = implicitly
    def tnodes(t: Term): List[Term] = {
      type Gather[A] = WriterT[Id, List[Term], A]
      Term.postReplace[Gather](t){t => writer(List(t), t)}.written
    }
    (eval("True", imps).whnf ?= True) &&
    sessionProp(implicit s =>
      (testParse(phrase(term), desugared, imps),
       testParse(phrase(term), sugary, imps)) match {
        case ((_, ds), (_, su)) =>
          (tnodes(ds).map(_.toString) ?= tnodes(su).map(_.toString))
        case (de, su) => false :| (de, su).toString
    })
  }
}*/
