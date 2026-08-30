package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.syntax.Module
import scalaparsers.Supply

/** The resident Ermine session (roadmap 0.2): booted once — Lib.preamble
  * plus the Prelude/Layout closure, the way ErmineFixture and Console do —
  * then copied per request so a failed load never poisons the resident env
  * (ErmineFixture's mkEnv idiom).  SessionEnv is mutable and not
  * thread-safe; everything here runs on the single dispatch loop
  * (roadmap decision 3).
  *
  * The whole session runs with useInterface off.  For checks a stale .ei
  * would let loadModule skip body inference (missed type errors) and
  * writebacks would litter the workspace; for navigation an interface-
  * loaded module's definition locations would point into .ei text instead
  * of the real source.  Cost: boot is ~13s instead of ~7s, once.
  */
final class Resident(log: String => Unit) {

  final case class Ready(env: SessionEnv, modules: Int, seconds: Double)

  implicit val supply: Supply = Supply.create

  // All Session chatter (progress bars, load timings) arrives here; it must
  // never reach stdout, the protocol channel (roadmap decision 4).  The
  // progress bar redraws with '\r' and never sends '\n', so split on both.
  implicit val printer: Printer = Printer { s =>
    s.split("[\r\n]") foreach { line =>
      val t = line.trim
      if (t.nonEmpty) log("session: " + t)
    }
  }

  private var booted = Option.empty[Ready]

  def ready: Boolean = booted.isDefined

  /** Boot if not yet booted.  Failures propagate (and leave this
    * un-booted, so a later call retries). */
  def boot(): Ready = booted getOrElse {
    log("session: booting (Lib.preamble + Prelude/Layout, interface-free)")
    val t0 = System.nanoTime
    implicit val env: SessionEnv =
      new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false))
    Lib.preamble
    val loaded = Session.loadModules(List("Prelude", "Layout"))
    val r = Ready(env, loaded.size, (System.nanoTime - t0) / 1e9)
    booted = Some(r)
    log(f"session: ready — ${r.modules} modules in ${r.seconds}%.1fs")
    r
  }

  /** Run f against a fresh copy of the resident env (booting on demand). */
  def withEnv[A](f: SessionEnv => A): A = f(boot().env.copy)

  /** Parse and typecheck one file against a fresh env copy, resolving
    * imports first against the file's own directory (workspace siblings),
    * then the resident loader (the stdlib).  Throws Death on any parse or
    * type error; the copy — and whatever the failed load dragged into it —
    * is discarded on failure (roadmap 0.3).
    *
    * On success, returns the env (its termNames now hold every global
    * relocated to its true definition site — globalTermDef's "actual
    * definition location" update) and the module AST re-parsed for
    * navigation: Session.load does not expose the Module it parsed, so
    * the body is parsed once more, the way Session.dep and ErmineFixture's
    * testParse do (roadmap 0.5).  The re-parse binds fresh ids for the
    * file's own top-level definitions; they are consistent with the
    * occurrences inside the same tree, which is all hit-testing needs. */
  def checkFile(path: java.nio.file.Path): (SessionEnv, Module) = withEnv { env =>
    implicit val e: SessionEnv = env
    val dir = Option(path.getParent) map (_.toString) getOrElse "."
    e.loadFile = Session.SourceFile.inOrder(Session.SourceFile.filesystem(dir) _, e.loadFile)
    val file = Session.Filesystem(path.toString, exotic = true)
    Session.load(file)
    val (ps, mh) = Session.parse(
      ModuleParsers.moduleHeader(file.defaultModuleName),
      ErParseState.mk(file.toString, file.contents, file.defaultModuleName))
    // Seed the re-parse the way dep's body parse saw the world: before the
    // module itself was loaded.  With its own globals in scope, every
    // definition in the file would refuse to "shadow" itself.
    val (_, m) = Session.parse(
      ModuleParsers.moduleBody(mh),
      ps.importing(
        e.termNames.filterNot { case (g, _) => g.module == mh.name },
        e.cons.keySet.filterNot(_.module == mh.name),
        mh.imports,
        e.termNameOrigins.filterNot { case (g, _) => g.module == mh.name },
        e.consOrigins.filterNot { case (g, _) => g.module == mh.name }))
    (e, m)
  }
}
