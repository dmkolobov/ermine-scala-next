package com.clarifi.reporting

import com.clarifi.reporting.ermine.lsp.{ Definitions, Documents, Json, Preview, Resident, Rpc, Server, Wire }
import com.clarifi.reporting.ermine.session.{ Printer, Session => S, SessionEnv }

import java.io.{ ByteArrayOutputStream, File, OutputStream }
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.{ Files, Path }

import scalaparsers.{ Death, Supply }

/** THE SHARED LSP/PREVIEW TEST HARNESS, and nothing else.
  *
  * IT WAS EXTRACTED FOR A SECOND SUITE THAT NO LONGER EXISTS, AND IS KEPT
  * BECAUSE `TestLspRobustness` USES IT.  The second suite was
  * `TestPreviewCancel` (WP-6), which drove a `Preview` over a real `Wire`
  * of its own rather than adding five more seconds to `TestLspRobustness`
  * group D, MEASURED at 23-40 s against §11's 60 s cap; WP-24 REMOVED that
  * suite together with WP-6's cancel (tracker/JSON-WIDGET-PLAYGROUND.md,
  * Q13).  So group D (WP-5) is the ONE caller today.  Everything here was
  * MOVED out of `TestLspRobustness` unchanged (the object-level `private`
  * modifiers aside, which had to go: this object is `private[reporting]`
  * and its members were reached from both suites).  No behaviour of any
  * existing property changed with the move.
  *
  * THE LOCK ORDER IS FIXED HERE, and stays fixed although one suite takes
  * it today: `previewLock`, then `residentLock`, then
  * `ErmineFixture.literalLock`.  `core/test` is UNFORKED and PARALLEL, so a
  * second suite sharing this harness really would run at once with group D
  * in one JVM -- which is how `TestPreviewCancel` ran while it existed --
  * and a lock taken the other way round in either of them is a deadlock.
  * Nothing outside this file may take them in another order.
  *
  * WHAT STAYED BEHIND, on purpose: everything that is about ONE group's
  * subject -- group B's corpus and edit grammar, group C's reload fixtures,
  * group D's own `timedD` budget, its Q6/Q7 root directories and its
  * `WpSales` fixtures. */
private[reporting] object PreviewSupport {

  val quiet: String => Unit = _ => ()

  /** A log sink safe to append from several threads, and the sink every
    * harness in this file uses.  Since WP-1 the "<<" line inside
    * `Wire.send` runs on whatever thread answered, so a deferred answer's
    * thread and the dispatch thread append CONCURRENTLY; a `ListBuffer`
    * would drop a line under that and falsify property A at random (a lost
    * "ignoring notification unknown" is the way it would show).  Read the
    * result only after every answering thread has been joined -- the queue
    * gives the happens-before edge, the join gives the completeness. */
  final class LogSink {
    private val lines = new java.util.concurrent.ConcurrentLinkedQueue[String]
    val add: String => Unit = s => { lines.add(s); () }
    def result(): List[String] = {
      val b  = List.newBuilder[String]
      val it = lines.iterator
      while (it.hasNext) b += it.next()
      b.result()
    }
  }

  val residentLock = new Object
  val stdlibRoot   = new File("core/src/main/resources/modules").getAbsoluteFile

  def walk(f: File): List[File] =
    if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
    else if (f.getName endsWith ".e") List(f) else Nil

  def stdlibModules: List[String] = {
    val root = stdlibRoot.getPath + File.separator
    walk(stdlibRoot).map(_.getPath.stripPrefix(root).stripSuffix(".e").replace(File.separator, ".")).sorted
  }

  /** A second root, outside every checkout, that part C writes modules into;
    * removed, contents and all, when the JVM exits (`deleteOnExit` would
    * leave a non-empty directory behind). */
  lazy val extraRoot: Path = {
    val d = Files.createTempDirectory("ermine-lsp-robust")
    Runtime.getRuntime.addShutdownHook(new Thread(() => {
      val s = Files.walk(d)
      try s.sorted(java.util.Comparator.reverseOrder[Path]).forEach(p => Files.deleteIfExists(p))
      catch { case _: java.io.IOException => () }
      finally s.close()
    }))
    d
  }

  def write(p: Path, text: String): Unit = {
    Files.createDirectories(p.getParent)
    Files.write(p, text.getBytes(UTF_8))
  }

  val leafGood = "module Rob.Leaf where\n\nleaf : Int\nleaf = 1\n"

  /** ONE resident for parts B and C, booted with the temp root AHEAD of
    * the stdlib source root, both ahead of the classpath (step 1), and
    * warmed with the whole stdlib the way TestTolerantCheck's is. */
  lazy val resident: Resident = {
    write(extraRoot.resolve("Rob").resolve("Leaf.e"), leafGood)
    write(extraRoot.resolve("Rob").resolve("Dep.e"),
          "module Rob.Dep where\n\nimport Rob.Leaf\n\nuseLeaf : Int\nuseLeaf = leaf\n")
    val r = new Resident(quiet)
    r.moduleRoots = List(extraRoot.toString, stdlibRoot.getPath)
    val ready = r.boot()
    implicit val s: SessionEnv = ready.env
    implicit val su: Supply = r.supply
    implicit val con: Printer = r.printer
    try S.loadModules(stdlibModules)
    catch { case Death(_, _) =>
      stdlibModules.foreach { m => try S.loadModules(List(m)) catch { case Death(_, _) => () } } }
    r
  }

  /** WP-5 stage A (`tracker/JSON-WIDGET-PLAYGROUND.md` §2.3, §2.4, §2.5, §3,
    * §4; §11 row "Render session").  ONE `Preview` -- one daemon thread, one
    * render session, one boot -- drives every property below, through a real
    * `Server` on a real `Wire` over a real byte stream, so that what is
    * asserted is the WIRE's behaviour and not a method call's.
    *
    * WHY ONE.  A render session's boot is the `Lib.preamble` plus
    * `Layout.Doc` plus `Layout.Fetch` of §2.2, measured in seconds, and §11
    * caps this group at 60 s.  Sharing is sound because every property below
    * holds `previewLock`, so they are serialised exactly as B and C are by
    * `residentLock`, and because THE ROOT SET NEVER CHANGES: every fixture
    * lives in one temp directory and every request names it, so §2.4's "a
    * change to the set discards the `Runner`" never fires and the boot is
    * paid once.  Each property `collect`s the group's cumulative wall time,
    * so §11's MEASURED figure is in the suite's own report.
    *
    * LOCK ORDER: `previewLock`, then `residentLock` (one property checks
    * that the resident still answers with a render session loaded beside
    * it), then `ErmineFixture.literalLock` -- which SINCE ROBUST-3
    * (2026-09-20) is taken by every group-D property that RENDERS and not
    * only by the one whose verdict is an invalidation closure: a render
    * walks the process-global `Session.depCache` through
    * `Runner.invalidateStale` whether the property asks it to or not (see
    * `TestLspRobustness.renderingD`, and `withDepCache` for who empties
    * that cache).  Nothing anywhere takes them the other way round:
    * `previewLock` is private to this object and named by nothing that
    * holds either of the others.  The bench -- whose lazy initializer BOOTS
    * a render session, so that its initializer monitor is a lock held for
    * seconds -- is forced under `previewLock` and BEFORE `literalLock`, for
    * the reason `withDepCache`'s LOCK ORDER note gives; the boot itself
    * then takes `literalLock` for its own warm-up render, which is the one
    * render `renderingD` cannot wrap (see `Bench.bootMillis`).
    *
    * NO SHAPE OF `Sales.*` IS EVER REGISTERED HERE.  `DataConDecl`'s maps
    * are process-wide and both `TestRunner` and the registration property
    * above read `Sales.Heading`; the fixture below is
    * `core/src/test/resources/doc/Sales.e` COPIED into a temp root with its
    * module header rewritten to `WpSales`, so every `data` it declares is a
    * fresh `Global`, and the file under `core/src/test/resources` is read
    * and never written.
    *
    * NO PROPERTY DEPENDS ON WALL-CLOCK TIMING.  Where a render has to be
    * held in flight it is held on a latch through `Preview.beforeJob`, which
    * runs on the preview thread holding NO lock -- not the queue's, not the
    * process-wide `Runner.evalLock` -- so the hold costs no other suite
    * anything.  Every wait is bounded and generous (tens of seconds), which
    * fails on a hang and on nothing else. */
  val previewLock = new Object

  /** A byte stream a property WRITES frames into and the server READS.  Not
    * a `PipedInputStream`: that one remembers the thread that last wrote and
    * throws "Write end dead" once it exits, and ScalaCheck's property
    * threads come and go under one shared bench. */
  final class Feed extends java.io.InputStream {
    private val q = new java.util.concurrent.LinkedBlockingQueue[Array[Byte]]
    private var cur: Array[Byte] = Array.emptyByteArray
    private var pos  = 0
    private var done = false
    def put(b: Array[Byte]): Unit = { q.put(b); () }
    def finish(): Unit = { q.put(Array.emptyByteArray); () }
    def read(): Int = {
      while (pos >= cur.length) {
        if (done) return -1
        val next = q.take()
        if (next.isEmpty) { done = true; return -1 }
        cur = next
        pos = 0
      }
      val b = cur(pos) & 0xff
      pos += 1
      b
    }
    override def available(): Int = cur.length - pos
  }

  /** Everything the server SENDS, one parsed message per frame.  `Wire.send`
    * writes header, body and `flush` inside its own monitor, so one flush is
    * exactly one whole frame and nothing here can observe a torn one. */
  final class FrameSink extends OutputStream {
    private val buf  = new ByteArrayOutputStream
    private val msgs = new java.util.concurrent.LinkedBlockingQueue[Json]
    def write(b: Int): Unit = buf.write(b)
    override def write(b: Array[Byte], o: Int, l: Int): Unit = buf.write(b, o, l)
    override def flush(): Unit = {
      val bytes = buf.toByteArray
      buf.reset()
      if (bytes.nonEmpty) {
        val text = new String(bytes, UTF_8)
        val i    = text.indexOf("\r\n\r\n")
        Json.parse(if (i >= 0) text.substring(i + 4) else text) match {
          case Right(j) => msgs.add(j); ()
          case Left(_)  => ()
        }
      }
    }
    def poll(ms: Long): Option[Json] =
      Option(msgs.poll(math.max(0L, ms), java.util.concurrent.TimeUnit.MILLISECONDS))
  }

  /** The one temp module root every render-session fixture lives in. */
  lazy val previewRoot: Path = {
    val d = Files.createTempDirectory("ermine-wp5")
    Runtime.getRuntime.addShutdownHook(new Thread(() => {
      val s = Files.walk(d)
      try s.sorted(java.util.Comparator.reverseOrder[Path]).forEach(p => Files.deleteIfExists(p))
      catch { case _: java.io.IOException => () }
      finally s.close()
    }))
    d
  }

  /** A temp directory removed at JVM exit -- `outsideRoot`'s own body, named
    * because Q6 needs three more of them. */
  def tempRoot(prefix: String): Path = {
    val d = Files.createTempDirectory(prefix)
    Runtime.getRuntime.addShutdownHook(new Thread(() => {
      val s = Files.walk(d)
      try s.sorted(java.util.Comparator.reverseOrder[Path]).forEach(p => Files.deleteIfExists(p))
      catch { case _: java.io.IOException => () }
      finally s.close()
    }))
    d
  }

  /** Write a fixture and make sure its modification time MOVED.  A
    * filesystem stamp has a granularity, and `Runner.staleFiles`' test is
    * `depCache(sf)._1 != lastModified`: two writes inside one tick would
    * leave an edited file looking current and cost a property its verdict
    * for the clock's reason (the hazard `TestRunner.rewriteModule` writes
    * down). */
  def writeFixture(name: String, text: String): Path =
    writeFixtureIn(previewRoot, name, text)

  /** `writeFixture` into a directory other than `previewRoot` (Q6). */
  def writeFixtureIn(dir: Path, name: String, text: String): Path = {
    val p = dir.resolve(name + ".e")
    val before = if (Files.exists(p)) p.toFile.lastModified else 0L
    write(p, text)
    if (p.toFile.lastModified <= before && !p.toFile.setLastModified(before + 2000L))
      throw new IllegalStateException("could not move the modification time of " + p)
    p
  }

  /** One module that is its own report: a number in a widget. */
  def wpSimple(module: String, n: Int): String =
    "module " + module + " where\n\nimport Builtin\nimport Int\nimport Json\nimport List\n" +
    "import Layout.Doc\n\nwidgetNumber : Int\nwidgetNumber = " + n + "\n\n" +
    "report : Int -> Node\nreport n = rawWidget \"w\" widgetNumber\n"

  /** The shared bench: a `Server` over a real `Wire`, a `Preview` installed
    * on it exactly as `Main` installs one, a dispatch thread running
    * `server.run()`, and one test-only SYNCHRONOUS request (`wp5/ping`) --
    * the witness that a render in flight does not block that thread. */
  final class Bench(warm: Boolean = true, residentRoots: List[Path] = Nil) {
    val sink   = new LogSink
    val feed   = new Feed
    val frames = new FrameSink
    val server = new Server(new Wire(feed, frames, sink.add), sink.add)
    // `residentRoots` (Q7 part 2): extra entries for the `moduleRoots`
    // function `Main` supplies from the RESIDENT's own roots.  They LEAD the
    // render session's chain in both branches of `Preview.rootSet` (§2.2
    // wants both sessions to register equal shapes), which is the one way a
    // pick can still be shadowed after Q6 -- so it is the one way to build
    // that case here.  `Nil` for every other bench, which is stage A's
    // behaviour exactly.
    val preview: Preview =
      Preview.install(server, () => stdlibRoot.getPath :: residentRoots.map(_.toString), sink.add)
    // WP-5 stage B (§2.5): this bench's client DECLARES
    // `window.workDoneProgress`, as `Main` would from the `initialize`
    // capabilities, and the very first render below is therefore the one
    // booting render of the whole group -- which is what makes the boot's
    // create / begin / end observable without paying a second boot for it.
    preview.progressCapable = true
    server.onRequest("wp5/ping") { _ => Json.Str("pong") }

    /** `Definitions.install` on this bench's server, so the two requests
      * stage B routes through it -- `ermine/schema` and
      * `ermine/preview/reports` -- can be asked over this wire, by the same
      * registration `Main` makes.  LAZY, and forced only by the properties
      * that need it: its handlers reach the RESIDENT, so a property that
      * forces it holds `residentLock` (the group's lock order). */
    lazy val docs: Documents = {
      val d = new Documents
      Definitions.install(server, resident, d, sink.add, preview)
      d
    }

    private val dispatch = {
      val t = new Thread(new Runnable { def run(): Unit = { server.run(); () } }, "wp5-dispatch")
      t.setDaemon(true)
      t.start()
      t
    }

    /** Messages read but not yet matched.  Touched only by the one property
      * thread holding `previewLock`. */
    private val seen = scala.collection.mutable.ListBuffer.empty[Json]

    def send(j: Json): Unit = {
      val body = Json.print(j).getBytes(UTF_8)
      feed.put(("Content-Length: " + body.length + "\r\n\r\n").getBytes(UTF_8))
      feed.put(body)
    }
    def request(id: Int, method: String, params: Json): Unit =
      send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> Json.num(id),
                    "method" -> Json.Str(method), "params" -> params))
    def notifyServer(method: String, params: Json): Unit =
      send(Json.obj("jsonrpc" -> Json.Str("2.0"), "method" -> Json.Str(method), "params" -> params))

    /** Every request names the SAME roots, so that §2.4's discard-on-change
      * never fires across this group (see the section note). */
    def renderOf(uri: String, binding: String, params: String, generation: Int): Json =
      Json.obj("uri" -> Json.Str(uri), "binding" -> Json.Str(binding),
               "params" -> Json.parse(params).getOrElse(Json.Null),
               "roots" -> Json.Arr(List(Json.Str(previewRoot.toString))),
               "generation" -> Json.num(generation))

    def render(id: Int, path: Path, binding: String, params: String, generation: Int): Unit =
      request(id, "ermine/render", renderOf(path.toUri.toString, binding, params, generation))

    /** `ermine/schema`'s binding form in Q7's shape -- `{uri, binding,
      * roots}`, the same three keys a render identifies its report by, and
      * the SAME roots `renderOf` names, so that a schema and a render on
      * this bench share one session. */
    def schemaOf(uri: String, binding: String): Json =
      Json.obj("uri" -> Json.Str(uri), "binding" -> Json.Str(binding),
               "roots" -> Json.Arr(List(Json.Str(previewRoot.toString))))

    def schema(id: Int, path: Path, binding: String): Unit =
      request(id, "ermine/schema", schemaOf(path.toUri.toString, binding))

    /** A schema naming roots of its own: `renderWith`'s counterpart, and
      * used only by benches of their own, for the same reason. */
    def schemaWith(id: Int, path: Path, binding: String, roots: List[Path]): Unit =
      request(id, "ermine/schema", Json.obj(
        "uri" -> Json.Str(path.toUri.toString), "binding" -> Json.Str(binding),
        "roots" -> Json.Arr(roots map (r => Json.Str(r.toString)))))

    /** A render naming roots of its own (Q6): the one thing `renderOf`
      * deliberately cannot do, because the shared bench's root set must
      * never move.  Only the Q6 properties use it, each on a bench of its
      * own. */
    def renderWith(id: Int, path: Path, binding: String, params: String,
                   generation: Int, roots: List[Path]): Unit =
      request(id, "ermine/render", Json.obj(
        "uri" -> Json.Str(path.toUri.toString), "binding" -> Json.Str(binding),
        "params" -> Json.parse(params).getOrElse(Json.Null),
        "roots" -> Json.Arr(roots map (r => Json.Str(r.toString))),
        "generation" -> Json.num(generation)))

    /** HOW A BOOT IS OBSERVED (Q6): `Preview.ensureSession` logs
      * "preview: render session booted in ..." on the ONE path that builds a
      * `Runner`, and this bench's log is a `LogSink`.  No product surface is
      * added for the test: the line is stage A's own and the count is the
      * number of times a session was built on this bench.  Read it after the
      * answer to the render that would have booted -- the preview thread
      * writes the line before it renders, and the answer is the
      * happens-before edge. */
    def boots: Int = sink.result().count(_.startsWith("preview: render session booted"))

    /** The first message satisfying `p`, waiting at most `ms`: a bounded
      * wait, generous by design, that fails on a hang and nothing else. */
    def await(ms: Long)(p: Json => Boolean): Option[Json] =
      seen.find(p) match {
        case Some(j) => seen -= j; Some(j)
        case None =>
          val deadline = System.currentTimeMillis + ms
          var found = Option.empty[Json]
          while (found.isEmpty && System.currentTimeMillis < deadline)
            frames.poll(deadline - System.currentTimeMillis) match {
              case None    => ()
              case Some(j) => if (p(j)) found = Some(j) else { seen += j; () }
            }
          found
      }

    /** An ANSWER to our request `id` -- a message with that id and NO
      * `method`.  The `method` test is not decoration: since stage B the
      * server sends requests of its OWN (`window/workDoneProgress/create`,
      * §2.5), whose ids are `Server.ask`'s counter and start at 1, which is
      * also where these properties' request ids start.  Without it the
      * first progress request would be read as the first render's answer. */
    def answer(id: Int, ms: Long = 180000L): Option[Json] =
      await(ms)(j => (j / "id" flatMap (_.int)) == Some(id) && (j / "method").isEmpty)
    def notification(method: String, ms: Long = 60000L): Option[Json] =
      await(ms)(j => (j / "method" flatMap (_.str)) == Some(method))

    /** The first REQUEST the server sent us with this method (an `id` and a
      * `method`), waiting at most `ms`. */
    def serverRequest(method: String, ms: Long = 60000L): Option[Json] =
      await(ms)(j => (j / "method" flatMap (_.str)) == Some(method) && (j / "id").isDefined)

    /** Answer a request the SERVER sent us with a JSON-RPC error -- the one
      * thing a client does that this bench could not do before (review S1:
      * a `window/workDoneProgress/create` the client refuses). */
    def replyError(id: Json, code: Int, message: String): Unit =
      send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> id,
                    "error" -> Json.obj("code" -> Json.num(code), "message" -> Json.Str(message))))

    /** Every message this bench has received and not matched, including
      * whatever is still buffered.  ONLY MEANINGFUL once every thread that
      * could still send has been joined (`stop`), which is what makes the
      * "nothing else was ever sent" half of a property a fact rather than a
      * wait. */
    def remaining(): List[Json] = {
      var more = frames.poll(0L)
      while (more.isDefined) { seen += more.get; more = frames.poll(0L) }
      seen.toList
    }

    /** Every message so far whose `method` is `m`, in wire order, matched
      * or not.  A server-sent notification nothing awaits stays in `seen`
      * for the life of the bench, which is what lets the progress property
      * read the frames of a boot that happened in this initializer. */
    def sightings(m: String): List[Json] = {
      var more = frames.poll(0L)
      while (more.isDefined) { seen += more.get; more = frames.poll(0L) }
      seen.toList filter (j => (j / "method" flatMap (_.str)) == Some(m))
    }

    /** The queue's depth once it reaches `n`, or whatever it was when the
      * bound ran out.  The dispatch thread enqueues ASYNCHRONOUSLY -- a
      * property writes bytes, it does not call a method -- so the depth has
      * to be waited for rather than read; the verdict is the value, never
      * the time it took. */
    def awaitQueued(n: Int, ms: Long): Int = {
      val deadline = System.currentTimeMillis + ms
      var q = preview.queuedRenders
      while (q != n && System.currentTimeMillis < deadline) {
        Thread.sleep(5L)
        q = preview.queuedRenders
      }
      q
    }

    /** §2.4's lazy boot, paid ONCE and inside this initializer, so that the
      * figure below is the group's one boot.
      *
      * UNDER `ErmineFixture.literalLock` SINCE ROBUST-3 (2026-09-20), WHICH
      * IS THE OPPOSITE OF WHAT THIS COMMENT USED TO SAY ("so that no
      * property pays it under `literalLock`").  The warm-up below is a REAL
      * render, so `Preview.placeAndSession` runs §2.5's mtime scan on it
      * like any other (`lsp/Preview.scala:1339` ->
      * `Runner.invalidateStale`), and a foreign `Session.depCache.clear()`
      * landing part way through THAT walk is what leaves the render session
      * with `termNames` entries whose values are gone -- the gate red on
      * tree key `cae6f47f42cc3a6cf0c99b0c46e61f1a1d4ff890`
      * (`TestLspRobustness.renderingD` has the whole chain, and the product
      * half is ticket WP-25).  The boot has to be excluded as well, and it
      * is the ONE render `renderingD` cannot cover: it forces this lazy val
      * before taking the lock, precisely so that no property pays a boot
      * under it.  What the exclusion costs is one hold of `literalLock` for
      * the length of this boot -- MEASURED at 2.6 s on the red gate run --
      * once per JVM, against the 23.7 s the longest wrapped property holds
      * it for anyway.
      *
      * THE LOCK ORDER IS KEPT: every force of `bench` happens under
      * `previewLock` (and, for the resident properties, under
      * `residentLock`), and nothing that holds `literalLock` can name
      * either -- so `previewLock` -> `residentLock` -> `literalLock` still
      * describes every path to this line.  A `new Bench` made INSIDE a
      * wrapped property boots under a `literalLock` this thread already
      * holds; a Java monitor is re-entrant. */
    val bootMillis: Long = if (!warm) 0L else ErmineFixture.literalLock.synchronized {
      val p  = writeFixture("WpWarm", wpSimple("WpWarm", 1))
      val t0 = System.currentTimeMillis
      render(1, p, "report", "1", 0)
      val a  = answer(1, 300000L)
      val ms = System.currentTimeMillis - t0
      if ((a flatMap (_ / "result") flatMap (_ / "ok") flatMap (_.bool)) != Some(true))
        throw new IllegalStateException("the preview's warm-up render did not answer ok: " +
                                        a.map(Json.print).getOrElse("(no answer in 300s)"))
      ms
    }

    def stop(): Boolean = {
      preview.shutdown()
      feed.finish()
      dispatch.join(30000L)
      preview.awaitStopped(30000L) && !dispatch.isAlive
    }
  }

  /** ONE bench for the group.  Its threads are daemons, and it is stopped at
    * JVM exit rather than by a property: no single property may stop it
    * without costing every other one its session, and `core/test` is
    * unforked, so leaving a RUNNING thread behind is what the hook is for.
    * The daemon flag is itself asserted below. */
  lazy val bench: Bench = {
    val b = new Bench
    Runtime.getRuntime.addShutdownHook(new Thread(() => { b.stop(); () }))
    b
  }

  def resultOf(j: Option[Json]): Option[Json]  = j flatMap (_ / "result")
  def okOf(j: Option[Json]): Option[Boolean]   = resultOf(j) flatMap (_ / "ok") flatMap (_.bool)
  def statusOf(j: Option[Json]): Option[Int]   = resultOf(j) flatMap (_ / "status") flatMap (_.int)
  def genOf(j: Option[Json]): Option[Int]      = resultOf(j) flatMap (_ / "generation") flatMap (_.int)
  def msgOf(j: Option[Json]): Option[String]   = resultOf(j) flatMap (_ / "message") flatMap (_.str)
  /** Q15's machine-readable `reason`.  `None` means THE KEY IS ABSENT, which
    * is the discriminator itself: only the preview's own front half mints
    * one, so a 404 out of the `Runner` has none. */
  def reasonOf(j: Option[Json]): Option[String] = resultOf(j) flatMap (_ / "reason") flatMap (_.str)
  def docOf(j: Option[Json]): Option[String]   = resultOf(j) flatMap (_ / "document") map Json.print
  /** The JSON-RPC error code of an answer.  TWO ARMS, both moved here from
    * `TestLspRobustness`: group A holds a `Json` and group D an
    * `Option[Json]`, and an overload only works when both live in the one
    * object an importer sees. */
  def errCode(j: Json): Option[Int]           = j / "error" flatMap (_ / "code") flatMap (_.int)
  def errCode(j: Option[Json]): Option[Int]   = j flatMap (_ / "error") flatMap (_ / "code") flatMap (_.int)
  def modulesOf(j: Option[Json]): Option[List[String]] =
    j flatMap (_ / "params") flatMap (_ / "modules") flatMap (_.arr) map (_ flatMap (_.str))
  def show(j: Option[Json]): String = j.map(x => Json.print(x).take(400)).getOrElse("(no answer)")

  def methodOf(j: Json): Option[String] = j / "method" flatMap (_.str)

  /** Q8's marker on an ANSWER (`"stuck": true` in the result), and whether
    * the key is there at all.  The second is what catches the shared-
    * `refusal` bug: an ordinary 500 that gained the flag has `Some(true)`
    * for the first and would pass any test that only looked for it. */
  def stuckOf(j: Option[Json]): Option[Boolean] =
    resultOf(j) flatMap (_ / "stuck") flatMap (_.bool)
  def hasStuckKey(j: Option[Json]): Boolean =
    (resultOf(j) flatMap (_ / "stuck")).isDefined

  /** Q8's notification: `ermine/preview/stuck {stuck, message}` with the
    * value asked for.  A BOUNDED, generous wait, like every other wait in
    * this group: it fails on a notification that never comes and on
    * nothing else. */
  def stuckNote(b: Bench, want: Boolean, ms: Long): Option[Json] =
    b.await(ms)(j => methodOf(j) == Some("ermine/preview/stuck") &&
                     (j / "params" flatMap (_ / "stuck") flatMap (_.bool)) == Some(want))

  def noteText(j: Option[Json]): Option[String] =
    j flatMap (_ / "params") flatMap (_ / "message") flatMap (_.str)
  def noteType(j: Option[Json]): Option[Int] =
    j flatMap (_ / "params") flatMap (_ / "type") flatMap (_.int)

  /** A recording `Rpc.Answer`: every call is kept, in order, and awaited
    * with a bounded wait. */
  final class Answers {
    private val got =
      new java.util.concurrent.LinkedBlockingQueue[Either[(Int, String), Json]]
    val answer: Rpc.Answer = a => { got.add(a); () }
    def await(ms: Long): Option[Either[(Int, String), Json]] =
      Option(got.poll(ms, java.util.concurrent.TimeUnit.MILLISECONDS))
  }

  /** `ermine/render` params for a `Preview` that will never get as far as
    * looking at the file: `beforeJob` throws first. */
  def crashParams(generation: Int): Json =
    Json.obj("uri" -> Json.Str(previewRoot.resolve("WpNoSuchFile.e").toUri.toString),
             "binding" -> Json.Str("report"), "params" -> Json.num(1),
             "roots" -> Json.Arr(Nil), "generation" -> Json.num(generation))

  def answerText(a: Option[Either[(Int, String), Json]]): String = a match {
    case Some(Left((c, m))) => "error " + c + " " + m
    case Some(Right(j))     => Json.print(j)
    case None               => "(NO ANSWER)"
  }
}
