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
      val docs   = new Documents
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

      // `ermine.fastMode` may arrive two ways: in initializationOptions
      // at startup, or in a settings push at any time.  Both land here.
      def applyFastMode(v: Option[Boolean], how: String): Unit = v foreach { b =>
        if (b != ermine.fastMode) {
          ermine.fastMode = b
          log(s"fast mode ${if (b) "ON — type checking skipped" else "OFF"} ($how)")
          logMessage(3, if (b) "Ermine: fast mode on — diagnostics are syntax-only"
                        else "Ermine: fast mode off — full type checking")
        }
      }

      request("initialize") { params =>
        log("initialize received")
        applyFastMode(
          params / "initializationOptions" flatMap (_ / "fastMode") flatMap (_.bool),
          "initializationOptions")
        Json.obj(
          "capabilities" -> Json.obj(
            "textDocumentSync" -> Json.obj(
              "openClose" -> Json.Bool(true),
              "change"    -> Json.num(1),      // FULL: didChange carries the whole document (5.3)
              "save"      -> Json.Bool(true)),
            "definitionProvider" -> Json.Bool(true),
            "hoverProvider"      -> Json.Bool(true),
            // 6.3: all three answer from the index the last check built.
            "referencesProvider"        -> Json.Bool(true),
            "documentHighlightProvider" -> Json.Bool(true),
            "renameProvider"            -> Json.obj(
              "prepareProvider" -> Json.Bool(true))),
          "serverInfo" -> Json.obj(
            "name"    -> Json.Str("ermine-lsp"),
            "version" -> Json.Str("0.1")))
      }

      // Boot the resident session right after the handshake, on the one
      // dispatch thread: initialize answers fast, and anything the client
      // sends during the ~6-12s boot just queues on the stream behind it.
      // Let the session speak to the client, not just to the log file: a
      // silent 13s is indistinguishable from a hang.
      ermine.announce = (m: String) => logMessage(3, m)

      server.onNotification("initialized") { _ =>
        try {
          val r = ermine.boot()
          logMessage(3, f"Ermine session ready: ${r.modules} modules in ${r.seconds}%.1fs")
        } catch {
          case e: Throwable =>
            log("boot failed: " + Rpc.stackTrace(e))
            // Remember it, so later checks fail fast instead of each
            // spending another ~13s failing the same way.
            ermine.bootFailedWith(e)
            logMessage(1, "Ermine session failed to boot: " + e.getMessage +
                          " — run 'Ermine: Restart Language Server' after fixing it")
        }
      }

      // A settings push can arrive at any time; VS Code sends one on
      // every configuration change.  Nothing here blocks — it flips a
      // var that the NEXT check reads.
      server.onNotification("workspace/didChangeConfiguration") { params =>
        // Clients disagree about whether the section name is included in the
        // payload, so accept both {settings:{ermine:{fastMode}}} and
        // {settings:{fastMode}} rather than silently ignoring one of them.
        val settings = params / "settings"
        applyFastMode(
          (settings flatMap (_ / "ermine") flatMap (_ / "fastMode") flatMap (_.bool)) orElse
            (settings flatMap (_ / "fastMode") flatMap (_.bool)),
          "didChangeConfiguration")
      }

      Diagnostics.install(server, ermine, docs, log)
      Definitions.install(server, ermine, docs, log)
      References.install(server, ermine, docs, log)

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
