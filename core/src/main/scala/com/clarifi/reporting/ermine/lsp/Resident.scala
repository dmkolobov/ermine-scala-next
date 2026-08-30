package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import scalaparsers.Supply

/** The resident Ermine session (roadmap 0.2): booted once — Lib.preamble
  * plus the Prelude/Layout closure, the way ErmineFixture and Console do —
  * then copied per request so a failed load never poisons the resident env
  * (ErmineFixture's mkEnv idiom).  SessionEnv is mutable and not
  * thread-safe; everything here runs on the single dispatch loop
  * (roadmap decision 3).
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

  /** Boot if not yet booted; ~6-12s cold.  Failures propagate (and leave
    * this un-booted, so a later call retries). */
  def boot(): Ready = booted getOrElse {
    log("session: booting (Lib.preamble + Prelude/Layout)")
    val t0 = System.nanoTime
    implicit val env: SessionEnv = new SessionEnv(_typeCheck = Some(true))
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
    * is discarded either way (roadmap 0.3). */
  def checkFile(path: java.nio.file.Path): Unit = {
    implicit val e: SessionEnv = checkEnv()
    val dir = Option(path.getParent) map (_.toString) getOrElse "."
    e.loadFile = Session.SourceFile.inOrder(Session.SourceFile.filesystem(dir) _, e.loadFile)
    Session.load(Session.Filesystem(path.toString, exotic = true))
    ()
  }

  // A diagnostics check must never trust or produce .ei interface files:
  // with useInterface on, a Foo.ei newer than Foo.e makes loadModule skip
  // body inference entirely (errors go unreported — mtimes lie after e.g.
  // a git checkout), and writebacks litter the user's workspace.  The boot
  // env keeps interfaces for warm-start speed; checks run on a copy with
  // useInterface pinned off.  Mirrors SessionEnv.copy, which cannot
  // override the flag.
  private def checkEnv(): SessionEnv = {
    val b = boot().env
    new SessionEnv(b.env, b.termNames, b.termNameOrigins, b.cons, b.privateCons,
      b.consOrigins, b.loadFile, b.loadedFiles, b.loadedModules, b.classes,
      b.classOrigins, Some(b.typeCheck), Some(false))
  }
}
