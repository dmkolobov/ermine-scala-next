package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Global, Type }
import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.rename.{ NewPipeline, Renamer }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv, TolerantCheck }
import com.clarifi.reporting.ermine.surface.{ SErrorStatement, SModule, SStatement,
  SDatabaseBlock, SPrivateBlock, StatementExtents }

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
final class Resident(val log: String => Unit) {

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
    * the diagnostics the tolerant read collected (5.1), the type-level
    * notes (5.4), and the types checking gave the module's own top-level
    * bindings — which is what hover reads now that the editor path runs
    * TolerantCheck instead of a real load. */
  final case class Checked(env: SessionEnv, name: String,
                           module: SModule, renamed: Renamer.Result,
                           diags: List[NewPipeline.Diag],
                           notes: List[TolerantCheck.Note],
                           types: Map[String, Type])

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
    * Since 5.4 type checking is TolerantCheck, not Session.load: the
    * healthy definitions of a broken file get checked, and independent
    * errors are all reported instead of just the first.  Death here — a
    * header that will not parse, an import that will not load —
    * propagates; Diagnostics turns it into the single diagnostic it has
    * always been.
    *
    * Since 5.3 the text comes from the OPEN BUFFER when there is one,
    * for this file and for its workspace siblings alike: a cross-file
    * check has to see a sibling's unsaved edits, or the editor reports
    * errors about text nobody is looking at. */
  def checkFile(path: java.nio.file.Path, docs: Documents): Checked = withEnv { env =>
    implicit val e: SessionEnv = env
    val dir = Option(path.getParent) map (_.toString) getOrElse "."
    e.loadFile = Session.SourceFile.inOrder(
      docs.loaderFor(dir), Session.SourceFile.filesystem(dir) _, e.loadFile)
    val file: Session.SourceFile = docs.byPath(path.toString).map(_.source) getOrElse
      Session.Filesystem(path.toString, exotic = true)
    val contents = file.contents
    val (_, mh) = Session.parse(
      ModuleParsers.moduleHeader(file.defaultModuleName),
      ErParseState.mk(file.toString, contents, file.defaultModuleName))
    // EVERY module implicitly imports ITSELF (ModuleParsers.scala:34),
    // and the resident session holds the whole Prelude/Layout closure —
    // so checking a stdlib file that is already loaded would put its own
    // globals in its own scope and draw "term definition would shadow
    // global definition" on every top-level head (329 of them on
    // Layout/Report.e).  Scrub the module out of the COPY first, the way
    // :reload's scrubber does (Session.reloadChangedModules).
    if (e.loadedModules contains mh.name) {
      def mine(g: Global) = g.module == mh.name
      e.env = e.env filter { case (v, _) => v.name match {
        case Some(g: Global) => !mine(g)
        case _               => true
      } }
      e.termNames       = e.termNames       filterNot { case (g, _) => mine(g) }
      e.termNameOrigins = e.termNameOrigins filterNot { case (g, _) => mine(g) }
      e.cons            = e.cons            filterNot { case (g, _) => mine(g) }
      e.privateCons     = e.privateCons     filterNot { case (g, _) => mine(g) }
      e.consOrigins     = e.consOrigins     filterNot { case (g, _) => mine(g) }
      e.classes         = e.classes         filterNot { case (g, _) => mine(g) }
      e.classOrigins    = e.classOrigins    filterNot { case (g, _) => mine(g) }
      e.loadedFiles     = e.loadedFiles     filterNot { case (_, n) => n == mh.name }
      e.loadedModules   = e.loadedModules - mh.name
    }

    // Session.load's own import step (Session.scala:718), hoisted so the
    // tolerant read runs between it and `make` (SourceFile.forModule is
    // private[Session]; loadModules is the same closure by module name,
    // and it is what boot already uses).
    val missing = (mh.importExports.map(_.module).toSet &~ e.loadedModules.keySet).toList
    if (missing.nonEmpty) Session.loadModules(missing.sorted)
    val tRead0 = System.nanoTime
    val r = NewPipeline.readModuleTolerant(file.toString, contents, mh)
    val tRead = System.nanoTime

    // Dep.checkNames' import-list requirements, which the editor path no
    // longer gets for free from Session.load.
    val reqs = {
      def req(g: com.clarifi.reporting.ermine.Global, what: String) =
        TolerantCheck.Note(mh.loc.report(scalaparsers.Document.text(
          s"Module '${g.module}' does not export $what '${g.string}'.")).toString,
          TolerantCheck.Error)
      val ex = mh.importExports.flatMap(_.explicits)
      ex.collect { case x if x.isType && !e.cons.contains(x.global) => req(x.global, "type") } ++
      ex.collect { case x if !x.isType && !e.termNames.contains(x.global) => req(x.global, "term") }
    }

    // --- 5.5: what an SCC's inference depends on, split in two.
    // `groups` is one top-level spelling's own source, sig and equations
    // together (the invalidation unit), with start lines in it so a
    // reused result can never carry drifted positions.  `scopeKey` is
    // everything else: imports, the scope-bearing statements, the head
    // set, and the other open buffers' versions.
    val (groups, scopeKey) = TolerantCheck.keys(
      contents, mh.name, mh.imports.toList.sortBy(_._1).toString,
      docs.otherVersions(path.toString))

    val (checked, cache) =
      TolerantCheck.checkWith(r.ps, r.module, groups, scopeKey, docs.cacheFor(path.toString))
    docs.putCache(path.toString, cache)
    val tCheck = System.nanoTime
    log(f"check: ${mh.name} read ${(tRead - tRead0) / 1e9}%.2fs, " +
        f"typecheck ${(tCheck - tRead) / 1e9}%.2fs " +
        f"(reused ${checked.reused} of ${checked.components} components)")

    // A statement the splitter could not parse defines nothing, so every
    // reference to its head word is an undefined term — one syntax error
    // would otherwise light up the whole file.  Match by spelling: it is
    // the REFERRING statements that mint those placeholder Vs.  When no
    // head word can be recovered (an error nested inside a block, which
    // the top-level extent scan does not see) suppress undefined-term
    // notes outright while syntax errors stand.
    val broken = errorStatements(r.surface.statements)
    val notes =
      if (broken.isEmpty) reqs ++ checked.notes
      else {
        val starts = broken.map(x => (x.loc.span.startLine, x.loc.span.startCol)).toSet
        val heads  = StatementExtents.scan(contents).items
          .filter(x => starts((x.startLine, x.startCol)))
          .map(_.headWord).filter(_.nonEmpty).toSet
        reqs ++ checked.notes.filterNot(n =>
          n.spelling.isDefined && (heads.isEmpty || n.spelling.exists(heads)))
      }

    Checked(e, mh.name, r.surface, r.renamed, r.diagnostics, notes, checked.types)
  }

  private def errorStatements(ss: List[SStatement]): List[SErrorStatement] = ss.flatMap {
    case x: SErrorStatement        => List(x)
    case SPrivateBlock(_, ss2)     => errorStatements(ss2)
    case SDatabaseBlock(_, _, ss2) => errorStatements(ss2)
    case _                         => Nil
  }
}
