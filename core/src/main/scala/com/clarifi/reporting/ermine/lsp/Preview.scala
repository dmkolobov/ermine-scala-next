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
  * WP-5 STAGE A built the thread, the queue, `ermine/render`,
  * `$/cancelRequest` and `invalidate`.  STAGE B adds the watchdog and the
  * stuck state (§2.5), the document-size cap (§2.3), `ermine/schema` with a
  * `binding` key as a queue job (§4, §6) and the boot's work-done progress
  * (§2.5).  `ermine/preview/reports` is stage B too but is NOT here: §3.2
  * puts it on the DISPATCH thread, over the resident's document index, and
  * this file never touches the resident -- it lives in `Definitions.scala`
  * beside the index it reads.  The launcher's heap cap is stage C; profiles,
  * `connect` and `disconnect` are WP-13 and WP-14, with named seams below.
  *
  * WHICH THREAD TOUCHES WHAT -- the whole of the concurrency argument:
  *
  * | state | thread | how it is safe |
  * |---|---|---|
  * | `runner`, `delegating`, `rootsInUse`, `headerSupply`, `armed` | THE PREVIEW THREAD ALONE | never read or written anywhere else; no lock, because there is no second reader.  `SessionEnv` is not thread-safe and this is the whole reason the thread exists (§2.3).  `armed` is the watchdog task this thread scheduled: only this thread arms and disarms one, and the TIMER thread never touches the field, only the task object it was handed |
  * | `jobs`, `inFlight`, `cancelledInFlight`, `stopping`, `answeredInFlight`, `stuck` | dispatch thread posts and cancels, preview thread consumes, TIMER thread fires | every access is inside `lock.synchronized`; the monitor is also the wait/notify channel.  Nothing that can block on the client -- an `Rpc.Answer`, a `notify` -- is ever called while holding it.  `answeredInFlight` moved under the lock in stage B: the watchdog answers from the timer thread, so the one-shot flag has a second writer and the log line `Rpc.deferredRequest` prints for a second answer is what it exists to keep out |
  * | `dirtyGeneration` | bumped by the dispatch thread, read by both | an `AtomicLong`.  It is the `stale` hint of §2.5 and nothing else depends on its value |
  * | `sessionUp`, `bootToken` | written by the preview thread, read by the dispatch thread | `@volatile`.  They are the ONLY thing the dispatch side learns about the render session, and it learns exactly one bit: "is there a session, so will the job I am about to enqueue boot one?" (§2.5's progress rule -- the `create` request is the dispatch thread's, the `$/progress` notifications the preview thread's).  A stale read costs at most one progress token that is never begun, never a wrong answer |
  * | `timeoutMillis`, `maxDocumentBytes`, `progressCapable` | written by the dispatch thread at `initialize` or a settings push, read by the preview and timer threads | `@volatile`.  Each is one scalar with no invariant tying it to another, so a read that crosses a write sees the old value or the new one and both are legal |
  * | the resident session | THE DISPATCH THREAD ALONE | this file never touches it.  `moduleRoots` is a function the server supplies; it is SAFELY PUBLISHED by the queue's monitor, not by anything about the field itself -- the dispatch thread writes `Resident.moduleRoots` at `initialize`, and every render that reads it was ENQUEUED (under `lock`) after that write and DEQUEUED (under `lock`) by this thread, which is the happens-before edge.  A later write of that field is racy in the same way `initialize` itself is, and costs one boot with stale roots |
  *
  * The preview thread and the timer thread answer requests through
  * `Rpc.Answer` (legal from any thread, exactly once) and send notifications
  * through `Server.notify` (legal from any thread since WP-1's synchronised
  * `Wire.send`).  NEITHER calls `Server.ask`: that is dispatch-thread-only
  * (§2.3, resolution 6e), which is why the one server-to-client REQUEST this
  * file makes -- `window/workDoneProgress/create` -- is issued by `render`,
  * on the dispatch thread, before the job is even enqueued.
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
                    /** DISPATCH THREAD ONLY, and called from exactly one
                      * place: `render`, for §2.5's
                      * `window/workDoneProgress/create`.  It is a function
                      * rather than the `Server` itself so that this file
                      * cannot reach `ask` from anywhere else -- the thread
                      * rule made structural, as `rawLog` makes rule A5
                      * structural. */
                    askFromDispatch: (String, Json, Json => Unit) => Unit,
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
  /** The job that OWES AN ANSWER the preview thread is working on, or
    * `null`.  A NULLABLE FIELD and not an `Option` on purpose (delta review
    * item 1): `takeJob` must record the job it has just removed from `jobs`
    * with a write that CANNOT THROW, or an `OutOfMemoryError` on the `Some`
    * would leave a request that is neither in the queue nor named anywhere,
    * which nothing could then answer.  A reference store is that write.
    *
    * `Answering` and not `Render` since stage B: `ermine/schema {binding}`
    * is a second job kind that carries an `Rpc.Answer`, and every path that
    * exists so that no request is left unanswered -- `rescueInFlight`,
    * `drainOnDeath`, `runJob`'s `finally`, the watchdog -- has to cover it
    * too.  That is why the distinction is in the TYPE: a third job kind with
    * an answer cannot be added without the compiler pointing at each of
    * them. */
  private var inFlight: Answering = null
  private var cancelledInFlight   = false
  private var stopping            = false

  /** §2.5's STUCK state: the watchdog fired, so the preview thread is
    * presumed wedged inside an evaluation that cannot be interrupted (WP-6
    * is what makes it interruptible).  From here on every `ermine/render`
    * and every `ermine/schema` is answered with the same failure WITHOUT
    * being queued -- queueing behind a thread that will never come back is
    * a client waiting for ever -- and nothing new is posted to the queue.
    *
    * IT IS NEVER CLEARED.  §2.5's remedy is a server restart, and the
    * notification the watchdog sends says so; a preview that un-stuck
    * itself would be claiming the runaway evaluation had stopped, which
    * nothing in this process can know. */
  private var stuck = false

  /** Whether the preview thread is still consuming the queue.  `loop`'s
    * outermost `finally` clears it -- however the thread ended, including by
    * an `Error` that escaped every guard -- BEFORE draining, so a render is
    * either enqueued and answered by that drain or refused by `render`, and
    * is never left in a queue with no consumer (M1 of the stage A review).
    * Volatile for the read in `render`; the write is ordered against the
    * drain by `lock`. */
  @volatile private var alive = true

  /** Whether the job in flight has already been handed to its `Rpc.Answer`
    * -- claimed BEFORE the send, mirroring the one-shot token
    * `Rpc.deferredRequest` takes before ITS send, so a send that died on a
    * broken pipe counts as spent (it is: that scaladoc says such a request
    * is not retried).  Reset when an `Answering` job is dequeued.
    *
    * UNDER `lock` SINCE STAGE B, and read only through `claimAnswer`.  The
    * watchdog answers from the TIMER thread while the job is still running
    * on the preview thread, so "who answers" is now a race between two
    * threads and has to be decided by one atomic step.  `Rpc.Answer` is
    * one-shot and would keep the WIRE correct on its own; this flag is what
    * keeps the LOG correct, because the loser of that race would otherwise
    * earn a "second answer ... ignored" line on every watchdog fire. */
  private var answeredInFlight = false

  /** Claim the right to answer the job in flight: true for the FIRST
    * caller, false for every other.  The one place `answeredInFlight` is
    * written. */
  private def claimAnswer(): Boolean = lock.synchronized {
    if (answeredInFlight) false else { answeredInFlight = true; true }
  }

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

  // ------------------------------------------------- settings (§2.3, §2.5)

  /** `ermine.preview.timeoutSeconds` (§2.5), in milliseconds.  Zero or less
    * disarms the watchdog entirely, which is what a client that wants a
    * render to run to completion asks for by setting it to 0.
    *
    * Also THE TEST SEAM for the watchdog properties: they set milliseconds
    * directly rather than wait a minute.  `private[reporting]` for the same
    * reason `beforeJob` is. */
  @volatile private[reporting] var timeoutMillis: Long = DefaultTimeoutSeconds * 1000L

  /** `ermine.preview.maxDocumentBytes` (§2.3): a rendered document over this
    * many UTF-8 bytes is answered 500 "document too large for the panel"
    * BEFORE it reaches `Wire.send`, whose monitor it would otherwise hold
    * for the length of the write.  The test seam, as above. */
  @volatile private[reporting] var maxDocumentBytes: Long = DefaultMaxDocumentBytes

  /** Whether the client declared `window.workDoneProgress` (§2.5).  Without
    * it NOTHING of the progress machinery runs: no `create` request, no
    * `$/progress` notification, and a boot is silent -- which is what the
    * LSP specification asks of a server whose client did not opt in. */
  @volatile private[reporting] var progressCapable: Boolean = false

  /** `ermine.preview.timeoutSeconds` and `ermine.preview.maxDocumentBytes`,
    * from `initializationOptions` at startup or from a settings push at any
    * time -- the two ways `Main.applyFastMode` already accepts
    * `ermine.fastMode`, and the same shape: this is handed the object under
    * `ermine`, whichever way it arrived.
    *
    * AN OUT-OF-RANGE VALUE IS REFUSED, not clamped, exactly as
    * `ermine.debounce` refuses one (`Main.scala`): a client that asks for a
    * negative cap has a bug, and a setting that silently became something
    * else is worse than one that was ignored out loud.  Zero seconds is IN
    * range and means "no watchdog"; zero bytes is not, because it would
    * refuse every document. */
  def applySettings(ermine: Option[Json], how: String): Unit = {
    val preview = ermine flatMap (_ / "preview")
    preview flatMap (_ / "timeoutSeconds") foreach {
      case Json.Num(d) =>
        val n = d.toInt
        if (n >= 0 && n <= 3600) {
          timeoutMillis = n * 1000L
          log("preview: timeoutSeconds = " + n + (if (n == 0) " (the watchdog is off)" else "") + " (" + how + ")")
        } else
          log("preview: timeoutSeconds of " + n + " ignored (outside 0..3600s) (" + how + ")")
      case other => illTyped("timeoutSeconds", "a number of seconds", other, how)
    }
    preview flatMap (_ / "maxDocumentBytes") foreach {
      case Json.Num(d) =>
        val n = d.toLong
        if (n >= 1024L && n <= (1L << 40)) {
          maxDocumentBytes = n
          log("preview: maxDocumentBytes = " + n + " (" + how + ")")
        } else
          log("preview: maxDocumentBytes of " + n + " ignored (outside 1KiB..1TiB) (" + how + ")")
      case other => illTyped("maxDocumentBytes", "a number of bytes", other, how)
    }
  }

  /** A setting whose VALUE IS THE WRONG SHAPE -- `"60"`, `true`, an object
    * (review S5).  Said out loud, naming the key and what arrived, for the
    * reason an out-of-range value is said out loud: a setting the developer
    * wrote and the server silently dropped is a preview that mysteriously
    * behaves as if the setting were not there.  The VALUE itself is never
    * logged, only its JSON type: nothing forbids a client from putting
    * something private in a settings object it sends wholesale. */
  private def illTyped(key: String, want: String, got: Json, how: String): Unit =
    log("preview: " + key + " ignored: it is " + want + ", but a " + jsonType(got) +
        " arrived (" + how + ")")

  private def jsonType(j: Json): String = j match {
    case Json.Null    => "null"
    case Json.Bool(_) => "boolean"
    case Json.Num(_)  => "number"
    case Json.Str(_)  => "string"
    case Json.Arr(_)  => "array"
    case Json.Obj(_)  => "object"
  }

  // --------------------------------------------- the boot's progress (§2.5)

  /** Whether a render session is booted RIGHT NOW.  The one bit the
    * dispatch thread reads off the preview thread's own state, and it reads
    * it for one purpose: §2.5 wants the `window/workDoneProgress/create`
    * request issued by the dispatch thread when it enqueues a job that will
    * BOOT, and "will it boot" is "is there no session".
    *
    * WHAT THIS DOES NOT COVER, stated rather than hidden: a job that finds
    * a session but a DIFFERENT ROOT SET discards it and boots again inside
    * `ensureSession` (§2.4, and Q6 of §13).  The dispatch thread cannot
    * predict that -- the root set includes the report's own INFERRED root,
    * which is a file read and a header parse and therefore preview-thread
    * work -- so such a re-boot has no token and reports no progress.  A
    * boot after an explicit `discard()` does report, because the discard
    * clears this flag before the next render is enqueued. */
  @volatile private var sessionUp = false

  /** The progress token the dispatch thread minted for the job it last
    * enqueued while there was no session, or `null`.  AT MOST ONE is
    * outstanding: `render` mints one only when this is `null`, and the
    * preview thread clears it when the job carrying it ends.  So a token
    * the client created and this server never began -- the job found a
    * session after all, or was cancelled -- costs the client one inert
    * progress and never accumulates. */
  private val bootToken = new java.util.concurrent.atomic.AtomicReference[Json](null)

  /** The token whose `window/workDoneProgress/create` HAS NO REPLY YET, or
    * `null` (review S6).  While one is outstanding no second create is
    * issued: `Server.ask` keeps a continuation per request in
    * `clientPending`, and a client that never answers -- plus a boot that
    * fails and is retried on every render -- would otherwise grow that map
    * without bound for the life of the process.  The render simply proceeds
    * with no progress, which is what a client without the capability gets
    * anyway.  Written by the dispatch thread only (mint, and the `ask`
    * continuation, both run there); `@volatile` because the preview thread
    * never reads it and the field must still publish safely. */
  @volatile private var createPending: Json = null

  /** The token whose create the client REFUSED, or `null` (review S1).  The
    * LSP specification has the client create the progress before the server
    * reports on it, so a refused create means the client will not show one
    * and every `$/progress` for that token is noise it must discard.  A
    * token still PENDING is fine to report on: the create is on the wire
    * before any `$/progress` for it, in that order, because `render` asks
    * before it enqueues the job that begins.  Tokens are unique strings, so
    * a late refusal of an old token can never silence a new one. */
  @volatile private var createRefused: Json = null

  private val progressSeq = new java.util.concurrent.atomic.AtomicLong(0L)

  // -------------------------------------------------- the watchdog (§2.5)

  /** THE WATCHDOG'S THREAD.  A `java.util.Timer` (§2.5 names it) with its
    * own daemon thread, so neither a scheduled task nor a forgotten one can
    * keep the server -- or an unforked test JVM -- alive.
    *
    * `java.util.Timer` KILLS ITS THREAD on an exception that escapes a
    * task's `run`, and then every later `schedule` throws
    * `IllegalStateException`; a watchdog that quietly stopped watching is
    * exactly the failure this file's crash contract exists to forbid.  So
    * `fire` is written the way the job crash handler is -- every step
    * separately guarded, nothing on the path that must not throw -- and the
    * task's `run` is one `guard` over the whole of it.  `arm` guards the
    * `schedule` too, so a timer that died anyway costs the render its
    * watchdog and not its answer.
    *
    * LAZY, created by the FIRST `arm` and never before (review S7).  A
    * `java.util.Timer` STARTS ITS THREAD in its constructor, and §2.4's
    * "nothing before the first render" is the same rule that keeps
    * `headerSupply` lazy: a `Preview` nobody renders with should cost the
    * process nothing at all.  Only the preview thread creates it (inside
    * `arm`); `@volatile` because `shutdown` cancels it from another thread,
    * and cancelling reads the field rather than forcing it, so a preview
    * that never armed a watchdog is shut down without ever starting a
    * timer thread. */
  @volatile private var timer: java.util.Timer = null

  /** The task armed for the job in flight, or `null`.  PREVIEW THREAD ONLY
    * (both `arm` and `disarm` run there); the timer thread reads only the
    * task object it was handed, never this field. */
  private var armed: java.util.TimerTask = null

  /** WHICH ARMING IS CURRENT (review M2).  Bumped under `lock` by every
    * `arm` and every `disarm`; each task carries the value its own `arm`
    * minted, and `fire` does nothing unless the two still agree.
    *
    * IT EXISTS BECAUSE `TimerTask.cancel()` CAN LOSE.  It answers `false`
    * for a task that has already entered `run`, and that task then finds
    * `inFlight eq job` perfectly true -- the SAME job, a moment after its
    * watchdog was called off for the boot -- and fires anyway.  A "did the
    * cancel win" flag per task would be the same thing written less
    * plainly; a counter also covers re-arming the same job any number of
    * times, which the boot bracket does. */
  private var armEpoch = 0L

  /** The timeout, in seconds, that the arming which FIRED was made with
    * (review S4), and the message built from it.  `stuckWhy` is what every
    * later refusal repeats, so the panel sees one message and not a second
    * one quoting a setting that has since changed.  Written under `lock` by
    * the timer thread in `fire`, read under `lock` by the dispatch thread. */
  private var stuckWhy: String = null

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

  /** TEST SEAM (review M2's property).  Called on the preview thread INSIDE
    * the boot bracket -- after the watchdog has been called off and before
    * the boot itself -- so a property can make the unwatched window as long
    * as it likes, or raise `timeoutMillis` for the re-arm that follows the
    * boot, without a sleep and without a second real boot.  It holds no
    * lock, like `beforeJob`.  Never set in product code. */
  @volatile private[reporting] var duringBoot: () => Unit = () => ()

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
    * FOUR OUTCOMES, and every one of them ANSWERS SOMETHING.  A request
    * this method neither enqueues nor answers is a client waiting for ever,
    * which is the failure M1 of the stage A review found: the queue is
    * refused after `shutdown` (`-32800`, shutdown's own wording -- S1),
    * refused again if the preview thread is not running at all (an internal
    * error, because a dead consumer is not a cancellation and the client
    * should see the difference), and refused a third way once the watchdog
    * has fired (§2.5: "every later `ermine/render` is answered the same way
    * without queueing" -- the WATCHDOG'S OWN §4 failure, not a JSON-RPC
    * error, because to the panel it is the same outcome as the render that
    * timed out).
    *
    * THE ONE `ask` IN THIS FILE is here, and it is here because this is the
    * only method of the preview that runs on the dispatch thread while a
    * job is being enqueued (§2.3's rule, §2.5's progress row).  It is sent
    * BEFORE the job is enqueued, so the `create` request is on the wire
    * before any `$/progress` the preview thread could send for it. */
  def render(id: Json, params: Json, answer: Rpc.Answer): Unit =
    RenderRequest.parse(params) match {
      case Left(why) =>
        answer(Right(failure(params / "generation" getOrElse Json.Null, 400, why, None)))
      case Right(req) =>
        // PEEKED, then minted, then decided under the lock again.  The peek
        // is only an optimisation -- it keeps a dead, stopping or stuck
        // preview from asking the client for a progress token it will never
        // use -- and it is allowed to be wrong: `answerAll` releases the
        // token of every job it refuses, so a state that changed between
        // the peek and the decision costs nothing.  Minting cannot happen
        // INSIDE the lock: it reaches `Wire.send`, which a slow client
        // holds for the length of a document.
        val token = if (lock.synchronized(alive && !stopping && !stuck)) mintBootToken() else null
        val job   = Render(id, req, dirtyGeneration.get, token, answer)
        val acted = lock.synchronized {
          if (!alive)      refuse(job, Left((Rpc.InternalError, "the preview thread is not running")),
                                   "the preview thread is not running")
          else if (stopping) refuse(job, Left((Rpc.RequestCancelled, "the preview is shutting down")),
                                    "the preview is shutting down")
          else if (stuck)  refuse(job, Right(job.refusal(stuckWhy)), stuckWhy)
          else {
            // §2.5 allows ONE queued render, so this removes at most one --
            // but it removes and answers every one it finds rather than the
            // first, because a request that is dropped without an answer is
            // a request the client waits on for ever.  A queued `Schema` is
            // NOT a render and is left where it is (see `schema`).
            val old = jobs.dequeueAll { case _: Render => true; case _ => false }
            jobs.enqueue(job)
            lock.notifyAll()
            old.toList.collect { case r: Render =>
              (r, Left((Rpc.RequestCancelled, "replaced by a newer render")): Rpc.Answered,
               "replaced by a newer render") }
          }
        }
        answerAll("render", acted)
    }

  /** `ermine/schema` WITH A `binding` KEY (§4, §6), from the dispatch
    * thread.  The `type` and `name` forms are the resident's and never
    * reach this method: `Definitions.scala` branches on the key and only
    * the binding form is routed here, because only it needs the render
    * session -- the preview roots exist nowhere else, and the binding mode
    * EVALUATES a workspace module's top level, which §2.3 keeps off the
    * dispatch thread.
    *
    * HOW IT MEETS THE QUEUE'S OTHER RULES, each one a decision:
    *  - LATEST WINS is a rule about RENDERS (§2.5 says so in those words):
    *    a schema job is not replaced by a newer render, and does not
    *    replace one.  It could not be: a render and a schema answer
    *    different requests, and dropping one for the other would leave that
    *    request unanswered.  So the queue may hold one render and any
    *    schema jobs, in arrival order, and a schema queued behind a running
    *    render is answered after it;
    *  - CANCEL names an id, and a queued schema is removed and answered
    *    `-32800` exactly as a queued render is; an in-flight one is marked
    *    and its eventual answer replaced, exactly as an in-flight render is;
    *  - SHUTDOWN and a DEAD THREAD answer it rather than strand it --
    *    `shutdown`, `drainOnDeath` and `rescueInFlight` all speak of
    *    `Answering`, which is the type this job shares with `Render`;
    *  - STUCK refuses it without queueing, like a render, with the
    *    watchdog's message in `ermine/schema`'s own error shape;
    *  - THE WATCHDOG covers it: `paramSchema` compiles the report, which
    *    evaluates the binding, which is the very thing that can fail to
    *    terminate.
    *
    * UNBOUNDED? No worse than the client's own outstanding requests: every
    * schema job carries an `Rpc.Answer`, so one queued job is one request a
    * client is blocked on, and nothing in the server posts them. */
  def schema(id: Json, params: Json, answer: Rpc.Answer): Unit =
    SchemaRequest.parse(params) match {
      case Left(why) => answer(Right(schemaError(why)))
      case Right(req) =>
        val job = Schema(id, req.module, req.binding, answer)
        val acted = lock.synchronized {
          if (!alive)        refuse(job, Left((Rpc.InternalError, "the preview thread is not running")),
                                     "the preview thread is not running")
          else if (stopping) refuse(job, Left((Rpc.RequestCancelled, "the preview is shutting down")),
                                    "the preview is shutting down")
          else if (stuck)    refuse(job, Right(job.refusal(stuckWhy)), stuckWhy)
          else { jobs.enqueue(job); lock.notifyAll(); Nil }
        }
        answerAll("schema", acted)
    }

  /** One refusal, in the shape `render` and `schema` both collect.  The
    * reason is PASSED, not recovered from the answer (review nit 2): only
    * the caller knows which refusal this is, and a helper that guessed
    * "if it is a result then it must be the stuck one" would quietly start
    * logging the wrong line the day a second result-shaped refusal
    * exists. */
  private def refuse(job: Answering, a: Rpc.Answered,
                     why: String): List[(Answering, Rpc.Answered, String)] =
    List((job, a, why))

  /** Answer what the locked block decided to answer, OUTSIDE the lock:
    * every answer reaches `Wire.send`, whose monitor a slow client holds
    * for the length of a document. */
  private def answerAll(what: String, acted: List[(Answering, Rpc.Answered, String)]): Unit =
    acted foreach { case (j, a, why) =>
      // A job answered HERE never reaches `runJob`, so the progress token
      // it carries is released here instead: otherwise one refused or
      // displaced render would hold the single outstanding token for ever
      // and no later boot could report anything.
      releaseToken(j)
      log("preview: " + what + " " + Json.print(j.id) + ": " + why)
      j.answer(a)
    }

  private def releaseToken(j: Answering): Unit = j match {
    case r: Render if r.progress ne null => bootToken.compareAndSet(r.progress, null); ()
    case _                               => ()
  }

  /** §2.5's boot progress, the DISPATCH THREAD's half: if the client can
    * show work-done progress and there is no render session, ask it to
    * create a token for the boot the job about to be enqueued will pay.
    * The preview thread does the rest (`$/progress` begin and end), through
    * `notify`.
    *
    * `null` -- no token -- whenever the client cannot show progress, a
    * session is already up, or a token is already outstanding.  Everything
    * downstream treats `null` as "report nothing", so a client without the
    * capability takes exactly the stage A path and nothing can break for
    * it. */
  private def mintBootToken(): Json =
    if (!progressCapable || sessionUp || (createPending ne null)) null
    else {
      val t = Json.Str("ermine-preview-boot-" + progressSeq.incrementAndGet())
      // The CAS is the "at most one outstanding" rule: the loser mints
      // nothing.  It also makes the clear in `runJob`'s `finally`, which
      // runs on the preview thread, unable to drop a token the dispatch
      // thread minted a moment later -- it clears only its OWN.
      if (!bootToken.compareAndSet(null, t)) null
      else {
        createPending = t
        try askFromDispatch(WorkDoneCreate, Json.obj("token" -> t), reply => {
          // The continuation runs on the DISPATCH thread, like every other
          // `ask` continuation (`Server.handle`).
          if (createPending == t) createPending = null
          reply / "error" match {
            case Some(e) =>
              createRefused = t
              log("preview: the client refused a progress token: " + Json.print(e))
            case None => ()
          }
        })
        catch { case e: Throwable =>
          // The token stays claimed and the create stays "pending": if the
          // create could not even be SENT, the wire is in no state for a
          // second try, and the boot simply reports nothing.
          log("preview: could not ask for a progress token: " + messageOf(e)) }
        t
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
      val hits = jobs.dequeueAll { case a: Answering => a.id == id; case _ => false }
      if (hits.isEmpty && (inFlight ne null) && inFlight.id == id) cancelledInFlight = true
      hits.toList.collect { case a: Answering => a }
    }
    queued foreach { a =>
      releaseToken(a)      // it will never reach `runJob`: see `answerAll`
      log("preview: queued job " + Json.print(id) + " cancelled")
      a.answer(Left((Rpc.RequestCancelled, "cancelled")))
    }
  }

  /** §3 step 3: what `Main.afterReload` posts, on every reload path -- the
    * watcher's and the `ermine.reloadModules` command's.  A no-op before the
    * preview has booted: the job runs on the preview thread and finds no
    * session, which is also the only race-free place to ask. */
  def invalidate(paths: Set[Path]): Unit = if (paths.nonEmpty) {
    val ps = paths map Session.normalize
    lock.synchronized {
      // `!stuck` since stage B, and for the same reason `alive` is here: a
      // wedged consumer will never apply this invalidation either, and a
      // render that could be flagged by it can no longer be answered.
      if (alive && !stopping && !stuck) {
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

  /** End the thread.  Every queued job that owes an answer -- a render, a
    * schema request -- is answered `-32800`; an in-flight one finishes and
    * is answered normally.  Idempotent.
    *
    * The watchdog's timer is cancelled too: its thread is a daemon and
    * could not hold the JVM open, but a task that fired after `shutdown`
    * would send the client a "stuck" notification about a preview that is
    * merely gone. */
  def shutdown(): Unit = {
    val left = lock.synchronized {
      stopping = true
      lock.notifyAll()
      jobs.dequeueAll(_ => true)
    }
    left foreach { case a: Answering => a.answer(Left((Rpc.RequestCancelled, "the preview is shutting down")))
                   case _            => () }
    cancelTimer()
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

  /** How many `ermine/schema` jobs are waiting; a group-D property reads
    * it to see that a schema queued behind a held render stayed there. */
  private[reporting] def queuedSchemas: Int =
    lock.synchronized(jobs.count { case _: Schema => true; case _ => false })

  /** Whether the watchdog has fired (§2.5).  A group-D property reads it;
    * the product branches on the field, never on this. */
  private[reporting] def isStuck: Boolean = lock.synchronized(stuck)

  /** Whether the preview thread is still consuming.  A group-D property
    * reads it; nothing in the product branches on it. */
  private[reporting] def threadAlive: Boolean = thread.isAlive && alive

  private def post(j: Job): Unit = lock.synchronized {
    if (alive && !stopping && !stuck) { jobs.enqueue(j); lock.notifyAll() }
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
          case a: Answering => inFlight = a; cancelledInFlight = false; answeredInFlight = false
          case _            => ()
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
        // ARMED BEFORE `beforeJob` and before any work: the watchdog's
        // clock covers everything the job does on this thread, and a test
        // that holds a job on a latch in the seam is holding it INSIDE the
        // watched window, which is what makes the watchdog testable at all.
        job match { case a: Answering => arm(a); case _ => () }
        beforeJob(job)
        job match {
          case r: Render        => doRender(r)
          case s: Schema        => doSchema(s)
          case Invalidate(ps)   => doInvalidate(ps)
          case DiscardSession   => discardSession("asked to")
        }
      } catch {
        case e: Throwable =>
          guard(log("preview: job crashed: " + Rpc.stackTrace(e)))
          job match {
            case a: Answering => guard(finish(a, a.refusal("the preview failed: " + messageOf(e))))
            case _            => ()
          }
      }
    } finally {
      guard(disarm())
      // The progress token this job carried, used or not, is spent: clear
      // it so the next boot can mint one (see `bootToken`).
      guard(job match {
        case r: Render if r.progress ne null => bootToken.compareAndSet(r.progress, null); ()
        case _                               => ()
      })
      job match {
        case a: Answering =>
          // CLAIMED, not tested-then-set: the watchdog may be answering
          // this very job from the timer thread right now, and only one of
          // the two may reach the wire and the log.  A throw out of the
          // claim itself (an `OutOfMemoryError` inside the monitor) answers
          // ANYWAY: `Rpc.Answer` is one-shot, so the worst that costs is a
          // duplicate log line, and the alternative is a request nothing
          // ever answers.
          var mine = true
          try mine = claimAnswer() catch { case _: Throwable => () }
          if (mine) try a.answer(crashAnswer) catch { case _: Throwable => () }
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
    * The claim and the clear are ONE locked step, which is what keeps the
    * watchdog -- firing on the timer thread for the very job this is
    * rescuing -- from answering it as well. */
  private def rescueInFlight(): Unit = {
    var orphan: Answering = null
    try lock.synchronized {
      if (!answeredInFlight) { answeredInFlight = true; orphan = inFlight }
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
      case a: Answering => try a.answer(crashAnswer) catch { case _: Throwable => () }
      case _            => ()
    }
    // The timer thread outlives this one only as a daemon with nothing
    // scheduled; end it here too, so a task armed by the job that killed
    // the thread cannot fire into a preview that no longer exists.
    cancelTimer()
  }

  /** One render, §4's two answer shapes.  In order: the root set and the
    * session it implies, the mtime scan, the uri, the connection, the
    * document. */
  private def doRender(r: Render): Unit = {
    // N3: normalised ONCE, here, so that the module lookup, the inferred
    // root and the discard key below all speak of the same spelling.
    val path  = Documents.pathFor(r.req.uri) map Session.normalize
    val roots = rootSet(r.req, path)
    // The boot inside is UNWATCHED and the watchdog is re-armed as it ends,
    // by `ensureSession` itself (review M2): nothing is needed here.
    ensureSession(roots, r.progress, r) match {
      case Left(why) => finish(r, failure(r.req.generation, 500, why, None))
      case Right(_) =>
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
                  case Right(_) =>
                    // THE DOCUMENT-SIZE CAP (§2.3), measured BEFORE the
                    // answer and therefore before `Wire.send`, whose monitor
                    // is held for the length of a write and which the
                    // dispatch thread's next `publishDiagnostics` queues
                    // behind.  Counted in UTF-8 BYTES because that is what
                    // `Content-Length` counts and what the panel would have
                    // to parse -- and counted over the `StringBuilder` the
                    // writer filled, without materialising a second copy of
                    // a document that is by hypothesis too big.
                    val bytes = utf8Length(out)
                    val cap   = maxDocumentBytes
                    if (bytes > cap)
                      finish(r, failure(r.req.generation, 500,
                        "document too large for the panel: " + bytes +
                        " bytes exceeds ermine.preview.maxDocumentBytes (" + cap + ")", None))
                    else Json.parse(out.toString) match {
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

  /** `ermine/schema {module, binding}` (§4, §6), on the preview thread:
    * `Runner.paramSchema`, which compiles the report through the very cache
    * a render uses and exports the schema from the very `paramTy` the
    * decoder was compiled from -- so the params file's squiggles and the
    * 400s a bad value earns cannot disagree.
    *
    * WHICH SESSION, and the one thing §6 does not say.  `ermine/schema`
    * carries `{module, binding}` and NOTHING ELSE: no `uri`, no `roots`
    * (§4's row).  So this job cannot compute the root set a render computes,
    * and the rule is therefore:
    *  - if a session is up, ANSWER FROM IT, whatever its roots are.  It
    *    must not call `ensureSession` with a root set of its own, because a
    *    root set that differed would DISCARD the render session (§2.4) and
    *    the next render would pay a boot for a schema request;
    *  - if no session is up, boot one over the resident's module roots
    *    alone -- the only roots this request can know.  A schema asked for
    *    a WORKSPACE module before the first render then answers "no module
    *    named ..." rather than a wrong schema.  In the loop §6 describes the
    *    render comes first (the panel renders, then the extension asks for
    *    the schema to write the params skeleton), so this is the unusual
    *    order, and it is honest about it.
    * Stated in the report rather than improvised further: giving
    * `ermine/schema` a `uri` or `roots` key would fix it and is new wire
    * surface, which is §4's to decide. */
  private def doSchema(s: Schema): Unit =
    ensureSchemaSession(s) match {
      case Left(why) => finish(s, schemaError(why))
      case Right(()) =>
        // The same mtime scan a render runs at its head (§2.5): a schema
        // exported from a module that moved on disk would describe the file
        // as it was, and the render that follows would decode against the
        // file as it is.
        scanForMovedFiles()
        runner.paramSchema(s.module, s.binding) match {
          case Left(e)  => finish(s, schemaError(scrubUrls(e.message)))
          case Right(j) => finish(s, com.clarifi.reporting.ermine.json.LspSchema.toLsp(j))
        }
    }

  private def ensureSchemaSession(s: Schema): Either[String, Unit] =
    if (runner != null) Right(())
    else ensureSession(moduleRoots().flatMap(normalRoot).distinct, null, s) match {
      case Left(why) => Left(why)
      case Right(_)  => Right(())
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
  private def ensureSession(roots: List[String], progress: Json,
                            job: Answering): Either[String, Boolean] = {
    if (runner != null && rootsInUse != roots) discardSession("the root set changed")
    if (runner != null) Right(false)
    // THE BOOT IS NOT WATCHED (review M2): `unwatched` disarms before it and
    // re-arms after it however it ends, and this is the ONE place a session
    // is built, so a render's boot and a schema's boot are covered by the
    // same three lines.
    else unwatched(job) { beginProgress(progress) {
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
              sessionUp = true
              log(f"preview: render session booted in ${(System.nanoTime - t0) / 1e9}%.1fs over " +
                  (if (roots.isEmpty) "the classpath alone" else roots.mkString(", ")))
              Right(true)
          }
      }
    } }
  }

  /** §2.5's boot progress, the PREVIEW THREAD's half: `$/progress` begin
    * around `body`, `$/progress` end whatever `body` does -- a boot that
    * FAILED must still end its progress, or the client shows a spinner for
    * the life of the session.  `cancellable: false`, because nothing here
    * can be cancelled: §2.5 honours a `$/cancelRequest` that arrives during
    * a boot when the boot ENDS, and keeps the boot.
    *
    * With no token (no client capability, no boot pending when the job was
    * enqueued) this is `body` and nothing else, so the stage A path is
    * literally unchanged for a client that did not opt in. */
  private def beginProgress[A](token: Json)(body: => A): A =
    // `createRefused` (review S1): a client that answered the create with
    // an error gets no `$/progress` for that token.  A token still PENDING
    // does get one -- see `createRefused` for why that order is safe.
    if ((token eq null) || (createRefused == token)) body
    else {
      guard(notify(Progress, Json.obj("token" -> token, "value" -> Json.obj(
        "kind"        -> Json.Str("begin"),
        "title"       -> Json.Str(BootTitle),
        "cancellable" -> Json.Bool(false)))))
      try body
      finally guard(notify(Progress, Json.obj("token" -> token,
        "value" -> Json.obj("kind" -> Json.Str("end")))))
    }

  private def discardSession(why: String): Unit = {
    if (runner != null) log("preview: discarding the render session (" + why + ")")
    // WP-14: the connection a `connect` opened is closed here, from what
    // `clear()` answers.  Stage A's target opens one connection per run and
    // closes it again, so there is nothing to close.
    if (delegating != null) delegating.clear()
    runner = null; delegating = null; rootsInUse = Nil
    // The dispatch thread's one bit (§2.5's progress rule): cleared LAST,
    // so a render enqueued after this point mints a token for the boot it
    // will really pay.
    sessionUp = false
  }

  /** Answer one render, honouring an in-flight `$/cancelRequest` (§2.5: the
    * work was not interrupted, the ANSWER is replaced).  Outside `lock`,
    * because answering reaches `Wire.send`. */
  private def finish(j: Answering, result: Json): Unit = {
    val (cancelled, mine) = lock.synchronized {
      val c = cancelledInFlight && (inFlight ne null) && inFlight.id == j.id
      // CLAIMED before the send, mirroring the one-shot token
      // `Rpc.deferredRequest` takes before its own: a send that dies on a
      // broken pipe has spent the request, and neither `runJob`'s
      // last-resort answer nor the watchdog may pretend otherwise.
      val m = if (answeredInFlight) false else { answeredInFlight = true; true }
      (c, m)
    }
    // NOT MINE means the WATCHDOG already answered this job (§2.5): the
    // evaluation finished after the deadline, and the client has had its
    // failure.  Say so once in the log -- a render that came back after the
    // watchdog gave up on it is worth knowing about -- and send nothing.
    if (!mine) log("preview: job " + Json.print(j.id) + " finished after the watchdog answered it")
    else if (cancelled) j.answer(Left((Rpc.RequestCancelled, "cancelled")))
    else j.answer(Right(result))
  }

  private def document(generation: Json, doc: Json, stale: Boolean): Json =
    Json.Obj(List("ok" -> Json.Bool(true), "document" -> doc, "generation" -> generation) ++
             (if (stale) List("stale" -> Json.Bool(true)) else Nil))

  // ------------------------------------------------- the watchdog (§2.5)

  /** Arm the watchdog for `job`, replacing whatever was armed before.
    * PREVIEW THREAD ONLY.  A timeout of zero or less is "no watchdog" and
    * arms nothing, which is also what a `Timer` that has been cancelled
    * (`shutdown`) leaves behind -- the `schedule` throws and the catch below
    * is the whole handling: a job without a watchdog is answered by the job. */
  private def arm(job: Answering): Unit = {
    disarm()
    val ms = timeoutMillis
    if (ms > 0L) {
      // The EPOCH and the TIMEOUT THAT WILL HAVE FIRED are both fixed
      // before the task exists, so the task closes over values and reads no
      // mutable field of this object.
      val why = timedOutMessage(ms)
      // ONE LOCKED STEP, and `cancelTimer` takes the same monitor (delta
      // review nit 3): the epoch, the `stopping` test, the timer's creation
      // and the schedule are atomic against a `shutdown` running on another
      // thread.  Either this completes and `cancelTimer` then sees the
      // timer it created, or `shutdown` got here first and `stopping` stops
      // a timer thread being started at all -- there is no window in which
      // one is created and missed.  Nothing under this monitor can block on
      // the client: a `Timer` constructor and a `schedule` touch no wire.
      var failed: Throwable = null
      lock.synchronized {
        if (!stopping) {
          armEpoch += 1
          val epoch = armEpoch
          val t = new java.util.TimerTask {
            // `java.util.Timer` KILLS ITS THREAD on a throw out of `run`,
            // and every later `schedule` then throws: one guard here, and
            // `fire` guards each of its own steps separately.
            def run(): Unit = guard(fire(job, epoch, why))
          }
          armed = t
          try {
            if (timer eq null) timer = new java.util.Timer("ermine-preview-watchdog", true)
            timer.schedule(t, ms)
          } catch { case e: Throwable => armed = null; failed = e }
        }
      }
      if (failed ne null) log("preview: the watchdog could not be armed: " + messageOf(failed))
    }
  }

  /** Call the watchdog off.  The epoch bump is what makes it STICK: a task
    * `cancel()` could not stop -- one already inside `run` -- finds the
    * epoch moved and does nothing (see `armEpoch`). */
  private def disarm(): Unit = {
    val t = armed
    armed = null
    lock.synchronized { armEpoch += 1 }
    if (t ne null) try { t.cancel(); () } catch { case _: Throwable => () }
  }

  /** The boot, and ONLY the boot, with no watchdog over it (review M2).
    * `ensureSession` is the one place a session is ever built, for a render
    * and for a schema alike, so bracketing it here covers both.
    *
    * WHY THE BOOT IS NOT WATCHED.  §2.5's watchdog row is about "a
    * non-terminating EVALUATION"; the boot is a different row with a
    * different remedy (progress, so it does not look like a hang) and a
    * duration of seconds that nothing in the timeout's wording accounts for
    * -- Q6 measures 2.3-7.3 s on a fixture and a real workspace is
    * unmeasured and larger.  A watchdog fired mid-boot would answer 500 and
    * mark a perfectly healthy preview stuck until the server restarts,
    * which is what the stage B review reproduced.
    *
    * THE RE-ARM IS IN A `finally`, so a boot that THREW is still followed
    * by a watched job rather than an unwatched one.
    *
    * WHAT THE CLOCK STILL COVERS, and it is not nothing: everything a
    * render does BEFORE this bracket, which is `rootSet` -- and that reads
    * the report's file and parses its module header (`inferredRoot`).  At
    * the 60 s default it is noise; at a deliberately short
    * `ermine.preview.timeoutSeconds` a slow filesystem could be fired on
    * before a session is ever built, and the message would say "evaluation
    * did not finish" about a file read.  Stated rather than bracketed
    * away, because the read is genuinely part of answering the render. */
  private def unwatched[A](job: Answering)(body: => A): A = {
    disarm()
    duringBoot()
    try body finally arm(job)
  }

  /** THE WATCHDOG FIRES (§2.5).  `ermine.preview.timeoutSeconds` have
    * passed since this job started -- or since its boot ended -- and the
    * preview thread is still inside it, in an evaluation nothing in this
    * process can interrupt (WP-6 is the ticket that makes it interruptible).
    *
    * EVERY STEP IS SEPARATELY GUARDED, for the reason the job crash handler
    * is: this runs on the `Timer`'s thread, and a throw that escapes would
    * kill that thread and silently end the watchdog for the life of the
    * server.
    *
    * ONE LOCKED STEP decides everything.  Under `lock`, and only if this is
    * still the job in flight, this arming is still the current one and
    * nothing has answered it, the preview is marked STUCK, the answer is
    * claimed AND THE WHOLE QUEUE IS TAKEN.  So:
    *  - the job's own `finish`, arriving a microsecond later, finds the
    *    claim taken and sends nothing -- no second frame on the wire and no
    *    "second answer ... ignored" line in the log;
    *  - a job that answered a microsecond EARLIER leaves the claim taken
    *    here, and then nothing is marked stuck either: a preview whose
    *    render completed is not stuck, however late it was;
    *  - a task left over from a previous arming -- a different job, or the
    *    same job whose watchdog the boot bracket called off and whose
    *    `cancel()` lost the race into `run` -- finds the epoch moved and
    *    does nothing.
    *
    * THE QUEUE MUST BE DRAINED HERE (review M1), and this is the only
    * place that can drain it.  The preview thread is wedged inside the
    * evaluation for good; `render` and `schema` refuse NEW requests from
    * the moment `stuck` is set, but a job ALREADY QUEUED behind the wedged
    * one has no other reader -- nothing runs it, nothing refuses it, and
    * `shutdown`'s drain is the only thing left, which for an editor means
    * "when the user quits".  §6's ordinary loop puts a schema request there
    * (the extension renders, then asks for the params schema), so the
    * stranded request is the happy path.  Each one is answered with ITS OWN
    * refusal shape, separately guarded, outside the lock. */
  private def fire(job: Answering, epoch: Long, why: String): Unit = {
    var mine      = false
    var cancelled = false
    var queued    = List.empty[Job]
    try lock.synchronized {
      if ((inFlight eq job) && epoch == armEpoch && !answeredInFlight) {
        answeredInFlight = true
        stuck    = true
        stuckWhy = why
        mine     = true
        // §2.5: "in flight: marked, its eventual answer replaced by
        // -32800".  THIS is that eventual answer, so the client that asked
        // for the cancellation gets the cancellation it asked for -- but
        // the preview is stuck all the same, and everything below still
        // happens: the queue is drained, the notification goes out, and no
        // later request is queued.  The two facts are independent; only the
        // wedged request's own answer differs.
        cancelled = cancelledInFlight
        // Taken under the SAME lock as the claim, so nothing can be
        // enqueued between marking stuck and emptying the queue: `render`
        // and `schema` take this monitor to enqueue and see `stuck` first.
        queued = jobs.dequeueAll(_ => true).toList
      }
    } catch { case _: Throwable => () }
    if (mine) {
      guard(log("preview: WATCHDOG: " + why +
                (if (cancelled) " (the request was cancelled; answering -32800)" else "")))
      guard(if (cancelled) job.answer(Left((Rpc.RequestCancelled, "cancelled")))
            else job.answer(Right(job.refusal(why))))
      queued foreach {
        case a: Answering =>
          guard(releaseToken(a))
          guard(log("preview: queued job " + Json.print(a.id) + " refused: the preview is stuck"))
          guard(a.answer(Right(a.refusal(why))))
        // An `Invalidate` or a `DiscardSession` owes nobody an answer, and
        // a wedged session will never apply either: dropped, not kept.
        case _ => ()
      }
      // §2.5's notification, from the TIMER thread through `notify` (§4:
      // "the render watchdog therefore uses a `Timer` thread and the
      // synchronised `send`").  `window/showMessage` is the LSP's own
      // server-to-client NOTIFICATION for this; `ask` -- which
      // `window/showMessageRequest` would need for a real button -- is
      // dispatch-thread-only and this thread may not call it.  So the
      // action is NAMED, and the BUTTON is the panel's, in the extension
      // (WP-7's banner states; resolution A4 says the button lands there).
      guard(notify(ShowMessage, Json.obj(
        "type"    -> Json.num(1),              // Error
        "message" -> Json.Str(why))))
    }
  }

  /** What the watchdog answers with, built at ARM time from the timeout
    * that arming used (review S4) and stored in `stuckWhy`, so that every
    * later refusal repeats the message that actually fired rather than
    * quoting whatever `ermine.preview.timeoutSeconds` says now -- a setting
    * the client may have changed in between, and a second wording for one
    * cause would read to the panel as a second cause.
    *
    * `millis / 1000` and not a rounded quotient: the setting is in whole
    * seconds (`applySettings`), so the only fractional values here are a
    * test's, and a test that injects 300 ms is told "0s", which is true. */
  private def timedOutMessage(millis: Long): String =
    "evaluation did not finish after " + (millis / 1000L) + "s; the preview is stuck " +
    "until the language server is restarted -- run \"" + RestartTitle + "\" (" + RestartCommand + ")"

  /** End the watchdog's thread IF ONE WAS EVER STARTED (review S7).  It
    * READS the field and never creates one: a `Preview` that shut down
    * without arming a watchdog must not start a timer thread in order to
    * stop it.  Called from `shutdown` (any thread) and from the preview
    * thread's own death drain, so it must be idempotent, and
    * `Timer.cancel` is. */
  private def cancelTimer(): Unit = {
    val t = try lock.synchronized { timer } catch { case _: Throwable => timer }
    if (t ne null) try t.cancel() catch { case _: Throwable => () }
  }

  private def schemaError(message: String): Json =
    Json.obj("error" -> Json.Str(scrubUrls(message)))

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

  /** `ermine.preview.timeoutSeconds` (§2.5) and `ermine.preview.maxDocumentBytes`
    * (§2.3), as the design states them. */
  val DefaultTimeoutSeconds   = 60
  val DefaultMaxDocumentBytes = 16L * 1024L * 1024L

  /** The three LSP methods stage B speaks, and the two strings §2.5's
    * notification names.  `RestartCommand` is the extension's own command
    * (`editor/vscode/src/extension.js`, `ermine.restartServer`) and
    * `RestartTitle` its palette title: the message NAMES the action the
    * user is to run, because `window/showMessage` carries no action list
    * and `window/showMessageRequest`, which does, is a REQUEST and so
    * dispatch-thread-only (§2.3).  The button itself is the panel's, in
    * WP-7. */
  private val WorkDoneCreate = "window/workDoneProgress/create"
  private val Progress       = "$/progress"
  private val ShowMessage    = "window/showMessage"
  private val BootTitle      = "Ermine preview: booting the render session"
  private val RestartTitle   = "Ermine: Restart Language Server"
  private val RestartCommand = "ermine.restartServer"

  /** What the preview thread does, in queue order (§2.5).
    *
    * WP-13 adds `Connect(profile, password, answer)` and `Disconnect`; each
    * is a case of this type and a branch of `runJob`, and `Connect` -- which
    * answers a request -- is an `Answering`.
    *
    * `Answering` IS THE INVARIANT "no request is left unanswered", written
    * where the reader of a new job kind will meet it: `runJob`'s `finally`,
    * `rescueInFlight`, `drainOnDeath`, `shutdown`, `cancel` and the
    * watchdog all speak of this type, so a new answering job is served by
    * every one of them the moment it extends this trait.
    *
    * WHAT THE COMPILER DOES AND DOES NOT CHECK, stated honestly (review
    * nit 3): those matches are over `Job` and all have a `case _ => ()`
    * arm, so a new job kind that FORGOT to extend `Answering` compiles and
    * is silently dropped by each of them.  What the type system really
    * buys is that a job which DOES extend it cannot be added without an
    * `id`, an `answer` and a `refusal`, and that every one of those six
    * paths then handles it with no edit at all.  The rest is this
    * paragraph. */
  sealed trait Job

  sealed trait Answering extends Job {
    /** The JSON-RPC id of the request this job answers -- what
      * `$/cancelRequest` names (`Rpc.onRequestDeferredWithId`). */
    def id: Json
    def answer: Rpc.Answer
    /** This job's own shape for "it did not work": §4's `{ok: false, ...}`
      * for a render, `ermine/schema`'s `{error}` for a schema.  The
      * watchdog and the stuck refusal both go through it, so that a client
      * gets a failure in the shape of the request it made rather than a
      * JSON-RPC error it has no branch for. */
    def refusal(message: String): Json
  }

  /** `progress` is the `window/workDoneProgress/create` token the DISPATCH
    * thread minted for this render because no session was up when it was
    * enqueued, or `null` (§2.5).  It travels on the job so that the preview
    * thread needs no shared state to know which token its boot belongs to. */
  final case class Render(id: Json, req: RenderRequest, dirtyAt: Long,
                          progress: Json, answer: Rpc.Answer) extends Answering {
    def refusal(message: String): Json = failure(req.generation, 500, message, None)
  }

  final case class Schema(id: Json, module: String, binding: String,
                          answer: Rpc.Answer) extends Answering {
    def refusal(message: String): Json = Json.obj("error" -> Json.Str(scrubUrls(message)))
  }

  final case class Invalidate(paths: Set[Path]) extends Job
  case object DiscardSession extends Job

  /** §4's failure shape.  On the companion since stage B, because each
    * `Answering` builds its own refusal. */
  private def failure(generation: Json, status: Int, message: String, path: Option[String]): Json =
    Json.Obj(List("ok" -> Json.Bool(false), "status" -> Json.num(status),
                  "message" -> Json.Str(scrubUrls(message))) ++
             path.toList.map(p => "path" -> Json.Str(p)) ++
             List("generation" -> generation))

  /** How many UTF-8 BYTES a rendered document is, without building them
    * (§2.3's cap): the document is by hypothesis the largest thing in this
    * process, and `getBytes` on it would double that before deciding it was
    * too big.  Unpaired surrogates count as one replacement character's
    * three bytes, which is what the encoder writes for them. */
  private[lsp] def utf8Length(cs: CharSequence): Long = {
    var i = 0
    var n = 0L
    val len = cs.length
    while (i < len) {
      val c = cs.charAt(i)
      if (c < 0x80) n += 1L
      else if (c < 0x800) n += 2L
      else if (Character.isHighSurrogate(c) && i + 1 < len && Character.isLowSurrogate(cs.charAt(i + 1))) {
        n += 4L; i += 1
      } else n += 3L
      i += 1
    }
    n
  }

  /** `ermine/schema`'s binding form (§4, §6). */
  final case class SchemaRequest(module: String, binding: String)

  object SchemaRequest {
    def parse(params: Json): Either[String, SchemaRequest] =
      (params / "module" flatMap (_.str), params / "binding" flatMap (_.str)) match {
        case (None, _) => Left("ermine/schema needs a \"module\"")
        case (_, None) => Left("ermine/schema needs a \"binding\" naming the report")
        case (Some(m), Some(b)) => Right(SchemaRequest(m, b))
      }
  }

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
    // `ask` is handed over as a FUNCTION, not as the server: this file may
    // not reach `ask` from anywhere but `render` (§2.3), and a parameter
    // that only `render` is given is that rule made structural.  The reply
    // is logged and nothing else: §2.5 wants the client to have created the
    // token, and a client that refuses simply gets no progress.
    val ask: (String, Json, Json => Unit) => Unit = (method, params, k) =>
      server.ask(method, params)(k)
    val preview = new Preview(moduleRoots, server.notify, ask, log)
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
