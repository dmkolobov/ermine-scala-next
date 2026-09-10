package com.clarifi.reporting.ermine.lsp

import java.nio.file.Path
import com.clarifi.reporting.ermine.rename.NewPipeline
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
  * typing (Server.onIdle, ~300ms of quiet on the input stream — a queue
  * check on the one dispatch thread, not a race).
  */
object Diagnostics {

  /** How long the input stream must be quiet before a queued check runs. */
  private val DebounceMillis = 300

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

    server.onIdle(DebounceMillis)(queued.nonEmpty) {
      val due = queued.toList
      queued.clear()
      due foreach { case (uri, v) =>
        // Versioned drop.  Dispatch is single-threaded, so this can only
        // fire if a newer edit was handled while an earlier check ran;
        // it is the guard that keeps that from publishing stale results.
        if (docs.get(uri).exists(_.version == v)) run(server, ermine, docs, log, "didChange", uri)
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
        log(f"diagnostics: $what ${path.getFileName} -> ${ds.size} diagnostic(s) in ${(System.nanoTime - t0) / 1e9}%.1fs")
        publish(server, uri, ds)
    }

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
      docs.putIndex(uri, Definitions.index(path.toString, checked))
      checked.diags.map(fromDiag) :::
        checked.notes.map(n => n.span match {
          // LSP-FFI: a tolerated foreign binding knows its class or
          // member span exactly, so it squiggles the name rather
          // than the caret `fromReport` recovers from the text.
          case Some(sp) => fromSpan(sp, n.report, n.severity)
          case None     => fromReport(n.report, path, n.severity)
        })
    } catch {
      case Death(err, _) => List(fromReport(err.toString, path))
      // `Recoverable`, not `NonFatal` (LSP-FFI review finding P-1):
      // NonFatal counts every LinkageError as fatal, so a reflective
      // lookup over a stale classpath used to unwind past here into
      // Rpc's notification guard and the file got NO diagnostics at
      // all — stale squiggles and a stack trace in the log.  This is
      // the backstop that keeps "the editor never goes dark" from
      // resting on having enumerated every reflective call.
      case com.clarifi.reporting.ermine.parsing.Recoverable(e) =>
        log("diagnostics: internal error on " + path + ": " + Rpc.stackTrace(e))
        List(diagnostic(0, 0, "ermine-lsp internal error: " + e))
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
  private def fromDiag(d: NewPipeline.Diag): Json = {
    val sp = d.span
    val sl = 0 max (sp.startLine - 1)
    val sc = 0 max (sp.startCol - 1)
    val el = 0 max (sp.endLine - 1)
    val ec = 0 max (sp.endCol - 1)
    val (endLine, endCol) =
      if (el > sl || (el == sl && ec > sc)) (el, ec) else (sl, sc)
    range(sl, sc, endLine, endCol, d.message)
  }

  /** A note that came with a real span renders like a structured
    * diagnostic: 1-based inclusive in, 0-based half-open out. */
  private def fromSpan(sp: com.clarifi.reporting.ermine.surface.Span,
                       message: String, severity: Int): Json = {
    val sl = 0 max (sp.startLine - 1)
    val sc = 0 max (sp.startCol - 1)
    val el = 0 max (sp.endLine - 1)
    val ec = 0 max (sp.endCol - 1)
    val (endLine, endCol) =
      if (el > sl || (el == sl && ec > sc)) (el, ec) else (sl, sc)
    range(sl, sc, endLine, endCol, message, severity)
  }

  private def fromReport(report: String, path: Path, severity: Int = 1): Json =
    (report.linesIterator.toSeq.headOption getOrElse "") match {
      case PosPrefix(file, l, c) if new java.io.File(file).getName == path.getFileName.toString =>
        range(0 max (l.toInt - 1), 0 max (c.toInt - 1),
              0 max (l.toInt - 1), 0 max (c.toInt - 1), report, severity)
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
