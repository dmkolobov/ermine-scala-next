package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.rename.{ ModuleScope, Renamer }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.surface.{ SModule, SurfaceParsers }
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
    * G1Resolution differential is the spec these tables passed). */
  final case class Checked(env: SessionEnv, name: String,
                           module: SModule, renamed: Renamer.Result)

  /** Parse, rename, and typecheck one file against a fresh env copy,
    * resolving imports first against the file's own directory (workspace
    * siblings), then the resident loader (the stdlib).  Throws Death on
    * any parse or type error; the copy — and whatever the failed load
    * dragged into it — is discarded on failure (roadmap 0.3).
    *
    * The navigation tables come from the Stage-1 renamer over the
    * resolution-free surface parse, built AFTER the load so sibling
    * imports are in termNames.  The module's own globals being in scope
    * is harmless here — the renamer's top-level binder frame shadows
    * them for references, and its shadow diagnostics go unused (the
    * load already reported real errors).  That retires both the fused
    * re-parse and its self-global filter (roadmap 4.3). */
  def checkFile(path: java.nio.file.Path): Checked = withEnv { env =>
    implicit val e: SessionEnv = env
    val dir = Option(path.getParent) map (_.toString) getOrElse "."
    e.loadFile = Session.SourceFile.inOrder(Session.SourceFile.filesystem(dir) _, e.loadFile)
    val file = Session.Filesystem(path.toString, exotic = true)
    val contents = file.contents
    val (_, mh) = Session.parse(
      ModuleParsers.moduleHeader(file.defaultModuleName),
      ErParseState.mk(file.toString, contents, file.defaultModuleName))
    Session.load(file)
    val sm = SurfaceParsers.module(file.toString, contents, mh.name) match {
      case Right(m)  => m
      case Left(err) => throw Death(err.pretty)
    }
    val scope = ModuleScope.importing(mh.name, ModuleScope.Scope.empty,
      e.termNames, e.cons.keySet, mh.imports, e.termNameOrigins, e.consOrigins)
    val renamed = Renamer.rename(sm, scope)
    Checked(e, mh.name, sm, renamed)
  }
}
