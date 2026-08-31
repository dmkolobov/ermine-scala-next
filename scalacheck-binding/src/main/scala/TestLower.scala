package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.Subst.inferType
import com.clarifi.reporting.ermine.session.{ Session => S, SessionEnv }
import com.clarifi.reporting.ermine.parsing.{ phrase, ErParseState, TermParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.rename.{ Lower, ModuleScope, Reassoc, Renamer }
import com.clarifi.reporting.ermine.surface.{ SEquation, SurfaceParsers }

import org.scalacheck._
import Prop._

/** 3.4a tnodes differential (the revived TestRelations shape): the OLD
  * pipeline's desugared Term for an expression vs the NEW
  * parse->rename->reassoc->lower output, compared structurally modulo
  * variable ids and locations. */
object TestLower extends Properties("Lower 3.4a") {
  private val fx = ErmineFixture()
  import fx._
  // the fixture writes loaded modules back into its baseEnv ("kind of
  // evil"); different import families get their own fixtures so one
  // family's transitive loads cannot shadow-poison another's reloads
  private val fxAlt = ErmineFixture()
  private val fxRel = ErmineFixture()

  private val im: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
        "Function" -> all, "Maybe" -> all, "Field" -> all,
        "List" -> all, "Bool" -> all)

  /** Old side: the fused pipeline's term parse (resolution + desugar). */
  private def oldTerm(src: String, imps: Map[String, ImportSpec] = im,
                      f: ErmineFixture = fx): Term =
    f.session { implicit s =>
      f.loadModules(imps.keySet.toList)
      val ps = ErParseState.mk("<test>", src, "Test")
        .importing(s.termNames, s.cons.keySet, imps, s.termNameOrigins, s.consOrigins)
      com.clarifi.reporting.ermine.session.Session.parse(phrase(TermParsers.term), ps)._2
    }

  /** New side: surface -> rename -> reassociate -> lower. */
  private def newTerm(src: String, imps: Map[String, ImportSpec] = im,
                      f: ErmineFixture = fx): Term =
    f.session { implicit s =>
      f.loadModules(imps.keySet.toList)
      val ps = ErParseState.mk("<scope>", "", "Test")
        .importing(s.termNames, s.cons.keySet, imps, s.termNameOrigins, s.consOrigins)
      val scope = ModuleScope.Scope(ps.s.canonicalTerms, ps.s.canonicalTypes,
        ps.s.termNames, ps.s.termOrigins, ps.s.typeOrigins)
      val m = SurfaceParsers.module("t", "module T where\nw = " + src, "T")
        .getOrElse(sys.error("surface parse failed for: " + src))
      val r = Renamer.rename(m, scope)
      val (env, envDs) = Reassoc.moduleEnv(m, scope)
      val body = m.statements.collectFirst { case SEquation(_, n, _, b, _) if n.spelling == "w" => b }.get
      val (re, ds) = Reassoc.term(body, env)
      if ((envDs ++ ds).nonEmpty) sys.error("reassoc diags: " + (envDs ++ ds))
      val ctx = Lower(r, "t", s.termNames, scope)
      val out = Lower.term(re, ctx)
      val lds = ctx.diags.result()
      if (lds.nonEmpty) sys.error("lower diags: " + lds)
      out
    }

  // ---- structural equality modulo ids and locs --------------------------

  private def nameOf(v: V[Type]): Option[Name] = v.name

  private def alphaEq(a: Term, b: Term, bij: Map[Int, Int]): Option[Map[Int, Int]] = (a, b) match {
    case (Var(x), Var(y)) => varEq(x, y, bij)
    case (App(f1, a1), App(f2, a2)) => alphaEq(f1, f2, bij).flatMap(alphaEq(a1, a2, _))
    case (Lam(_, p1, b1), Lam(_, p2, b2)) => patEq(p1, p2, bij).flatMap(alphaEq(b1, b2, _))
    case (Case(_, e1, as1), Case(_, e2, as2)) if as1.size == as2.size =>
      as1.zip(as2).foldLeft(alphaEq(e1, e2, bij)) { case (acc, (x, y)) =>
        acc.flatMap(altEq(x, y, _))
      }
    case (Let(_, is1, es1, b1), Let(_, is2, es2, b2))
        if is1.size == is2.size && es1.size == es2.size =>
      val z = is1.zip(is2).foldLeft(Option(bij)) { case (acc, (x, y)) =>
        acc.flatMap(m => varEq(x.v, y.v, m).flatMap { m2 =>
          if (x.alts.size != y.alts.size) None
          else x.alts.zip(y.alts).foldLeft(Option(m2)) { case (a2, (p, q)) => a2.flatMap(altEq(p, q, _)) }
        })
      }
      z.flatMap(alphaEq(b1, b2, _))
    case (Product(_, n1), Product(_, n2)) => if (n1 == n2) Some(bij) else None
    case (EmptyRecord(_), EmptyRecord(_)) => Some(bij)
    case (Remember(_, e1), Remember(_, e2)) => alphaEq(e1, e2, bij)
    case (Hole(_), Hole(_)) => Some(bij)
    case (Sig(_, t1, _), t2) => alphaEq(t1, t2, bij)  // annotations lower at 4.1
    case (t1, Sig(_, t2, _)) => alphaEq(t1, t2, bij)
    case (l1: Lit[_], l2: Lit[_]) => if (l1.value == l2.value && l1.getClass == l2.getClass) Some(bij) else None
    case _ => None
  }

  private def varEq(x: V[Type], y: V[Type], bij: Map[Int, Int]): Option[Map[Int, Int]] =
    (nameOf(x), nameOf(y)) match {
      case (Some(g1: Global), Some(g2: Global)) => if (g1 == g2) Some(bij) else None
      case _ =>
        bij.get(x.id) match {
          case Some(m) => if (m == y.id) Some(bij) else None
          case None =>
            if (nameOf(x).map(_.string) != nameOf(y).map(_.string)) None
            else Some(bij + (x.id -> y.id))
        }
    }

  private def altEq(a: Alt, b: Alt, bij: Map[Int, Int]): Option[Map[Int, Int]] =
    if (a.patterns.size != b.patterns.size) None
    else a.patterns.zip(b.patterns).foldLeft(Option(bij)) { case (acc, (p, q)) =>
      acc.flatMap(patEq(p, q, _))
    }.flatMap(alphaEq(a.body, b.body, _))

  private def patEq(a: Pattern, b: Pattern, bij: Map[Int, Int]): Option[Map[Int, Int]] = (a, b) match {
    case (VarP(x), VarP(y)) => varEq(x.map(_ => (null: Type)), y.map(_ => (null: Type)), bij)
    case (WildcardP(_), WildcardP(_)) => Some(bij)
    case (ConP(_, c1, ps1), ConP(_, c2, ps2)) if ps1.size == ps2.size =>
      varEq(c1, c2, bij).flatMap(m =>
        ps1.zip(ps2).foldLeft(Option(m)) { case (acc, (p, q)) => acc.flatMap(patEq(p, q, _)) })
    case (ProductP(_, ps1), ProductP(_, ps2)) if ps1.size == ps2.size =>
      ps1.zip(ps2).foldLeft(Option(bij)) { case (acc, (p, q)) => acc.flatMap(patEq(p, q, _)) }
    case (StrictP(_, p1), StrictP(_, p2)) => patEq(p1, p2, bij)
    case (LazyP(_, p1), LazyP(_, p2)) => patEq(p1, p2, bij)
    case (AsP(_, v1, p1), AsP(_, v2, p2)) => patEq(v1, v2, bij).flatMap(patEq(p1, p2, _))
    case (l1: LitP[_], l2: LitP[_]) => if (l1.getClass == l2.getClass) Some(bij) else None
    case _ => None
  }

  private def diff(src: String, imps: Map[String, ImportSpec] = im,
                   f: ErmineFixture = fx): Prop = secure {
    val o = oldTerm(src, imps, f)
    val n = newTerm(src, imps, f)
    alphaEq(o, n, Map()).isDefined :| s"OLD: ${o.toString.take(300)}\nNEW: ${n.toString.take(300)}"
  }

  property("negation applies primNeg to the whole chain") = diff("(q -> -q + 1)")
  property("record literal folds Field.cons onto EmptyRecord") = diff("{af = 1, bf = 2}")
  property("list pattern folds Builtin cons onto Nil") = diff("([a, b] -> a)")
  property("case with constructor patterns") = diff("(m -> case m of\n  Just q -> q\n  Nothing -> 0)")
  property("tuples and sections are Product spines") = diff("(1, \"two\", (,))")
  property("let groups adjacent equations into one binding") = diff("let f 0 = 1; f q = q in f 2")

  // ---- 3.4b: channel-A hooks (custom bracket syntax), do-notation -------

  property("plain bracket literal folds the List hooks") = diff("[1, 2, 3]")

  property("alias-suffixed bracket literal resolves _L hooks (DateRange shape)") = {
    val aliased: Map[String, ImportSpec] =
      Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
          "Function" -> all, "List" -> ((Some("L"), List[com.clarifi.reporting.ermine.syntax.Explicit[Global]](), false)))
    diff("[1, 2]_L", aliased, fxAlt)
  }

  property("a custom hook provider serves plain brackets (Vector shape)") = {
    import com.clarifi.reporting.ermine.syntax.Single
    val hideL: List[com.clarifi.reporting.ermine.syntax.Explicit[Global]] =
      List(Single(Global("List", "empty_Bracket"), false), Single(Global("List", "cons_Bracket"), false))
    val vectorish: Map[String, ImportSpec] =
      Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
          "Function" -> all, "Vector" -> all, "List" -> ((None, hideL, false)))
    diff("[1, 2]", vectorish, fxAlt)
  }

  property("do-notation folds Syntax.Do.bind from the last statement back") =
    diff("do q <- liftDo (Just 1); liftDo (Just 2); unit q", im + ("Syntax.Do" -> all), fxAlt)

  property("pattern cons chains re-associate and lower (h :: t)") =
    diff("((h :: t) -> h)")

  // ---- 3.4c: relArrows (the hard relocation) ----------------------------

  private val relImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
        "Function" -> all, "Relation" -> all)

  property("combine arm: rebound + and prim-wrapped literal") =
    diff("(f op r -> [| f = op + 1 |] r)", relImps, fxRel)

  property("filter arm: rebound > with prim") =
    diff("(p r -> [| p > 1 |] r)", relImps, fxRel)

  property("rename arm: Relation.rename(from, to)") =
    diff("(p i r -> [| p <- i |] r)", relImps, fxRel)

  property("column set evolves left to right (col wrapping)") =
    diff("(g r -> [| f = g + 1, f > 2 |] r)", relImps, fxRel)

  property("all three arms compose via Function.(.) with not rebound") =
    diff("(f op p i r -> [| f = op, not p, i <- f |] r)", relImps, fxRel)

  // ---- 4.1a: eval-level integration — the lowered terms typecheck and
  // ---- evaluate to the same VALUES through the real inference + evaluator

  private def lowered(src: String, imps: Map[String, ImportSpec], f: ErmineFixture)
                     (implicit s: SessionEnv): Term = {
    val ps = ErParseState.mk("<scope>", "", "Test")
      .importing(s.termNames, s.cons.keySet, imps, s.termNameOrigins, s.consOrigins)
    val scope = ModuleScope.Scope(ps.s.canonicalTerms, ps.s.canonicalTypes,
      ps.s.termNames, ps.s.termOrigins, ps.s.typeOrigins)
    val m = SurfaceParsers.module("t", "module T where\nw = " + src, "T")
      .getOrElse(sys.error("surface parse failed for: " + src))
    val r = Renamer.rename(m, scope)
    val (env, envDs) = Reassoc.moduleEnv(m, scope)
    val body = m.statements.collectFirst {
      case com.clarifi.reporting.ermine.surface.SEquation(_, n, _, b, _) if n.spelling == "w" => b }.get
    val (re, ds) = Reassoc.term(body, env)
    if ((envDs ++ ds).nonEmpty) sys.error("reassoc diags: " + (envDs ++ ds))
    val ctx = Lower(r, "t", s.termNames, scope)
    val out = Lower.term(re, ctx)
    if (ctx.diags.result().nonEmpty) sys.error("lower diags: " + ctx.diags.result())
    out
  }

  private def evalDiff(src: String, imps: Map[String, ImportSpec] = im,
                       f: ErmineFixture = fx): Prop = secure {
    val oldV = f.session { implicit s =>
      f.loadModules(imps.keySet.toList)
      S.eval(src, imps)._2.nf.extract[Int]
    }
    val newV = f.session { implicit s =>
      f.loadModules(imps.keySet.toList)
      val tm = lowered(src, imps, f)
      S.subst { implicit hm => inferType(Nil, tm) }  // must typecheck
      Term.eval(tm, s.env).nf.extract[Int]
    }
    (oldV ?= newV) :| s"old=$oldV new=$newV"
  }

  property("EVAL: whole-chain negation computes the same value") =
    evalDiff("(q -> -q + 1) 5")   // -6, not -4

  property("EVAL: bracket literal through List hooks") =
    evalDiff("head [7, 8, 9]")

  property("EVAL: pattern cons chain destructures") =
    evalDiff("((h :: t) -> h) [7, 8]")

  property("EVAL: let with grouped equations") =
    evalDiff("let f 0 = 1; f q = q in f 9")

  property("EVAL: do-notation over Maybe") =
    evalDiff("orElse 0 ((do q <- liftDo (Just 20); unit (q + 1)) maybeMonad)",
             im + ("Syntax.Do" -> all), fxAlt)
}



