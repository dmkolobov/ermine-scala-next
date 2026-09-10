package com.clarifi.reporting

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.rename.{ NewPipeline, Renamer }
import com.clarifi.reporting.ermine.surface.{ SClassStatement, SDatabaseBlock, SEquation,
  SPat, SPAs, SPParen, SPSig, SPVar, SPrivateBlock, SStatement, Span }
import com.clarifi.reporting.ermine.Pretty
import com.clarifi.reporting.ermine.lsp.{ Diagnostics, Documents, Json, Resident }
import com.clarifi.reporting.ermine.session.{ Printer, Session => S, SessionEnv, TolerantCheck }

import org.scalacheck._
import Prop._
import scalaparsers.{ Death, Supply }

import java.io.File

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

  /** As `check`, but asking for what only the editor path asks for
    * (6.2): the local binder types.  `check` itself must never grow
    * them — the batch entry's behaviour is frozen — which is what the
    * "the batch entry collects nothing" property pins. */
  private def checkLocals(body: String, imports: List[String] = Nil)
      : (TolerantCheck.Result, Renamer.Result) =
    fx.session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      val mods = List("Function", "List", "Primitive") ++ imports
      S.loadModules(mods)
      val src = "module TC where\nimport Function\nimport List\nimport Primitive\n" +
                imports.map("import " + _ + "\n").mkString + "\n" + body
      val (_, mh) = S.parse(ModuleParsers.moduleHeader("TC"), ErParseState.mk("TC", src, "TC"))
      val r = NewPipeline.readModuleTolerant("TC", src, mh)
      (TolerantCheck.checkWith(r.ps, r.module, Map(), "", TolerantCheck.Cache.empty,
                               wantLocals = true)._1, r.renamed)
    }

  /** A local's type AS HOVER WOULD RENDER IT, by def-site spelling —
    * `scope` and all, so these properties pin the string the editor
    * shows and not a second rendering of my own. */
  private def render(l: TolerantCheck.LocalTy): String = l.scope match {
    case Some(sc) => Pretty.prettyTypeIn(sc, l.ty).toString
    case None     => Pretty.prettyType(l.ty, -1).toString
  }

  private def localsBySpelling(r: TolerantCheck.Result, rn: Renamer.Result): Map[String, String] =
    rn.binders.values.flatMap { b =>
      r.locals.get((b.defSite.startLine, b.defSite.startCol))
        .map(l => b.spelling -> render(l))
    }.toMap

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

  // ---- 6.2: types at every binder the collection can reach -----------
  //
  // THE MECHANISM, and its limit (tracker/loopmodel/LSP3-6.2-LOCALS.md).
  // Lower gives every renamer binder ONE `V[Type]` whose type is a fresh
  // meta; a zonk of that meta after inference is the binder's type.
  // Inference constrains that meta for a BINDING HEAD (`let`, `where`,
  // top level) -- `Subst.inferImplicitBindingTypes` subsumes it against
  // the inferred type.  It does NOT for a PATTERN binder: Lower drops
  // the meta when it builds the pattern (`VarP(v.map(_ => annotOf(..)))`)
  // and `Subst.inferPatternType` mints a fresh one per occurrence into a
  // local copy of the body.  So a LAMBDA arg, a `case` binder and a `do`
  // binder are absent by MECHANISM, not by accident.
  //
  // An EQUATION's arguments are recovered anyway, without asking
  // inference again (6.2 option 4, review R-2): `b.arity` patterns, and
  // the head's own type is an arrow chain whose first `arity` domains
  // ARE those arguments.  The properties below pin both sides of the
  // remaining line, and the letters of the two hovers.

  private val kindsBody =
    "argEq a b = a && b\n" +
    "\n" +
    "letLocal x =\n" +
    "  let y = x && True\n" +
    "  in y\n" +
    "\n" +
    "whereLocal x = z\n" +
    "  where z = x || False\n" +
    "\n" +
    "caseLocal p = case p of\n" +
    "  Just q -> q\n" +
    "  Nothing -> True\n" +
    "\n" +
    "lamArg = (w -> w && True)\n" +
    "\n" +
    "signedArg = (v : Bool) -> v\n" +
    "\n" +
    "asLocal l = case l of\n" +
    "  whole@(h :: t) -> h\n" +
    "  _ -> True\n" +
    "\n" +
    "polyWhere x = idy x\n" +
    "  where idy u = u\n" +
    "\n" +
    "doLocal m ma = (do a <- liftDo ma\n" +
    "                   unit (a && True)) m\n" +
    "\n" +
    "sigWhere x = sw x\n" +
    "  where sw : Bool -> Bool\n" +
    "        sw y = y && True\n"

  private lazy val kinds: (TolerantCheck.Result, Renamer.Result) =
    checkLocals(kindsBody, List("Bool", "Syntax.Do"))

  property("6.2: every LET and WHERE binder gets a type") = {
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    (r.notes.isEmpty :| ("the fixture must be clean: " +
       r.notes.map(_.report.linesIterator.take(1).mkString).mkString(" ;; "))) &&
    ((got.get("y") ?= Some("Bool")) :| s"let binder: $got") &&
    ((got.get("z") ?= Some("Bool")) :| s"where binder: $got") &&
    ((got.get("idy") ?= Some("a -> a")) :| s"polymorphic where binder: $got") &&
    // A SIGNED `let`/`where` binding is a local ExplicitBinding after
    // `assemble`'s `lowerLet`, and shows AS DECLARED (Decision a).
    ((got.get("sw") ?= Some("Bool -> Bool")) :| s"signed where binder: $got")
  }

  property("6.2: the pattern binders the split cannot reach are absent") = {
    // A LAMBDA argument, a `case` binder, a `do` binder and a var nested
    // in a constructor pattern lower to pattern vars whose meta
    // inference never touches, and no equation head's arity reaches
    // them.  A wrong type is worse than none, so they are absent rather
    // than guessed.  If this property starts failing because they are
    // PRESENT, the collection grew a new mechanism and the report must
    // say which.
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    val absent = List("q", "w", "whole", "h", "t")
    ((absent.filter(got.contains) ?= Nil) :| s"unexpectedly present: $got") &&
    // ... and the renamer DID record them, so the absence is about the
    // collection and not about an empty binder table (anti-vacuity).
    ((rn.binders.values.count(b => b.kind == Renamer.Arg) >= 6) :|
      s"only ${rn.binders.values.count(b => b.kind == Renamer.Arg)} Arg binders") &&
    ((rn.binders.values.exists(_.kind == Renamer.CaseBound)) :| "no CaseBound binder") &&
    ((rn.binders.values.exists(_.kind == Renamer.DoBound)) :| "no DoBound binder")
  }

  property("6.2: an EQUATION's arguments get their types from the head") = {
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    ((got.get("a") ?= Some("Bool")) :| s"argEq's first argument: $got") &&
    ((got.get("b") ?= Some("Bool")) :| s"argEq's second argument: $got") &&
    // ... at every depth: a `where` equation's own arguments too
    ((got.get("u") ?= Some("a")) :| s"the where-helper's argument: $got")
  }

  property("6.2: one binding's argument letters agree with its own type") = {
    // Review R-4.  `g : forall a b. a -> b -> a` must give `x : a` and
    // `y : b`.  Two independent `prettyType` calls would say `a` and `a`
    // — the same letter for two different variables, which is worse than
    // no answer.  `Pretty.prettyTypeIn` warms the letter state up with
    // the binding's own type first.
    val (r, rn) = checkLocals("g x y = x\n")
    val got = localsBySpelling(r, rn)
    val head = r.types.get("g").map(t => Pretty.prettyType(t, -1).toString)
    ((head ?= Some("forall a b. a -> b -> a")) :| s"g's own type: $head") &&
    ((got.get("x") ?= Some("a")) :| s"g's first argument: $got") &&
    ((got.get("y") ?= Some("b")) :| s"g's second argument: $got")
  }

  property("6.2: an argument the split cannot see stays absent") = {
    // Conservative by construction: a var inside a constructor pattern
    // has a type this arithmetic does not know, a lambda's argument is
    // not an equation head's argument at all.
    val (r, rn) = checkLocals(
      "conP (Just q) = q\n" +
      "lam = (w -> w)\n", List("Bool"))
    val got = localsBySpelling(r, rn)
    ((!got.contains("q")) :| s"a var inside a ConP was guessed: $got") &&
    ((!got.contains("w")) :| s"a lambda argument was guessed: $got")
  }

  property("6.2: an explicit local signature shows as declared") = {
    // `(v : Bool) -> v`: Lower puts the DECLARED type in the pattern
    // var's annot, so this one needs no inference at all — Decision (a).
    val (r, rn) = kinds
    val got = localsBySpelling(r, rn)
    (got.get("v") ?= Some("Bool")) :| s"signed lambda parameter: $got"
  }

  property("6.2: a component that died contributes no locals") = {
    val (r, rn) = checkLocals(
      "broken = (let bad = 1 True in bad)\n" +
      "healthy = (let good = 2 in good)\n")
    val got = localsBySpelling(r, rn)
    ((errors(r).size == 1) :| errors(r).map(_.report.linesIterator.take(1).mkString).toString) &&
    ((!got.contains("bad")) :| s"a dead component's local was published: $got") &&
    ((got.get("good") ?= Some("Int")) :| s"the healthy component's local: $got")
  }

  property("6.2: the batch entry collects nothing new") = {
    // BATCH FROZEN: `check` is what everything but the editor calls, and
    // `wantLocals` defaults to false there.
    val r = check("letLocal x =\n  let y = x\n  in y\n")
    (r.locals.isEmpty :| s"check() collected ${r.locals.size} locals")
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
      // 6.2 asks the reuse question of the locals too, so the reuse
      // properties below must run the path that carries them.
      TolerantCheck.checkWith(r.ps, r.module, groups, scopeKey, cache, wantLocals = true)
    }

  private def rendered(r: TolerantCheck.Result): Map[String, String] =
    r.types.map { case (k, t) => k -> Pretty.prettyType(t, -1).toString }

  /** 6.2, Decision (b): a reused entry carries its component's locals,
    * POSITIONS INCLUDED — so warm and cold must agree on the def-site
    * keys, not merely on the types. */
  private def renderedLocals(r: TolerantCheck.Result): Map[(Int, Int), String] =
    r.locals.map { case (k, l) => k -> render(l) }

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
    ((renderedLocals(warm) ?= renderedLocals(cold)) :| s"$what: locals differ") &&
    (if (expectReuse) (warm.reused > 0) :| s"$what: nothing was reused (vacuous)"
     else (warm.reused == 0) :| s"$what: reused ${warm.reused}, expected a full drop")
  }

  private val base =
    // `six` carries a LOCAL, so the invisibility set is not vacuous on
    // the 6.2 half: without a let/where binder anywhere in the module
    // "warm locals == cold locals" would compare two empty maps.
    "one = 1\ntwo = one\nthree : Int\nthree = two\nfour = three\n" +
    "six = (let loc = four in loc)\n"

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

  // ---- 6.1: the editor path's POSITIONS ------------------------------
  //
  // These drive `Diagnostics.check` -- the very call `Diagnostics.run`
  // makes -- against a real `Resident`, so what they inspect is what the
  // server publishes, not a re-implementation of it.  They are in this
  // suite because they are editor-check properties; they are JVM-local
  // (no socket, no client) so a failure names the file and the message.

  /** ONE resident session for both sweeps: booting is ~13 s and warming
    * it with the stdlib is more, and `Resident.supply` is a single
    * `Supply` (documented single-threaded), so the properties below hold
    * this lock rather than running concurrently on it -- ScalaCheck runs
    * a Properties object's properties on a pool. */
  private val residentLock = new Object

  private val stdlibRoot = new File("core/src/main/resources/modules")

  private def walk(f: File): List[File] =
    if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
    else if (f.getName endsWith ".e") List(f) else Nil

  /** The 180-file rule: stdlib AND core/examples, minus the directories
    * whose contents are not good code (TestTolerantRead's `notGoodCode`,
    * same reasons: `shouldfail` must be rejected and `incomplete` does
    * not terminate). */
  private val notGoodCode = Set("shouldfail", "shouldfail-controls", "incomplete")

  private def corpusFiles: List[File] =
    (walk(stdlibRoot) ++ walk(new File("core/examples")))
      .filterNot(f => Option(f.getParentFile).exists(d => notGoodCode(d.getName)))

  /** The LSP fixtures, which are broken ON PURPOSE: the ones that make
    * the 0:0 property non-vacuous. */
  private def fixtureFiles: List[File] = walk(new File("tracker/lsp-tests"))

  private def stdlibModules: List[String] = {
    val root = stdlibRoot.getPath + File.separator
    walk(stdlibRoot).map(_.getPath.stripPrefix(root).stripSuffix(".e")
                          .replace(File.separator, ".")).sorted
  }

  private lazy val resident: Resident = {
    val r = new Resident(_ => ())
    val ready = r.boot()
    // Warm the resident env with the WHOLE stdlib.  Without it every
    // corpus file whose imports are outside the booted Prelude/Layout
    // closure re-loads them into its own throwaway copy, once per file.
    implicit val s: SessionEnv = ready.env
    implicit val su: Supply = r.supply
    implicit val con: Printer = r.printer
    try S.loadModules(stdlibModules)
    catch { case Death(_, _) =>
      stdlibModules.foreach { m => try S.loadModules(List(m)) catch { case Death(_, _) => () } } }
    r
  }

  private def diagnose(f: File, docs: Documents): List[Json] =
    Diagnostics.check(resident, docs, f.toURI.toString, f.toPath, _ => ())

  private def at(d: Json, which: String, field: String): Int =
    (d / "range" flatMap (_ / which) flatMap (_ / field) flatMap (_.int)) getOrElse -1
  private def message(d: Json): String =
    (d / "message" flatMap (_.str)) getOrElse ""
  private def severity(d: Json): Int =
    (d / "severity" flatMap (_.int)) getOrElse -1
  private def at00(d: Json): Boolean =
    at(d, "start", "line") == 0 && at(d, "start", "character") == 0 &&
    at(d, "end", "line") == 0 && at(d, "end", "character") == 0
  private def where(d: Json): String =
    "%d:%d-%d:%d".format(at(d, "start", "line"), at(d, "start", "character"),
                         at(d, "end", "line"), at(d, "end", "character"))

  property("no editor-path diagnostic lands at 0:0") = secure {
    // 6.1(c).  0:0 is line 1, column 1 -- a position the editor CAN
    // show, and therefore a position that hides a real one when it is
    // reached by giving up rather than by pointing.  No corpus file and
    // no fixture is designed to fail there, so the expected count is 0.
    residentLock.synchronized {
      val docs = new Documents
      val files = corpusFiles ++ fixtureFiles
      var seen = 0
      val bad = files.flatMap { f =>
        val ds = diagnose(f, docs)
        seen += ds.size
        ds.filter(at00).map(d =>
          f.getName + " " + where(d) + ": " + message(d).linesIterator.take(1).mkString)
      }
      ((corpusFiles.size >= 180) :| s"only ${corpusFiles.size} corpus files") &&
      ((fixtureFiles.size >= 30) :| s"only ${fixtureFiles.size} fixtures") &&
      // ANTI-VACUITY: the corpus is silent by construction (that is
      // TestTolerantRead's sweep), so all the positions this property can
      // actually inspect come from the fixtures.  If a change made the
      // editor path publish nothing at all, "no diagnostic at 0:0" would
      // pass for the worst possible reason.
      ((seen >= 40) :| s"only $seen diagnostic(s) inspected over ${files.size} files") &&
      ((bad.isEmpty) :| s"${bad.size} diagnostic(s) at 0:0: ${bad.take(6).mkString(" ;; ")}")
    }
  }

  /** The EQUATION-ARGUMENT class the split must cover completely: every
    * argument pattern of a top-level or `where` equation that is a bare
    * variable (parens and a signature do not change that; an `as`
    * pattern's OUTER var is one too).  A `let` inside an expression is
    * not walked here — the statement tree does not reach into terms — so
    * its arguments count as residual rather than as required. */
  private def eqArgSpans(ss: List[SStatement]): List[(String, Span)] = {
    def bare(p: SPat): List[(String, Span)] = p match {
      case SPVar(n)       => List(n.spelling -> n.span)
      case SPAs(_, n, _)  => List(n.spelling -> n.span)
      case SPParen(_, i)  => bare(i)
      case SPSig(_, i, _) => bare(i)
      case _              => Nil
    }
    ss.flatMap {
      case SEquation(_, _, as, _, wh) =>
        as.flatMap(bare) ++ wh.toList.flatMap(w => eqArgSpans(w.statements))
      case SPrivateBlock(_, ss2)     => eqArgSpans(ss2)
      case SDatabaseBlock(_, _, ss2) => eqArgSpans(ss2)
      case x: SClassStatement        => eqArgSpans(x.body)
      case _                         => Nil
    }
  }

  property("6.2: the 253-file sweep — every reachable local binder has a type") = secure {
    // THE SWEEP.  For every clean corpus module, two classes must be
    // COMPLETE — no misses, not "few":
    //   (1) binding heads: LetBound and WhereBound;
    //   (2) equation arguments: every bare-variable argument pattern of a
    //       top-level or `where` equation (`eqArgSpans` above).
    // Everything else is the residual the item documents, and it is a
    // CLASS, not a number: a binder that lowers to a pattern var and has
    // no equation head's arity over it — a lambda argument, a `case`
    // binder, a `do` binder, a var nested in a constructor or product
    // pattern, and a `let`-in-a-term equation's arguments.  Those are
    // counted and printed.
    residentLock.synchronized {
      val docs = new Documents
      val files = corpusFiles
      var checked = 0
      val misses = scala.collection.mutable.ListBuffer.empty[String]
      val seen = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
      val hit  = scala.collection.mutable.Map.empty[String, Int].withDefaultValue(0)
      files.foreach { f =>
        val c =
          try Some(resident.checkFile(f.toPath, docs))
          catch { case Death(_, _) => None }
        c foreach { ch =>
          // Only a module the editor path checked CLEANLY can be
          // expected to have typed every binder: a component that failed
          // or went unchecked legitimately contributes none.
          if (!ch.notes.exists(_.severity == TolerantCheck.Error)) {
            checked += 1
            val required = eqArgSpans(ch.module.statements)
              .map { case (sp, s) => (s.startLine, s.startCol) }.toSet
            ch.renamed.binders.values.foreach { b =>
              val local = b.kind match {
                case Renamer.Arg | Renamer.LetBound | Renamer.WhereBound |
                     Renamer.DoBound | Renamer.CaseBound => true
                case _ => false
              }
              if (local) {
                val at = (b.defSite.startLine, b.defSite.startCol)
                val k  = if (b.kind == Renamer.Arg && required(at)) "Arg(equation)"
                         else if (b.kind == Renamer.Arg) "Arg(other)"
                         else b.kind.toString
                seen(k) = seen(k) + 1
                if (ch.locals.contains(at)) hit(k) = hit(k) + 1
                else if (b.kind == Renamer.LetBound || b.kind == Renamer.WhereBound ||
                         k == "Arg(equation)")
                  misses += "%s:%d:%d %s (%s)".format(
                    f.getName, b.defSite.startLine, b.defSite.startCol, b.spelling, k)
              }
            }
          }
        }
      }
      val summary = seen.keys.toList.sorted
        .map(k => "%s %d/%d".format(k, hit(k), seen(k))).mkString(", ")
      println("### 6.2 sweep: " + checked + " clean modules of " + files.size +
              " — " + summary + "; required-class misses " + misses.size)
      ((files.size >= 180) :| s"only ${files.size} corpus files") &&
      ((checked >= 150) :| s"only $checked modules checked cleanly") &&
      // anti-vacuity: the sweep must actually be looking at binders
      ((seen("LetBound") + seen("WhereBound") >= 200) :|
        s"only ${seen("LetBound") + seen("WhereBound")} binding-head locals seen: $summary") &&
      // and at the equation-argument class too, or an empty `eqArgSpans`
      // would pass at 0 misses covering nothing (6.2 review S-3)
      ((seen("Arg(equation)") >= 2000) :|
        s"only ${seen("Arg(equation)")} equation-argument binders seen: $summary") &&
      ((misses.isEmpty) :|
        "%d binder(s) of a REQUIRED class with no type: %s".format(
          misses.size, misses.take(10).mkString(" ;; ")))
    }
  }

  property("an import that will not load is reported on its own import statement") = secure {
    // 6.1(b).  BadImport.e imports a module that does not exist and a
    // sibling whose body has a syntax error.  Before this item the first
    // failure threw out of checkFile and became ONE diagnostic at 0:0:
    // the second import, and every healthy definition in the file, went
    // unreported.
    residentLock.synchronized {
      val docs = new Documents
      val ds = diagnose(new File("tracker" + File.separator + "lsp-tests" +
                                 File.separator + "BadImport.e"), docs)
      val missing = ds.filter(d => message(d) contains "NoSuchModule")
      val sibling = ds.filter(d => message(d) contains "BadSib")
      // two import failures AND the file's own type error: the roadmap's
      // tick condition is that the other diagnostics still publish, so it
      // is asserted positively, not as an absence (review R4).
      ((ds.size == 3) :| s"got ${ds.size}: ${ds.map(d => where(d) + " " + message(d).take(60))}") &&
      ((ds.count(d => message(d) contains "failed to unify") == 1) :|
        ds.map(message(_).take(60)).toString) &&
      ((missing.size == 1 && sibling.size == 1) :| ds.map(message(_).take(60)).toString) &&
      // the module NAME of `import NoSuchModule`, line 3, columns 8-19
      ((missing.forall(d => severity(d) == 1 && at(d, "start", "line") == 2 &&
                            at(d, "start", "character") == 7 &&
                            at(d, "end", "character") == 19)) :|
        missing.map(where).toString) &&
      // ... and of `import BadSib`, line 4, columns 8-13
      ((sibling.forall(d => severity(d) == 1 && at(d, "start", "line") == 3 &&
                            at(d, "start", "character") == 7 &&
                            at(d, "end", "character") == 13)) :|
        sibling.map(where).toString) &&
      // the loader's own report is kept: it names the sibling's file and
      // the position inside it, which is the only thing that says WHY
      ((sibling.forall(d => message(d) contains "BadSib.e:5:")) :|
        sibling.map(message).toString) &&
      // the rule (6.1(b) step 2): while an import has failed, the names
      // it would have provided are not reported as undefined terms, and
      // nothing is reported "unchecked" on their account
      ((!ds.exists(d => message(d) contains "undefined term")) :| ds.map(message).toString) &&
      ((!ds.exists(d => message(d) contains "unchecked")) :| ds.map(message).toString)
    }
  }

  property("a header that will not parse is still positioned in this file") = secure {
    // 6.1(b) step 3: the one Death that is genuinely about THIS file.
    // `fromReport` recovers its position from the report's first line;
    // the pin is that it does, and that the end is not 0:0 either.
    residentLock.synchronized {
      val docs = new Documents
      val ds = diagnose(new File("tracker" + File.separator + "lsp-tests" +
                                 File.separator + "BadHeader.e"), docs)
      ((ds.size == 1) :| ds.map(d => where(d) + " " + message(d).take(60)).toString) &&
      (ds.forall(d => at(d, "start", "line") == 0 && at(d, "start", "character") == 17 &&
                      at(d, "end", "line") == 0 && at(d, "end", "character") == 17) :|
        ds.map(where).toString) &&
      (ds.forall(d => !at00(d)) :| ds.map(where).toString)
    }
  }
}
