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
  */
object Diagnostics {

  def install(server: Server, ermine: Resident, docs: Definitions.Docs, log: String => Unit): Unit = {
    def uriOf(params: Json): Option[String] =
      params / "textDocument" flatMap (_ / "uri") flatMap (_.str)

    def check(what: String)(params: Json): Unit =
      uriOf(params) foreach { uri => run(server, ermine, docs, log, what, uri) }

    server.onNotification("textDocument/didOpen")(check("didOpen"))
    server.onNotification("textDocument/didSave")(check("didSave"))
    // The squiggles should not outlive the buffer.
    server.onNotification("textDocument/didClose") { params =>
      uriOf(params) foreach { uri => docs drop uri; publish(server, uri, Nil) }
    }
  }

  private def run(server: Server, ermine: Resident, docs: Definitions.Docs,
                  log: String => Unit, what: String, uri: String): Unit =
    pathFor(uri) match {
      case None =>
        log("diagnostics: ignoring non-file uri " + uri)
      case Some(path) if !(path.toString endsWith ".e") =>
        log("diagnostics: ignoring non-.e file " + path)
      case Some(path) =>
        val t0 = System.nanoTime
        val ds =
          try {
            val checked = ermine.checkFile(path)
            // The index is rebuilt from the SAME parse that produced the
            // diagnostics, broken file or not: navigation on a file's
            // healthy statements no longer decays to the last good save.
            docs.put(uri, Definitions.index(path.toString, checked))
            checked.diags.map(fromDiag) :::
              checked.typeError.toList.map(fromReport(_, path))
          } catch {
            case Death(err, _) => List(fromReport(err.toString, path))
            case scala.util.control.NonFatal(e) =>
              log("diagnostics: internal error on " + path + ": " + Rpc.stackTrace(e))
              List(diagnostic(0, 0, "ermine-lsp internal error: " + e))
          }
        log(f"diagnostics: $what ${path.getFileName} -> ${ds.size} diagnostic(s) in ${(System.nanoTime - t0) / 1e9}%.1fs")
        publish(server, uri, ds)
    }

  private def publish(server: Server, uri: String, ds: List[Json]): Unit =
    server.notify("textDocument/publishDiagnostics",
      Json.obj("uri" -> Json.Str(uri), "diagnostics" -> Json.Arr(ds)))

  private def pathFor(uri: String): Option[Path] =
    try {
      val u = new java.net.URI(uri)
      if (u.getScheme == "file") Some(java.nio.file.Paths.get(u)) else None
    } catch { case _: Exception => None }

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

  private def fromReport(report: String, path: Path): Json =
    (report.linesIterator.toSeq.headOption getOrElse "") match {
      case PosPrefix(file, l, c) if new java.io.File(file).getName == path.getFileName.toString =>
        diagnostic(0 max (l.toInt - 1), 0 max (c.toInt - 1), report)
      case _ =>
        diagnostic(0, 0, report)
    }

  private def diagnostic(line: Int, character: Int, message: String): Json =
    range(line, character, line, character, message)

  private def range(sl: Int, sc: Int, el: Int, ec: Int, message: String): Json =
    Json.obj(
      "range"    -> Json.obj(
        "start" -> Json.obj("line" -> Json.num(sl), "character" -> Json.num(sc)),
        "end"   -> Json.obj("line" -> Json.num(el), "character" -> Json.num(ec))),
      "severity" -> Json.num(1),
      "source"   -> Json.Str("ermine"),
      "message"  -> Json.Str(message))
}
