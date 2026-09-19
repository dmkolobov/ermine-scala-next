package com.clarifi.reporting.ermine.lsp

import java.nio.file.Path
import com.clarifi.reporting.ermine.rename.NewPipeline
import com.clarifi.reporting.ermine.session.Phases
import scalaparsers.Death

/** didOpen/didSave -> parse+typecheck -> publishDiagnostics (roadmap 0.3).
  *
  * Every check runs against a fresh copy of the resident env
  * (Resident.checkFile), so there is no reload or cache-invalidation
  * story: a didSave re-checks the file and its workspace imports from
  * scratch, and a failed load poisons nothing.
  *
  * Since 5.1 a check reports ALL of the read's diagnostics, each with the
  * real span the phase found it at, and the navigation index is rebuilt
  * even when the file is broken.  Only the two unrecoverable cases (a
  * header that will not parse, an import that will not load) still arrive
  * as a Death with nothing but a rendered report to go on.
  *
  * Since 5.3 checks run on the BUFFER, not the saved file.  didOpen and
  * didSave are deliberate acts and check at once; didChange is a
  * keystroke and only queues, so the check fires when the client stops
  * typing (Server.onIdle, a quiet window on the input stream — a queue
  * check on the one dispatch thread, not a race).
  *
  * Since 7.4 that window is DERIVED from what checking this document has
  * been measured to cost, instead of the fixed 300 ms 5.3 picked: see
  * `Debounce` below.
  */
object Diagnostics {

  /** 7.4: THE DEBOUNCE, as a function of the MEASURED check time.
    *
    *     D(C) = clamp(Min, Ratio * C, Max)       Min = 150, Max = 300, Ratio = 1
    *
    * where C is the MEDIAN of the last `Window` = 5 measured check times OF
    * THAT DOCUMENT (`Documents.Doc.checkMillis`), and D = Max for the
    * defensive case of a document with no history at all (see `policy`: the
    * ordinary first debounced check already has the didOpen's sample).
    *
    * WHAT THE WINDOW IS FOR, because the constants are argued from that and
    * not copied from clangd's `{50 ms, 500 ms, ratio 1}`: it coalesces a
    * burst of keystrokes into ONE check (the stream quiet for D ms), and it
    * keeps a check that costs more than the typing interval from eating the
    * one dispatch thread.
    *
    * `Min` = 150 ms.  It is bounded BELOW by the interval between
    * keystrokes: a window shorter than the gap coalesces nothing.  The
    * assumption, stated so it can be argued with: sustained prose at
    * 40-60 wpm is ~200-300 ms per character, a fast typist at ~100 wpm is
    * ~120 ms, and within-word digraphs reach 60-80 ms.  150 ms therefore
    * coalesces any burst FASTER than ~150 ms per character, and it does NOT
    * coalesce slower steady typing: at 40-60 wpm, on a file whose check is
    * at or below the floor, every character gets its own check.  That is
    * accepted, and the reason it is acceptable is that on such a file the
    * CHECK IS CHEAPER THAN THE WINDOW — a 20 ms check every 150 ms of quiet
    * is at most a ~43 % duty cycle on the dispatch thread, a request that
    * arrives waits at most one 20 ms check, and the squiggles are fresher
    * for it.  What must not happen is a check per character on an EXPENSIVE
    * file, and the clamp is what prevents that: a file whose check exceeds
    * 150 ms raises its own window to match it.  clangd's 50 ms is below
    * every one of those typing figures, and Ermine cannot afford it for a
    * second reason clangd does not have: a check here runs to completion ON
    * THE DISPATCH THREAD (Decision 3, and Stage 4 adds no thread), so every
    * check that fires is a window in which a hover waits — 1.47 s measured
    * at G3 on the largest file.  clangd's rebuild is cancellable and on a
    * worker, so it can afford to start one it will throw away.
    * (`Wire.ready` also polls at 5 ms, so anything under ~25 ms would not
    * be expressible accurately anyway.)
    *
    * `Max` = 300 ms, which is the 300 ms of record and not clangd's 500.
    * It is bounded ABOVE by the staleness a user tolerates in a squiggle,
    * and 300 ms is the ceiling 5.3 chose for exactly that reason; raising
    * it would make the MEASURED round trip on the largest stdlib file worse
    * (0.90 s -> 1.10 s) to buy pile-up protection that this server already
    * has for free.  That is the structural difference from clangd: dispatch
    * is single-threaded and the queue holds ONE entry per uri with a
    * versioned drop, so while a check runs the keystrokes behind it are not
    * even parsed, and what they leave when they are is one pending check of
    * the newest version.  Checks CANNOT pile up here, so the ceiling does
    * not have to be raised to stop them.
    *
    * `Ratio` = 1, i.e. "wait as long as the last check took".  Since the
    * versioned drop already prevents pile-up, a ratio below 1 is tempting;
    * it is rejected because with Min = 150 and Max = 300 the ratio is only
    * live in the 150-300 ms band, and a ratio below 1 would flatten that
    * band to Min and make D a two-valued step function.  Ratio 1 keeps the
    * one property worth having there: D >= C, so at most half of the
    * dispatch thread's time goes to checks while someone is typing in a
    * mid-sized file, and a request that arrives waits at most one check.
    *
    * WHAT IT DOES AT THE MEASURED CHECK TIMES (7.0's and 7.1b's tables):
    * a 44-line module checks in ~31 ms -> D = 150 (Min; it used to wait 300
    * for 31 ms of work, 90 % debounce); `Layout/Report.e` warm checks in
    * ~0.55 s -> D = 300 (Max, unchanged); cold or at its worst site
    * ~1.1-2.3 s -> D = 300 (Max, unchanged).  The policy can therefore only
    * SHORTEN a wait, never lengthen one.
    *
    * NO OSCILLATION, and the bound is the CLAMP rather than the median.  A
    * longer window coalesces more keystrokes into one check, which can make
    * that check cost more, which lengthens the window: the feedback is real
    * and it is bounded at both ends by `Min` and `Max`, the upper end being
    * exactly the window this server waited before the policy existed.  The
    * median smooths but does not bound — a document whose check cost
    * alternates between, say, 100 ms and 400 ms will alternate the window
    * between 150 and 300 ms, and that is harmless precisely because those
    * are the clamp values: the worst of it is the old constant.  Outside
    * 150-300 ms the function is FLAT, so jitter on a file whose check is
    * well above or below the band cannot move D at all.  A cold open is
    * exactly such an outlier (2.3 s on Report.e) and is FORGOTTEN: it stops
    * being the median after three warm checks and leaves the window after
    * five.
    */
  object Debounce {
    val Min    = 150
    val Max    = 300
    val Ratio  = 1.0
    val Window = 5

    /** The policy, as a pure function of one document's samples (most
      * recent first).  No history means no cost model, so the answer is
      * the conservative end of the range — the window this server waited
      * before 7.4.  That case is DEFENSIVE rather than ordinary: didOpen
      * and didSave check synchronously and pay no window at all, so by the
      * time a document's first DEBOUNCED check is owed it already has the
      * open's sample, and the empty list is reached only by a didChange on
      * a document nothing has ever checked. */
    def policy(samples: List[Long]): Int = median(samples) match {
      case None    => Max
      case Some(c) =>
        val d = math.round(Ratio * c.toDouble)
        if (d < Min) Min else if (d > Max) Max else d.toInt
    }

    /** The median of at most `Window` samples; None for none. */
    def median(samples: List[Long]): Option[Long] = {
      val xs = samples.take(Window).sorted
      if (xs.isEmpty) None
      else if (xs.length % 2 == 1) Some(xs(xs.length / 2))
      else Some((xs(xs.length / 2 - 1) + xs(xs.length / 2)) / 2)
    }

    /** A FIXED window, in ms, pinned by `initializationOptions.debounce`.
      * Its one purpose is reproducibility: `tracker/tools/perf-bench.sh` is
      * the measurement of record and pins 300 so its editor numbers stay
      * comparable with every figure the roadmap recorded while the window
      * was a constant. */
    private var pinnedMillis: Option[Int] = None
    def pinned: Option[Int] = pinnedMillis
    def pin(ms: Int): Unit  = pinnedMillis = Some(ms)
    def unpin(): Unit       = pinnedMillis = None

    /** The window to wait for a document with these samples. */
    def millis(samples: List[Long]): Int = pinnedMillis getOrElse policy(samples)
  }

  def install(server: Server, ermine: Resident, docs: Documents, log: String => Unit): Unit = {
    def uriOf(params: Json): Option[String] =
      params / "textDocument" flatMap (_ / "uri") flatMap (_.str)
    def versionOf(params: Json): Long =
      (params / "textDocument" flatMap (_ / "version") flatMap (_.int) map (_.toLong)) getOrElse 0L

    // uri -> the version whose check is owed.  One entry per uri: a
    // second keystroke replaces the first rather than queueing behind it.
    val queued = scala.collection.mutable.LinkedHashMap.empty[String, Long]

    server.onNotification("textDocument/didOpen") { params =>
      for {
        td   <- params / "textDocument"
        uri  <- td / "uri" flatMap (_.str)
        text <- td / "text" flatMap (_.str)
      } {
        docs.put(uri, text, versionOf(params))
        queued -= uri
        run(server, ermine, docs, log, "didOpen", uri)
      }
    }

    server.onNotification("textDocument/didChange") { params =>
      for {
        uri  <- uriOf(params)
        // TextDocumentSync FULL: each change carries the whole document,
        // so the last one wins outright (incremental deltas are a later
        // optimization — the capability says which we speak).
        text <- params / "contentChanges" flatMap (_.arr) flatMap
                  (_.lastOption) flatMap (_ / "text") flatMap (_.str)
      } {
        val v = versionOf(params)
        docs.put(uri, text, v)
        queued += uri -> v
      }
    }

    // A save is an act, not a keystroke: check it now, and drop whatever
    // keystroke check was owed for the same text.
    server.onNotification("textDocument/didSave") { params =>
      uriOf(params) foreach { uri =>
        queued -= uri
        run(server, ermine, docs, log, "didSave", uri)
      }
    }

    // The squiggles should not outlive the buffer.
    server.onNotification("textDocument/didClose") { params =>
      uriOf(params) foreach { uri =>
        queued -= uri
        docs drop uri
        publish(server, uri, Nil)
      }
    }

    // 7.4: the quiet window, recomputed on every loop iteration that has a
    // check owed, from the measured cost of the documents that owe one.  The
    // SHORTEST wins: the window is a per-document staleness budget, a
    // document whose check is cheap should not be made to wait behind an
    // expensive sibling, and firing early costs the expensive one nothing —
    // its check is queued either way and the work is the same work.  (In
    // practice one document is queued: you type in one buffer.)  The value
    // returned is remembered so the log line below reports the window that
    // was ACTUALLY waited rather than one recomputed after the fact.
    var waited = Debounce.Max
    def quiet(): Int = {
      val d =
        if (queued.isEmpty) Debounce.Max
        else queued.keysIterator.map(u => Debounce.millis(docs.checksFor(u))).min
      waited = d
      d
    }

    server.onIdle(quiet())(queued.nonEmpty) {
      val due = queued.toList
      queued.clear()
      due foreach { case (uri, v) =>
        // Versioned drop.  Dispatch is single-threaded, so this can only
        // fire if a newer edit was handled while an earlier check ran;
        // it is the guard that keeps that from publishing stale results.
        if (docs.get(uri).exists(_.version == v)) {
          // One line per debounced check saying what the policy decided and
          // from what, so the window is auditable from the log the way every
          // other number on this path is (perf-client.py harvests it, and
          // lsp-smoke asserts the arithmetic).
          val samples = docs.checksFor(uri)
          log("debounce: " + docs.get(uri).map(_.path.getFileName.toString).getOrElse(uri) +
              s" waited ${waited}ms (median ${Debounce.median(samples) getOrElse -1L}ms of " +
              s"${samples.size} checks, policy ${Debounce.policy(samples)}ms" +
              (Debounce.pinned map (p => s", PINNED at ${p}ms") getOrElse "") + ")")
          run(server, ermine, docs, log, "didChange", uri)
        }
        else log(s"diagnostics: dropping superseded check for $uri v$v")
      }
    }
  }

  private def run(server: Server, ermine: Resident, docs: Documents,
                  log: String => Unit, what: String, uri: String): Unit =
    docs.pathFor(uri) match {
      case None =>
        log("diagnostics: ignoring non-file uri " + uri)
      case Some(path) if !(path.toString endsWith ".e") =>
        log("diagnostics: ignoring non-.e file " + path)
      case Some(path) =>
        val t0 = System.nanoTime
        val ds = check(ermine, docs, uri, path, log)
        val t1 = System.nanoTime
        // 7.4: the measured cost of THIS check, into this document's own
        // rolling sample.  It is the figure the next keystroke's debounce is
        // derived from, and it is the same clock the line below prints.
        docs.recordCheck(uri, (t1 - t0) / 1000000L)
        log(f"diagnostics: $what ${path.getFileName} -> ${ds.size} diagnostic(s) in ${(t1 - t0) / 1e9}%.1fs")
        // 7.0: one line per check with every timed phase, to the LOG --
        // never stdout, which is the protocol channel (Decision 4).  Off
        // unless -Dermine.lsp.phases=true; `check.total` is the number the
        // phase rows must reconcile against, and the Rpc rows are the
        // didChange that triggered this check (recorded since the last
        // reset, which is the previous check's).
        if (Phases.enabled) {
          Phases.record("check.total", t1 - t0)
          log("phases: " + Phases.render)
          Phases.reset()
        }
        publish(server, uri, ds)
    }

  /** LSP-STALENESS step 2: after the resident session reloaded modules,
    * every open document is checked again and its diagnostics republished,
    * so a squiggle about a stdlib name that just changed does not outlive
    * the change.  Synchronous, on the dispatch thread, like a didSave. */
  def recheckAll(server: Server, ermine: Resident, docs: Documents, log: String => Unit): Unit =
    docs.all foreach (d => run(server, ermine, docs, log, "reload", d.uri))

  /** ONE check, as the LSP diagnostics it publishes.  Split out of `run`
    * (6.1(c)) so a property can drive the editor path in this JVM
    * instead of over a socket: `run` adds the timing line and the
    * publish, and nothing else. */
  def check(ermine: Resident, docs: Documents, uri: String, path: Path,
            log: String => Unit): List[Json] =
    try {
      val checked = ermine.checkFile(path, docs)
      // The index is rebuilt from the SAME parse that produced the
      // diagnostics, broken file or not: navigation on a file's
      // healthy statements no longer decays to the last good save.
      //
      // 6.3: the index build is on the CHECK path (every keystroke), and
      // 6.3 made it carry more, so it is timed out loud rather than
      // argued about -- the number is the item's own budget line.
      val tIdx0 = System.nanoTime
      val idx = Definitions.index(path.toString, checked)
      Phases.add("index", tIdx0)   // guarded: no clock call when the property is off
      // 6.4 folded the document-symbol tree into the same build; report
      // its share so "the symbol list did not move the check" is a
      // measured claim and not an argument.
      log(f"index: ${path.getFileName} ${idx.occs.size} occurrences, "
          + f"${Symbols.flatten(idx.symbols).size} symbols in "
          + f"${(System.nanoTime - tIdx0) / 1e6}%.1fms")
      docs.putIndex(uri, idx)
      // 7.5, ticket E8: every range this check publishes is converted
      // from parser columns to LSP characters against the text the check
      // read -- the `Lines` the index has just built, so no second scan.
      val ls = idx.lines
      val ds =
        checked.diags.map(d => (fromDiag(d, ls), None: Option[String])) :::
        checked.notes.map(n => (n.span match {
          // LSP-FFI: a tolerated foreign binding knows its class or
          // member span exactly, so it squiggles the name rather
          // than the caret `fromReport` recovers from the text.
          case Some(sp) => fromSpan(sp, n.report, n.severity, ls)
          case None     => fromReport(n.report, path, n.severity, ls)
        }, n.spelling))
      // 6.6.1: keep what went out, WITH its source.  The range stored is
      // read back off the JSON that is about to be published, so the
      // list a code action matches against and the list the editor shows
      // are the same list by construction; `spelling` is the flag
      // `TolerantCheck.Note` carries for an undefined term, which is what
      // an add-import action keys on (never the rendered message text --
      // 6.1's rule).
      stored(docs, uri, ds)
    } catch {
      // 7.5, ticket E8: this path has no index to convert against (the check
      // DIED -- a header that will not parse, an import that will not load),
      // so the line model is built from the buffer itself.  It is the one
      // place in the server that pays a scan for the conversion, it happens
      // at most once per failed check, and the alternative is the only
      // remaining `column - 1` on a path that can report a tabbed line.
      case Death(err, _) =>
        val ls = docs.get(uri).map(d => new Definitions.Lines(d.text))
        stored(docs, uri, List((fromReport(err.toString, path, 1, ls), None)))
      // `Recoverable`, not `NonFatal` (LSP-FFI review finding P-1):
      // NonFatal counts every LinkageError as fatal, so a reflective
      // lookup over a stale classpath used to unwind past here into
      // Rpc's notification guard and the file got NO diagnostics at
      // all — stale squiggles and a stack trace in the log.  This is
      // the backstop that keeps "the editor never goes dark" from
      // resting on having enumerated every reflective call.
      case com.clarifi.reporting.ermine.parsing.Recoverable(e) =>
        log("diagnostics: internal error on " + path + ": " + Rpc.stackTrace(e))
        stored(docs, uri, List((diagnostic(0, 0, "ermine-lsp internal error: " + e), None)))
    }

  /** Publish-and-remember: every path out of `check` goes through here,
    * so the stored list is never one check behind the wire (the two
    * unrecoverable cases -- a header that will not parse, an import that
    * will not load -- included). */
  private def stored(docs: Documents, uri: String,
                     ds: List[(Json, Option[String])]): List[Json] = {
    docs.putDiags(uri, ds.map { case (d, sp) => published(d, sp) })
    ds.map(_._1)
  }

  /** One published diagnostic, as a code action needs it: the range that
    * WENT OUT (read back off the JSON, so it cannot drift from it), the
    * message, the severity, and the note's `spelling`. */
  private def published(d: Json, spelling: Option[String]): QuickFix.Published = {
    def at(which: String, f: String) =
      (d / "range" flatMap (_ / which) flatMap (_ / f) flatMap (_.int)) getOrElse 0
    QuickFix.Published(at("start", "line"), at("start", "character"),
                       at("end", "line"), at("end", "character"),
                       (d / "message" flatMap (_.str)) getOrElse "",
                       (d / "severity" flatMap (_.int)) getOrElse 1,
                       spelling, d)
  }

  private def publish(server: Server, uri: String, ds: List[Json]): Unit =
    server.notify("textDocument/publishDiagnostics",
      Json.obj("uri" -> Json.Str(uri), "diagnostics" -> Json.Arr(ds)))

  // A Death only carries the rendered report, but Pos.report always leads
  // with "fileName:line:column: ...", so recover the position from the
  // first line.  Positions are 1-based; LSP wants 0-based.  When the first
  // line names some other file (the error is in an import) or carries no
  // position, anchor at 0:0 — the report text still names the real spot,
  // and it keeps the caret rendering (end = start is fine, roadmap 0.3).
  private val PosPrefix = """^(.*?):(\d+):(\d+):.*""".r

  /** A structured diagnostic keeps its whole extent, so a broken
    * statement squiggles as far as the splitter took it instead of
    * pointing at one character.  Spans are 1-based and their end is
    * already one past the last character — LSP wants 0-based with an
    * exclusive end, so both ends lose one. */
  private def fromDiag(d: NewPipeline.Diag, ls: Option[Definitions.Lines]): Json = {
    val sp = d.span
    val sl = 0 max (sp.startLine - 1)
    val sc = 0 max Definitions.toCharacter(ls, sp.startLine, sp.startCol)
    val el = 0 max (sp.endLine - 1)
    val ec = 0 max Definitions.toCharacter(ls, sp.endLine, sp.endCol)
    val (endLine, endCol) =
      if (el > sl || (el == sl && ec > sc)) (el, ec) else (sl, sc)
    range(sl, sc, endLine, endCol, d.message)
  }

  /** A note that came with a real span renders like a structured
    * diagnostic: 1-based inclusive in, 0-based half-open out. */
  private def fromSpan(sp: com.clarifi.reporting.ermine.surface.Span,
                       message: String, severity: Int,
                       ls: Option[Definitions.Lines]): Json = {
    val sl = 0 max (sp.startLine - 1)
    val sc = 0 max Definitions.toCharacter(ls, sp.startLine, sp.startCol)
    val el = 0 max (sp.endLine - 1)
    val ec = 0 max Definitions.toCharacter(ls, sp.endLine, sp.endCol)
    val (endLine, endCol) =
      if (el > sl || (el == sl && ec > sc)) (el, ec) else (sl, sc)
    range(sl, sc, endLine, endCol, message, severity)
  }

  private def fromReport(report: String, path: Path, severity: Int = 1,
                         ls: Option[Definitions.Lines] = None): Json =
    (report.linesIterator.toSeq.headOption getOrElse "") match {
      case PosPrefix(file, l, c) if new java.io.File(file).getName == path.getFileName.toString =>
        val chr = 0 max Definitions.toCharacter(ls, l.toInt, c.toInt)
        range(0 max (l.toInt - 1), chr,
              0 max (l.toInt - 1), chr, report, severity)
      case _ =>
        range(0, 0, 0, 0, report, severity)
    }

  private def diagnostic(line: Int, character: Int, message: String): Json =
    range(line, character, line, character, message)

  private def range(sl: Int, sc: Int, el: Int, ec: Int, message: String, severity: Int = 1): Json =
    Json.obj(
      "range"    -> Json.obj(
        "start" -> Json.obj("line" -> Json.num(sl), "character" -> Json.num(sc)),
        "end"   -> Json.obj("line" -> Json.num(el), "character" -> Json.num(ec))),
      "severity" -> Json.num(severity),
      "source"   -> Json.Str("ermine"),
      "message"  -> Json.Str(message))
}
