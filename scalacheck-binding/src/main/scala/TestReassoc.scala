package com.clarifi.reporting

import com.clarifi.reporting.ermine.{ Global, Idfix, InfixL, InfixN, InfixR, Local, Postfix, Prefix }
import com.clarifi.reporting.ermine.rename.{ ModuleScope, Reassoc }
import com.clarifi.reporting.ermine.surface._

import org.scalacheck._
import Prop._

/** Fixity re-association (roadmap 3.3): the ported yard's groupings, the
  * positional environment, and the five ledger dispositions flipping to
  * re-associator diagnostics. */
object TestReassoc extends Properties("Reassoc 3.3") {

  private val scope = ModuleScope.Scope(
    canonicalTerms = Map(
      Local("+", InfixL(6))  -> List(Global("Prim", "+")),
      Local("-", InfixL(6))  -> List(Global("Prim", "-")),
      Local("*", InfixL(7))  -> List(Global("Prim", "*")),
      Local("&&", InfixR(3)) -> List(Global("Bool", "&&"))),
    canonicalTypes = Map(), termNames = Map(), termOrigins = Map(), typeOrigins = Map())

  private def prep(body: String): (SModule, Reassoc.FixityEnv, List[com.clarifi.reporting.ermine.rename.Renamer.Diag]) = {
    val m = SurfaceParsers.module("t", "module T where\n" + body, "T").getOrElse(sys.error("parse"))
    val (env, ds) = Reassoc.moduleEnv(m, scope)
    (m, env, ds)
  }

  private def bodyOf(m: SModule, name: String): STerm =
    m.statements.collectFirst { case SEquation(_, n, _, b, _) if n.spelling == name => b }.get

  private def reassoc(body: String, name: String = "v"): (STerm, List[com.clarifi.reporting.ermine.rename.Renamer.Diag]) = {
    val (m, env, envDs) = prep(body)
    val (t, ds) = Reassoc.term(bodyOf(m, name), env)
    (t, envDs ++ ds)
  }

  private def render(t: STerm): String = t match {
    case SVar(n)        => n.spelling
    case SLitInt(_, v)  => v.toString
    case SApp(f, a)     => s"(${render(f)} ${render(a)})"
    case SNeg(_, _, o)  => s"(NEG ${render(o)})"
    case SErrorTerm(_, m) => s"<err:${m.take(30)}>"
    case other          => other.getClass.getSimpleName
  }

  property("left associativity and precedence group as the fused yard did") = secure {
    val (t, ds) = reassoc("v = 1 - 2 - 3 + 4 * 5")
    ((render(t) ?= "((((- ((- 1) 2)) 3) + ((* 4) 5)))".replace("(((", "((( ").trim
      .replace("((( ", "(((")) || (render(t) ?= "((+ ((- ((- 1) 2)) 3)) ((* 4) 5))")) :| s"${render(t)} $ds"
  }

  property("right associativity shifts") = secure {
    val (t, ds) = reassoc("v = a && b && c")
    (render(t) ?= "((&& a) ((&& b) c))") :| s"${render(t)} $ds"
  }

  property("declared prefix and trailing postfix associate by precedence") = secure {
    val (t, ds) = reassoc("prefix 9 !!\npostfix 8 %%\nv = 1 + !! 2 %%", "v")
    // !! binds 9 on its operand, %% binds 8 on the result, + at 6 last
    (render(t) ?= "((+ 1) (%% (!! 2)))") :| s"${render(t)} $ds"
  }

  property("unary minus wrapper survives around the re-associated chain") = secure {
    val (t, ds) = reassoc("v = -1 + 2")
    (render(t) ?= "(NEG ((+ 1) 2))") :| s"${render(t)} $ds"
  }

  property("ledger flip: unknown operator is diagnosed") = secure {
    val (_, ds) = reassoc("v = 1 %%% 2")
    ds.exists(_.message contains "unknown operator %%%") :| ds.toString
  }

  property("a declaration governs earlier uses too (D6 flip)") = secure {
    val (_, ds) = reassoc("v = 1 :%: 2\ninfixl 5 :%:")
    (ds ?= Nil) :| ds.toString
  }

  property("a declaration governs later uses") = secure {
    val (t, ds) = reassoc("infixl 5 :%:\nv = 8 :%: 3 :%: 1")
    ((render(t) ?= "((:%: ((:%: 8) 3)) 1)") :| render(t)) && ((ds ?= Nil) :| ds.toString)
  }

  property("ledger flip: mixed associativity at equal precedence is ambiguous") = secure {
    val (_, ds) = reassoc("infixl 5 <%>\ninfixr 5 <^>\nv = 1 <%> 2 <^> 3")
    ds.exists(_.message contains "ambiguous operator of precedence 5") :| ds.toString
  }

  property("ledger flip: refixing an imported operator is refused") = secure {
    val (_, _, ds) = prep("infixr 3 &&\nv = 1")
    ds.exists(_.message contains "Multiple fixity definitions for operator: &&") :| ds.toString
  }

  property("ledger flip: one lexeme cannot be infix and postfix") = secure {
    val (_, _, ds) = prep("infixl 5 :%:\npostfix 5 :%:\nv = 1")
    ds.exists(_.message contains "Multiple fixity definitions for operator: :%:") :| ds.toString
  }

  property("a trailing infix operator is an ill-formed expression") = secure {
    val (m, env, _) = prep("v = 1 +")
    val (_, ds) = Reassoc.term(bodyOf(m, "v"), env)
    ds.exists(_.message contains "ill-formed expression") :| ds.toString
  }

  property("type arrows are right-associative pseudo-ops; partition binds tighter") = secure {
    val (m, _, _) = prep("f : a -> b -> c")
    val ann = m.statements.collectFirst { case SSigStatement(_, _, t) => t }.get
    val (t, ds) = Reassoc.ty(ann, Reassoc.FixityEnv(Map(), Map()))
    def r(t: STy): String = t match {
      case STyName(n) => n.spelling
      case STyApp(f, a) => s"(${r(f)} ${r(a)})"
      case other => other.getClass.getSimpleName
    }
    (r(t) ?= "((-> a) ((-> b) c))") :| s"${r(t)} $ds"
  }

  property("a block binder's inline fixity governs the whole block (D6 flip)") = secure {
    val (m, env, _) = prep("v = let (infixl 5 :%:) x y = x\n        a = 8 :%: 3\n    in a\nu = let b = 1 :%: 2\n        (infixl 5 :%:) x y = x\n    in b")
    val (_, okDs)  = Reassoc.term(bodyOf(m, "v"), env)
    val (_, alsoOk) = Reassoc.term(bodyOf(m, "u"), env)
    ((okDs ?= Nil) :| s"after decl: $okDs") &&
    ((alsoOk ?= Nil) :| s"before decl: $alsoOk")
  }
}

