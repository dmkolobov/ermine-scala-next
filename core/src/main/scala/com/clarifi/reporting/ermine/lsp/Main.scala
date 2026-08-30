package com.clarifi.reporting.ermine.lsp

/** Ermine language server, stage 0 (tracker/LSP-ROADMAP.md).
  *
  * Speaks LSP over stdio.  stdout carries the protocol and nothing else
  * (roadmap decision 4); diagnostics about the server itself go to the file
  * named by -Dermine.lsp.log, or nowhere.
  */
object Main {

  private def log(s: String): Unit = logSink(s)

  private lazy val logSink: String => Unit =
    sys.props get "ermine.lsp.log" match {
      case None       => _ => ()
      case Some(path) =>
        val w   = new java.io.PrintWriter(new java.io.FileWriter(path, true), true)
        val fmt = java.time.format.DateTimeFormatter ofPattern "HH:mm:ss.SSS"
        s => w.println(java.time.LocalTime.now.format(fmt) + " " + s)
    }

  def main(args: Array[String]): Unit =
    try {
      val wire   = new Wire(System.in, System.out, log)
      val server = new Server(wire, log)
      var shutdownSeen = false

      // After shutdown the client may only send exit; answer anything else
      // with InvalidRequest, per the protocol.
      def request(method: String)(h: Json => Json): Unit =
        server.onRequest(method) { params =>
          if (shutdownSeen) throw RpcError(Rpc.InvalidRequest, "server is shutting down")
          h(params)
        }

      request("initialize") { _ =>
        log("initialize received")
        Json.obj(
          "capabilities" -> Json.obj(
            "textDocumentSync" -> Json.obj(
              "openClose" -> Json.Bool(true),
              "change"    -> Json.num(0),      // no didChange bodies yet: diagnostics run on open/save
              "save"      -> Json.Bool(true)),
            "definitionProvider" -> Json.Bool(true),
            "hoverProvider"      -> Json.Bool(true)),
          "serverInfo" -> Json.obj(
            "name"    -> Json.Str("ermine-lsp"),
            "version" -> Json.Str("0.1")))
      }

      server.onNotification("initialized") { _ => log("client initialized") }

      server.onRequest("shutdown") { _ =>
        log("shutdown received")
        shutdownSeen = true
        Json.Null
      }

      server.onNotification("exit") { _ =>
        log("exit received")
        server.stop(if (shutdownSeen) 0 else 1)
      }

      val code = server.run() getOrElse {
        log("client closed the stream without exit")
        if (shutdownSeen) 0 else 1
      }
      log("exiting with code " + code)
      System.exit(code)
    } catch {
      case e: Throwable =>
        // Last resort; never stdout (decision 4).
        System.err.println("ermine-lsp panic: " + e)
        e.printStackTrace()
        log("panic: " + Rpc.stackTrace(e))
        System.exit(2)
    }
}
