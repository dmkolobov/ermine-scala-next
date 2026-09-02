package com.clarifi.reporting

import com.clarifi.reporting.ermine.{ Global, Idfix, InfixR, Local }
import com.clarifi.reporting.ermine.rename.{ ModuleScope, Renamer }
import com.clarifi.reporting.ermine.rename.Renamer._
import com.clarifi.reporting.ermine.surface._

import org.scalacheck._
import Prop._

/** Renamer semantics against the pinned spec (roadmap 3.2a): resolution
  * through frames + canonical scope, id-unification, whole-block
  * scoping, do sequencing, the two owed refusals, and the LSP outputs.
  * Uses a synthetic import scope — no session boot. */
object TestRenamer extends Properties("Renamer 3.2a") {

  private val funcId    = Global("Function", "id")
  private val funcConst = Global("Function", "const")
  private val boolAnd   = Global("Bool", "&&")

  private val scope = ModuleScope.Scope(
    canonicalTerms = Map(
      Local("id", Idfix)      -> List(funcId),
      Local("id_F", Idfix)    -> List(funcId),
      Local("const", Idfix)   -> List(funcConst),
      Local("&&", InfixR(3))  -> List(boolAnd)),
    canonicalTypes = Map(),
    termNames = Map(),
    termOrigins = Map(funcId -> List(funcId), funcConst -> List(funcConst)),
    typeOrigins = Map())

  private def renamed(body: String): Renamer.Result = {
    SurfaceParsers.module("t", "module T where\n" + body, "T") match {
      case Right(m)  => Renamer.rename(m, scope)
      case Left(err) => sys.error("parse failed: " + err)
    }
  }

  private def resOf(r: Renamer.Result, spelling: String): List[Resolution] =
    r.occurrences.filter(_.spelling == spelling).map(_.resolution)

  property("sig and equations share one binder; def-site is the last equation") = secure {
    val r = renamed("f : a\nf 0 = 1\nf q = q")
    val ids = r.occurrences.filter(_.spelling == "f").collect { case Occurrence(_, _, ToBinder(i), _) => i }.distinct
    val info = r.binders(ids.head)
    val qKinds = resOf(r, "q").collect { case ToBinder(i) => r.binders(i).kind }.distinct
    ((ids.size ?= 1) :| "one binder id") &&
    ((info.defSite.startLine ?= 4) :| s"def-site last equation, got ${info.defSite}") &&
    ((qKinds ?= List(Renamer.Arg: BinderKind)) :| s"body q binds the argument, got $qKinds")
  }

  property("references: own binder beats import; import resolves with origin; unknown tolerated") = secure {
    val r = renamed("mine = 1\nuse = mine\nborrow = const\nmystery = frob")
    (resOf(r, "mine").forall(_.isInstanceOf[ToBinder]) :| "own binder") &&
    ((resOf(r, "const").head ?= ToGlobal(funcConst, funcConst, funcConst)) :| "imported") &&
    ((resOf(r, "frob").head ?= Unresolved("frob")) :| "placeholder tolerance")
  }

  property("let and where scope over every rhs and the body (heads first)") = secure {
    val r = renamed("v = let a = w\n        w = 5\n    in a\nu = q where q = w2\n            w2 = 6")
    val letW = resOf(r, "w")
    val whW2 = resOf(r, "w2")
    (letW.forall(_.isInstanceOf[ToBinder]) :| s"early sibling w binds block: $letW") &&
    (whW2.forall(_.isInstanceOf[ToBinder]) :| s"where sibling w2 binds block: $whW2")
  }

  property("a where binding shadows the equation argument for the body") = secure {
    val r = renamed("f w = w + 1 where w = 5")
    val wOccs = r.occurrences.filter(o => o.spelling == "w" && o.span.startLine == 2)
    val bodyRef = wOccs.find(o => o.span.startCol > 6 && o.span.startCol < 12).get
    val whereBinder = r.binders(bodyRef.resolution.asInstanceOf[ToBinder].id)
    (whereBinder.kind ?= WhereBound) :| s"body w resolves to the where binder, got $whereBinder"
  }

  property("do binders: rhs sees outer, later statements see the binder") = secure {
    val r = renamed("g w = do w <- liftDo (w + 1)\n         unit w")
    val occs = r.occurrences.filter(_.spelling == "w").sortBy(o => (o.span.startLine, o.span.startCol))
    // order: arg binder is not an occurrence; rhs w (line 2), final w (line 3)
    val rhsW  = occs.find(o => o.span.startLine == 2 && o.span.startCol > 20).get
    val lastW = occs.find(_.span.startLine == 3).get
    val rhsKind  = r.binders(rhsW.resolution.asInstanceOf[ToBinder].id).kind
    val lastKind = r.binders(lastW.resolution.asInstanceOf[ToBinder].id).kind
    ((rhsKind ?= (Renamer.Arg: BinderKind)) :| s"rhs sees the outer argument, got $rhsKind") &&
    ((lastKind ?= DoBound) :| s"after the bind, the do binder, got $lastKind")
  }

  property("shadowing the plain name leaves the alias resolving to the global") = secure {
    val r = renamed("f id = id_F id")
    ((resOf(r, "id_F").head ?= ToGlobal(funcId, funcId, funcId)) :| "alias untouched") &&
    (resOf(r, "id").forall(_.isInstanceOf[ToBinder]) :| "plain name captured by the binder")
  }

  property("owed refusal: a top-level binder shadowing an import is diagnosed") = secure {
    val r = renamed("id = 1")
    r.diagnostics.exists(_.message contains "would shadow global definition") :| r.diagnostics.toString
  }

  property("owed refusal: a ':'-operator binder naming a constructor is diagnosed") = secure {
    val consScope = scope.copy(canonicalTerms =
      scope.canonicalTerms + (Local("::", InfixR(5)) -> List(Global("Builtin", "::"))))
    val m = SurfaceParsers.module("t", "module T where\nv = let (::) a b = 7 in 1", "T")
      .getOrElse(sys.error("parse"))
    val r = Renamer.rename(m, consScope)
    r.diagnostics.exists(_.message contains "would shadow a data constructor") :| r.diagnostics.toString
  }

  property("operator occurrences resolve through the fixity bucket") = secure {
    val r = renamed("v = a && b\na = 1\nb = 2")
    (resOf(r, "&&").head ?= ToGlobal(boolAnd, boolAnd, boolAnd)) :| resOf(r, "&&").toString
  }

  property("scope-at-position sees block binders only inside the block") = secure {
    val r = renamed("v = let deep = 1 in deep\nafter = 2")
    val inside  = r.scopeAt(2, 22)
    val outside = r.scopeAt(3, 3)
    ((inside contains "deep") :| s"inside: $inside") &&
    ((!(outside contains "deep")) :| s"outside: $outside") &&
    ((outside contains "after") :| "top-level visible")
  }

  // ------------------------------------------------------------- 3.2b

  property("Death rendering carries file:line:col plus the caret line") = secure {
    val source = "module T where\nok = 1\nid = 2\n"
    val m = SurfaceParsers.module("t", source, "T").getOrElse(sys.error("parse"))
    try { Renamer.renameOrDie(m, scope, source); falsified :| "expected Death" }
    catch {
      case d: scalaparsers.Death =>
        val msg = d.getMessage
        ((msg.linesIterator.next() startsWith "t:3:1: error: term definition would shadow") :| msg.take(90)) &&
        ((msg.linesIterator.toList.lift(1) ?= Some("id = 2")) :| "source line for the caret") &&
        ((msg.linesIterator.toList.lift(2).exists(_.trim == "^")) :| "caret")
    }
  }

  property("class members bind like top-levels and refuse import shadowing") = secure {
    val ok = renamed("class Frob a where\n  frob q = frub q\n  frub q = q")
    val frubRes = resOf(ok, "frub").collect { case ToBinder(i) => ok.binders(i).kind }
    val shadow = renamed("class Frob a where\n  id q = q")
    ((frubRes.distinct ?= List(Renamer.TopLevel: BinderKind)) :| s"member cross-ref: $frubRes") &&
    (shadow.diagnostics.exists(_.message contains "would shadow global definition") :| shadow.diagnostics.toString)
  }

  property("foreign class names resolve at rename; failures are diagnosed") = secure {
    val good = renamed("foreign\n  data \"java.lang.String\" JStr")
    val bad  = renamed("foreign\n  data \"com.nope.Missing\" Gone")
    ((good.diagnostics ?= Nil) :| good.diagnostics.toString) &&
    (bad.diagnostics.exists(_.message contains "error loading 'com.nope.Missing'") :| bad.diagnostics.toString)
  }

  // ------------------------------------------------------------- 3.2c

  private def tyOccs(r: Renamer.Result, spelling: String) =
    r.occurrences.filter(_.spelling == spelling)

  property("sig type variables quantify per annotation, independently") = secure {
    val r = renamed("f : a -> a\ng : a -> b")
    val aIds = tyOccs(r, "a").map(_.resolution).collect { case ToBinder(i) => i }.distinct
    val kinds = aIds.map(r.binders(_).kind).distinct
    ((aIds.size ?= 2) :| s"two independent implicit binders for a, got $aIds") &&
    ((kinds ?= List(Renamer.TyImplicit: BinderKind)) :| kinds.toString) &&
    ((tyOccs(r, "a").size ?= 3) :| "three occurrences of a (2 in f, 1 in g)")
  }

  property("forall binders capture; kind braces bind kind vars") = secure {
    val r = renamed("h : forall {k} (a: k) b. a -> b")
    val aRes = tyOccs(r, "a").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    val kRes = tyOccs(r, "k").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    ((aRes ?= List(Renamer.TyParam: BinderKind)) :| s"a: $aRes") &&
    ((kRes ?= List(Renamer.KindParam: BinderKind)) :| s"k: $kRes")
  }

  property("data declaration args scope over constructor fields") = secure {
    val r = renamed("data D {k} (a: k) b = MkD a b")
    val fieldRefs = tyOccs(r, "a").map(_.resolution) ++ tyOccs(r, "b").map(_.resolution)
    fieldRefs.forall {
      case ToBinder(i) => r.binders(i).kind == Renamer.TyParam
      case _ => false
    } :| fieldRefs.toString
  }

  property("kind atoms and arrows are builtin; unknown constructors tolerated") = secure {
    val r = renamed("w : forall (m: rho -> *). Wibble m")
    val star = tyOccs(r, "*").map(_.resolution)
    val wib  = tyOccs(r, "Wibble").map(_.resolution)
    (star.forall { case ToGlobal(g, _, _) => g.module == "Builtin"; case _ => false } :| star.toString) &&
    ((wib ?= List(Unresolved("Wibble"))) :| wib.toString)
  }

  property("partition constraints share the annotation's implicit vars") = secure {
    val r = renamed("q : exists c. r <- (h, c)")
    // r and h are annotation-implicit; c is the exists binder
    val cKind = tyOccs(r, "c").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    val rKind = tyOccs(r, "r").map(_.resolution).collect { case ToBinder(i) => r.binders(i).kind }.distinct
    ((cKind ?= List(Renamer.TyParam: BinderKind)) :| s"c: $cKind") &&
    ((rKind ?= List(Renamer.TyImplicit: BinderKind)) :| s"r: $rKind")
  }
}


