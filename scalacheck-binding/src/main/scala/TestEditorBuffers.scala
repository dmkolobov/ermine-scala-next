package com.clarifi.reporting

import com.clarifi.reporting.ermine.session.{ Session => S, SessionEnv }

import org.scalacheck._
import Prop._
import scalaparsers.Supply

import java.io.File

/** Stage 2 item 5.3: Session.Buffer, the SourceFile an open editor
  * buffer loads through.
  *
  * The properties here are the guard on the process-global depCache
  * poisoning class fixed at D0 and D3 part 3b.  Two shapes were
  * explicitly rejected for buffers: Session.Literal, whose equality
  * keys off the MODULE NAME (so one editor's text would replay into
  * every other session's load of that name), and a plain Filesystem
  * dep, whose mtime does not move when a buffer changes (so the dep
  * built from the SAVED text would be served back).  Buffer's identity
  * is content-bearing and its lastModified is the document version;
  * these pin both halves.
  */
object TestEditorBuffers extends Properties("Editor buffers 5.3") {
  private val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)

  private val path = "editor-buffer-test" + File.separator + "BufOne.e"

  private def src(body: String) =
    "module BufOne where\nimport Primitive\n\n" + body

  /** Load one buffer in its OWN session and answer what it defined.  The
    * sessions are independent; the depCache between them is not. */
  private def namesFrom(text: String, version: Long): Set[String] =
    fx.session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      S.loadModules(List("Primitive"))
      S.load(S.Buffer(path, text, version))
      s.termNames.keysIterator.collect { case g if g.module == "BufOne" => g.string }.toSet
    }

  property("a buffer loads its own text, and the file need not exist") =
    (namesFrom(src("alpha = 1\n"), 1) ?= Set("alpha")) &&
      (!new File(path).exists :| "the test wrote a file it should not have")

  property("a new version is not served the old version's dep") = {
    val a = namesFrom(src("alpha = 1\n"), 1)
    val b = namesFrom(src("beta = 2\n"), 2)
    (a ?= Set("alpha")) && (b ?= Set("beta"))
  }

  property("same version, different text is still not served the old dep") = {
    // The sharp form: a client that reuses a version number (or a server
    // that forgets to bump one) must not get the previous text back.
    // Literal-style module-name keying fails exactly here.
    val a = namesFrom(src("alpha = 1\n"), 7)
    val b = namesFrom(src("gamma = 3\n"), 7)
    (a ?= Set("alpha")) && (b ?= Set("gamma"))
  }

  property("a buffer's toString is the plain file name") =
    // It is the fileName threaded into every ParseState and every Pos
    // built from one, so the "file:line:col:" contract the Diagnostics
    // regex and definition locations rest on depends on it.
    S.Buffer("/x/Y.e", "module Y where\n", 1).toString ?= "/x/Y.e"

  property("a buffer's lastModified IS its version") =
    S.Buffer("/x/Y.e", "module Y where\n", 42).lastModified ?= Some(42L)

  property("buffers for different paths are different cache keys") =
    (S.Buffer("/x/Y.e", "same", 1) != S.Buffer("/z/Y.e", "same", 1)) :|
      "same module name, different files must not collide (the Literal trap)"

  // ------------------------------------------------------------------ 7.4
  // The adaptive debounce: the POLICY as a pure function of one document's
  // measured check times, and the LOOP that waits it, driven through the real
  // Rpc Server/Wire with a fake unit of work in place of a check.

  import com.clarifi.reporting.ermine.lsp.{ Diagnostics, Server, Wire }
  import Diagnostics.Debounce

  property("7.4 the policy is clamp(Min, C, Max) over the median") = {
    // (samples, D), the measured check times of 7.0 and 7.1b first
    val cases: List[(List[Long], Int)] = List(
      (Nil,          Debounce.Max),   // no history: the pre-7.4 fixed window
      (List(31L),    Debounce.Min),   // a 44-line module (7.0: 30.7 ms)
      (List(550L),   Debounce.Max),   // Report.e warm after 7.1b
      (List(1100L),  Debounce.Max),   // Report.e cold / its worst site
      (List(3000L),  Debounce.Max),   // a hypothetical 3 s file
      (List(200L),   200),            // inside the band: D = C (ratio 1)
      (List(150L),   150),
      (List(300L),   300),
      (List(149L),   150),            // just outside it, both ends
      (List(301L),   300))
    all(cases map { case (samples, want) =>
      (Debounce.policy(samples) ?= want) :| ("samples " + samples)
    }: _*)
  }

  property("7.4 the median outvotes, then forgets, a cold check") = {
    // One cold open (2.3 s on Report.e) among warm 31 ms checks must not
    // hold the window at Max: it stops being the median at three warm
    // samples and has left the five-sample window at five.
    val cold = 2300L
    val warm = 31L
    val step = (n: Int) => Debounce.policy(List.fill(n)(warm) :+ cold)
    (Debounce.policy(List(cold)) ?= Debounce.Max) &&
      (step(1) ?= Debounce.Max) &&          // median of two = their mean
      (step(2) ?= Debounce.Min) &&          // outvoted
      (step(3) ?= Debounce.Min) &&
      (step(4) ?= Debounce.Min) &&
      (Debounce.median(List.fill(5)(warm) :+ cold) ?= Some(warm)) :|
        "the sixth sample is outside the window entirely"
  }

  property("7.4 the policy never lengthens a wait, and never shortens below Min") =
    Prop.forAll(Gen.listOfN(5, Gen.choose(0L, 20000L))) { samples =>
      val d = Debounce.policy(samples)
      (d >= Debounce.Min) :| ("below Min: " + d) &&
        ((d <= Debounce.Max) :| ("above Max: " + d)) &&
        ((d <= 300) :| "the pre-7.4 fixed window was 300; this may only shorten")
    }

  /** The real dispatch loop (`Server.run` over a `Wire`) with a counter in
    * place of a check: n messages `gapMs` apart, then quiet.  Answers how many
    * times the idle work fired.  `during` runs inside the work, which is how a
    * keystroke that arrives DURING a check is delivered. */
  private def loopFires(quietMs: Int, n: Int, gapMs: Int, workMs: Int,
                        during: Int = 0): Int = {
    val toServer = new java.io.PipedOutputStream
    val in       = new java.io.PipedInputStream(toServer, 1 << 16)
    val out      = new java.io.ByteArrayOutputStream
    val wire     = new Wire(in, out, _ => ())
    val server   = new Server(wire, _ => ())
    var pending  = 0
    var fires    = 0
    var sentExtra = 0
    server.onNotification("k") { _ => pending += 1 }
    def send(i: Int): Unit = {
      val body = ("{\"jsonrpc\":\"2.0\",\"method\":\"k\",\"params\":{\"i\":" + i + "}}")
        .getBytes("UTF-8")
      toServer.write(("Content-Length: " + body.length + "\r\n\r\n").getBytes("US-ASCII"))
      toServer.write(body)
      toServer.flush()
    }
    server.onIdle(quietMs)(pending > 0) {
      pending = 0
      fires += 1
      // a check arriving keystrokes cannot interrupt: one dispatch thread
      while (sentExtra < during) { send(1000 + sentExtra); sentExtra += 1 }
      Thread.sleep(workMs)
    }
    val t = new Thread(new Runnable { def run(): Unit = { server.run(); () } })
    t.setDaemon(true)
    t.start()
    var i = 0
    while (i < n) { send(i); Thread.sleep(gapMs); i += 1 }
    // Long enough for the window to expire and the work to run, twice over.
    Thread.sleep((2 * quietMs + 4 * workMs + 200).toLong)
    server.stop(0)
    send(9999)                 // unblock the loop's read so the thread exits
    t.join(5000)
    toServer.close()
    fires
  }

  // Timing-dependent by nature (it drives the real wall-clock loop); the
  // margins are wide -- a 20 ms gap would have to stretch 7x to break the
  // first two.
  property("7.4 a burst of keystrokes 20 ms apart is ONE check, at D_small") =
    loopFires(Debounce.Min, n = 8, gapMs = 20, workMs = 30) ?= 1

  property("7.4 a burst of keystrokes 20 ms apart is ONE check, at D_large") =
    loopFires(Debounce.Max, n = 8, gapMs = 20, workMs = 30) ?= 1

  property("7.4 a keystroke arriving DURING a check produces exactly one more") =
    loopFires(Debounce.Min, n = 4, gapMs = 20, workMs = 200, during = 3) ?= 2
}
