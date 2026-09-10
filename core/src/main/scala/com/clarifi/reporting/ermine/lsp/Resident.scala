package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Global, Type }
import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.rename.{ ModuleScope, NewPipeline, Renamer }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv, TolerantCheck }
import com.clarifi.reporting.ermine.surface.{ SErrorStatement, SModule, SStatement,
  SDatabaseBlock, SPrivateBlock, Span, StatementExtents }

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

  /** `builtins` is the env as it stands after `Lib.preamble` and BEFORE any
    * module is read: everything Scala installs rather than source declares.
    * `checkFile` needs it to avoid scrubbing away a module's own builtins. */
  final case class Ready(env: SessionEnv, builtins: SessionEnv, modules: Int, seconds: Double)

  implicit val supply: Supply = Supply.create

  /** Set by Main so the session can tell the CLIENT what it is doing.
    * Without it the "booting" line reaches only the log file, and a
    * ~13s startup is indistinguishable from a hung server. */
  var announce: String => Unit = _ => ()

  /** Record a boot failure so it is not retried on every later check. */
  def bootFailedWith(e: Throwable): Unit = bootFailure = Some(e)

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
  private var bootFailure = Option.empty[Throwable]

  def ready: Boolean = booted.isDefined

  /** Why boot failed, if it did.  A failed boot is NOT retried on the
    * next keystroke: boot() memoizes only on success, and every check
    * goes through it, so an env that cannot load would spend ~13s
    * failing again on every didOpen and didChange — a hang that repeats
    * rather than one that ends.  The restart command spawns a fresh
    * process, which is the honest way back. */
  def failed: Option[Throwable] = bootFailure

  /** FAST MODE: skip type checking, keep everything the read gives.
    *
    * The read (parse -> rename -> re-associate -> assemble) and the type
    * check are roughly half the cost each — measured on Layout/Report.e,
    * 1757 lines: read 0.80s, typecheck 0.45s warm and 1.12s cold
    * (roadmap 5.5).  Fast mode drops the second half.
    *
    * KEPT: every syntax, shadowing, unknown-operator, interleaved-
    * equation and lowering diagnostic, plus go-to-definition and hover
    * on IMPORTED names (their types come from the resident session, not
    * from checking this file).
    * LOST: every type error, the "unchecked" notes, the import-list
    * export requirements, and hover on this module's OWN top-level
    * names — nothing computes those but the check.
    *
    * Set through `initializationOptions.fastMode` at startup or
    * `workspace/didChangeConfiguration` at any time; single-threaded
    * dispatch makes it a plain var, not a race. */
  var fastMode: Boolean = false

  /** Boot if not yet booted.  Failures propagate (and leave this
    * un-booted, so a later call retries). */
  def boot(): Ready = booted getOrElse {
    bootFailure foreach { e =>
      throw new IllegalStateException(
        "the Ermine session failed to boot and will not be retried automatically: " +
        e.getMessage, e)
    }
    log("session: booting (Lib.preamble + Prelude/Layout, interface-free)")
    announce("Ermine: loading the session (129 modules, ~13s)…")
    val t0 = System.nanoTime
    // LSP-FFI: foreign tolerance is ON here and only here.  The fork this
    // server is pointed at declares foreign bindings this JVM does not
    // have; without tolerance the first of them kills its module at load
    // and every dependent goes unchecked in the editor.  Batch loads keep
    // today's hard failure — the option is a SessionEnv field, not a
    // global (tracker/LSP-FFI-TOLERANCE.md).
    implicit val env: SessionEnv =
      new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false),
                     _foreignTolerant = Some(true))
    Lib.preamble
    val builtins = env.copy
    val loaded = Session.loadModules(List("Prelude", "Layout"))
    val r = Ready(env, builtins, loaded.size, (System.nanoTime - t0) / 1e9)
    booted = Some(r)
    bootFailure = None
    log(f"session: ready — ${r.modules} modules in ${r.seconds}%.1fs")
    r
  }

  /** Run f against a fresh copy of the resident env (booting on demand). */
  def withEnv[A](f: SessionEnv => A): A = f(boot().env.copy)

  /** The post-`Lib.preamble` env: names Scala installs, not source. */
  def builtinEnv: SessionEnv = boot().builtins

  /** The RESIDENT env itself, if the session is up -- never a copy, and
    * never a boot.  6.4's `workspace/symbol` walks it ONCE to build the
    * session's searchable name list; it cannot go stale, because the
    * session is interface-free and loads its modules exactly once
    * (Decision 5) and every check runs against a `withEnv` copy.  `None`
    * while booting, so a query during boot answers the empty list rather
    * than queueing behind a thirteen-second load. */
  def loadedEnv: Option[SessionEnv] = booted.map(_.env)

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
                           types: Map[String, Type],
                           locals: Map[(Int, Int), TolerantCheck.LocalTy],
                           // 6.3: the renamer's own import scope, so
                           // rename can ask whether a NEW name would
                           // already resolve in this file without
                           // re-running any analysis on a request path.
                           scope: ModuleScope.Scope = ModuleScope.Scope.empty,
                           // 6.3 fix round (review R2): THE TEXT THIS
                           // CHECK READ.  A span says where a name is,
                           // not how it is written -- a backtick literal
                           // (``wide``) spells `wide` and occupies eight
                           // characters -- so the index measures every
                           // name against the source it came from.  It
                           // is the same String the read already holds;
                           // `Checked` is transient (Documents stores
                           // text, version, index and cache, never a
                           // Checked), so this retains nothing new.
                           contents: String = "")

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
    val file: Session.SourceFile = docs.byPath(path.toString).map(_.source) getOrElse
      Session.Filesystem(path.toString, exotic = true)
    val contents = file.contents
    val (_, mh) = Session.parse(
      ModuleParsers.moduleHeader(file.defaultModuleName),
      ErParseState.mk(file.toString, contents, file.defaultModuleName))
    // The header is parsed BEFORE the loader is built, because the module's own
    // name determines where its siblings live.  `SourceFile.filesystem(root)`
    // appends the whole dotted path, so a module `A.B.C` at `<root>/A/B/C.e`
    // resolves `import A.B.D` against <root> -- NOT against its own directory,
    // which would look for `<root>/A/B/A/B/D.e`.  Walk up one level per extra
    // name segment.  Without this, no project with a module hierarchy can resolve
    // its own imports in the editor; the file's own directory happens to work
    // only for single-segment module names.
    val dir = Option(path.getParent) map (_.toString) getOrElse "."
    val root = {
      var d = Option(path.getParent)
      var i = mh.name.split('.').length - 1
      while (i > 0 && d.isDefined) { d = Option(d.get.getParent); i -= 1 }
      d map (_.toString) getOrElse dir
    }
    e.loadFile =
      if (root == dir)
        Session.SourceFile.inOrder(
          docs.loaderFor(dir), Session.SourceFile.filesystem(dir) _, e.loadFile)
      else
        Session.SourceFile.inOrder(
          docs.loaderFor(dir),  Session.SourceFile.filesystem(dir) _,
          docs.loaderFor(root), Session.SourceFile.filesystem(root) _, e.loadFile)
    // EVERY module implicitly imports ITSELF (ModuleParsers.scala:34),
    // and the resident session holds the whole Prelude/Layout closure —
    // so checking a stdlib file that is already loaded would put its own
    // globals in its own scope and draw "term definition would shadow
    // global definition" on every top-level head (329 of them on
    // Layout/Report.e).  Scrub the module out of the COPY first, the way
    // :reload's scrubber does (Session.reloadChangedModules).
    if (e.loadedModules contains mh.name) {
      // Scrub only what the SOURCE declares.  `Lib` installs builtins under the
      // module they belong to -- `asOp` and class `AsOp` are `Global("Relation.Op",
      // ...)`, declared in Scala and merely COMMENTED in `Relation/Op.e` -- so a
      // scrub by module name alone deletes them, and re-reading the file cannot
      // put them back.  `Session.reloadChangedModules` guards its scrub with
      // `|| builtinEnv.contains(...)` for exactly this reason; mirror it, which is
      // what the comment below always claimed this code did.
      val b = builtinEnv
      def mine(g: Global) = g.module == mh.name
      e.env = e.env filter { case (v, _) => v.name match {
        case Some(g: Global) => !mine(g) || b.env.contains(v)
        case _               => true
      } }
      e.termNames       = e.termNames       filterNot { case (g, _) => mine(g) && !b.termNames.contains(g) }
      e.termNameOrigins = e.termNameOrigins filterNot { case (g, _) => mine(g) && !b.termNameOrigins.contains(g) }
      e.cons            = e.cons            filterNot { case (g, _) => mine(g) && !b.cons.contains(g) }
      e.privateCons     = e.privateCons     filterNot { case (g, _) => mine(g) && !b.privateCons.contains(g) }
      e.consOrigins     = e.consOrigins     filterNot { case (g, _) => mine(g) && !b.consOrigins.contains(g) }
      e.classes         = e.classes         filterNot { case (g, _) => mine(g) && !b.classes.contains(g) }
      e.classOrigins    = e.classOrigins    filterNot { case (g, _) => mine(g) && !b.classOrigins.contains(g) }
      e.loadedFiles     = e.loadedFiles     filterNot { case (_, n) => n == mh.name }
      e.loadedModules   = e.loadedModules - mh.name
    }

    // Session.load's own import step (Session.scala:718), hoisted so the
    // tolerant read runs between it and `make` (SourceFile.forModule is
    // private[Session]; loadModules is the same closure by module name,
    // and it is what boot already uses).
    //
    // 6.1(b): an import that will not load used to throw out of here.
    // Diagnostics turned that Death into ONE diagnostic, and since the
    // report names the IMPORT's file (or has no position at all —
    // "Module not found") it landed at 0:0: the second broken import,
    // and every healthy definition in this file, went unreported.  So:
    // load the whole batch first (the fast path, the only one a healthy
    // file takes, and the one that keeps the loader's parallelism), and
    // only when it dies re-load ONE AT A TIME under a catcher, so each
    // failure is attributed to the import statement that named it and
    // one broken import cannot hide another.  The env is a throwaway
    // copy, so a half-loaded module poisons nothing.
    val missing = (mh.importExports.map(_.module).toSet &~ e.loadedModules.keySet).toList.sorted
    val importFailures: List[(String, String)] =
      if (missing.isEmpty) Nil
      else
        try { Session.loadModules(missing); Nil }
        catch {
          case Death(_, _) | com.clarifi.reporting.ermine.parsing.Recoverable(_) =>
            missing flatMap { m =>
              if (e.loadedModules contains m) None
              else
                try { Session.loadModules(List(m)); None }
                catch {
                  case Death(err, _) => Some(m -> err.toString)
                  case com.clarifi.reporting.ermine.parsing.Recoverable(x) =>
                    Some(m -> ("error: " + Option(x.getMessage).getOrElse(x.toString)))
                }
            }
        }
    val failedImports = importFailures.map(_._1).toSet
    val tRead0 = System.nanoTime
    val r = NewPipeline.readModuleTolerant(file.toString, contents, mh)
    val tRead = System.nanoTime

    // 6.1(b): one Error per failed import, ON the import statement that
    // named it.  The exact module-name span comes from the tolerant
    // read (`SImport.moduleSpan`, the same span go-to-definition on an
    // import uses); the header's own `Pos` — the `import` keyword — is
    // the fallback for a read that did not shape the header the same
    // way.  The loader's report is kept verbatim after the prefix: it
    // names the import's file and the position inside it, and that is
    // the only thing in the message that says WHY.
    val importNotes: List[TolerantCheck.Note] = {
      val spans = r.surface.header.imports.map(i => i.module -> i.moduleSpan).toMap
      val heads = mh.importExports.map(i => i.module -> i.loc).toMap
      val order = mh.importExports.map(_.module).zipWithIndex.toMap
      importFailures.sortBy { case (m, _) => order.getOrElse(m, Int.MaxValue) } map {
        case (m, report) =>
          val sp = spans.get(m) orElse (heads.get(m) map { p =>
            // `import`/`export` is six characters; a caret is worse than
            // a keyword, and this arm runs only when the read lost the
            // header.
            Span(p.line, p.column, p.line, p.column + 6)
          })
          TolerantCheck.Note("import " + m + " failed: " + report, TolerantCheck.Error, None, sp)
      }
    }

    // Dep.checkNames' import-list requirements, which the editor path no
    // longer gets for free from Session.load.  A module that did not load
    // exports nothing, so every name in ITS import list would draw one of
    // these — a note per name saying what the import failure already
    // said.  Skip those; the other imports' lists still get checked.
    //
    // 6.1(c): these used to render at `mh.loc`, the module header — line
    // 1, column 1, which is LSP 0:0, the position this item exists to
    // stop producing.  The name is right there in the import list and the
    // read knows its span, so squiggle THAT; the header Pos survives only
    // as the fallback for a read that did not shape the list.
    val reqs = {
      val imported = r.surface.header.imports.map(i => i.module -> i).toMap
      def spanOf(g: com.clarifi.reporting.ermine.Global, isType: Boolean): Option[Span] =
        imported.get(g.module) flatMap { i =>
          i.items.flatMap(_._2.find(x => x.isType == isType && x.name.spelling == g.string))
            .map(_.name.span) orElse Some(i.moduleSpan)
        }
      def req(g: com.clarifi.reporting.ermine.Global, what: String, isType: Boolean) = {
        val text = s"Module '${g.module}' does not export $what '${g.string}'."
        spanOf(g, isType) match {
          case Some(sp) => TolerantCheck.Note(text, TolerantCheck.Error, None, Some(sp))
          case None     => TolerantCheck.Note(
            mh.loc.report(scalaparsers.Document.text(text)).toString, TolerantCheck.Error)
        }
      }
      val ex = mh.importExports.filterNot(i => failedImports(i.module)).flatMap(_.explicits)
      ex.collect { case x if x.isType && !e.cons.contains(x.global) => req(x.global, "type", true) } ++
      ex.collect { case x if !x.isType && !e.termNames.contains(x.global) => req(x.global, "term", false) }
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
      if (fastMode) (TolerantCheck.Result(Nil, Map()), docs.cacheFor(path.toString))
      // 6.2: `wantLocals` is asked for HERE and nowhere else -- the batch
      // entry `TolerantCheck.check` keeps the default false, so the walk
      // and its zonks exist only on the editor path.  In fast mode
      // nothing checks, so `locals` is empty and hover on a local
      // answers null, exactly as it does for this module's own top
      // levels.
      else TolerantCheck.checkWith(r.ps, r.module, groups, scopeKey,
                                   docs.cacheFor(path.toString), wantLocals = true)
    // In fast mode the cache is carried forward untouched, so switching
    // back does not start cold.
    docs.putCache(path.toString, cache)
    val tCheck = System.nanoTime
    log(f"check: ${mh.name} read ${(tRead - tRead0) / 1e9}%.2fs, " +
        (if (fastMode) "typecheck SKIPPED (fast mode)"
         else f"typecheck ${(tCheck - tRead) / 1e9}%.2fs " +
              f"(reused ${checked.reused} of ${checked.components} components)"))

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

    // THE RULE (6.1(b) step 2), the same rule the broken-statement case
    // above already applies, for the same reason: while a NAME COULD NOT
    // ARRIVE, its consequences are not diagnostics.  A module that did
    // not load contributes no names, so every use of one is an
    // "undefined term" and everything downstream is "unchecked" — dozens
    // of notes, none of them actionable, burying the import failure that
    // caused them all.  So while any import failed: drop the
    // undefined-term notes (`spelling`) and the unchecked ones
    // (`dependsOnBroken`) WHOLESALE, and keep everything else — the
    // syntax diagnostics, the other imports' export requirements, and
    // the type errors of every definition that could still be checked.
    //
    // Wholesale rather than "only the names the failed import's explicit
    // list spelled": an open `import M` (the common form, and both arms
    // of the BadImport fixture) has no list to consult, so the narrow
    // rule would degenerate to no rule at all on exactly the case that
    // needs one.  The cost is a real typo going quiet until the import
    // is fixed; the import failure is the error the user must act on
    // first, and it is now the one they see.
    val published =
      if (failedImports.isEmpty) notes
      else notes.filterNot(n => n.spelling.isDefined || n.dependsOnBroken)

    // Fast mode drops what the CHECK found and keeps what the read
    // found; an import that would not load is neither — it is the same
    // failure in both modes, and silence about it in fast mode would be
    // a file full of unexplained undefined names.
    Checked(e, mh.name, r.surface, r.renamed, r.diagnostics,
            importNotes ++ (if (fastMode) Nil else published), checked.types,
            checked.locals, r.scope, contents)
  }

  private def errorStatements(ss: List[SStatement]): List[SErrorStatement] = ss.flatMap {
    case x: SErrorStatement        => List(x)
    case SPrivateBlock(_, ss2)     => errorStatements(ss2)
    case SDatabaseBlock(_, _, ss2) => errorStatements(ss2)
    case _                         => Nil
  }
}
