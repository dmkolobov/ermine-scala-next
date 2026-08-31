package com.clarifi.reporting

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.rename.NewPipeline
import com.clarifi.reporting.ermine.Pretty
import com.clarifi.reporting.ermine.session.{ Session => S, TolerantCheck }

import org.scalacheck._
import Prop._
import scalaparsers.Supply

/** Stage 2 item 5.4: the editor's type checker.
  *
  * Session.loadModule stops at the first Death, which is right for a
  * batch load and useless in an editor.  TolerantCheck reports every
  * independent problem, checks the healthy definitions of a broken
  * file, and refuses to infer anything that depends on something it
  * could not check.
  *
  * The silence-on-good-code half lives in TestTolerantRead's 180-file
  * sweep (the editor checker must find nothing the batch loader
  * accepts); these are the behaviours that need broken input.
  */
object TestTolerantCheck extends Properties("Tolerant check") {
  private val fx = ErmineFixture()

  private def header(body: String) =
    "module TC where\nimport Function\nimport List\nimport Primitive\n\n" + body

  private def check(body: String): TolerantCheck.Result =
    fx.session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      // Session.loadModules, not the fixture's: no writeback, so nothing
      // this property loads can reach another property's session.
      S.loadModules(List("Function", "List", "Primitive"))
      val src = header(body)
      val (_, mh) = S.parse(ModuleParsers.moduleHeader("TC"), ErParseState.mk("TC", src, "TC"))
      val r = NewPipeline.readModuleTolerant("TC", src, mh)
      TolerantCheck.check(r.ps, r.module)
    }

  private def errors(r: TolerantCheck.Result) = r.notes.filter(_.severity == TolerantCheck.Error)
  private def infos(r: TolerantCheck.Result)  = r.notes.filter(_.severity == TolerantCheck.Information)

  property("a module the batch loader accepts draws no notes") = {
    val r = check("v = 1\nw : Int\nw = 2\n")
    (r.notes.isEmpty :| r.notes.map(_.report).toString) &&
      (r.types.contains("v") :| s"types: ${r.types.keySet}") &&
      (r.types.contains("w") :| s"types: ${r.types.keySet}")
  }

  property("two INDEPENDENT type errors are both reported") = {
    // The whole point of the item: loadModule would report only the first.
    val r = check("a : Int\na = \"one\"\n\nb : Int\nb = \"two\"\n")
    ((errors(r).size == 2) :| errors(r).map(_.report.linesIterator.take(1).mkString).toString) &&
      (errors(r).forall(_.report contains "failed to unify") :| errors(r).map(_.report).toString)
  }

  property("an earlier component's failure leaves a later independent one alone") = {
    // With ONE shared SubstEnv the failed component's half-solved metas
    // stay bound on module-wide placeholders, and `good` gets inferred
    // against them.  A fresh SubstEnv per component is what keeps this
    // to exactly one note.
    val r = check("bad = 1 True\ngood = 2\n")
    ((errors(r).size == 1) :| errors(r).map(_.report.linesIterator.take(1).mkString).toString) &&
      (r.types.contains("good") :| s"good lost its type: ${r.types.keySet}")
  }

  property("a dependent component is unchecked, transitively") = {
    val r = check("broken = 1 True\nmid = broken\ntop = mid\n")
    ((errors(r).size == 1) :| errors(r).map(_.report).toString) &&
      ((infos(r).size == 2) :| infos(r).map(_.report.linesIterator.take(1).mkString).toString) &&
      (infos(r).forall(_.report contains "unchecked: depends on a broken definition") :|
        infos(r).map(_.report).toString) &&
      // never inferred against unconstrained metas — they would typecheck to lies
      (!r.types.contains("mid") :| "mid was given a type anyway") &&
      (!r.types.contains("top") :| "top was given a type anyway")
  }

  property("an undefined term is one note per name, carrying its spelling") = {
    // The spelling is what the editor matches against a broken
    // statement's head word to suppress the cascade (5.4).
    val r = check("v = nosuchthing\n")
    ((errors(r).size == 1) :| errors(r).map(_.report).toString) &&
      ((errors(r).head.spelling == Some("nosuchthing")) :| errors(r).head.spelling.toString) &&
      ((errors(r).head.report contains "undefined term") :| errors(r).head.report)
  }

  property("a definition mentioning an undefined term draws no SECOND note") = {
    // The undefined term IS the explanation; "unchecked" on top of it is
    // noise.  Its dependents still say so.
    val r = check("v = nosuchthing\nw = v\n")
    ((errors(r).size == 1) :| errors(r).map(_.report).toString) &&
      ((infos(r).size == 1) :| infos(r).map(_.report.linesIterator.take(1).mkString).toString)
  }

  // ---- 5.5: per-SCC reuse --------------------------------------------
  // The cache must be invisible: whatever it hands back must equal what
  // a cold check of the same text would have said.

  private def run(body: String, cache: TolerantCheck.Cache)
      : (TolerantCheck.Result, TolerantCheck.Cache) =
    fx.session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      S.loadModules(List("Function", "List", "Primitive"))
      val src = header(body)
      val (_, mh) = S.parse(ModuleParsers.moduleHeader("TC"), ErParseState.mk("TC", src, "TC"))
      val r = NewPipeline.readModuleTolerant("TC", src, mh)
      val (groups, scopeKey) =
        TolerantCheck.keys(src, mh.name, mh.imports.toList.sortBy(_._1).toString, "")
      TolerantCheck.checkWith(r.ps, r.module, groups, scopeKey, cache)
    }

  private def rendered(r: TolerantCheck.Result): Map[String, String] =
    r.types.map { case (k, t) => k -> Pretty.prettyType(t, -1).toString }

  /** Check `before`, then check `after` twice — once carrying the cache
    * `before` produced, once cold — and require the two to agree. */
  private def invisible(what: String, before: String, after: String,
                        expectReuse: Boolean = true): Prop = {
    val (_, cache) = run(before, TolerantCheck.Cache.empty)
    val (warm, _)  = run(after, cache)
    val (cold, _)  = run(after, TolerantCheck.Cache.empty)
    ((warm.notes.map(n => (n.severity, n.report)) ?= cold.notes.map(n => (n.severity, n.report)))
       :| s"$what: notes differ") &&
    ((rendered(warm) ?= rendered(cold)) :| s"$what: types differ") &&
    (if (expectReuse) (warm.reused > 0) :| s"$what: nothing was reused (vacuous)"
     else (warm.reused == 0) :| s"$what: reused ${warm.reused}, expected a full drop")
  }

  private val base =
    "one = 1\ntwo = one\nthree : Int\nthree = two\nfour = three\n"

  property("reuse is invisible: an edit inside one definition") =
    invisible("body edit", base, base.replace("two = one", "two =  one"))

  property("reuse is invisible: an edit that INTRODUCES an error") =
    invisible("break", base, base.replace("one = 1", "one = 1 True"))

  property("reuse is invisible: an edit that FIXES an error") =
    invisible("fix", base.replace("one = 1", "one = 1 True"), base)

  property("reuse is invisible: a signature edit") =
    // the sig and its equations are ONE invalidation unit
    invisible("sig edit", base, base.replace("three : Int", "three : Integer"))

  property("a new top-level definition drops the whole cache") =
    // the head set is part of the scope key
    invisible("head set", base, base + "five = four\n", expectReuse = false)

  property("a new import drops the whole cache") =
    fx.session { _ =>
      val (_, c1) = run(base, TolerantCheck.Cache.empty)
      val (warm, _) = run(base, c1.copy(scopeKey = c1.scopeKey + "!"))
      (warm.reused == 0) :| s"reused ${warm.reused} across a scope-key change"
    }

  property("a clean module reuses nearly all of its components") = {
    val (_, cache) = run(base, TolerantCheck.Cache.empty)
    val (warm, _)  = run(base, cache)
    ((warm.components >= 3) :| s"only ${warm.components} components") &&
      ((warm.reused == warm.components) :|
        s"reused ${warm.reused} of ${warm.components} on an UNCHANGED module")
  }

  property("a broken statement does not stop the healthy ones being checked") = {
    // The read drops `helper` as unparseable; `lonely` is still checked.
    val r = check("helper = = 3\nlonely : Int\nlonely = \"no\"\n")
    (errors(r).exists(_.report contains "failed to unify") :| errors(r).map(_.report).toString)
  }
}
