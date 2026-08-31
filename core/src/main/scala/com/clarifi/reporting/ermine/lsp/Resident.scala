package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.rename.{ NewPipeline, Renamer }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.surface.SModule
import scalaparsers.{ Death, Supply }

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

  /** Everything textDocument/definition and hover need from one check:
    * the post-load env (termNames carry inferred types and true def
    * sites), the surface module, and the renamer's occurrence/binder
    * tables — REAL SPANS, resolution included (roadmap 4.3; the
    * G1Resolution differential is the spec these tables passed) — plus
    * the diagnostics the tolerant read collected and, when the read was
    * clean enough to typecheck, the type error's rendered report
    * (roadmap 5.1). */
  final case class Checked(env: SessionEnv, name: String,
                           module: SModule, renamed: Renamer.Result,
                           diags: List[NewPipeline.Diag],
                           typeError: Option[String])

  /** Check one file against a fresh env copy, resolving imports first
    * against the file's own directory (workspace siblings), then the
    * resident loader (the stdlib).  The copy — and whatever a failed
    * load dragged into it — is discarded afterwards (roadmap 0.3).
    *
    * Since 5.1 the read is the TOLERANT one: parse, rename, re-associate
    * and assemble all run and all report, so a file with several broken
    * statements gets a diagnostic for each and its healthy statements
    * still yield navigation tables.  The ordering matters and is the
    * strict reader's own: the imports go in FIRST and the module itself
    * is not loaded yet, so the read sees exactly the env Session.load's
    * reader sees (own globals absent — with them present every top-level
    * head would draw a bogus "would shadow global definition").
    *
    * Type checking is still the strict Session.load, run only when the
    * read is clean: with diagnostics outstanding it would just re-report
    * the earliest of them.  Death here — a header that will not parse,
    * an import that will not load — propagates; Diagnostics turns it
    * into the single diagnostic it has always been. */
  def checkFile(path: java.nio.file.Path): Checked = withEnv { env =>
    implicit val e: SessionEnv = env
    val dir = Option(path.getParent) map (_.toString) getOrElse "."
    e.loadFile = Session.SourceFile.inOrder(Session.SourceFile.filesystem(dir) _, e.loadFile)
    val file = Session.Filesystem(path.toString, exotic = true)
    val contents = file.contents
    val (_, mh) = Session.parse(
      ModuleParsers.moduleHeader(file.defaultModuleName),
      ErParseState.mk(file.toString, contents, file.defaultModuleName))
    // Session.load's own import step (Session.scala:718), hoisted so the
    // tolerant read runs between it and `make` (SourceFile.forModule is
    // private[Session]; loadModules is the same closure by module name,
    // and it is what boot already uses).
    val missing = (mh.importExports.map(_.module).toSet &~ e.loadedModules.keySet).toList
    if (missing.nonEmpty) Session.loadModules(missing.sorted)
    val r = NewPipeline.readModuleTolerant(file.toString, contents, mh)
    val typeError =
      if (r.diagnostics.nonEmpty) None
      else try { Session.load(file); None }
           catch { case Death(err, _) => Some(err.toString) }
    Checked(e, mh.name, r.surface, r.renamed, r.diagnostics, typeError)
  }
}
