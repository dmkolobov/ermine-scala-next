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
      // LSP-STALENESS step 2: whether the client lets the server register a
      // file watcher (`client/registerCapability`); read at initialize, used
      // at initialized.
      var watchDynamic = false

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
        // 7.4: `ermine.debounce` PINS the quiet window, in milliseconds,
        // instead of deriving it from the measured check time.  It exists for
        // reproducibility, not for tuning: tracker/tools/perf-bench.sh is the
        // measurement of record and pins 300 so its editor numbers stay
        // comparable with every figure taken while the window was a constant.
        // Out-of-range values are refused rather than clamped silently — a
        // client that asks for a 0 ms or a one-minute window has a bug, and a
        // pin that silently became something else would poison a measurement.
        params / "initializationOptions" flatMap (_ / "debounce") flatMap (_.int) foreach { ms =>
          if (ms >= 1 && ms <= 10000) {
            Diagnostics.Debounce.pin(ms)
            log(s"debounce PINNED at ${ms}ms (initializationOptions); the adaptive policy is off")
          } else
            log(s"debounce pin of ${ms}ms ignored (outside 1..10000ms); the adaptive policy stands")
        }
        // Staleness step 1 (tracker/LSP-STALENESS.md): the SOURCE ROOTS the
        // session reads the stdlib from, ahead of the classpath copy.  Explicit
        // `initializationOptions.moduleRoots` first, in the order given; then
        // what every workspace folder implies (`Resident.rootsUnder`:
        // `core/src/main/resources/modules` beneath it, when that exists), with
        // `rootUri` counted as a folder for a client that sends only that.  Set
        // here and read at `initialized`, when the session boots, so a client
        // that sends neither gets the classpath and nothing else changes.
        // A relative entry resolves against the server's working directory (the
        // checkout `bin/ermine-lsp` runs in); one that is not a path at all is
        // logged and dropped, the way a root that is not a directory is skipped
        // at boot -- never a failed handshake.
        val explicitRoots =
          params / "initializationOptions" flatMap (_ / "moduleRoots") flatMap (_.arr) map
            (_ flatMap (_.str) flatMap { r =>
              try Some(java.nio.file.Paths.get(r).toAbsolutePath.normalize.toString)
              catch { case e: java.nio.file.InvalidPathException =>
                log("module root dropped, not a path: " + r + " (" + e.getMessage + ")"); None }
            }) getOrElse Nil
        val folderUris =
          (params / "workspaceFolders" flatMap (_.arr) map (_ flatMap (f => f / "uri" flatMap (_.str))) getOrElse Nil) ++
          (params / "rootUri" flatMap (_.str)).toList
        val impliedRoots = folderUris.distinct flatMap docs.pathFor flatMap Resident.rootsUnder
        ermine.moduleRoots = (explicitRoots ++ impliedRoots).distinct
        log("module roots: " +
            (if (ermine.moduleRoots.isEmpty) "none (no moduleRoots option, no workspace folder with a stdlib)"
             else ermine.moduleRoots.mkString(", ")))
        watchDynamic =
          (params / "capabilities" flatMap (_ / "workspace") flatMap (_ / "didChangeWatchedFiles")
                  flatMap (_ / "dynamicRegistration") flatMap (_.bool)) getOrElse false
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
              "prepareProvider" -> Json.Bool(true)),
            // 6.4: the document tree comes from the last check's stored
            // symbols; the workspace query from those plus the resident
            // session's own globals.
            "documentSymbolProvider"    -> Json.Bool(true),
            "workspaceSymbolProvider"   -> Json.Bool(true),
            // 6.5: completion from the last check's tables and the
            // current buffer text.  `.` is the one trigger character (a
            // qualified name and an `import X.` are both dotted); there
            // is no completionItem/resolve -- every item arrives with
            // its detail already on it.
            "completionProvider"        -> Json.obj(
              "triggerCharacters" -> Json.Arr(List(Json.Str("."))),
              "resolveProvider"   -> Json.Bool(false)),
            // 6.6: quick fixes.  Two kinds are advertised and two are
            // served -- `quickfix` for add-import (which carries the
            // diagnostic it fixes) and for one binding's signature, and
            // `source` for "add all missing signatures".  A signature
            // action is a `quickfix` with no diagnostic rather than a
            // `refactor.rewrite` because these are the kinds this server
            // declares: a client asking `only: ["refactor"]` must not be
            // told we have something we then do not send.
            "codeActionProvider"        -> Json.obj(
              "codeActionKinds" -> Json.Arr(List(Json.Str("quickfix"), Json.Str("source")))),
            // LSP-STALENESS step 2: the manual reload, for a client that does
            // not watch files (or a save the watcher missed).
            "executeCommandProvider"    -> Json.obj(
              "commands" -> Json.Arr(List(Json.Str("ermine.reloadModules"))))),
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

      // LSP-STALENESS step 2: what follows a reload, whoever asked for it.
      // The workspace-symbol table, the inference caches and the published
      // diagnostics all describe the session before the reload.
      def afterReload(how: String, r: Option[Resident.Reloaded]): Unit = r match {
        case None                  => log(s"$how: session not booted; nothing to reload")
        case Some(x) if x.nothing  => log(s"$how: no loaded module changed")
        case Some(x) =>
          log(f"$how: reloaded ${x.modules.mkString(", ")} in ${x.seconds}%.1fs" +
              x.failure.fold("")(f => "; FAILED: " + f))
          Symbols.forgetSession()
          QuickFix.forgetSession()
          docs.dropCaches()
          Diagnostics.recheckAll(server, ermine, docs, log)
          x.failure match {
            case None    => logMessage(3, s"Ermine: reloaded ${x.modules.size} module(s): ${x.modules.mkString(", ")}")
            case Some(f) => logMessage(1, s"Ermine: reload of ${x.modules.mkString(", ")} failed: $f " +
                                          "-- the session lacks them until a save succeeds")
          }
      }

      server.onNotification("initialized") { _ =>
        // Watch every .e file the client can see, through the client's own
        // watcher (`vscode-languageclient` turns this registration into a
        // FileSystemWatcher).  Asked BEFORE the boot: the reply queues behind
        // it, and an event that arrives before the session is up finds
        // nothing loaded and is a no-op -- the boot reads the disk as it is.
        if (watchDynamic)
          server.ask("client/registerCapability", Json.obj(
            "registrations" -> Json.Arr(List(Json.obj(
              "id"     -> Json.Str("ermine.watch.e"),
              "method" -> Json.Str("workspace/didChangeWatchedFiles"),
              "registerOptions" -> Json.obj(
                "watchers" -> Json.Arr(List(Json.obj("globPattern" -> Json.Str("**/*.e")))))))))) { reply =>
            reply / "error" match {
              case Some(e) => log("watch: client refused the **/*.e watcher registration: " + e)
              case None    => log("watch: client registered the **/*.e watcher")
            }
          }
        else
          log("watch: client does not register file watchers dynamically; " +
              "workspace/didChangeWatchedFiles is honoured if it sends them anyway, " +
              "and ermine.reloadModules is the manual way")
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

      // LSP-STALENESS step 2: a file the resident loaded changed on disk.
      // Created counts as changed (a module deleted then restored comes back
      // this way); a deleted file's module is scrubbed and loaded back from
      // the next root that has it, or left pending.
      server.onNotification("workspace/didChangeWatchedFiles") { params =>
        val changes = params / "changes" flatMap (_.arr) getOrElse Nil
        def paths(types: Set[Int]): Set[java.nio.file.Path] = changes.flatMap { c =>
          for {
            t <- c / "type" flatMap (_.int) if types(t)
            u <- c / "uri" flatMap (_.str)
            p <- docs.pathFor(u) if p.toString endsWith ".e"
          } yield p
        }.toSet
        val changed = paths(Set(1, 2))
        val removed = paths(Set(3))
        log(s"watch: ${changed.size} created/changed, ${removed.size} deleted")
        afterReload("watch", ermine.reload(changed, removed))
      }

      request("workspace/executeCommand") { params =>
        params / "command" flatMap (_.str) match {
          case Some("ermine.reloadModules") =>
            val r = ermine.reloadStale()
            afterReload("reload command", r)
            Json.obj(
              "reloaded" -> Json.Arr(r.toList.flatMap(_.modules).map(Json.Str(_))),
              "failure"  -> (r.flatMap(_.failure).map(Json.Str(_)) getOrElse Json.Null))
          case other =>
            throw RpcError(Rpc.InvalidParams, "unknown command: " + other.getOrElse("(none)"))
        }
      }

      Diagnostics.install(server, ermine, docs, log)
      Definitions.install(server, ermine, docs, log)
      References.install(server, ermine, docs, log)
      Symbols.install(server, ermine, docs, log)
      Completion.install(server, ermine, docs, log)
      QuickFix.install(server, ermine, docs, log)

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
