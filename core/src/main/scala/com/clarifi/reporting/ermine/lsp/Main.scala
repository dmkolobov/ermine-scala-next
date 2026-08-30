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

  /** The real stdout, reserved for the protocol.  Everything else that
    * tries to print — library code, log4j's console appender, the one
    * stray println — lands in the log instead (decision 4). */
  private def stealStdout(): java.io.OutputStream = {
    val protocol = System.out
    System.setOut(new java.io.PrintStream(new java.io.OutputStream {
      private val line = new java.lang.StringBuilder
      override def write(b: Int): Unit =
        if (b == '\n' || b == '\r') flushLine() else line.append(b.toChar)
      override def write(b: Array[Byte], off: Int, len: Int): Unit =
        new String(b, off, len, java.nio.charset.StandardCharsets.UTF_8) foreach (c => write(c.toInt))
      private def flushLine(): Unit =
        if (line.length > 0) { log("stdout: " + line); line.setLength(0) }
    }, true))
    protocol
  }

  def main(args: Array[String]): Unit =
    try {
      val wire   = new Wire(System.in, stealStdout(), log)
      val server = new Server(wire, log)
      val ermine = new Resident(log)
      var shutdownSeen = false

      def logMessage(messageType: Int, message: String): Unit =
        server.notify("window/logMessage",
          Json.obj("type" -> Json.num(messageType), "message" -> Json.Str(message)))

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

      // Boot the resident session right after the handshake, on the one
      // dispatch thread: initialize answers fast, and anything the client
      // sends during the ~6-12s boot just queues on the stream behind it.
      server.onNotification("initialized") { _ =>
        try {
          val r = ermine.boot()
          logMessage(3, f"Ermine session ready: ${r.modules} modules in ${r.seconds}%.1fs")
        } catch {
          case e: Throwable =>
            log("boot failed: " + Rpc.stackTrace(e))
            logMessage(1, "Ermine session failed to boot: " + e.getMessage)
        }
      }

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
