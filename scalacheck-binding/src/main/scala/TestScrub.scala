package com.clarifi.reporting

import com.clarifi.reporting.ermine.{ Global, Pretty }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import scalaparsers.{ Death, Supply }

import org.scalacheck._
import Prop.{ Result => _, _ }

/** WP-25 (`tracker/JSON-WIDGET-PLAYGROUND.md` §14, §13 Q20; the ticket came
  * out of ROBUST-3 in `tracker/LSP-STALENESS.md`): THE PIN for
  * `Session.scrub`.  One question, asked of an arbitrary subset:
  *
  *   **is ANY set of modules safe to unload?**
  *
  * It was not.  `scrub` filters `e.env` by each `V`'s OWN defining module
  * and every name table by the KEY's module, so a set holding a DEFINER but
  * not its RE-EXPORTERS deleted `Control.Functor.Functor` from `env` while
  * `Control.Monad.Functor`, `Control.Alt.Functor` and `Control.Ap.Functor`
  * went on naming it -- and the next read of a module whose spelling
  * collapses to the origin (`rename/ModuleScope.scala` `collapseNames`) died
  * in `Subst.assertTermClosed` with `undefined term` INSIDE A STDLIB FILE,
  * rather than with an honest "not in scope".
  *
  * WHAT THESE PROPERTIES OBSERVE, and what they deliberately do not:
  *
  *  - they observe the TABLES after a scrub -- every name->entity map in
  *    `SessionEnv`, each named in `dangling` below -- and the RELOAD of what
  *    the scrub actually unloaded;
  *  - they do NOT observe the caller-side race that found the bug (a
  *    `Session.depCache.clear()` landing mid-walk in `Runner.staleFiles`).
  *    That race is a TEST-harness matter, fixed by ROBUST-3's locks, and a
  *    green run could never prove a race fixed anyway.  These properties
  *    pin the PRODUCT invariant the race merely exposed, which is why they
  *    take an arbitrary subset instead of trying to reproduce a schedule.
  *
  * THE EFFECTIVE SET.  `scrub` may unload MORE than it is asked to (it
  * closes the set over re-exporters), so these properties never assume the
  * set they passed is the set that went: they read it back off
  * `loadedModules`, which is what a caller that must reload has to do too.
  *
  * PROCESS-GLOBAL STATE, and the locks (ROBUST-3's rule, `TestLspRobustness`
  * `:735-792`): the fixture LOADS MODULES, which fills the process-global
  * `Session.depCache`, and four suites `clear()` that cache under
  * `ErmineFixture.literalLock`.  So the boot and every property that loads
  * hold `literalLock`.  The properties that only SCRUB work on copies of
  * the booted snapshot and touch no shared state at all -- `SessionEnv`'s
  * tables are immutable maps behind `var`s, so a `copy` is independent.
  * The copies are `copyNotRegistering` so that no property here writes the
  * process-wide constructor registry (`SessionState.registerDecls`).
  */
object TestScrub extends Properties("Scrub") {

  private implicit val con: Printer = Printer.ignore
  // Supply is documented single-threaded and ScalaCheck runs properties on
  // a pool (ErmineFixture's note): one per thread.
  private val tlSupply = ThreadLocal.withInitial[Supply](() => Supply.create)
  private implicit def supply: Supply = tlSupply.get

  /** The fixture module.  Its closure is 20 files and holds the exact shape
    * the defect needs: `Maybe` reaches `Functor` by TWO import paths
    * (`Control.Monad` and `Control.Alt`, both of which `export Control.Ap`,
    * which exports `Control.Functor`), so `Maybe.e:53`'s `Functor` collapses
    * to the origin. */
  private val Root = "Layout.Doc"

  /** booted ONCE: the loaded session, its post-preamble builtins, and the
    * modules that were read.
    *
    * LOCK ORDER, and it is not decoration: sbt runs the properties of one
    * `Properties` object IN PARALLEL, so a property that takes
    * `literalLock` and THEN forces this lazy val will hold the lock while
    * waiting on the initialization latch, against the thread that won the
    * latch and is waiting for the lock inside here.  That deadlocks (it
    * did).  **Every property forces `fixture` BEFORE taking
    * `literalLock`** -- the same discipline `TestLspRobustness.renderingD`
    * uses for `bench` and `resident`. */
  private lazy val fixture: Fix = booted(List(Root))

  /** A booted session, its builtins, its modules, and ITS OWN importer graph.
    *
    * The graph is a SNAPSHOT, taken under `literalLock` at boot, and the
    * properties use it instead of calling `Session.dependentsOf`.  That
    * routine reads the PROCESS-GLOBAL `Session.depCache`, which four other
    * suites `clear()`; a clear landing between two conjuncts would make
    * `dependentsOf` answer `roots` with no edges and turn the upper-bound
    * conjunct into a flake.  Same six lines as `Session.dependentsOf`
    * (`session/Session.scala:771-783`), over a map that cannot change. */
  private case class Fix(env: SessionEnv, builtins: SessionEnv, modules: List[String],
                         imports: Map[String, Set[String]]) {
    def dependentsOf(roots: Set[String]): Set[String] = {
      var seen = roots; var frontier = roots
      while (frontier.nonEmpty) {
        val next = imports.collect { case (m, is) if !seen(m) && (is & frontier).nonEmpty => m }.toSet
        seen ++= next; frontier = next
      }
      seen
    }
  }

  private def booted(targets: List[String]): Fix =
    ErmineFixture.literalLock.synchronized {
      implicit val e: SessionEnv =
        new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false))
      Lib.preamble
      val b = e.copy
      Session.loadModules(targets)
      val imports = e.loadedFiles.toList.flatMap {
        case (sf, m) => Session.depCache.get(sf).map { case (_, d) => m -> d.imports }
      }.toMap
      Fix(e, b, e.loadedFiles.values.toList.sorted, imports)
    }

  private def base     = fixture.env
  private def builtins = fixture.builtins
  private def modules  = fixture.modules

  /** THE BIG FIXTURE -- `Prelude` + `Layout`, the set `lsp.Resident.boot`
    * loads, 130 modules.  It exists because the small one CANNOT hold the
    * defect the review found: a re-export chain three deep, where scrubbing
    * the MIDDLE module cuts a name-level edge that `reExportClosure` cannot
    * see (`Prelude.Nil#`'s entity belongs to `Native.List`, the definer, so
    * `Prelude` correctly stays loaded while `Native.Nil#` goes).  MEASURED:
    * every scrub of the `Layout.Doc` fixture leaves the walk unchanged,
    * while `{Native}` on this one moved 111 answers before the fix.
    *
    * IT COSTS ONE BOOT of about 13 s, paid once for the whole suite and
    * only by the properties below that name it. */
  private lazy val bigFixture: Fix = booted(List("Prelude", "Layout"))

  /** THE FOUR name->ENTITY maps.  `env` is keyed by the entity itself, so
    * it cannot dangle; `termNames`, `cons`, `privateCons` and `classes` are
    * keyed by a NAME and can outlive what they name -- that is the original
    * defect.
    *
    * The three `*Origins` maps are name->NAME and are NOT checked here:
    * counting entries that point at a gone name is the wrong question, and
    * asking it was the review's must-fix.  `Renamer.resolveGlobal`
    * (`rename/Renamer.scala:158-164`) resolves only a ONE-element answer, so
    * what matters is what `ModuleScope.collapseNames`' greatest-ancestor
    * WALK returns -- see `chaseChanged`, which asks that directly.  (A table
    * with zero dangling origin entries can still walk to a different answer,
    * MEASURED: deleting the entries scores 0 and the witness load still
    * dies.) */
  private def dangling(e: SessionEnv): List[(String, Int)] = {
    def liveCon(g: Global) = e.cons.contains(g) || e.privateCons.contains(g)
    List(
      "termNames->env" ->
        e.termNames.count { case (_, v) => !e.env.contains(v) },
      "cons->cons" ->
        e.cons.count { case (_, c) => !e.cons.contains(c.name) },
      "privateCons->cons" ->
        e.privateCons.count { case (_, c) => !liveCon(c.name) },
      // DEAD BY CONSTRUCTION (review N4): no source-level `instance`
      // statement exists, so `classes` is only ever written under the
      // class's own name and this can never be non-zero.  Kept so that the
      // day one appears, the pin already covers it.
      "classes->classes" ->
        e.classes.count { case (_, c) => !e.classes.contains(c.name) }
    ).filter(_._2 > 0)
  }

  /** `ModuleScope.collapseNames`' greatest-ancestor walk over an origins
    * table, memoised, with `Definitions.canonWith`'s depth cap. */
  private def ancestors(m: Map[Global, List[Global]]): Global => List[Global] = {
    val memo = scala.collection.mutable.HashMap.empty[Global, List[Global]]
    def go(g: Global, d: Int): List[Global] = memo.get(g) match {
      case Some(r) => r
      case None =>
        val up = m.getOrElse(g, List(g))
        val r  = if (d <= 0 || up == List(g)) List(g) else up.flatMap(go(_, d - 1)).distinct
        memo.put(g, r); r
    }
    go(_, 32)
  }

  /** THE INVARIANT THE REVIEW'S MUST-FIX ASKED FOR, and the one that
    * actually decides whether a module still reads: for every name that is
    * STILL IN SCOPE after the scrub, does the walk `collapseNames` performs
    * answer what it answered before?
    *
    * If it does, a spelling reaching that name by two import paths collapses
    * to the same single name it collapsed to on the whole session, and the
    * renamer resolves it.  If it does not -- because the scrub cut a
    * re-export chain in the MIDDLE and the walk now stops at a dead
    * intermediate -- the renamer gets two names, answers `Ambiguous`, and
    * the read dies with `undefined term` in a file the user never touched.
    * Returns the names whose answer moved, with the two answers. */
  private def chaseChanged(before: SessionEnv, after: SessionEnv): List[String] = {
    val bT = ancestors(before.termNameOrigins); val aT = ancestors(after.termNameOrigins)
    val bC = ancestors(before.consOrigins);     val aC = ancestors(after.consOrigins)
    def diff(ks: Iterable[Global], b: Global => List[Global], a: Global => List[Global], what: String) =
      ks.toList.flatMap { g =>
        val x = b(g).toSet; val y = a(g).toSet
        if (x == y) None
        else Some(what + g.toString + ": " + x.toList.map(_.toString).sorted.mkString(",") +
                  " -> " + y.toList.map(_.toString).sorted.mkString(","))
      }
    diff(after.termNames.keys, bT, aT, "") ++
    diff(after.cons.keys ++ after.privateCons.keys, bC, aC, "type ")
  }

  /** What THE NET (`Session.scala`'s `net`) removed: keys the module filter
    * alone would have kept but that are gone.  The product comment claims
    * this is always empty (review N2 asks for it to be pinned, not
    * asserted). */
  private def netRemoved(before: SessionEnv, after: SessionEnv, b: SessionEnv, ms: Set[String]): List[String] = {
    def survivesFilter(g: Global, inB: Boolean) = !(ms(g.module) && !inB)
    before.termNames.keys.filter(g => survivesFilter(g, b.termNames.contains(g)) && !after.termNames.contains(g)).toList.map(_.toString) ++
    before.cons.keys.filter(g => survivesFilter(g, b.cons.contains(g)) && !after.cons.contains(g)).toList.map("type " + _.toString) ++
    before.privateCons.keys.filter(g => survivesFilter(g, b.privateCons.contains(g)) && !after.privateCons.contains(g)).toList.map("private " + _.toString) ++
    before.classes.keys.filter(g => survivesFilter(g, b.classes.contains(g)) && !after.classes.contains(g)).toList.map("class " + _.toString)
  }

  private def show(v: List[(String, Int)]) = v.map { case (n, c) => n + "=" + c }.mkString(" ")

  /** One scrub of a fresh copy of the booted session: the copy, what was
    * loaded before, what ACTUALLY left `loadedModules`, and what `scrub`
    * SAID it unloaded. */
  private case class Run(e: SessionEnv, before: Set[String], gone: Set[String], said: Set[String])

  private def scrubbed(s: Set[String]): Run = scrubbedIn(base, builtins, s)

  private def scrubbedIn(from: SessionEnv, b: SessionEnv, s: Set[String]): Run = {
    val e = from.copyNotRegistering
    val before = e.loadedModules.keySet
    val said = Session.scrub(e, b, s)
    Run(e, before, before -- e.loadedModules.keySet, said)
  }

  /** Every conjunct that must hold of ANY scrub, in either fixture. */
  private def safe(f: Fix, s: Set[String], r: Run): Prop = {
    val from = f.env
    val b    = f.builtins
    val at = "scrub of {" + s.toList.sorted.mkString(",") + "} (by {" +
             r.said.toList.sorted.mkString(",") + "}) "
    val v      = dangling(r.e)
    val moved  = chaseChanged(from, r.e)
    val netted = netRemoved(from, r.e, b, r.said)
    (v.isEmpty           :| (at + "left " + show(v))) &&
    ((s subsetOf r.gone) :| (at + "did not unload " + (s -- r.gone).toList.sorted.mkString(","))) &&
    // THE CONTRACT a reloading caller depends on: what `scrub` returns is
    // the set it scrubbed BY, and intersected with what was loaded it is
    // exactly what left -- which is what `Runner.invalidate0` and
    // `Resident.reloadModules` reload
    ((r.said.intersect(r.before) == r.gone) :|
      (at + "what left loadedModules was {" + r.gone.toList.sorted.mkString(",") + "}")) &&
    // THE UPPER BOUND (review N1).  Nothing else in this suite would notice
    // a regression to the importer closure, or to "unload everything" --
    // and `reExportClosure(S) subsetOf dependentsOf(S)` is exactly what
    // makes `Resident.checkFile` safe to ignore the return value and keeps
    // `Runner.invalidate0`'s answer unchanged.
    ((r.gone subsetOf f.dependentsOf(s)) :|
      (at + "unloaded outside dependentsOf: " +
       (r.gone -- f.dependentsOf(s)).toList.sorted.mkString(","))) &&
    // THE WALK (the review's must-fix): a name still in scope must collapse
    // to what it collapsed to before
    (moved.isEmpty :| (at + "moved the greatest-ancestor walk for " + moved.size +
                       " names in scope; e.g. " + moved.take(3).mkString(" | "))) &&
    // THE NET's comment says it never removes anything (review N2)
    (netted.isEmpty :| (at + "the net removed " + netted.size + " keys; e.g. " +
                        netted.take(3).mkString(" | ")))
  }

  /** The PUBLIC SURFACE of ONE module: its exported spellings and the types
    * they print with.  `Maybe` is the module the defect killed, and the one
    * that uses re-exported names.
    *
    * RESTRICTING IT TO ONE MODULE IS LOAD-BEARING, not arbitrary.  A
    * whole-session printed-type comparison is FLAKY: two independent fresh
    * boots of `Prelude`+`Layout` in one JVM, with no scrub at all, already
    * disagree on four names -- `Prelude.joinOn`, `Prelude.lookbackJoin`,
    * `Relation.UnifyFields.joinOn`, `Relation.lookbackJoin` -- which is the
    * id-order nondeterminism behind `-Dermine.solveDet` (MEASURED by the
    * WP-25 review, `scratchpad/wp25-repro-attack2.log` `[F3]`).  A property
    * that compared everything would fail for a reason that has nothing to
    * do with `scrub`. */
  private def surface(e: SessionEnv, m: String): Map[String, String] =
    e.termNames.collect {
      case (g, v) if g.module == m => g.toString -> Pretty.prettyType(v.extract, -1).toString
    }.toMap

  // ------------------------------------------------------------------
  // 1. the invariant, over an arbitrary subset

  /** An arbitrary subset of the loaded modules.  NO SHRINKING: a shrunk
    * `Set[String]` is not a set of modules -- it would name modules that do
    * not exist, and a counterexample made of those says nothing about the
    * defect.  The label carries the real subset instead. */
  private def genSubset: Gen[Set[String]] = Gen.someOf(modules).map(_.toSet)
  private implicit val noShrinkSubset: Shrink[Set[String]] = Shrink.shrinkAny

  property("any subset is safe to unload: no name outlives what it names") =
    forAll(genSubset) { s => safe(fixture, s, scrubbed(s)) }

  /** THE UPPER BOUND, exactly (review N1): the closure is not merely inside
    * `dependentsOf`, it is these sets.  A regression that widened further
    * would still satisfy every other conjunct in this suite. */
  property("the closure of a known module is exactly its re-exporters") = {
    val expected = Map(
      "Control.Functor" -> Set("Control.Alt", "Control.Ap", "Control.Functor", "Control.Monad"),
      "Control.Ap"      -> Set("Control.Alt", "Control.Ap", "Control.Monad"),
      "Control.Monad"   -> Set("Control.Monad"),
      "Control.Alt"     -> Set("Control.Alt"),
      "Maybe"           -> Set("Maybe"))
    expected.toList.map { case (m, exp) =>
      val got = scrubbed(Set(m)).said
      (got == exp) :| ("scrub({" + m + "}) unloaded by {" + got.toList.sorted.mkString(",") +
                       "}, expected {" + exp.toList.sorted.mkString(",") + "}")
    }.reduce(_ && _)
  }

  /** The same question asked of the THIRTY subsets ROBUST-3's probe used, so
    * the answer is a seed nobody has to rerun: 16 of these 30 left a
    * dangling name on the tree before WP-25 (ROBUST-3's own narrower
    * `termNames->env` probe scored 13 of them; this counts the type side
    * too). */
  property("the thirty seeded subsets") = {
    val rnd = new scala.util.Random(20260920L)
    val subsets = (1 to 30).map { _ =>
      val k = rnd.nextInt(modules.size + 1); rnd.shuffle(modules).take(k).toSet
    }.toList
    subsets.map(s => safe(fixture, s, scrubbed(s))).reduce(_ && _)
  }

  // ------------------------------------------------------------------
  // 2. builtins are never scrubbed

  property("scrubbing every module leaves the builtins whole") = {
    val e = scrubbed(modules.toSet ++ base.loadedModules.keySet).e
    (builtins.env.keySet.subsetOf(e.env.keySet)        :| "env lost a builtin") &&
    (builtins.termNames.keySet.subsetOf(e.termNames.keySet) :| "termNames lost a builtin") &&
    (builtins.cons.keySet.subsetOf(e.cons.keySet)      :| "cons lost a builtin") &&
    (builtins.privateCons.keySet.subsetOf(e.privateCons.keySet) :| "privateCons lost a builtin") &&
    (builtins.classes.keySet.subsetOf(e.classes.keySet) :| "classes lost a builtin") &&
    (dangling(e).isEmpty                               :| ("the empty session dangles: " + show(dangling(e))))
  }

  // ------------------------------------------------------------------
  // 3. the operational half: what scrub unloaded can be loaded back

  /** Four sets, the first of which is ROBUST-3's exact reproduction --
    * the DEFINER `Control.Functor` and the USER `Maybe` without the
    * RE-EXPORTERS in between -- and on the unhardened tree it dies with
    * `Maybe.e:53:16: error: undefined term`.
    *
    * Holds `literalLock`: this one loads.  The fixture is forced FIRST,
    * outside the lock -- see its own note. */
  property("reloading what scrub unloaded restores a fresh session") = {
    val f = fixture                // forced OUTSIDE the lock, always
    val (booted, b) = (f.env, f.builtins)
    ErmineFixture.literalLock.synchronized {
      val fresh = (booted.termNames.keySet, booted.cons.keySet, surface(booted, "Maybe"))
      List(Set("Control.Functor", "Maybe"),
           Set("Control.Functor"),
           Set("Control.Ap", "Maybe"),
           Set("Maybe")).map { s =>
        val e = booted.copyNotRegistering
        val before = e.loadedModules.keySet
        Session.scrub(e, b, s)
        val gone = before -- e.loadedModules.keySet
        val died =
          try { Session.loadModules(gone.toList.sorted)(e, supply, con); None }
          catch { case Death(d, _)  => Some(d.toString)
                  case t: Throwable => Some(t.toString) }
        val at = "after scrub of {" + s.toList.sorted.mkString(",") + "} (unloaded {" +
                 gone.toList.sorted.mkString(",") + "}): "
        // the surface conjuncts only mean anything when the reload ran
        val surfaceOk: Prop =
          if (died.isDefined) Prop.passed
          else
            ((e.termNames.keySet == fresh._1)  :| (at + "the term names in scope differ from a fresh load")) &&
            ((e.cons.keySet == fresh._2)       :| (at + "the type names in scope differ from a fresh load")) &&
            ((surface(e, "Maybe") == fresh._3) :| (at + "Maybe's printed types differ from a fresh load")) &&
            (dangling(e).isEmpty               :| (at + "the reloaded session dangles: " + show(dangling(e))))
        (died.isEmpty :| (at + "the reload died: " + died.getOrElse(""))) && surfaceOk
      }.reduce(_ && _)
    }
  }

  // ------------------------------------------------------------------
  // 4. THE RESIDENT'S OWN SESSION (the review's must-fix)
  //
  // The 20-file fixture above cannot hold the defect: it has no re-export
  // chain three deep, so no scrub of it ever cuts a name-level edge that
  // `reExportClosure` cannot see.  Everything below runs on `Prelude` +
  // `Layout` -- what `lsp.Resident.boot` loads -- and pays one ~13 s boot.

  /** The review's two cases by name, plus twenty-five seeded subsets of one
    * to six modules -- the shape the reviewer swept.  On the tree before
    * this round, `{Native}` moved the walk for 111 names in scope. */
  property("the resident's own session: any subset is still safe") = {
    val big = bigFixture
    val (bigBase, bigB, bigMods) = (big.env, big.builtins, big.modules)
    val named = List(
      Set("Native"),
      Set("Field", "Long", "Native.Map", "Native.Throwable", "Relation.Row", "Runners"))
    val rnd = new scala.util.Random(20260921L)
    val seeded = (1 to 25).map { _ =>
      rnd.shuffle(bigMods).take(1 + rnd.nextInt(6)).toSet
    }.toList
    (named ++ seeded).map(t => safe(big, t, scrubbedIn(bigBase, bigB, t))).reduce(_ && _)
  }

  /** `lsp/Definitions.canonWith` (`lsp/Definitions.scala:839-853`), verbatim.
    * It is NOT the same walk as `collapseNames`': it follows only a
    * SINGLE-element origins entry and stops at a multi-element one, so it
    * answers a NAME, never a set.  `canonTerm`/`canonType` feed `gkey` ->
    * `GlobalKey` (`:858-859`), which is how definition, references and
    * RENAME bucket occurrences -- two buckets where there should be one is
    * an incomplete rename edit, a wrong edit rather than a missing answer. */
  private def canonWith(origins: Map[Global, List[Global]])(g: Global): Global = {
    var x = g; var d = 0; var going = true
    while (going && d < 32) origins.get(x) match {
      case Some(List(y)) if y != x => x = y; d += 1
      case _                       => going = false
    }
    x
  }

  /** The names whose canonical key moved, and the number of BUCKETS that
    * split -- live keys that shared a canonical key before and no longer
    * agree.  A moved key that takes its whole bucket with it is a rename
    * that still edits every occurrence; a SPLIT bucket is not. */
  private def canonDelta(before: SessionEnv, after: SessionEnv): (List[String], Int) = {
    def go(ks: Iterable[Global], bm: Map[Global, List[Global]], am: Map[Global, List[Global]], tag: String) = {
      val b = canonWith(bm) _; val a = canonWith(am) _
      val moved = ks.toList.flatMap { g =>
        val x = b(g); val y = a(g); if (x == y) None else Some(tag + g.toString) }
      val split = ks.toList.groupBy(b).count { case (_, gs) => gs.map(a).distinct.size > 1 }
      (moved, split)
    }
    val (m1, s1) = go(after.termNames.keys, before.termNameOrigins, after.termNameOrigins, "")
    val (m2, s2) = go(after.cons.keys ++ after.privateCons.keys, before.consOrigins, after.consOrigins, "type ")
    (m1 ++ m2, s1 + s2)
  }

  /** THE ONE THING THE CHAIN REPAIR CANNOT KEEP, pinned with its number.
    *
    * `reorigin` keeps `collapseNames`' walk exact, which is what decides
    * whether a module READS.  `canonWith` asks a different question -- it
    * follows single-element entries only -- so where a dead ancestor had TWO
    * greatest ancestors the repaired entry becomes two-element and that
    * chase stops one step early, at a different LIVE name.  **No repair can
    * fix that case**: the answer it used to give was the dead name itself,
    * and no live value equals a dead name.  (Where the dead ancestor had ONE
    * greatest ancestor the repair already preserves the chase -- MEASURED:
    * 16 331 of the 16 356 single-element entries are that shape.)
    *
    * So this pins the three things that CAN be pinned, each MEASURED:
    *  - an IMPORTER-CLOSED set -- every product caller with intact
    *    dependency edges -- moves NOTHING;
    *  - `checkFile`'s single-module scrub moves nothing for every module
    *    except `Native`, whose two multi-ancestor names are named here;
    *  - no shape SPLITS A BUCKET, which is the part a rename depends on. */
  property("the definition index's canonical keys survive a scrub") = {
    val big = bigFixture                     // forced OUTSIDE the lock
    def delta(t: Set[String]) = {
      val e = big.env.copyNotRegistering
      Session.scrub(e, big.builtins, t)
      canonDelta(big.env, e)
    }
    val rnd = new scala.util.Random(20260922L)
    val sample = rnd.shuffle(big.modules).take(12).filterNot(_ == "Native")
    // (1) the product shape that must be perfect
    val closed = rnd.shuffle(big.modules).take(6).map(m => big.dependentsOf(Set(m)))
    val p1 = closed.map { c =>
      val (moved, split) = delta(c)
      ((moved.isEmpty && split == 0) :|
        ("an importer-closed scrub of " + c.size + " modules moved " + moved.size +
         " canonical keys (" + moved.take(3).mkString(",") + ") and split " + split + " buckets"))
    }.reduce(_ && _)
    // (2) checkFile's shape, everywhere but the one measured exception
    val p2 = sample.map { m =>
      val (moved, split) = delta(Set(m))
      ((moved.isEmpty && split == 0) :|
        ("scrub({" + m + "}) moved " + moved.size + " canonical keys (" +
         moved.take(3).mkString(",") + ") and split " + split + " buckets"))
    }.reduce(_ && _)
    // (3) the exception, by name
    val (movedN, splitN) = delta(Set("Native"))
    val p3 =
      ((movedN.toSet == Set("Prelude.head#", "Prelude.tail#")) :|
        ("scrub({Native}) moved {" + movedN.sorted.mkString(",") +
         "}, expected exactly {Prelude.head#,Prelude.tail#} -- the two names whose " +
         "origin has TWO greatest ancestors")) &&
      ((splitN == 0) :| ("scrub({Native}) split " + splitN + " buckets"))
    p1 && p2 && p3
  }

  /** THE WITNESS, end to end, in the state `Resident.reloadModules` leaves
    * when a reload FAILS: the modules are scrubbed and NOT loaded back
    * (`pendingReload`).  A module that reaches one spelling by two import
    * paths -- `Prelude` and `Native.List` both offer `Nil#` -- must then
    * still read exactly as it reads on the whole session.
    *
    * THE CONTROL IS THE POINT.  The first conjunct asserts the witness
    * loads on the UNSCRUBBED session, because a witness that fails either
    * way proves nothing: the review's own candidate (`Relation` +
    * `Relation.Sort`, `append`) is ambiguous on a whole session and dies
    * there too, which is why it is not used here.
    *
    * Holds `literalLock` -- it loads, and a `Literal`'s dep-cache key is its
    * module NAME, shared across the process.  The fixture is forced first,
    * outside the lock. */
  property("a read after a failed reload resolves what a whole session resolves") = {
    val big = bigFixture                     // forced OUTSIDE the lock
    val (bigBase, bigB) = (big.env, big.builtins)
    val src = "module WpScrubWitness where\nimport Prelude\nimport Native.List\n\nwpScrubWitness = Nil#\n"
    def read(e: SessionEnv): Option[String] = {
      implicit val ei: SessionEnv = e
      val f = Session.Literal(src, "WpScrubWitness")
      try { Session.depCache -= f; Session.load(f); None }
      catch { case Death(d, _)  => Some(d.toString)
              case t: Throwable => Some(t.toString) }
      finally Session.depCache -= f
    }
    ErmineFixture.literalLock.synchronized {
      val control = read(bigBase.copyNotRegistering)
      val e = bigBase.copyNotRegistering
      val said = Session.scrub(e, bigB, Set("Native"))   // and reload NOTHING
      val after = read(e)
      (control.isEmpty :|
        ("the witness does not read on the unscrubbed session, so it witnesses nothing: " +
         control.getOrElse(""))) &&
      (after.isEmpty :|
        ("after scrub({Native}) -> {" + said.toList.sorted.mkString(",") +
         "} with nothing reloaded, the witness died: " + after.getOrElse("")))
    }
  }
}
