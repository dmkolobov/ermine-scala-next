package com.clarifi.reporting.ermine.lsp

import java.nio.file.Path
import scalaparsers.Death

/** didOpen/didSave -> parse+typecheck -> publishDiagnostics (roadmap 0.3).
  *
  * Every check runs against a fresh copy of the resident env
  * (Resident.checkFile), so there is no reload or cache-invalidation
  * story: a didSave re-checks the file and its workspace imports from
  * scratch, and a failed load poisons nothing.
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
            val (env, module) = ermine.checkFile(path)
            // A clean check refreshes navigation; a failed one keeps the
            // last good index (stale hits beat none, misses answer null).
            docs.put(uri, Definitions.index(path.toString, env, module))
            Nil
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

  private def fromReport(report: String, path: Path): Json =
    (report.linesIterator.toSeq.headOption getOrElse "") match {
      case PosPrefix(file, l, c) if new java.io.File(file).getName == path.getFileName.toString =>
        diagnostic(0 max (l.toInt - 1), 0 max (c.toInt - 1), report)
      case _ =>
        diagnostic(0, 0, report)
    }

  private def diagnostic(line: Int, character: Int, message: String): Json = {
    val pos = Json.obj("line" -> Json.num(line), "character" -> Json.num(character))
    Json.obj(
      "range"    -> Json.obj("start" -> pos, "end" -> pos),
      "severity" -> Json.num(1),
      "source"   -> Json.Str("ermine"),
      "message"  -> Json.Str(message))
  }
}
