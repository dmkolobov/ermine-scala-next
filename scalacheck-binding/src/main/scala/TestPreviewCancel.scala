package com.clarifi.reporting

import com.clarifi.reporting.ermine.{ Bottom, Box, Cancelled, Prim, Runtime => ErmineRuntime }
import com.clarifi.reporting.ermine.lsp.{ Json, Preview }

import org.scalacheck._
import Prop._

import java.nio.file.Path

/** WP-6, THE COOPERATIVE CANCEL (tracker/JSON-WIDGET-PLAYGROUND.md section
  * 2.5's cooperative-cancel row, section 13 Q13, section 14's WP-6 row).
  *
  * A SUITE OF ITS OWN, and that is the point of `PreviewSupport`: group D of
  * `TestLspRobustness` is MEASURED at 23-40 s against section 11's 60 s cap,
  * with about 5 s of margin, and five more render-session properties would
  * cross it.  Everything shared with that group -- the bench, the log sink,
  * the temp roots, `previewLock`, the resident and `residentLock` -- is
  * imported from `PreviewSupport` and is the SAME OBJECT, so the two suites
  * serialise against each other in the one unforked, parallel test JVM.
  *
  * LOCK ORDER, and it is `PreviewSupport`'s and not this file's:
  * `previewLock`, then `residentLock`, then `ErmineFixture.literalLock`.
  * Every property below takes `previewLock` and nothing else.
  *
  * TWO KINDS OF PROPERTY, with very different costs:
  *
  *   R. `Runtime`-level, no bench, no session, MILLISECONDS.  They arm
  *      WP-6's PROCESS-GLOBAL flag, so every one of them runs on a thread it
  *      constructed itself and clears the flag in a `finally` -- see
  *      `onOwnThread` for why that cannot reach another suite;
  *   C. render-session properties on a `Bench`, each paying at least one
  *      boot (MEASURED at 1.9-7.3 s in section 2.2).  The suite's own wall
  *      time is collected and `collect`ed exactly as group D's is.
  *
  * WHAT THE LOOPING FIXTURES COST, stated because it is the one way this
  * suite can hurt another.  A real Ermine loop runs under the PROCESS-WIDE
  * `Runner.evalLock`, so while one is running every other suite's evaluation
  * waits.  Each loop here is bounded by `timeoutMillis` plus the cancel, a
  * fraction of a second and never more than the grace -- EXCEPT in the
  * switch-OFF property, where by construction nothing stops the loop and the
  * property ends it by arming the flag itself; that property says so where
  * it does it. */
object TestPreviewCancel extends Properties("preview cooperative cancel") {

  import PreviewSupport._

  // ------------------------------------------------------------ the clock

  /** The suite's cumulative wall time, reported the way group D reports its
    * own: the largest label in the run is what this suite costs. */
  private val millis = new java.util.concurrent.atomic.AtomicLong(0L)

  private def timed(what: String)(body: => Prop): Prop = {
    val t0  = System.currentTimeMillis
    val p   = body
    val ms  = System.currentTimeMillis - t0
    val cum = millis.addAndGet(ms)
    collect(f"WP-6: $what%s ${ms / 1000.0}%.1fs, suite so far ${cum / 1000.0}%.1fs")(p)
  }

  // ================================================== R. the Runtime flag

  /** Run `body` on a thread THIS PROPERTY CONSTRUCTED and hand back what it
    * did (a `Left` for whatever it threw, `Cancelled` included).
    *
    * THIS IS THE WHOLE SAFETY ARGUMENT for arming a process-global flag in
    * an unforked, parallel test JVM.  `Runtime.cancelTarget` is only ever
    * set to a `Thread` object made here, and `swhnf`'s test is
    * `ct eq Thread.currentThread` -- an object identity no other thread in
    * the JVM can satisfy: not a ScalaCheck pool thread, not another suite's,
    * not a `Preview`'s.  So a stray arming cannot cancel anybody else's
    * evaluation; the worst it could do is nothing at all.  Every property
    * below also clears the flag in a `finally` ON THAT THREAD, so the window
    * in which the global is non-null is the probe's own body. */
  private def onOwnThread[A](name: String)(body: => A): Either[Throwable, A] = {
    val out = new java.util.concurrent.ArrayBlockingQueue[Either[Throwable, A]](1)
    val t = new Thread(new Runnable {
      def run(): Unit = {
        val r: Either[Throwable, A] = try Right(body) catch { case e: Throwable => Left(e) }
        out.put(r)
      }
    }, name)
    t.setDaemon(true)
    t.start()
    Option(out.poll(60000L, java.util.concurrent.TimeUnit.MILLISECONDS))
      .getOrElse(Left(new IllegalStateException("the probe thread did not finish in 60s")))
  }

  /** Arm WP-6's cancel FOR THE CALLING THREAD, in the order
    * `Runtime.cancelTarget`'s contract states: the reason first, the target
    * second.
    *
    * EVERY PROPERTY THAT CALLS THIS HOLDS `previewLock`, and that is not
    * decoration: `Runtime.cancelTarget` is ONE GLOBAL REFERENCE, so two
    * properties arming at once would each name their own probe thread and
    * the second write would silently un-arm the first.  MEASURED, not
    * feared: without the lock this suite failed two `R` properties on one
    * run in five ("Expected ... but got" with no throw at all), because
    * ScalaCheck runs a `Properties` object's properties on a pool. */
  private def armHere(why: String): Unit = {
    val ok = ErmineRuntime.armCancel(Thread.currentThread, new Cancelled(why, false))
    // NOT SWALLOWED: `armCancel` refuses only when ANOTHER thread's arming
    // is live, which `previewLock` exists to prevent.  A refusal means that
    // defence has failed, and a property that then quietly asserted nothing
    // would be worse than one that stops.
    if (!ok) throw new IllegalStateException(
      "wp6: another thread's cancel was live, so this property could not arm one; " +
      "previewLock is not doing its job")
  }

  /** Clear an arming THIS THREAD made, and never anyone else's -- the
    * identity guard lives in `Runtime.disarmCancel` (S1/S2 of the stage 1
    * review), which is why this is a forwarder and not a pair of stores. */
  private def disarmHere(): Unit = ErmineRuntime.disarmCancel(Thread.currentThread)

  private def describe(e: Either[Throwable, _]): String = e match {
    case Left(t)  => t.getClass.getName + ": " + t.getMessage
    case Right(v) => String.valueOf(v)
  }

  property("R: a cancel armed for ANOTHER thread leaves this thread's forcing alone") = secure {
    previewLock.synchronized { timed("R: armed elsewhere") {
      // A thread that has already FINISHED: a distinct `Thread` object that
      // no live thread can be `eq` to, so this arming is inert by
      // construction and cannot stop anything anywhere.
      val other = new Thread(new Runnable { def run(): Unit = () }, "wp6-other")
      other.setDaemon(true)
      other.start()
      other.join(30000L)
      val got = onOwnThread("wp6-armed-elsewhere") {
        if (!ErmineRuntime.armCancel(other, new Cancelled("wp6: armed for another thread", false)))
          throw new IllegalStateException("wp6: could not arm for the finished probe thread")
        // Cleared BY IDENTITY: this is the one arming in the file that does
        // not name the clearing thread, so `disarmHere` would not match it.
        try ErmineRuntime.swhnf(ErmineRuntime.Thunk(Prim(41))).extract[Int]
        finally ErmineRuntime.disarmCancel(other)
      }
      ((got ?= Right(41)) :| ("forcing under another thread's cancel gave " + describe(got))) &&
        ((ErmineRuntime.cancelArmedFor eq null) :| "the probe left the cancel armed")
    }
  } }

  property("R: a cancel armed for THIS thread throws Cancelled, and the thunk it stopped is NOT memoised") = secure {
    previewLock.synchronized { timed("R: armed here") {
      val why = "wp6: armed for this thread"
      val got = onOwnThread("wp6-armed-here") {
        val t = ErmineRuntime.Thunk(Prim(7))
        try {
          armHere(why)
          // THE CHECK IS AT THE HEAD, so this throws BEFORE the thunk is
          // entered: `t.state` is still `Unevaluated` and `t.pending` is
          // empty.  Neither is readable from here (`private[Runtime]`), so
          // what is asserted is the consequence -- forcing it again, with
          // the flag clear, answers the real value and not a `Bottom`.
          val first: Either[Throwable, Int] =
            try Right(ErmineRuntime.swhnf(t).extract[Int])
            catch { case c: Cancelled => Left(c) }
          disarmHere()
          val second = ErmineRuntime.swhnf(t)
          (first, second)
        } finally disarmHere()
      }
      got match {
        case Left(e) => falsified :| ("the probe threw: " + describe(Left(e)))
        case Right((first, second)) =>
          (first.isLeft :| ("forcing under an armed cancel answered " + describe(first))) &&
            (first.left.toOption.exists(_.isInstanceOf[Cancelled]) :|
              ("what it threw was not a Cancelled: " + describe(first))) &&
            (first.left.toOption.collect { case c: Cancelled => c.why }.contains(why) :|
              ("the Cancelled does not carry the canceller's reason: " + describe(first))) &&
            ((!second.isInstanceOf[Bottom]) :|
              ("the cancelled thunk was memoised as a Bottom: " + second.toString)) &&
            ((second.extract[Int] ?= 7) :| ("re-forcing it gave " + second.toString))
      }
    }
  } }

  property("R: a cancel that unwinds a thunk ALREADY BEING FORCED leaves a whitehole -- which is why the cancel path discards the session") = secure {
    previewLock.synchronized { timed("R: the whitehole") {
      // THE EVIDENCE FOR `Preview.isFatal`'S WP-6 EXCEPTION, and for the
      // unconditional discard that makes it sound.  `Cancelled` is a
      // `ControlThrowable`, so `swhnf`'s `NonFatal` capture does not run and
      // `writeback` never happens: the thunk this unwind passed through is
      // left `Whitehole` with the forcing thread still in its `pending`
      // queue, and a later force of it ON THAT THREAD is a PERMANENT
      // "infinite loop detected".  A session holding those is not one to go
      // on rendering with.
      val got = onOwnThread("wp6-whitehole") {
        try {
          val inner = ErmineRuntime.Thunk(Prim(1))
          val outer = ErmineRuntime.Thunk({ armHere("wp6: mid-force"); ErmineRuntime.swhnf(inner) })
          val first =
            try { ErmineRuntime.swhnf(outer); "returned" }
            catch { case _: Cancelled => "cancelled" }
          disarmHere()
          (first, ErmineRuntime.swhnf(outer))
        } finally disarmHere()
      }
      got match {
        case Left(e) => falsified :| ("the probe threw: " + describe(Left(e)))
        case Right((first, second)) =>
          ((first ?= "cancelled") :| ("the mid-force cancel " + first)) &&
            (second.isInstanceOf[Bottom] :|
              ("the half-forced thunk is not a Bottom on re-force: " + second.toString)) &&
            (second.toString.contains("infinite loop detected") :|
              ("re-forcing it gave " + second.toString))
      }
    }
  } }

  property("R: a Cancelled raised inside a Prim or a Box body ESCAPES rather than becoming a Bottom") = secure {
    previewLock.synchronized { timed("R: Prim and Box") {
      // THE REGRESSION TEST FOR TWO OF WP-6'S FOUR SWALLOWING CATCHES.
      // `Prim.apply` and `Box.apply` both end in
      // `catch { case e: Throwable => Bottom(throw e) }`, which would turn
      // the cancel into a VALUE -- and `writeback` would then memoise it.
      // With the `case c: Cancelled => throw c` arm ahead of it, it escapes.
      val got = onOwnThread("wp6-prim-box") {
        try {
          val t = ErmineRuntime.Thunk(Prim(3))
          armHere("wp6: inside a primitive")
          val viaPrim = try { Prim({ ErmineRuntime.swhnf(t); 1 }); "swallowed" }
                        catch { case _: Cancelled => "escaped" }
          val viaBox  = try { Box({ ErmineRuntime.swhnf(t); 1 }); "swallowed" }
                        catch { case _: Cancelled => "escaped" }
          (viaPrim, viaBox)
        } finally disarmHere()
      }
      got match {
        case Left(e) => falsified :| ("the probe threw: " + describe(Left(e)))
        case Right((viaPrim, viaBox)) =>
          ((viaPrim ?= "escaped") :| ("Prim.apply " + viaPrim + " the cancel")) &&
            ((viaBox ?= "escaped") :| ("Box.apply " + viaBox + " the cancel"))
      }
    }
    // THE OTHER TWO CATCHES -- `session/Lib.scala`'s `IO.Unsafe.eval` and
    // `session/Session.scala`'s foreign invoke -- ARE UNVERIFIED BY TEST.
    // Both are Ermine primitives reachable only from a booted session
    // through Ermine source that uses them, which is a render-session
    // property and several seconds each; they were fixed by the same
    // one-line rule and read, not measured.
  } }

  property("R: a Bottom whose body FORCES does not catch the cancel and hand it back as a value") = secure {
    previewLock.synchronized { timed("R: Bottom.thrown") {
      // DM-3 OF THE STAGE 1 REVIEW.  `Bottom.thrown` is
      // `try msg catch { case e: Throwable => e }`, and a `Bottom`'s body is
      // USUALLY a bare `throw` -- but not always: `session/Lib.scala`'s
      // stdlib `error` is `Bottom(error(s.extract[String]))` and its `pipe#`
      // failure is `Bottom(... + rel.whnf)`, and BOTH FORCE.  Without the
      // rethrow the cancel would be caught there and RETURNED AS A VALUE, to
      // be printed into an error node by `json/Encode.scala`,
      // `json/Doc.scala` or `Pretty.ppRuntime` -- a job that "succeeded"
      // with the cancel's own text inside its document, or a 200 carrying a
      // bogus error node.
      //
      // `thrown` is `private[ermine]`, so this reaches it the way every
      // caller does: `Bottom.toString` is `"Bottom(" + thrown.toString + ")"`.
      val got = onOwnThread("wp6-bottom-thrown") {
        try {
          val t   = ErmineRuntime.Thunk(Prim(5))
          val bot = Bottom({ ErmineRuntime.swhnf(t); sys.error("wp6: unreachable") })
          armHere("wp6: inside a Bottom body")
          try { bot.toString; "returned a value" }
          catch { case _: Cancelled => "threw" }
        } finally disarmHere()
      }
      got match {
        case Left(e)  => falsified :| ("the probe threw: " + describe(Left(e)))
        case Right(v) => (v ?= "threw") :| ("Bottom.thrown " + v + " for a cancelled force")
      }
    } }
  }

  // ============================================ C. the two-phase watchdog

  /** A report whose evaluation LOOPS through `Runtime.swhnf` and builds no
    * datum of its own -- section 2.5's MEASURED `WpSpin`, which re-enters
    * with the very argument thunk it was given. */
  private def wpSpinSource(module: String): String =
    "module " + module + " where\n\nimport Builtin\nimport Int\nimport Json\nimport Layout.Doc\n\n" +
    "spin : Int -> Int\nspin n = spin n\n\n" +
    "report : Int -> Node\nreport n = rawWidget \"spin\" (spin n)\n"

  /** A report whose DOCUMENT holds a CYCLIC list: the stdlib's
    * `repeat a = t where t = a :: t`.  This is the shape that falsified the
    * cheaper placement of WP-6's check -- `json/Encode.scala`'s `spine`
    * walks it with `while (true) { Runtime.swhnf(cur) ... }`, and after the
    * first step every thunk it re-reads is already `Evaluated`, so
    * `swhnf`'s `case old =>` branch is never entered again. */
  private def wpCyclicSource(module: String): String =
    "module " + module + " where\n\nimport Builtin\nimport Int\nimport Json\n" +
    "import List using {repeat}\nimport Layout.Doc\n\n" +
    "report : Int -> Node\nreport n = rawWidget \"cyc\" (repeat n)\n"

  /** Every `ermine/preview/stuck` this bench ever saw, of either polarity.
    * Read after `stop()`, when nothing can send another frame. */
  private def stuckNotes(b: Bench): List[Json] = b.sightings("ermine/preview/stuck")

  /** The cancel flag, as a string, for a label. */
  private def flagNow: String = String.valueOf(ErmineRuntime.cancelArmedFor)

  /** STOP A LOOP NOTHING ELSE CAN STOP, by arming the flag by hand for the
    * preview thread -- which is exactly what the switch would have done.
    * Used only by the switch-OFF property, where by construction nothing
    * else ends the evaluation and a leaked spinning thread would hold the
    * process-wide `Runner.evalLock` for the life of the test JVM.
    *
    * IDEMPOTENT, so that I4's rule can hold: it is called once BEFORE the
    * verdict is built and once again from the property's `finally`, so an
    * exception raised while building the verdict cannot leak the thread.  A
    * job that has already ended is not re-armed; the disarm is
    * unconditional and identity-guarded. */
  private def stopLoop(b: Bench, t: Thread, ms: Long): Boolean =
    if (t eq null) false
    else if (!b.preview.isStuck) { ErmineRuntime.disarmCancel(t); true }
    else {
      ErmineRuntime.armCancel(t, new Cancelled("wp6: the property's own teardown", false))
      val ok = awaitIdle(b, ms)
      ErmineRuntime.disarmCancel(t)
      ok
    }

  /** A bounded wait for the preview thread to let go of a job, used only by
    * the switch-OFF property's teardown. */
  private def awaitIdle(b: Bench, ms: Long): Boolean = {
    val deadline = System.currentTimeMillis + ms
    while (b.preview.isStuck && System.currentTimeMillis < deadline) Thread.sleep(20L)
    !b.preview.isStuck
  }

  property("C: with the switch ON a looping render is CANCELLED -- 500 with no stuck marker, no stuck notification, and the next render boots") = secure {
    previewLock.synchronized { timed("the cancel takes") {
      val b = new Bench(warm = false)
      try {
        // 800 ms, not 300: the watchdog's clock also covers the file read
        // and header parse that happen BEFORE the boot bracket, and a busy
        // machine can make those slow.  The grace is generous so that
        // phase 2b cannot win a race this property is not about.
        b.preview.cancelOnTimeout = true
        b.preview.timeoutMillis   = 800L
        b.preview.graceMillis     = 5000L
        val spin  = writeFixture("WpSpinCancel", wpSpinSource("WpSpinCancel"))
        val after = writeFixture("WpAfterCancel", wpSimple("WpAfterCancel", 5))
        b.render(1, spin, "report", "1", 601)
        // THE DISPATCH THREAD IS UNTOUCHED while the preview loops: a
        // synchronous request it serves itself is answered meanwhile.
        b.request(2, "wp5/ping", Json.Null)
        val pong  = b.answer(2, 120000L)
        val a1    = b.answer(1, 180000L)
        val flag  = flagNow
        val boots1 = b.boots
        // THE FOLLOW-UP RENDER IS NOT THE CASE UNDER TEST, so it runs with
        // NO WATCHDOG (`timeoutMillis = 0` is the documented off switch).
        // MEASURED, not precautionary: with the deliberately tiny deadline
        // still set, the combined run -- `TestRunner`, `TestSchema` and
        // `TestJson` in the same JVM, all taking the PROCESS-WIDE
        // `Runner.evalLock` -- had this render wait for the lock past the
        // deadline and be CANCELLED itself, and the property failed saying
        // so ("the render after the recovery answered ... was CANCELLED").
        // The deadline is right for the job under test and wrong for the
        // control that follows it.
        b.preview.timeoutMillis = 0L
        // THE SESSION IS GONE, so this one boots a fresh one.
        b.render(3, after, "report", "1", 602)
        val a2     = b.answer(3, 180000L)
        val boots2 = b.boots
        val stopped = b.stop()
        val notes   = stuckNotes(b)
        (stopped :| "the bench's threads did not stop") &&
          ((statusOf(a1) ?= Some(500)) :| ("the cancelled render answered " + show(a1))) &&
          (msgOf(a1).exists(_.contains("evaluation did not finish after")) :|
            ("its message: " + show(a1))) &&
          (msgOf(a1).exists(_.contains("CANCELLED")) :|
            ("the message does not say the evaluation was cancelled: " + show(a1))) &&
          ((genOf(a1) ?= Some(601)) :| ("it must still echo the generation: " + show(a1))) &&
          ((!hasStuckKey(a1)) :|
            ("a CANCELLED render carries a stuck marker: " + show(a1))) &&
          ((notes ?= Nil) :|
            ("a cancel that succeeded sent an ermine/preview/stuck: " +
             notes.map(Json.print).mkString(" | "))) &&
          ((pong flatMap (_ / "result") flatMap (_.str) ?= Some("pong")) :|
            ("the dispatch thread stopped answering while the preview looped: " + show(pong))) &&
          ((flag ?= "null") :| ("the cancel flag was left armed: " + flag)) &&
          ((okOf(a2) ?= Some(true)) :| ("the render after the cancel answered " + show(a2))) &&
          ((boots2 ?= boots1 + 1) :|
            ("the session was not discarded: boots went " + boots1 + " -> " + boots2))
      } finally b.stop()
    } }
  }

  property("C: with the switch ON a job the cancel cannot reach falls back to today's stuck state, and the flag is clear before it resumes") = secure {
    previewLock.synchronized { timed("the cancel does not take") {
      // THE SLOW-SCAN CASE.  The job is held in `beforeJob`, which is not an
      // evaluation at all: it never calls `Runtime.swhnf`, so the cancel has
      // nothing to act on -- exactly like a loop inside one primitive, the
      // relational row loop, a JDBC scan, or a thread parked in
      // `future.get`.  Phase 2b must therefore fall back to today's
      // behaviour, and -- the conjunct that matters most -- it must CLEAR
      // the flag first, so that the job which was merely slow completes
      // normally when it resumes.
      val b = new Bench(warm = false)
      val started  = new java.util.concurrent.CountDownLatch(1)
      val release  = new java.util.concurrent.CountDownLatch(1)
      val flagSeen = new java.util.concurrent.atomic.AtomicReference[String]("(the job never resumed)")
      try {
        b.preview.cancelOnTimeout = true
        b.preview.timeoutMillis   = 300L
        b.preview.graceMillis     = 300L
        b.preview.beforeJob = {
          case r: Preview.Render if r.req.generation == Json.num(611) =>
            started.countDown()
            release.await(180L, java.util.concurrent.TimeUnit.SECONDS)
            flagSeen.set(String.valueOf(ErmineRuntime.cancelArmedFor))
          case _ => ()
        }
        val slow = writeFixture("WpSlowScan", wpSimple("WpSlowScan", 6))
        b.render(1, slow, "report", "1", 611)
        val inFlight = started.await(180L, java.util.concurrent.TimeUnit.SECONDS)
        val a1    = b.answer(1, 120000L)
        val rise  = stuckNote(b, true, 60000L)
        // Released only once the FALLBACK has happened, so the order is a
        // fact and not a race: `{stuck: true}` is sent by `fireStuck`, which
        // phase 2b reaches only after it has cleared the flag.
        release.countDown()
        val fall   = stuckNote(b, false, 180000L)
        val boots1 = b.boots
        // THE FOLLOW-UP RENDER IS NOT THE CASE UNDER TEST, so it runs with
        // NO WATCHDOG (`timeoutMillis = 0` is the documented off switch).
        // MEASURED, not precautionary: with the deliberately tiny deadline
        // still set, the combined run -- `TestRunner`, `TestSchema` and
        // `TestJson` in the same JVM, all taking the PROCESS-WIDE
        // `Runner.evalLock` -- had this render wait for the lock past the
        // deadline and be CANCELLED itself, and the property failed saying
        // so ("the render after the recovery answered ... was CANCELLED").
        // The deadline is right for the job under test and wrong for the
        // control that follows it.
        b.preview.timeoutMillis = 0L
        b.render(2, slow, "report", "1", 612)
        val a2     = b.answer(2, 180000L)
        val boots2 = b.boots
        val stopped = b.stop()
        (inFlight :| "the render never reached the preview thread") &&
          ((statusOf(a1) ?= Some(500)) :| ("the fallback answered " + show(a1))) &&
          ((stuckOf(a1) ?= Some(true)) :|
            ("the fallback's answer carries no stuck marker: " + show(a1))) &&
          (msgOf(a1).exists(_.contains("the preview is stuck")) :|
            ("it is not the watchdog's own text: " + show(a1))) &&
          (rise.isDefined :| "no ermine/preview/stuck {stuck:true} was sent by the fallback") &&
          ((flagSeen.get ?= "null") :|
            ("the job resumed with the cancel still armed: " + flagSeen.get)) &&
          (fall.isDefined :| "the released job never announced the recovery") &&
          ((okOf(a2) ?= Some(true)) :| ("the render after the recovery answered " + show(a2))) &&
          ((boots2 ?= boots1) :|
            ("the session was discarded although the job returned OK: boots " +
             boots1 + " -> " + boots2)) &&
          (stopped :| "the bench's threads did not stop")
      } finally {
        b.preview.beforeJob = _ => ()
        release.countDown()
        b.stop()
      }
    } }
  }

  property("C: with the switch OFF the watchdog takes today's path and never arms the flag") = secure {
    previewLock.synchronized { timed("the switch off") {
      val b = new Bench(warm = false)
      val onThread = new java.util.concurrent.atomic.AtomicReference[Thread](null)
      try {
        b.preview.cancelOnTimeout = false      // the shipped default, said out loud
        b.preview.timeoutMillis   = 800L
        b.preview.graceMillis     = 5000L
        // The preview thread, captured through the seam that already runs on
        // it.  It is needed ONLY by the teardown below.
        b.preview.beforeJob = { case _ => onThread.set(Thread.currentThread) }
        val spin = writeFixture("WpSpinStuck", wpSpinSource("WpSpinStuck"))
        b.render(1, spin, "report", "1", 621)
        val a1   = b.answer(1, 180000L)
        val rise = stuckNote(b, true, 60000L)
        val flag = flagNow
        val log  = b.sink.result()
        val armedLine = log.exists(_.contains("cancelling the evaluation"))
        // TEARDOWN FIRST, VERDICT AFTERWARDS (I4 of the stage 1 review).  It
        // uses the very mechanism under test -- deliberately, and said out
        // loud -- because with the switch off NOTHING else stops this loop.
        // It runs BEFORE the verdict is built and AGAIN from the `finally`
        // below, so that an exception raised while building the verdict
        // cannot leave a spinning preview thread holding the process-wide
        // `Runner.evalLock` for the rest of the JVM.
        val ended = stopLoop(b, onThread.get, 60000L)
        val verdict =
          ((statusOf(a1) ?= Some(500)) :| ("the watchdog answered " + show(a1))) &&
            ((stuckOf(a1) ?= Some(true)) :|
              ("with the switch off the answer must carry the stuck marker: " + show(a1))) &&
            (msgOf(a1).exists(_.contains("the preview is stuck")) :|
              ("it is not the watchdog's own text: " + show(a1))) &&
            (rise.isDefined :| "no ermine/preview/stuck {stuck:true} was sent") &&
            ((flag ?= "null") :| ("the switch is off and the cancel flag was armed: " + flag)) &&
            ((!armedLine) :|
              ("the switch is off and the watchdog logged a cancel: " +
               log.filter(_.contains("WATCHDOG")).mkString(" | ")))
        verdict && (ended :| "TEARDOWN: the looping render could not be stopped; a spinning " +
                             "preview thread holding Runner.evalLock is left in this JVM")
      } finally {
        b.preview.beforeJob = _ => ()
        // I4: idempotent, and the catch-all for a throw anywhere above.
        stopLoop(b, onThread.get, 30000L)
        b.stop()
      }
    } }
  }

  property("C: a $/cancelRequest in flight still answers -32800 and does NOT discard the session") = secure {
    previewLock.synchronized { timed("the user cancel") {
      // WP-6 DELIBERATELY DOES NOT MAKE A USER CANCEL INTERRUPT (section
      // 14's WP-6 row): the extension sends none today, a discard costs a
      // boot, and the watchdog covers the case that matters.  So this is
      // stage A's behaviour, unchanged, with the switch ON.
      val b = new Bench(warm = false)
      val started = new java.util.concurrent.CountDownLatch(1)
      val release = new java.util.concurrent.CountDownLatch(1)
      try {
        b.preview.cancelOnTimeout = true       // and it must still not fire
        b.preview.beforeJob = {
          case r: Preview.Render if r.req.generation == Json.num(631) =>
            started.countDown()
            release.await(180L, java.util.concurrent.TimeUnit.SECONDS)
          case _ => ()
        }
        val simple = writeFixture("WpUserCancel", wpSimple("WpUserCancel", 7))
        b.render(1, simple, "report", "1", 631)
        val inFlight = started.await(180L, java.util.concurrent.TimeUnit.SECONDS)
        b.notifyServer("$/cancelRequest", Json.obj("id" -> Json.num(1)))
        // The cancel is only MARKED; the job runs to completion and its
        // ANSWER is replaced.
        Thread.sleep(200L)
        val flagWhileMarked = flagNow
        release.countDown()
        val a1     = b.answer(1, 180000L)
        val boots1 = b.boots
        b.render(2, simple, "report", "1", 632)
        val a2     = b.answer(2, 180000L)
        val boots2 = b.boots
        val stopped = b.stop()
        (inFlight :| "the render never reached the preview thread") &&
          ((errCode(a1) ?= Some(-32800)) :| ("the cancelled render answered " + show(a1))) &&
          ((flagWhileMarked ?= "null") :|
            ("a user cancel armed the evaluator's cancel flag: " + flagWhileMarked)) &&
          ((okOf(a2) ?= Some(true)) :| ("the render after it answered " + show(a2))) &&
          ((boots2 ?= boots1) :|
            ("a user cancel discarded the session: boots " + boots1 + " -> " + boots2)) &&
          (stopped :| "the bench's threads did not stop")
      } finally {
        b.preview.beforeJob = _ => ()
        release.countDown()
        b.stop()
      }
    } }
  }

  property("C: a document holding a CYCLIC list is cancelled too -- the Encode.spine case") = secure {
    previewLock.synchronized { timed("the cyclic document") {
      // THE PROPERTY THE CHEAPER PLACEMENT FAILS.  A check inside `swhnf`'s
      // `case old =>` branch never fires here: every thunk this walk
      // re-reads is already `Evaluated`.
      val b = new Bench(warm = false)
      try {
        b.preview.cancelOnTimeout = true
        b.preview.timeoutMillis   = 800L
        b.preview.graceMillis     = 5000L
        val cyc = writeFixture("WpCyclic", wpCyclicSource("WpCyclic"))
        b.render(1, cyc, "report", "1", 641)
        val a1   = b.answer(1, 180000L)
        val flag = flagNow
        val stopped = b.stop()
        val notes   = stuckNotes(b)
        (stopped :| "the bench's threads did not stop") &&
          ((statusOf(a1) ?= Some(500)) :| ("the cyclic render answered " + show(a1))) &&
          (msgOf(a1).exists(_.contains("CANCELLED")) :|
            ("the cyclic document was not cancelled: " + show(a1))) &&
          ((!hasStuckKey(a1)) :| ("a CANCELLED render carries a stuck marker: " + show(a1))) &&
          ((notes ?= Nil) :|
            ("a cancel that succeeded sent an ermine/preview/stuck: " +
             notes.map(Json.print).mkString(" | "))) &&
          ((flag ?= "null") :| ("the cancel flag was left armed: " + flag))
      } finally b.stop()
    } }
  }
}
