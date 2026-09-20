package com.clarifi.reporting.ermine.lsp

import java.nio.file.Path

import com.clarifi.reporting.backends.{ Backends, Runners }
import com.clarifi.reporting.ermine.json.{ Request => RunRequest, Runner, RunnerConfig }
import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.session.Session
import scalaparsers.Supply

/** THE PREVIEW: one daemon thread owning a second, render-only Ermine
  * session, and the queue the language server posts work to
  * (tracker/JSON-WIDGET-PLAYGROUND.md §2.3, §2.4, §2.5, §3, §4).
  *
  * WP-5 STAGE A builds the thread, the queue, `ermine/render`,
  * `$/cancelRequest` and `invalidate`.  The watchdog, the document-size cap,
  * `ermine/schema {binding}`, `ermine/preview/reports` and work-done progress
  * are stage B; the launcher's heap cap is stage C; profiles, `connect` and
  * `disconnect` are WP-13 and WP-14.  Each of those has a named seam below.
  *
  * WHICH THREAD TOUCHES WHAT -- the whole of the concurrency argument:
  *
  * | state | thread | how it is safe |
  * |---|---|---|
  * | `runner`, `delegating`, `rootsInUse`, `headerSupply` | THE PREVIEW THREAD ALONE | never read or written anywhere else; no lock, because there is no second reader.  `SessionEnv` is not thread-safe and this is the whole reason the thread exists (§2.3) |
  * | `jobs`, `inFlight`, `cancelledInFlight`, `stopping` | dispatch thread posts and cancels, preview thread consumes | every access is inside `lock.synchronized`; the monitor is also the wait/notify channel.  Nothing that can block on the client -- an `Rpc.Answer`, a `notify` -- is ever called while holding it |
  * | `dirtyGeneration` | bumped by the dispatch thread, read by both | an `AtomicLong`.  It is the `stale` hint of §2.5 and nothing else depends on its value |
  * | the resident session | THE DISPATCH THREAD ALONE | this file never touches it.  `moduleRoots` is a function the server supplies; it is SAFELY PUBLISHED by the queue's monitor, not by anything about the field itself -- the dispatch thread writes `Resident.moduleRoots` at `initialize`, and every render that reads it was ENQUEUED (under `lock`) after that write and DEQUEUED (under `lock`) by this thread, which is the happens-before edge.  A later write of that field is racy in the same way `initialize` itself is, and costs one boot with stale roots |
  *
  * The preview thread answers requests through `Rpc.Answer` (legal from any
  * thread, exactly once) and sends notifications through `Server.notify`
  * (legal from any thread since WP-1's synchronised `Wire.send`).  It never
  * calls `Server.ask`: that is dispatch-thread-only (§2.3, resolution 6e).
  *
  * THE THREAD CANNOT END ABNORMALLY, and a dead thread cannot swallow a
  * request: see `loop`, `runJob` and `alive`.
  *
  * EVERY LINE THIS OBJECT LOGS IS SCRUBBED.  Rule A5 (§8.1) covers what a
  * log sees as well as what a client sees, so the server's sink arrives as
  * `rawLog` and the only `log` in scope is the scrubbing wrapper below.  A
  * line added by stage B or WP-13 is scrubbed whether or not its author
  * remembered to think about it.
  */
final class Preview(moduleRoots: () => List[String],
                    notify: (String, Json) => Unit,
                    rawLog: String => Unit) {

  import Preview._

  /** The ONLY `log` in scope in this file, and the reason the constructor's
    * parameter is called `rawLog`: rule A5 is structural here rather than a
    * thing each call site has to remember (M2 of the WP-5 stage A review --
    * three lines had forgotten). */
  private def log(s: String): Unit = rawLog(scrubUrls(s))

  // ------------------------------------------------------------------ queue

  /** The monitor over the queue.  Nothing under it can block on the client:
    * an answer and a notification both reach `Wire.send`, whose monitor a
    * slow client holds for the length of a document, and taking that while
    * holding this one would let a slow client stall `$/cancelRequest`. */
  private val lock = new Object
  private val jobs = new scala.collection.mutable.Queue[Job]
  /** The `Render` the preview thread is working on, or `null`.  A NULLABLE
    * FIELD and not an `Option` on purpose (delta review item 1): `takeJob`
    * must record the render it has just removed from `jobs` with a write
    * that CANNOT THROW, or an `OutOfMemoryError` on the `Some` would leave a
    * render that is neither in the queue nor named anywhere, which nothing
    * could then answer.  A reference store is that write. */
  private var inFlight: Render  = null
  private var cancelledInFlight = false
  private var stopping          = false

  /** Whether the preview thread is still consuming the queue.  `loop`'s
    * outermost `finally` clears it -- however the thread ended, including by
    * an `Error` that escaped every guard -- BEFORE draining, so a render is
    * either enqueued and answered by that drain or refused by `render`, and
    * is never left in a queue with no consumer (M1 of the stage A review).
    * Volatile for the read in `render`; the write is ordered against the
    * drain by `lock`. */
  @volatile private var alive = true

  /** Whether the render in flight has already been handed to its
    * `Rpc.Answer` -- set by `finish` BEFORE the send, mirroring the one-shot
    * token `Rpc.deferredRequest` takes before ITS send, so a send that died
    * on a broken pipe counts as spent (it is: that scaladoc says such a
    * request is not retried).  Preview thread only; reset when a `Render` is
    * dequeued. */
  private var answeredInFlight = false

  /** THE LAST-RESORT ANSWER, allocated ONCE, here, at construction.  The
    * path that uses it (`runJob`'s `finally`) is the path on which building
    * a §4 failure object has ALREADY failed -- a second `OutOfMemoryError`,
    * an exception whose own `getMessage` throws -- so it must allocate
    * nothing at all.  It is a JSON-RPC error rather than `{ok: false, ...}`
    * because §4's shape needs the request's `generation`, which cannot be
    * pre-allocated, and because a handler that died is honestly an internal
    * error and not a render outcome. */
  private val crashAnswer: Either[(Int, String), Json] =
    Left((Rpc.InternalError, "the preview failed"))

  /** §2.5's `stale` counter: bumped when an `invalidate` is POSTED, not when
    * it runs.  Posting is the dispatch thread's, running is the preview
    * thread's, and between the two sits the render this counter exists to
    * flag -- were it bumped by the job, a single-threaded queue could never
    * move it during a render and `stale` would be dead code. */
  private val dirtyGeneration = new java.util.concurrent.atomic.AtomicLong(0L)

  /** TEST SEAM (stage A's group-D properties).  Called on the preview
    * thread with each job just after it leaves the queue and BEFORE any of
    * its work, so a test can hold a render in flight with a latch instead of
    * a sleep.  Blocking here holds NO lock -- not `lock`, not the
    * process-wide `Runner.evalLock` -- so a held render freezes this thread
    * and nothing else, which is precisely what the "the dispatch thread is
    * never blocked by a render" property has to observe.  Never set in
    * product code.
    *
    * `private[reporting]` and not `private[lsp]`: the properties that use it
    * live in `com.clarifi.reporting.TestLspRobustness`, which `private[lsp]`
    * would shut out.  `@volatile` because it is written on a property's
    * thread and read on the preview thread. */
  @volatile private[reporting] var beforeJob: Job => Unit = _ => ()

  // ------------------------------------------ the render session (preview thread)

  private var runner: Runner              = null
  private var delegating: DelegatingRun   = null
  private var rootsInUse: List[String]    = Nil
  /** LAZY, and it matters beyond this object.  `Supply.create` advances a
    * PROCESS-GLOBAL block counter by 1024 (`scalaparsers/Supply.scala`), and
    * metavariable ids are what several diagnostics print and at least one
    * orders by (tracker/LSP-STALENESS.md, ROBUST-1), so a `Preview` that
    * allocates a block it never uses shifts every later id in the JVM for
    * nothing.  Eager, it cost the unforked `core/test` JVM one block per
    * `Preview` constructed, including the two the crash properties build and
    * never render with.  It is also what §2.4's "lazy: nothing before the
    * first render" says: a preview nobody renders with should touch nothing
    * at all.  Preview thread only, so a `lazy val`'s one-time initialisation
    * is never contended. */
  private lazy val headerSupply: Supply   = Supply.create

  // -------------------------------------------------------- the dispatch side

  /** `ermine/render` (§4), from the dispatch thread.  Parses the request,
    * enqueues it, and -- outside the lock -- answers whatever that displaced
    * with `-32800` (§2.5, "latest wins").
    *
    * THREE OUTCOMES, and every one of them ANSWERS SOMETHING.  A request
    * this method neither enqueues nor answers is a client waiting for ever,
    * which is the failure M1 of the stage A review found: the queue is
    * refused after `shutdown` (`-32800`, shutdown's own wording -- S1) and
    * refused again if the preview thread is not running at all (an internal
    * error, because a dead consumer is not a cancellation and the client
    * should see the difference). */
  def render(id: Json, params: Json, answer: Rpc.Answer): Unit =
    RenderRequest.parse(params) match {
      case Left(why) =>
        answer(Right(failure(params / "generation" getOrElse Json.Null, 400, why, None)))
      case Right(req) =>
        val job = Render(id, req, dirtyGeneration.get, answer)
        val (displaced, code, why) = lock.synchronized {
          if (!alive)
            (List(job), Rpc.InternalError, "the preview thread is not running")
          else if (stopping)
            (List(job), Rpc.RequestCancelled, "the preview is shutting down")
          else {
            // §2.5 allows ONE queued render, so this removes at most one --
            // but it removes and answers every one it finds rather than the
            // first, because a request that is dropped without an answer is
            // a request the client waits on for ever.
            val old = jobs.dequeueAll { case _: Render => true; case _ => false }
            jobs.enqueue(job)
            lock.notifyAll()
            (old.toList.collect { case r: Render => r }, Rpc.RequestCancelled,
             "replaced by a newer render")
          }
        }
        displaced foreach { r =>
          log("preview: render " + Json.print(r.id) + ": " + why)
          r.answer(Left((code, why)))
        }
    }

  /** `$/cancelRequest` (§2.5).  A QUEUED render is removed and answered
    * `-32800`; the IN-FLIGHT one is only MARKED -- the work is not
    * interrupted (WP-6 does that) and its eventual answer is replaced.  A
    * cancel that arrives during a boot marks the render whose job the boot
    * is part of, so it is honoured when the boot ends, exactly as §2.5 asks,
    * with no boot-specific code. */
  def cancel(id: Json): Unit = {
    val queued = lock.synchronized {
      val hits = jobs.dequeueAll { case r: Render => r.id == id; case _ => false }
      if (hits.isEmpty && (inFlight ne null) && inFlight.id == id) cancelledInFlight = true
      hits.toList.collect { case r: Render => r }
    }
    queued foreach { r =>
      log("preview: queued render " + Json.print(id) + " cancelled")
      r.answer(Left((Rpc.RequestCancelled, "cancelled")))
    }
  }

  /** §3 step 3: what `Main.afterReload` posts, on every reload path -- the
    * watcher's and the `ermine.reloadModules` command's.  A no-op before the
    * preview has booted: the job runs on the preview thread and finds no
    * session, which is also the only race-free place to ask. */
  def invalidate(paths: Set[Path]): Unit = if (paths.nonEmpty) {
    val ps = paths map Session.normalize
    lock.synchronized {
      if (alive && !stopping) {
        // The bump is INSIDE the guard: with no consumer nothing will ever
        // apply this invalidation, and no render can complete to be flagged
        // by it either -- `render` refuses them -- so moving the counter
        // would only mislead whatever reads it next.
        dirtyGeneration.incrementAndGet()
        // COALESCED (S5), so that no queue in this design is unbounded: a
        // save storm can post invalidations faster than a slow render
        // consumes them, and each one is only a set of paths.  The union
        // goes into the EARLIEST pending invalidate's slot, never a later
        // one, so an invalidation is applied no LATER than the literal
        // queue order would have applied it.  That is the direction that is
        // safe: a render then sees a module scrubbed slightly earlier and
        // reloads it from disk -- fresher, which the mtime scan at its own
        // head would have done anyway -- whereas moving an invalidation
        // later would let a render answer from a module it should already
        // have forgotten.  `dirtyGeneration` is bumped per POST, not per
        // job, so coalescing costs no `stale` flag; the `invalidated`
        // notification still names the union.
        //
        // Coalescing on every post keeps the invariant "at most one
        // `Invalidate` in the queue", which is why one `indexWhere` is the
        // whole search.
        jobs.indexWhere { case _: Invalidate => true; case _ => false } match {
          case -1 => jobs.enqueue(Invalidate(ps))
          case i  => jobs(i) match {
            case Invalidate(q) => jobs(i) = Invalidate(q ++ ps)
            case _             => ()
          }
        }
        lock.notifyAll()
      }
    }
  }

  /** Discard the render session: the next render boots a new one.  §7.2 step
    * 4 (a profile or roots switch) and WP-6's cancel both want this. */
  def discard(): Unit = post(DiscardSession)

  /** End the thread.  Queued renders are answered `-32800`; an in-flight one
    * finishes and is answered normally.  Idempotent. */
  def shutdown(): Unit = {
    val left = lock.synchronized {
      stopping = true
      lock.notifyAll()
      jobs.dequeueAll(_ => true)
    }
    left foreach { case r: Render => r.answer(Left((Rpc.RequestCancelled, "the preview is shutting down")))
                   case _         => () }
  }

  /** Join the preview thread, for a test that must not leave one behind.
    * Answers whether it ended within `millis`. */
  private[reporting] def awaitStopped(millis: Long): Boolean = {
    thread.join(millis)
    !thread.isAlive
  }

  /** How many renders are waiting.  §2.5 allows at most one; the group-D
    * cancel property reads it to assert the queue is EMPTY. */
  private[reporting] def queuedRenders: Int =
    lock.synchronized(jobs.count { case _: Render => true; case _ => false })

  /** How many `Invalidate` jobs are waiting.  S5's invariant is that this is
    * never more than one; a group-D property reads it. */
  private[reporting] def queuedInvalidates: Int =
    lock.synchronized(jobs.count { case _: Invalidate => true; case _ => false })

  /** Whether the preview thread is still consuming.  A group-D property
    * reads it; nothing in the product branches on it. */
  private[reporting] def threadAlive: Boolean = thread.isAlive && alive

  private def post(j: Job): Unit = lock.synchronized {
    if (alive && !stopping) { jobs.enqueue(j); lock.notifyAll() }
  }

  // ------------------------------------------------------- the preview thread

  /** Run `body` and swallow whatever it throws.  THE CRASH PATH MUST NOT
    * HAVE A CRASH PATH (M1): the handler for a failed job logs, builds a
    * message and answers, and each of those three can itself throw -- the
    * logger on a closed file, `Wire.send` on a broken pipe, the message
    * builder on a second `OutOfMemoryError` -- and one of them failing must
    * not cost the others.  Nothing is logged here: logging is one of the
    * things that can throw.
    *
    * By-name, so one `Function0` is allocated per call.  That is fine
    * everywhere this is used and NOT fine on `runJob`'s last-resort answer,
    * which is written out as an inline `try` for exactly that reason. */
  private def guard(body: => Unit): Unit =
    try body catch { case _: Throwable => () }

  /** The next job, or None when the thread should stop.  An interrupt is
    * read as "stop": the flag is put back so that whoever interrupted can
    * see it, and the loop ends through the same `finally` a `shutdown` ends
    * through, which answers everything still queued.
    *
    * THE WINDOW THIS OPENS, and what closes it (delta review item 1): a
    * `Render` is out of `jobs` from `dequeue` onwards but does not reach
    * `runJob` -- where the last-resort answer lives -- until this method
    * RETURNS, and the `Some` it returns is an allocation that can fail.  So
    * the render is recorded in `inFlight` first, by a reference store that
    * cannot throw, and `rescueInFlight` answers whatever is left there.
    * What remains uncoverable, stated rather than hidden: a throw INSIDE
    * `dequeue` itself, which either leaves the job in the queue (the drain
    * takes it) or tears the deque mid-mutation, and nothing could name the
    * element then. */
  private def takeJob(): Option[Job] =
    lock.synchronized {
      try while (jobs.isEmpty && !stopping) lock.wait()
      catch { case _: InterruptedException => stopping = true; Thread.currentThread.interrupt() }
      if (stopping) None
      else {
        val j = jobs.dequeue()
        j match {
          case r: Render => inFlight = r; cancelledInFlight = false; answeredInFlight = false
          case _         => ()
        }
        Some(j)
      }
    }

  /** ONE job, and it cannot throw.  Three layers, innermost first:
    *  1. the job itself;
    *  2. the crash handler, every step of it separately guarded;
    *  3. a `finally` that answers the render if nothing above did, with the
    *     PRE-ALLOCATED `crashAnswer` and no allocation at all -- because the
    *     case it exists for is the one where allocating is what failed.
    *     `Rpc.Answer` is one-shot, so a redundant call would be harmless,
    *     but `answeredInFlight` avoids it anyway: `Rpc.deferredRequest` logs
    *     "second answer ... ignored", and a line of that per successful
    *     render is noise the log does not need. */
  private def runJob(job: Job): Unit =
    try {
      try {
        beforeJob(job)
        job match {
          case r: Render        => doRender(r)
          case Invalidate(ps)   => doInvalidate(ps)
          case DiscardSession   => discardSession("asked to")
        }
      } catch {
        case e: Throwable =>
          guard(log("preview: job crashed: " + Rpc.stackTrace(e)))
          job match {
            case r: Render => guard(finish(r, failure(r.req.generation, 500,
                                "the preview failed: " + messageOf(e), None)))
            case _         => ()
          }
      }
    } finally {
      job match {
        case r: Render =>
          if (!answeredInFlight) {
            // SET BEFORE the answer, as `finish` does and for the same
            // reason: if the clear below could not run, a later
            // `rescueInFlight` would otherwise answer this render a second
            // time -- harmless on the wire (`Rpc.Answer` is one-shot) but a
            // spurious "second answer ... ignored" line in the log.
            answeredInFlight = true
            try r.answer(crashAnswer) catch { case _: Throwable => () }
          }
        case _ => ()
      }
      try lock.synchronized { inFlight = null } catch { case _: Throwable => () }
    }

  /** The preview thread's whole life.  `runJob` guards everything of its
    * own, so the catch below is for the QUEUE MACHINERY failing -- an
    * `Error` out of `dequeue`, an `OutOfMemoryError` between the two -- and
    * the thread survives it, because a dead thread is a queue with no
    * consumer.
    *
    * IT DOES NOT SPIN.  A failure that repeats `MaxLoopFailures` times with
    * no job in between is not transient, and a thread that ends is better
    * than one that burns a core for the life of the editor; `alive` then
    * turns every later render into an answered error rather than a silent
    * enqueue.  One success resets the count.
    *
    * THE OUTERMOST `finally` IS THE CONTRACT: however this thread ends --
    * `shutdown`, an interrupt, the failure bound above, an `Error` that
    * escaped every guard -- `alive` is false before anything else happens,
    * and everything still queued is answered. */
  private def loop(): Unit = {
    try {
      var running  = true
      var failures = 0
      while (running) {
        try takeJob() match {
          case None      => running = false
          case Some(job) => runJob(job); failures = 0
        } catch {
          case e: Throwable =>
            failures += 1
            // FIRST, before anything that can fail again: a throw out of
            // `takeJob` may have left a render out of the queue and only
            // named by `inFlight` (delta review item 1).
            rescueInFlight()
            guard(log("preview: the job loop failed (" + failures + " in a row): " + Rpc.stackTrace(e)))
            if (failures >= MaxLoopFailures) running = false
        }
      }
    } finally {
      // A volatile write of a constant: it cannot itself throw, which is why
      // it comes before the two guarded steps rather than inside them.
      alive = false
      guard(lock.synchronized { stopping = true })
      guard(drainOnDeath())
      guard(log("preview: thread stopped"))
    }
  }

  /** Answer the render `inFlight` still names, if nothing has answered it,
    * and forget it (delta review item 1).  The field is taken and cleared
    * UNDER the lock and answered OUTSIDE it, like every other answer in this
    * file; the only allocation on the path is none -- a local reference, the
    * pre-allocated `crashAnswer`, and inline `try`s rather than `guard`'s
    * by-name closure, because the case this exists for is an allocation
    * having already failed.
    *
    * `answeredInFlight` is the preview thread's own field and both callers
    * are on that thread, so reading it here is not a race. */
  private def rescueInFlight(): Unit = {
    var orphan: Render = null
    try lock.synchronized {
      if (!answeredInFlight) orphan = inFlight
      inFlight = null
    } catch { case _: Throwable => () }
    if (orphan ne null)
      try orphan.answer(crashAnswer) catch { case _: Throwable => () }
  }

  /** Answer everything still queued once this thread has stopped consuming,
    * and the one that was in flight when it stopped.  `alive` is already
    * false, so `render` refuses from here on and the queue cannot grow
    * behind this. */
  private def drainOnDeath(): Unit = {
    rescueInFlight()
    val left = lock.synchronized { jobs.dequeueAll(_ => true) }
    left foreach {
      case r: Render => try r.answer(crashAnswer) catch { case _: Throwable => () }
      case _         => ()
    }
  }

  /** One render, §4's two answer shapes.  In order: the root set and the
    * session it implies, the mtime scan, the uri, the connection, the
    * document. */
  private def doRender(r: Render): Unit = {
    // N3: normalised ONCE, here, so that the module lookup, the inferred
    // root and the discard key below all speak of the same spelling.
    val path  = Documents.pathFor(r.req.uri) map Session.normalize
    val roots = rootSet(r.req, path)
    ensureSession(roots) match {
      case Left(why) => finish(r, failure(r.req.generation, 500, why, None))
      case Right(()) =>
        scanForMovedFiles()
        path match {
          case None =>
            finish(r, failure(r.req.generation, 400, "not a file: URI: " + r.req.uri, None))
          case Some(p) => Session.moduleUnder(roots, p) match {
            case None =>
              finish(r, failure(r.req.generation, 404, "not under a module root", None))
            case Some(module) =>
              // §4 / §7.2: WP-13's `disconnect` leaves the delegate unset and
              // every render answers 503 until the extension connects again.
              // `DelegatingRun` would throw and `Runner.drive` would call it
              // 500, so the question is asked HERE, as its scaladoc asks.
              //
              // UNREACHABLE IN STAGE A, and therefore UNTESTED: the boot
              // wires a target and stage A has no `disconnect` to remove it,
              // so `connected` is true from the first render onwards.  This
              // is a WP-13 seam -- the first thing that makes it reachable
              // is the `disconnect` job, and that ticket owns the property
              // that pins the 503.
              if (!delegating.connected)
                finish(r, failure(r.req.generation, 503, "not connected", None))
              else {
                val body = "{\"" + RunRequest.Params + "\":" + Json.print(r.req.params) + "}"
                val out  = new java.lang.StringBuilder
                runner.renderText(module, r.req.binding, body, out) match {
                  case Left(e) =>
                    finish(r, failure(r.req.generation, e.status, scrubUrls(e.message), e.path))
                  case Right(_) => Json.parse(out.toString) match {
                    case Left(why) =>
                      finish(r, failure(r.req.generation, 500,
                        "the rendered document is not JSON: " + why, None))
                    case Right(doc) =>
                      finish(r, document(r.req.generation, doc, dirtyGeneration.get != r.dirtyAt))
                  }
                }
              }
          }
        }
    }
  }

  /** §3 steps 4 and 5.  The notification goes out only for a non-empty dirty
    * set, so a save of a file this session never loaded is silent. */
  private def doInvalidate(paths: Set[Path]): Unit =
    if (runner == null) log("preview: invalidate of " + paths.size + " path(s) before the boot; nothing to do")
    else {
      val dirty = runner.invalidate(paths)
      if (dirty.nonEmpty) {
        log("preview: invalidated " + dirty.toList.sorted.mkString(", "))
        notify("ermine/preview/invalidated",
               Json.obj("modules" -> Json.Arr(dirty.toList.sorted.map(Json.Str(_)))))
      }
    }

  /** §2.5, "Fresh files, whoever saved them": at the head of every render,
    * one `stat` per file THIS session loaded, and what moved is invalidated.
    * That is how a save from outside VS Code, or from a client with no
    * dynamic watcher (`Main.scala`'s `watch:` branch), reaches the preview.
    *
    * It does NOT send `ermine/preview/invalidated`: the render it is the
    * head of answers with the re-loaded document, so the notification would
    * only ask the extension for a second render of what it is about to be
    * handed.  §3 step 5's notification belongs to the POSTED invalidate,
    * whose modules nobody has re-rendered yet. */
  private def scanForMovedFiles(): Unit = {
    // ONE `evalLock` section for the scan AND the invalidation it implies
    // (N2: `Runner.invalidateStale`).  Two sections would leave a window in
    // which another runner's load could refresh a file this one had just
    // decided was stale, and scrubbing on that decision would be a scrub for
    // no reason.
    val dirty = runner.invalidateStale()
    if (dirty.nonEmpty)
      log("preview: file(s) moved on disk; invalidated " + dirty.toList.sorted.mkString(", "))
  }

  /** The roots of §2.4, in order and distinct: the resident's own, then the
    * report's inferred root, then the request's.
    *
    * EVERY ENTRY IS NORMALISED FIRST (N3).  `distinct` decides the set, and
    * the set is the discard key of §2.4 -- two spellings of one directory
    * (`/a/b` and `/a/./b`, a relative entry) would otherwise look like a
    * change of roots and throw away a booted session for nothing.
    * Absolutising also matters for the request's own entries: a relative one
    * would resolve against the server's working directory, which is the
    * checkout `bin/ermine-lsp` runs in.  `req.roots` arrive normalised from
    * `RenderRequest.parse`, which refuses the entries that cannot be.  A
    * resident root that cannot be made into a path is logged and dropped,
    * which is what `Main` does with the same value at `initialize`. */
  private def rootSet(req: RenderRequest, path: Option[Path]): List[String] =
    (moduleRoots().flatMap(normalRoot) ++ path.flatMap(inferredRoot).toList ++ req.roots).distinct

  private def normalRoot(r: String): Option[String] =
    try Some(Session.normalize(r).toString)
    catch { case e: Throwable => log("preview: module root dropped, not a path: " + r); None }

  /** The root a file's OWN module name implies: parse the header and walk up
    * one directory per extra segment, as `Resident.checkFile` does for a
    * check's siblings.  `p` is already absolute and normalised, so what
    * comes back is too.
    *
    * NONE, never a guess, in three cases: the file cannot be read; its
    * header cannot be parsed; or the module name has MORE segments than the
    * path has parent directories (`module A.B.C` in `/tmp`), where the walk
    * runs out and the loop's `d.isDefined` guard ends it empty.
    * `Resident.checkFile` falls back to the file's own directory in that
    * last case; the preview does not, because a guessed root puts the file
    * under a root under a WRONG module name and the render would then fail
    * with a message about the wrong module.  None leaves the other roots to
    * answer, and a 404 if none of them does. */
  private def inferredRoot(p: Path): Option[String] =
    try {
      val file     = Session.Filesystem(p.toString, exotic = true)
      val contents = file.contents
      implicit val su: Supply = headerSupply
      val (_, mh) = Session.parse(
        ModuleParsers.moduleHeader(file.defaultModuleName),
        ErParseState.mk(file.toString, contents, file.defaultModuleName))
      var d = Option(p.getParent)
      var i = mh.name.split('.').length - 1
      while (i > 0 && d.isDefined) { d = Option(d.get.getParent); i -= 1 }
      if (i > 0) None else d.map(_.toString)
    } catch { case e: Throwable =>
      log("preview: no root inferred for " + p + ": " + messageOf(e))
      None
    }

  /** The render session for `roots`, booting it if there is none and
    * discarding the one in hand if the root set moved (§2.4: roots are
    * immutable `RunnerConfig` fields).  A boot that FAILED is discarded
    * rather than kept: its failure is usually a broken file under a root,
    * and keeping it would answer the same 500 until the server restarts
    * even after the file is fixed. */
  private def ensureSession(roots: List[String]): Either[String, Unit] = {
    if (runner != null && rootsInUse != roots) discardSession("the root set changed")
    if (runner != null) Right(())
    else {
      val t0  = System.nanoTime
      val del = new DelegatingRun
      Backends.scannerFor(StageABackend, "default") match {
        case Left(why) => Left("no scanner for " + StageABackend + ": " + why)
        case Right(sc) =>
          // ================= THE BACKEND SEAM (WP-13 / WP-14) =================
          // Stage A wires the ONE backend `core/src/test/resources/doc/Sales.e`
          // needs: a local in-memory SQLite, opened per run by
          // `DB.Run`/`ThreadLocalRunDB` and holding nothing between renders.
          // The driver class is loaded HERE, inside the first render, which is
          // what "lazy boot: no profile read, no driver class, no connection
          // before then" (§2.4) means.
          //
          // WP-13 replaces these two lines with the `connect` job: the
          // profile's dialect picks the scanner through this same
          // `Backends.scannerFor`, `Class.forName(profile.driver)` and
          // `DriverManager.getConnection` open the connection, and
          // `Runners.fromPersistentConnection` becomes the delegate's target.
          // WP-14 adds `disconnect`/recycle, which CLOSE what `clear()`
          // returns.  Nothing else in this file knows what is behind the
          // delegate; the 503 above is the one place that asks.
          del.use(Runners.SQLite(StageAUrl))
          // ====================================================================
          val r = new Runner(RunnerConfig(roots = roots, run = del, scanner = sc))
          r.bootFailure match {
            case Some(why) =>
              log("preview: the render session did not boot: " + why)
              Left("the render session did not boot: " + scrubUrls(why))
            case None =>
              runner = r; delegating = del; rootsInUse = roots
              log(f"preview: render session booted in ${(System.nanoTime - t0) / 1e9}%.1fs over " +
                  (if (roots.isEmpty) "the classpath alone" else roots.mkString(", ")))
              Right(())
          }
      }
    }
  }

  private def discardSession(why: String): Unit = {
    if (runner != null) log("preview: discarding the render session (" + why + ")")
    // WP-14: the connection a `connect` opened is closed here, from what
    // `clear()` answers.  Stage A's target opens one connection per run and
    // closes it again, so there is nothing to close.
    if (delegating != null) delegating.clear()
    runner = null; delegating = null; rootsInUse = Nil
  }

  /** Answer one render, honouring an in-flight `$/cancelRequest` (§2.5: the
    * work was not interrupted, the ANSWER is replaced).  Outside `lock`,
    * because answering reaches `Wire.send`. */
  private def finish(r: Render, result: Json): Unit = {
    val cancelled = lock.synchronized(cancelledInFlight && (inFlight ne null) && inFlight.id == r.id)
    // BEFORE the send, mirroring the one-shot token `Rpc.deferredRequest`
    // takes before its own: a send that dies on a broken pipe has spent the
    // request, and `runJob`'s last-resort answer must not pretend otherwise.
    answeredInFlight = true
    if (cancelled) r.answer(Left((Rpc.RequestCancelled, "cancelled")))
    else r.answer(Right(result))
  }

  private def document(generation: Json, doc: Json, stale: Boolean): Json =
    Json.Obj(List("ok" -> Json.Bool(true), "document" -> doc, "generation" -> generation) ++
             (if (stale) List("stale" -> Json.Bool(true)) else Nil))

  private def failure(generation: Json, status: Int, message: String, path: Option[String]): Json =
    Json.Obj(List("ok" -> Json.Bool(false), "status" -> Json.num(status),
                  "message" -> Json.Str(scrubUrls(message))) ++
             path.toList.map(p => "path" -> Json.Str(p)) ++
             List("generation" -> generation))

  /** DECLARED LAST, and it must be: starting a thread publishes `this`, so
    * every field the thread reads has to be initialised first.  A daemon, so
    * a looping render cannot keep a forked test JVM (or the server) alive
    * (§2.3). */
  private val thread: Thread = {
    val t = new Thread(new Runnable { def run(): Unit = loop() }, "ermine-preview")
    t.setDaemon(true)
    t.start()
    t
  }
}

object Preview {

  /** How many times the job loop may fail with no job succeeding in between
    * before the thread gives up (M1).  Small on purpose: the failures this
    * bound is about are `Error`s out of the queue machinery itself, and if
    * three in a row have not cleared, spinning will not clear the fourth. */
  private val MaxLoopFailures = 3

  /** Stage A's backend, and the two constants WP-13 replaces with a profile.
    * In-memory SQLite has no credential, so §8 does not apply to it. */
  private val StageABackend = "sqlite"
  private val StageAUrl     = "jdbc:sqlite::memory:"

  /** What the preview thread does, in queue order (§2.5).
    *
    * Stage B adds `Schema(id, module, binding, answer)` -- `ermine/schema`
    * with a `binding` key, answered by `Runner.paramSchema` (§6) -- and
    * WP-13 adds `Connect(profile, password, answer)` and `Disconnect`.
    * Each is a case of this type and a branch of `loop`; nothing else in
    * this file changes for them. */
  sealed trait Job
  final case class Render(id: Json, req: RenderRequest, dirtyAt: Long, answer: Rpc.Answer) extends Job
  final case class Invalidate(paths: Set[Path]) extends Job
  case object DiscardSession extends Job

  /** `ermine/render`'s parameters (§4). */
  final case class RenderRequest(uri: String, binding: String, params: Json,
                                 roots: List[String], generation: Json)

  object RenderRequest {
    def parse(params: Json): Either[String, RenderRequest] =
      (params / "uri" flatMap (_.str), params / "binding" flatMap (_.str)) match {
        case (None, _) => Left("\"uri\" is a string naming the report's file")
        case (_, None) => Left("\"binding\" is a string naming the report binding to render")
        case (Some(uri), Some(binding)) =>
          roots(params).right.map(rs => RenderRequest(
            uri, binding,
            params / "params" getOrElse Json.Null,
            rs,
            params / "generation" getOrElse Json.Null))
      }

    /** `ermine.preview.roots`, absolutised, or WHICH ENTRY IS WRONG (S2).
      * A bad entry is a 400 naming it and not a silent drop: the value comes
      * from a per-folder setting the developer wrote, and a root that is
      * quietly ignored is a preview that mysteriously cannot find a module.
      *
      * An EMPTY string is refused for its own reason: `Paths.get("")`
      * normalises to the server's working directory, which is the checkout
      * `bin/ermine-lsp` runs in, so an empty entry would silently add a
      * whole source tree as a module root. */
    private def roots(params: Json): Either[String, List[String]] = {
      val asked = (params / "roots" flatMap (_.arr) getOrElse Nil) flatMap (_.str)
      val each  = asked.map { r =>
        if (r.trim.isEmpty)
          Left("\"roots\" has an empty entry; each root is an absolute directory path")
        else
          try Right(Session.normalize(r).toString)
          catch { case e: Throwable =>
            Left("\"roots\" entry \"" + r + "\" is not a path: " + messageOf(e)) }
      }
      each.collectFirst { case Left(why) => why } match {
        case Some(why) => Left(why)
        case None      => Right(each.collect { case Right(r) => r })
      }
    }
  }

  /** Rule A5 (§8.1): no answer and no log line carries a JDBC URL.  Stage A's
    * URL is `jdbc:sqlite::memory:` and carries no secret, but the rule is
    * absolute and the message that would carry one -- a driver's "No suitable
    * driver found for <url>" -- reaches a client through exactly this path.
    * WP-13's scrub is wider (the profile's `url`, `user` and host, rule A10);
    * this is the part that needs no profile to do. */
  def scrubUrls(s: String): String =
    if (s == null) "" else JdbcUrl.replaceAllIn(s, "<url>")

  private val JdbcUrl = "(?i)jdbc:[^\\s\"'\\]),]*".r

  /** A throwable as one line.  `Runner.messageOf` is `private[json]`; this
    * is the same shape for the two places here that need it. */
  private def messageOf(e: Throwable): String =
    Option(e.getMessage) getOrElse e.getClass.getName

  /** Build the preview and register its two wire methods on `server`
    * (§4).  Answers it so `Main.afterReload` can post invalidations.
    *
    * `moduleRoots` is a function and not a list because the server learns
    * its roots at `initialize`, long before the first render, and the
    * preview thread must read them when it boots, not when it is built. */
  def install(server: Server, moduleRoots: () => List[String], log: String => Unit): Preview = {
    val preview = new Preview(moduleRoots, server.notify, log)
    server.onRequestDeferredWithId("ermine/render") { (id, params, answer) =>
      preview.render(id, params, answer)
    }
    // WP-1 routes `$/cancelRequest` to a registered handler; every other
    // `$/` notification stays dropped.
    server.onNotification("$/cancelRequest") { params =>
      params / "id" foreach preview.cancel
    }
    preview
  }
}
