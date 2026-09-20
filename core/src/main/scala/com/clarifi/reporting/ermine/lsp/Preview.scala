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
  * | `jobs`, `inFlight`, `cancelledInFlight`, `stopping`, `answeredInFlight`, `stuck`, `stuckWhy`, `stuckJob` | dispatch thread posts and cancels, preview thread consumes, TIMER thread fires | every access is inside `lock.synchronized`; the monitor is also the wait/notify channel.  Nothing that can block on the client -- an `Rpc.Answer`, a `notify` -- is ever called while holding it.  `answeredInFlight` moved under the lock in stage B: the watchdog answers from the timer thread, so the one-shot flag has a second writer and the log line `Rpc.deferredRequest` prints for a second answer is what it exists to keep out |
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
    * IT CLEARS WHEN THE WEDGED JOB RETURNS, and at no other time (Q10,
    * decided 2026-09-20).  §2.5's remedy is still the server restart the
    * watchdog's message names, because a runaway evaluation usually never
    * comes back -- but it CAN (a `Fetch` that was merely slow, a scan that
    * hit the 300 s statement timeout), and a preview thread that is alive,
    * idle and refusing every render until the user restarts a process that
    * is working is a worse answer than saying so.  `stuckJob` is what makes
    * "the wedged job" a fact rather than a guess, and `runJob`'s `finally`
    * is where it is read; `clearStuck` is the one place this field, and the
    * two beside it, are put back.  What does NOT clear it is written in
    * `isFatal`: anything that is a `java.lang.Error` or is not `NonFatal`,
    * and any other job's ending.
    *
    * AND IF THE JOB FAILED, THE RECOVERY DISCARDS THE RENDER SESSION
    * (DM-1, corrected by DD-1 of the second review): `Runtime.swhnf`
    * memoises a `NonFatal` failure into every thunk on the chain, so the
    * session's shared bindings would re-throw it for ever.  "FAILED" means
    * THE OUTCOME, not an escaping throw: the path that matters returns
    * NORMALLY with a 500, because `Encode` and `Runner` net the failure
    * (see `evalFailed`).  `runJob`'s `finally` is where the clear and the
    * discard are ordered. */
  private var stuck = false

  /** THE JOB THE WATCHDOG FIRED ON, or `null` (Q10).  Written under `lock`
    * by the timer thread in `fire` and by `clearStuck`; read under `lock`
    * by `runJob`'s `finally`, which is the preview thread's.
    *
    * IT IS WHY RECOVERY IS NOT A GUESS.  Without it the only thing the
    * preview thread could say as a job ended is "a job ended while the
    * preview was stuck", which is true of the NEXT job too -- and the next
    * job cannot run, because the wedged one owns this thread, so the field
    * looks redundant until WP-6 makes a wedged job abandonable and it stops
    * being.  Holding the reference costs the job's `Rpc.Answer` and its
    * request until the state clears, which is the same lifetime `inFlight`
    * already gives it. */
  private var stuckJob: Answering = null

  /** WHICH STATE CHANGE IS THE LATER ONE (IM-1 of the Q8-Q12 review).
    * Bumped under `lock` in the SAME step that flips `stuck` -- `fire`'s
    * claim and `clearStuck` -- and carried on the `ermine/preview/stuck`
    * notification as `seq`.
    *
    * IT EXISTS BECAUSE THE TWO EDGES ARE SENT BY DIFFERENT THREADS WITH NO
    * ORDERING BETWEEN THEM.  `{stuck: true}` is the TIMER thread's, the
    * LAST of `fire`'s sends; `{stuck: false}` is the PREVIEW thread's, the
    * FIRST of `recovered`'s.  A job released the instant the watchdog fired
    * can therefore put the FALSE on the wire first -- `Wire.send` is
    * synchronised, so the frames do not tear, but nothing decides which
    * enters the monitor first -- and a client reading them in arrival order
    * would latch a stuck banner on a healthy preview with no falling edge
    * ever to follow.  With `seq` the client keeps the highest it has seen
    * and ignores the rest, and the wire order stops mattering (§4).
    *
    * IT IS PER-PROCESS AND STARTS AT 0 IN EVERY ONE (DD-2 of the second
    * review).  A restart is the remedy the watchdog's own message names, so
    * a fresh server WILL send `{stuck: true, seq: 1}` -- and a client that
    * obeyed "keep the highest seq" across the restart would ignore it for
    * the life of its session.  §4's rule therefore has a second clause: the
    * client RESETS its high-water mark when the language client goes
    * Stopped -> Running (§5's own row for that transition). */
  private var stuckSeq: Long = 0L

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

  /** DID THE JOB NOW RUNNING ANSWER WITH AN *EVALUATION* FAILURE? (DD-1 of
    * the second Q8-Q12 review.)  PREVIEW THREAD ONLY: cleared by `runJob`
    * before the job starts, set by `doRender`/`doSchema` where they answer,
    * read by `runJob`'s `finally`.  No lock, because there is no second
    * reader -- the same argument as `runner` above.
    *
    * THE RULE, and it is narrow on purpose: it is set for a `RunError` of
    * STATUS >= 500 out of `renderText`/`paramSchema`, which is exactly
    * `Runner`'s `Failed` -- and `Failed` is minted at precisely the sites
    * that net a FORCING failure: `Session.eval` dying (`Runner.scala:845`),
    * the step driver's `Abort`/`WriteFailure`/`NonFatal`
    * (`:883-886` -- and `Abort` carries the step's own error, which is how
    * `Encode`'s `Left(bottom(...))` for a memoised `Bottom` arrives), the
    * writer (`:508`) and a document that cannot be encoded (`:929-930`).
    *
    * WHAT IS DELIBERATELY EXCLUDED, each because nothing of the report was
    * forced:
    *  - `BadRequest` (400): a params object that does not decode
    *    (`Runner.scala:873`), a binding whose signature is not a report.
    *    The decode happens BEFORE the report function is applied;
    *  - `NotFound` (404): no module, or no binding of that name -- refused
    *    before any load;
    *  - the 400 / 404 / 409 / 500 this file's own `placeAndSession`
    *    answers: a URI that is not a file, a pick that cannot be placed, a
    *    shadowed pick (nothing is loaded, it says so), and a boot that
    *    FAILED -- which `ensureSession` has already thrown away, so there
    *    is nothing left to discard;
    *  - the 503 "not connected";
    *  - THIS FILE'S OWN 500s after a SUCCESSFUL render: the document-size
    *    cap and "the rendered document is not JSON". The evaluation
    *    completed and wrote real values back; discarding there would cost a
    *    boot for nothing.
    * An ORDINARY (un-wedged) failure sets this too and nothing happens: the
    * `finally` reads it only when the stuck state was cleared for this job.
    * The un-wedged case is Q14's and is the user's. */
  private var evalFailed: Boolean         = false
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
          // `stuckRefusal` and NOT `refusal` (Q8, decided 2026-09-20): this
          // is one of exactly four answers that carry `"stuck": true`, the
          // marker WP-7's banner reads to know it may show the restart
          // button.  The crash handler's 500 must not carry it (the job was
          // SERVED and failed), which is why the flag is a second method on
          // `Answering` and not a field of the shape `refusal` builds.
          else if (stuck)  refuse(job, Right(job.stuckRefusal(stuckWhy)), stuckWhy)
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
    * Q7 (decided by the user on 2026-09-20): THE BINDING FORM IDENTIFIES
    * THE REPORT THE WAY A RENDER DOES -- `{uri, binding, roots}`, not
    * `{module, binding}` -- and `doSchema` computes the module and the root
    * set with exactly the functions a render uses (`placeAndSession`).  So a
    * schema and the render that follows it share ONE session in either
    * order, §6's first-pick order (the panel picks, the extension asks for
    * the schema, THEN renders) works for a workspace module, and a
    * same-named module under another root can no longer be described by
    * mistake.  A request that carries `binding` but no `uri` is an `{error}`
    * naming the missing key: the old form is not kept alive, because there
    * is no extension code to keep compatible yet (WP-7/WP-8) and keeping it
    * would keep its wrong-module hazard.
    *
    * THE PROGRESS TOKEN (§2.5's row, and Q7's second consequence): a schema
    * can now be the job that BOOTS -- a first pick asks for the schema
    * before it renders -- so it mints a `window/workDoneProgress/create`
    * token through the very same `mintBootToken`, on the very same thread,
    * under the very same at-most-one-outstanding rule.  It is three lines
    * and no new mechanism; before Q7 a schema-triggered boot reported
    * nothing, which was right only while a schema could not carry roots.
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
        // Minted OUTSIDE the lock and only on a peek that says a boot is
        // possible, exactly as `render` does it and for the same two
        // reasons (see `render`'s comment): `answerAll` releases the token
        // of every job it refuses, and minting reaches `Wire.send`.
        val token = if (lock.synchronized(alive && !stopping && !stuck)) mintBootToken() else null
        val job = Schema(id, req, token, answer)
        val acted = lock.synchronized {
          if (!alive)        refuse(job, Left((Rpc.InternalError, "the preview thread is not running")),
                                     "the preview thread is not running")
          else if (stopping) refuse(job, Left((Rpc.RequestCancelled, "the preview is shutting down")),
                                    "the preview is shutting down")
          // Q8's marker, beside `error` in `ermine/schema`'s own shape; see
          // the same line in `render`.
          else if (stuck)    refuse(job, Right(job.stuckRefusal(stuckWhy)), stuckWhy)
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

  private def releaseToken(j: Answering): Unit =
    // Q7: `progress` is on `Answering` rather than on `Render`, so a
    // SCHEMA's token is released by the very line a render's is.
    if (j.progress ne null) { bootToken.compareAndSet(j.progress, null); () }

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
    *     render is noise the log does not need.
    *
    * AND, SINCE Q10, IT IS WHERE THE STUCK STATE ENDS.  The `finally`
    * below is the one place in this file that knows a job has REALLY
    * finished, which is the only evidence §2.5's wedge is over; see
    * `recovered` for what it costs a client that was never told. */
  private def runJob(job: Job): Unit = {
    /** Whether the job died on a `java.lang.Error` (Q10).  The inner catch
      * swallows every `Throwable`, so by the `finally` below "how did this
      * end" is gone unless it is written down here.  `Unit`-returning and
      * one boolean, so the recording itself cannot fail. */
    var fatal = false
    /** Whether the job ended by THROWING at all (DM-1 of the Q8-Q12
      * review).  Distinct from `fatal`, and it decides something else
      * entirely: not "may the preview be believed" but "is the render
      * SESSION still usable".  See the discard in the `finally`. */
    var threw = false
    // Cleared HERE, before anything of the job runs, so that what the
    // `finally` reads is this job's outcome and never the last one's.
    evalFailed = false
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
          // Q10(b): FIRST, and by a store that cannot throw.  Everything
          // after it can fail, and a `finally` that then announced
          // "recovered" because it could not remember an
          // `OutOfMemoryError` is the one outcome this rule exists to
          // forbid.
          fatal = isFatal(e)
          threw = true
          guard(log("preview: job crashed: " + Rpc.stackTrace(e)))
          job match {
            // `refusal` and NOT `stuckRefusal` (Q8): this job was SERVED
            // and failed.  A client that saw `"stuck": true` here would
            // offer a restart for an ordinary broken report.
            case a: Answering => guard(finish(a, a.refusal("the preview failed: " + messageOf(e))))
            case _            => ()
          }
      }
    } finally {
      guard(disarm())
      // The progress token this job carried, used or not, is spent: clear
      // it so the next boot can mint one (see `bootToken`).
      guard(job match {
        case a: Answering => releaseToken(a)
        case _            => ()
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
      // Q10, LAST, and after `inFlight` is cleared: the wedge is over only
      // if the job that just ended is the one the watchdog fired on, and
      // only if it ended in a way that leaves this JVM able to keep its
      // promises (`isFatal`).  `clearStuck` decides both halves under
      // `lock` and answers the sequence number it minted, or 0;
      // `recovered` is the only thing that reaches the client, and it is
      // outside the lock and guarded, like every other send in this file.
      job match {
        case a: Answering if fatal =>
          // The wedge is PERMANENT, so nothing will ever match this job
          // again -- but the field would hold its `Rpc.Answer` closure and
          // its request JSON for the life of the process (review nit).
          guard(forgetStuckJob(a))
        case a: Answering =>
          var seq = 0L
          try seq = clearStuck("the job the watchdog fired on returned", a)
          catch { case _: Throwable => () }
          if (seq > 0L) {
            // DM-1 OF THE Q8-Q12 REVIEW: A JOB THAT ENDED BY THROWING
            // POISONED THE SESSION, so recovery DISCARDS it.
            // `Runtime.swhnf` captures a `NonFatal` throw as
            // `Bottom(throw e)` (`Runtime.scala:231`) and `writeback`
            // memoises that value into EVERY thunk on the chain
            // (`:245-250`) -- including the render session's SHARED
            // bindings, which outlive this render.  Leaving the session
            // alive would mean those bindings re-throw the OLD failure for
            // ever while this method tells the panel the preview is serving
            // renders again.  §2.5's own WP-6 row says the same thing of a
            // cancel ("poisons the render session's stdlib thunks, so a
            // cancel DISCARDS the `Runner`"); it is the same mechanism and
            // it deserves the same answer.
            //
            // THE WITNESS IS THE OUTCOME, NOT `threw` (DD-1 of the second
            // Q8-Q12 review, which found the first cut's witness wrong).
            // The poisoning path that MATTERS returns NORMALLY: `Encode`
            // turns a `Bottom` into `Left(bottom(...))`
            // (`Encode.scala:295`, `:242`, `:514`) and `Runner` nets every
            // `NonFatal` failure into `Left(Failed(...))`
            // (`Runner.scala:508`, `:845`, `:883-886`, `:929-930`), which
            // `doRender` answers as a 500 BY RETURNING.  So after a wedge
            // that came back FAILED, `threw` is false -- and the first cut
            // kept the poisoned session and announced recovery over it.
            // `threw` still counts, for what escapes those nets; `evalFailed`
            // is the rest, and its rule is on the field.
            //
            // THE ORDER IS FORCED, and `clearStuck`'s scaladoc says why:
            // the clear comes FIRST, and the discard is the private
            // preview-thread method, never `discard()`.
            //
            // IT RUNS UNWATCHED: `disarm()` is the first thing this
            // `finally` did, so nothing is timing the discard.  That is
            // free today (`DelegatingRun.clear()` closes nothing), and
            // WP-14 must not make it otherwise -- see that ticket's row.
            var rebuilt = false
            if (threw || evalFailed) {
              // TRUTHFULLY (review S2): `discardSession` on a preview that
              // never booted does nothing and logs nothing, so there is no
              // session to say was discarded.  The next render boots either
              // way, which is what the plain recovery message already says.
              rebuilt = runner != null
              if (rebuilt)
                guard(discardSession("the evaluation the watchdog fired on " +
                                     (if (threw) "ended by throwing" else "failed") +
                                     ", so its thunks hold a memoised failure"))
            }
            guard(recovered(seq, rebuilt))
          }
        case _ => ()
      }
    }
  }

  /** Let go of the job the watchdog fired on WITHOUT leaving the stuck
    * state (review nit).  Used on the FATAL path, where the wedge stands
    * for the life of the process: nothing can ever match this job again, so
    * the only thing the reference still does is retain the request's JSON
    * and its `Rpc.Answer` closure.  `stuck` and `stuckWhy` are untouched --
    * the refusals still repeat the message that fired. */
  private def forgetStuckJob(job: Answering): Unit = lock.synchronized {
    if (stuckJob eq job) stuckJob = null
  }

  /** AFTER THIS THROWABLE, MAY THE PREVIEW BE SAID TO BE WORKING AGAIN?
    * (Q10(b), decided 2026-09-20; CORRECTED by the Q8-Q12 review.)  TWO
    * INDEPENDENT REASONS, one per half of the test, and neither subsumes
    * the other:
    *
    *  1. `e.isInstanceOf[Error]` -- IS THIS JVM STILL BELIEVABLE?
    *     `java.lang.Error`'s own contract is the argument (*external*, its
    *     javadoc: "indicates serious problems that a reasonable application
    *     should not try to catch"), and it covers every class §2.5's
    *     failure story names -- `OutOfMemoryError` through
    *     `VirtualMachineError`, `LinkageError`, `AssertionError` -- plus
    *     whatever a future JDK adds, with no list here to go stale.
    *     `scala.util.control.NonFatal` ALONE would not do: it classes an
    *     `AssertionError` as non-fatal, so an assertion that blew up inside
    *     the evaluator would announce "recovered".
    *  2. `!NonFatal(e)` -- DID THE RUNTIME GET TO CLEAN UP?  This half is
    *     about `Runtime.swhnf`, not about the JVM, and `isInstanceOf[Error]`
    *     MISSES IT (the review's finding): `swhnf`'s ONE capture is
    *     `catch { case NonFatal(e) => r = Bottom(throw e) }`
    *     (`Runtime.scala:231`), so a throwable that is NOT `NonFatal`
    *     escapes the force WITHOUT reaching `writeback` -- and leaves every
    *     thunk on the chain in state `Whitehole` with THIS thread still in
    *     its `pending` queue (`:229-237`).  A later force of one of those
    *     thunks ON THE SAME THREAD takes the `pending.exists(sameId)`
    *     branch and memoises `Whitehole.result`, which is
    *     `Bottom(sys.error("infinite loop detected"))` (`:196`) -- a
    *     PERMANENT, and wrong, diagnosis.  `NonFatal`'s complement is
    *     exactly that set: `VirtualMachineError`, `ThreadDeath`,
    *     `InterruptedException`, `LinkageError`, `ControlThrowable`.  The
    *     last two of those are not `Error`s, which is why the first half is
    *     not enough.
    *
    * THE `StackOverflowError` ASYMMETRY IS DELIBERATE and its reason is (2),
    * not the heap: a stack overflow usually leaves a perfectly healthy JVM,
    * but it is a `VirtualMachineError` and therefore NOT `NonFatal`, so it
    * unwound the chain without writeback and left whiteholes behind.  A
    * session carrying those is not one to call recovered.
    *
    * WHY THE WIDE SIDE IS THE SAFE SIDE.  Refusing to clear costs exactly
    * the behaviour this preview had before Q10 -- the restart the
    * watchdog's message names -- while clearing wrongly tells a user the
    * preview works when it does not.  THE CASE THAT MAKES (1) CONCRETE:
    * `bin/ermine-lsp` adds `-XX:+ExitOnOutOfMemoryError`, so in the shipped
    * server an OOM usually ends the process before anything here runs --
    * but the unforked gate JVM has no such flag, nor does a user who sets
    * `-XX:-ExitOnOutOfMemoryError`, and an exhausted heap that keeps
    * running is precisely where "recovered" must not be said.
    *
    * THE "WRAPPED `Error`" GAP IS NARROWER THAN THE FIRST CUT CLAIMED
    * (review): an `Error` wrapped in an ordinary exception reads as
    * non-fatal here, but the WRAPPER was `NonFatal`, so `swhnf` DID capture
    * it and DID write it back -- there are no whiteholes, only a poisoned
    * `Bottom`, and the recovery path discards the session for exactly that
    * (see `runJob`'s `threw`).  What is left of the gap is (1) alone:
    * a JVM that may be sick is called healthy.  Unwrapping causes would be
    * a guess about a chain this file did not build. */
  private def isFatal(e: Throwable): Boolean =
    e.isInstanceOf[Error] || !scala.util.control.NonFatal(e)

  /** LEAVE THE STUCK STATE (Q10).  The ONE place `stuck`, `stuckWhy` and
    * `stuckJob` are put back, so that WP-6's cooperative cancel -- which
    * ends a wedged evaluation deliberately -- reuses this rather than
    * writing a second, subtly different version of it.
    *
    * `onlyFor` is the job whose ending justifies the clear, or `null` for
    * "whatever the watchdog fired on" (WP-6's case: the canceller knows the
    * wedge is over without knowing which job it was).  A non-null `onlyFor`
    * that is not `stuckJob` clears NOTHING: some other job ended.
    *
    * IT ANSWERS THE SEQUENCE NUMBER IT MINTED, or 0 if this call did not
    * clear.  The number is minted in the SAME LOCKED STEP as the flip, so
    * the `seq` on the wire orders exactly as the state did (IM-1 of the
    * Q8-Q12 review; `fire` mints its own the same way).  It sends nothing
    * to the client: a notification reaches `Wire.send`, whose monitor a
    * slow client holds for the length of a document, and this file never
    * takes that while holding `lock`.  The caller notifies, outside the
    * lock (`recovered`).  The log line is this method's, because every
    * caller would write the same one -- and it is emitted after the monitor
    * is released, like every other line here.
    *
    * THE ORDERING TRAP, FOR WP-6 (found by the Q8-Q12 review).  A caller
    * that wants to clear the state AND then post work -- a discard, say --
    * must CLEAR FIRST and must not reach the queue through `post`,
    * `discard()` or `invalidate`: all three refuse while `stuck`, so a
    * discard posted before the clear is silently dropped and a discard
    * posted after it lands behind whatever else has arrived.  The recovery
    * path in `runJob` does both things on the PREVIEW THREAD, calling the
    * private `discardSession` directly, which is neither queued nor
    * refusable.  WP-6's cancel runs on the TIMER or DISPATCH thread and has
    * no such shortcut: it must clear here and then either post the discard
    * (now that the guard is open) or hand it to the preview thread, and
    * whichever it picks it should say so here. */
  private def clearStuck(reason: String, onlyFor: Answering): Long = {
    val seq = lock.synchronized {
      if (!stuck || ((onlyFor ne null) && (stuckJob ne onlyFor))) 0L
      else {
        stuck = false; stuckWhy = null; stuckJob = null
        // `Long` here and `Json.num`'s `Int` on the wire: the counter
        // advances once per watchdog fire and once per clear IN ONE
        // PROCESS, so 2^31 of them is not a number a language server
        // reaches.  Kept as a `Long` all the same because the field costs
        // nothing and an overflow would be silent.
        stuckSeq += 1
        stuckSeq
      }
    }
    if (seq > 0L) guard(log("preview: no longer stuck (" + seq + "): " + reason))
    seq
  }

  /** THE PREVIEW IS WORKING AGAIN (Q8(b) and Q10(c), (e)), from the PREVIEW
    * THREAD, through `notify` and never `ask` (§2.3's rule), outside `lock`
    * and with every send separately guarded.
    *
    * TWO MESSAGES, because they are for two different readers.
    * `ermine/preview/stuck {stuck: false, message}` is §4's own row and is
    * what WP-7's banner listens to -- it is the counterpart of the
    * `{stuck: true}` the watchdog sends, and the panel needs the falling
    * edge as much as the rising one.  `window/showMessage` of the INFO type
    * is what any LSP client shows without knowing anything about this
    * server, exactly as the watchdog's own error-type message is.
    *
    * IT ASKS FOR A RE-RENDER, and that is not politeness (Q10(e)).  Every
    * `invalidate` posted while the preview was stuck was DROPPED at the
    * `!stuck` guard in `invalidate`, so the client has missed every
    * `ermine/preview/invalidated` of that whole interval and its §3 step 6
    * loop was never triggered.  What the next render DOES get right by
    * itself is the CONTENT of every module the render session has loaded:
    * §2.5's mtime scan runs at the head of every render and reloads what
    * moved on disk.  What it cannot get right is a module the session never
    * loaded -- the fix to a report whose load failed, Q4's case -- so the
    * re-render has to be asked for.
    *
    * `dirtyGeneration` IS DELIBERATELY NOT BUMPED, and the reasoning is
    * recorded because "bump the counter" is the obvious reflex and it is
    * inert here.  `stale` is `dirtyGeneration.get != r.dirtyAt`, comparing
    * the value at the render's ENQUEUE with the value at its ANSWER.
    * Nothing can be enqueued while stuck (`render`, `schema` and `post` all
    * refuse), so the first post-recovery render is enqueued AFTER any bump
    * this method could make and would snapshot the bumped value -- the two
    * reads agree and no `stale` appears.  A bump would therefore either do
    * nothing at all, or, if it were made to straddle the enqueue, flag a
    * render that really was fresh.  The honest mechanism for "you have
    * missed some invalidations" is this notification, and the honest
    * mechanism for "the files moved" is the mtime scan; `stale` stays what
    * §2.5 calls it, a hint about invalidations that landed DURING a
    * render.
    *
    * `seq` is the number `clearStuck` minted under `lock` (IM-1): it is
    * what lets a client that receives this notification and the watchdog's
    * `{stuck: true}` OUT OF ORDER -- two threads, two independent sends --
    * decide which is the later state. `rebuilt` says whether the session
    * was discarded with the recovery (DM-1), so the message can be honest
    * about the first render costing a boot. */
  private def recovered(seq: Long, rebuilt: Boolean): Unit = {
    // SILENT WHILE STOPPING (Q10(c)).  A `shutdown` is under way -- the
    // wedged job was released by the drain, or the thread is ending -- and
    // a "the preview recovered" banner on the way out would be true for
    // less than a second and wrong afterwards.  The state is cleared all
    // the same, and the log line `clearStuck` wrote says it happened.
    if (lock.synchronized(stopping)) ()
    else {
      // "the next render will boot a fresh one" is TRUE whether or not
      // there WAS a session to throw away: `discardSession` on an empty
      // preview does nothing, and an empty preview boots on its next
      // render either way.
      val why = scrubUrls(RecoveredMessage + (if (rebuilt) " " + RebuiltMessage else ""))
      guard(notify(StuckNotification, Json.obj(
        "stuck"   -> Json.Bool(false),
        "message" -> Json.Str(why),
        "seq"     -> Json.num(seq.toInt))))
      guard(notify(ShowMessage, Json.obj(
        "type"    -> Json.num(3),              // Info
        "message" -> Json.Str(why))))
    }
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

  /** THE FRONT HALF OF A RENDER AND OF A SCHEMA, one function so the two
    * cannot drift (Q7, decided by the user on 2026-09-20).  It answers
    * either "this cannot be served, and here is why" or the MODULE the
    * request names; the session itself is the field `runner`, which the
    * `ensureSession` inside has booted, found, or discarded and re-booted.
    *
    * IN ORDER, and every step is the one `doRender` already had: the path
    * from the URI, the report's own inferred root (Q5's four honest reasons
    * kept in its `Left`), the root set of §2.4 (Q6's rule lives inside
    * `rootSet`), the session those roots imply, §2.5's mtime scan, the
    * module the FINAL roots make of the path -- and, new with Q7, the
    * SHADOW test below.
    *
    * WHY A SCHEMA GOES THROUGH IT TOO.  Before Q7 `ermine/schema` carried
    * `{module, binding}` and could compute no root set at all, so it
    * answered from whatever session a render had booted and otherwise
    * booted one over `moduleRoots` alone: it could describe a SAME-NAMED
    * module under a resident root instead of the workspace report,
    * invisibly, and the first render then paid a second boot to replace
    * that session.  The request now carries `{uri, binding, roots}` and
    * this method is the whole of the difference -- a schema and the render
    * that follows it compute the same roots from the same functions, so
    * they share ONE session in either order.
    *
    * WHAT EACH CALLER STILL DOES ON ITS OWN: its ANSWER SHAPE (§4's
    * `{ok:false, status, message, generation}` for a render, `{error}` for
    * a schema), the 503 "not connected" (§7.2 -- a render scans, a schema
    * does not), and the work itself: `renderText` under the document-size
    * cap, or `paramSchema`. */
  private def placeAndSession(uri: String, reqRoots: List[String],
                              progress: Json, job: Answering): Either[CannotServe, String] = {
    // N3: normalised ONCE, here, so that the module lookup, the inferred
    // root and the discard key below all speak of the same spelling.
    val path  = Documents.pathFor(uri) map Session.normalize
    // Q5 (decided 2026-09-20, option (i)): the inferred root is computed
    // ONCE, here, and its FAILURE is kept -- it is the only thing that can
    // explain the 404 below, and re-deriving it there would read the file a
    // second time.
    val placed = path map inferredRoot
    val roots  = rootSet(reqRoots, path, placed flatMap (_.toOption))
    // The boot inside is UNWATCHED and the watchdog is re-armed as it ends,
    // by `ensureSession` itself (review M2): nothing is needed here.
    ensureSession(roots, progress, job) match {
      case Left(why) => Left(CannotServe(500, why))
      case Right(_) =>
        // The same mtime scan at the head of every job that will read a
        // module (§2.5): a schema exported from a module that moved on disk
        // would describe the file as it was, and the render that follows
        // would decode against the file as it is.
        scanForMovedFiles()
        path match {
          case None    => Left(CannotServe(400, "not a file: URI: " + uri))
          case Some(p) => Session.moduleUnder(roots, p) match {
            case None         => Left(CannotServe(404, cannotPlace(p, placed)))
            case Some(module) => shadowedPick(roots, module, p) match {
              case Some(why) => Left(CannotServe(ShadowedStatus, why))
              case None      => Right(module)
            }
          }
        }
    }
  }

  /** Q7, PART 2 (decided by the user on 2026-09-20): A SHADOWED PICK IS AN
    * ERROR, NOT A SILENT SUBSTITUTION.
    *
    * The resident's `moduleRoots` keep LEADING the root set -- §2.2 wants
    * both sessions to register EQUAL SHAPES for a shared module name, and
    * putting the resident's own roots first is what buys that -- so a
    * picked file whose header names a module a resident root also has is
    * NOT the file the loader would read.  Q6 made the REQUEST's own roots
    * safe; this is what remained, and the answer is an error naming both
    * files rather than a silent substitution.
    *
    * THE TEST is the loader's own question over the FINAL root chain: does
    * `<root>/A/B.e`, first root that has it, answer the file that was
    * PICKED?  When it does not, neither a render nor a schema may use the
    * other file.
    *
    * WHICH CASES CAN STILL SHADOW, after Q6 and as built:
    *  - A RESIDENT `moduleRoots` ENTRY, always.  It precedes every other
    *    root in BOTH branches of `rootSet`, so it wins whatever the request
    *    says.  This is the case the Q6 review found, and this is its answer;
    *  - a CONFIGURED root, but only when NO root could be inferred for the
    *    pick (an unreadable file, a header that does not parse, a module
    *    name deeper than the directories above it) and the path is under a
    *    configured root all the same: `rootSet` then has no inferred root to
    *    splice in, so an earlier configured root's copy of that name leads.
    *    Before Q7 that rendered the other file silently.
    * WHICH CANNOT, which is Q6's guarantee restated -- AND ONLY WHEN A ROOT
    * COULD BE INFERRED, which is the qualifier the whole sentence turns on:
    * an earlier entry of `ermine.preview.roots` cannot shadow a pick WHOSE
    * OWN ROOT WAS INFERRED.  Either the configured chain already resolves
    * the module back to the picked file (`configuredPlaces`, test (b)) and
    * there is nothing to shadow, or it does not and the file's OWN inferred
    * root is spliced in AHEAD of `req.roots`, where it out-ranks them.
    * Without an inferred root there is nothing to splice, and then a
    * configured root CAN shadow and earns the 409 -- the second case in the
    * list above, and the reason that list and this one must be read
    * together.  The
    * case worth spelling out because it looks dangerous and is not: the
    * inferred root EQUALS a LATER configured root -- the file is picked in
    * `B` while `A`, listed first, has the same module name.  Test (b) fails,
    * `B` goes in ahead of `A`, and the pick wins; the Q6 property "one name,
    * two roots" is exactly that case and is unchanged by this.
    *
    * WHAT IS PRINTED, and why it is allowed.  The SHADOWING FILE'S PATH and
    * the ROOT it sits under, beside the picked file's NAME.  Rule A5 (§8.1)
    * is about JDBC URLs, hosts and credentials -- and this message goes
    * through the same scrub every other one does -- while a message that
    * said only "something shadows this" would leave the developer with no
    * way to find it.  The shadowing file is an Ermine source file in a
    * directory the CLIENT or the SERVER configured as a module root; it is
    * not a secret, and naming it is the only useful thing this answer can
    * say.  The picked file is named by its NAME alone, because the REQUEST
    * supplied its URI and nothing here needs to echo a server-side spelling
    * back.
    *
    * TWO PATHS THAT SPELL THE SAME FILE ARE NOT A SHADOW (review must-fix,
    * 2026-09-20).  `Session.normalize` is `toAbsolutePath.normalize`
    * (`Session.scala:733-735`) -- PURELY SYNTACTIC, it does not resolve a
    * symbolic link -- so one directory reachable under two spellings would
    * otherwise refuse a legitimate pick: `moduleRoots` says
    * `/data/proj/reports`, the editor sends `/home/me/proj/reports/Rpt.e`
    * through a link, `resolvedUnder` answers the first spelling, and the
    * strings differ though the FILE is the same one. That configuration
    * rendered before Q7 and must go on rendering. So the string test is the
    * FAST path and `sameFile` -- one `Files.isSameFile` syscall, on the
    * would-be-refusal path only -- is what decides.
    *
    * IT COSTS WHAT `resolvedFile` COSTS -- at most one `File.exists` per
    * root, no read, and the one `isSameFile` above -- and it runs BEFORE
    * THE LOAD: when this answers, nothing of the wrong file has been
    * parsed, typechecked or evaluated.
    *
    * IT RUNS AFTER `ensureSession`, NOT BEFORE (orchestrator's decision,
    * 2026-09-20, recorded here rather than left to the next reader): moving
    * it ahead of the boot would change which refusal WINS among the 400,
    * the 404 and the 500 a failed boot answers, and the boot is not wasted
    * work -- it is the session the next request reuses. */
  private def shadowedPick(roots: List[String], module: String, p: Path): Option[String] =
    resolvedUnder(roots, module) match {
      case Some((root, other)) if other != p && !sameFile(other, p) =>
        val why =
          // "is module X under this session's roots" and NOT "declares
          // module X": `module` is what `Session.moduleUnder` makes of the
          // path over the FINAL chain, which is the file's own header in
          // every case but one -- a pick whose header could not be read at
          // all, where there is no inferred root and the name is the
          // chain's.  A message that claimed the file declared it would be
          // wrong in exactly the case this check newly catches.
          "shadowed pick: " + fileName(p) + " is module " + module +
          " under this session's roots, but the module root " + root +
          " comes first in the chain and resolves " + module + " to " + other +
          ", so that file, and not the one picked, is what would be loaded. Nothing was loaded."
        log("preview: " + why + " (the picked file is " + p + ")")
        Some(why)
      // `None` is NOT a shadow: `moduleUnder` has already answered, so the
      // path is under some root, and whatever the chain cannot resolve is
      // the LOAD's to complain about in its own words.
      case _ => None
    }

  /** Do these two paths name the SAME FILE on disk?  `false` on ANY
    * throwable: a path that cannot be stat'ed (it vanished between the
    * resolve and this call, or the filesystem refuses) is not evidence that
    * two spellings agree.  Asked only when the two strings already DIFFER,
    * so the syscall is off every ordinary path.
    *
    * `false` IS NOT "THE CONSERVATIVE ANSWER" IN ONE DIRECTION -- the two
    * callers move in OPPOSITE directions from it, and the earlier wording
    * here said otherwise (review nit, 2026-09-20):
    *  - `shadowedPick` reads `false` as "these really are two files" and
    *    REFUSES the render, loudly, with a 409.  Falling back to `false`
    *    there is the SAFE answer about the wrong file but the STRICT one
    *    about the user: a stat that failed costs a legitimate pick its
    *    render;
    *  - `configuredPlaces` reads `false` as "the configured chain does not
    *    resolve this name back to this file" and SPLICES THE INFERRED ROOT
    *    IN, which serves the render and costs at most one session re-boot.
    * So the same failure is strict on one path and permissive on the other.
    * That is not an inconsistency to fix: each caller wants "I could not
    * establish that these are one file", and what follows from it is the
    * caller's, not this method's. */
  private def sameFile(a: Path, b: Path): Boolean =
    try java.nio.file.Files.isSameFile(a, b) catch { case _: Throwable => false }

  /** One render, §4's two answer shapes.  The front half -- roots, session,
    * mtime scan, module, Q7's shadow test -- is `placeAndSession`, shared
    * with `doSchema`; what is left here is the connection, the document and
    * the size cap. */
  private def doRender(r: Render): Unit =
    placeAndSession(r.req.uri, r.req.roots, r.progress, r) match {
      case Left(no)      => finish(r, failure(r.req.generation, no.status, no.message, None))
      case Right(module) =>
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
              // DD-1: the ONE place a render learns that the EVALUATION
              // failed.  `>= 500` is `Runner`'s `Failed`; see `evalFailed`
              // for why a 400 and a 404 are not this.
              if (e.status >= 500) evalFailed = true
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

  /** `ermine/schema {uri, binding, roots}` (§4, §6), on the preview thread:
    * `Runner.paramSchema`, which compiles the report through the very cache
    * a render uses and exports the schema from the very `paramTy` the
    * decoder was compiled from -- so the params file's squiggles and the
    * 400s a bad value earns cannot disagree.
    *
    * WHICH SESSION: the one `placeAndSession` answers with, which is the
    * one a render with these roots would use.  That is Q7's whole point and
    * it replaces the old fallback ("answer from whatever session a render
    * booted, else boot one over `moduleRoots` alone"), whose two failures
    * the stage B review had written down: it could describe the WRONG
    * module of that name, and the first render after it paid a second boot.
    *
    * `{error}` AND NOT §4's `{ok:false, ...}`: the shape is the request's,
    * not the reason's.  The REASONS are now a render's own, word for word
    * (Q5's honest 404 texts included), because they come from the shared
    * front half. */
  private def doSchema(s: Schema): Unit =
    placeAndSession(s.req.uri, s.req.roots, s.progress, s) match {
      case Left(no)      => finish(s, schemaError(no.message))
      case Right(module) =>
        runner.paramSchema(module, s.req.binding) match {
          // DD-1, by the same rule as `doRender`: `paramSchema` COMPILES the
          // report, which evaluates the binding, so its `Failed` is a
          // forcing failure exactly as a render's is.
          case Left(e)  =>
            if (e.status >= 500) evalFailed = true
            finish(s, schemaError(scrubUrls(e.message)))
          case Right(j) => finish(s, com.clarifi.reporting.ermine.json.LspSchema.toLsp(j))
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
    * report's inferred root, then the request's -- EXCEPT when the
    * configured roots already place the file, which is Q6.
    *
    * EVERY ENTRY IS NORMALISED FIRST (N3).  `distinct` decides the set, and
    * the set is the discard key of §2.4 -- two spellings of one directory
    * (`/a/b` and `/a/./b`, a relative entry) would otherwise look like a
    * change of roots and throw away a booted session for nothing.
    * Absolutising also matters for the request's own entries: a relative one
    * would resolve against the server's working directory, which is the
    * checkout `bin/ermine-lsp` runs in.  `reqRoots` arrive normalised from
    * the request parser (`Preview.rootEntries`, shared by `ermine/render`
    * and `ermine/schema` since Q7), which refuses the entries that cannot
    * be.  A
    * resident root that cannot be made into a path is logged and dropped,
    * which is what `Main` does with the same value at `initialize`.
    *
    * Q6 (decided by the user on 2026-09-20).  The inferred root was spliced
    * in AHEAD of `req.roots`, so two reports in two directories that are
    * BOTH configured produced two different LISTS of the same directories --
    * `[M, A, B]` for a report under `A`, `[M, B, A]` for one under `B` --
    * and §2.4's discard-on-change then re-booted the render session on every
    * switch, for ever, for nothing.  The rule now: if the CONFIGURED roots
    * (`moduleRoots` then the request's, normalised) already place the file
    * under the module name its OWN HEADER declares, the inferred root is not
    * added; otherwise it is added exactly as before.
    *
    * IT NEVER CHANGES THE SET, ONLY THE ORDER.  `configuredPlaces` is true
    * only when some configured root `r` satisfies `p == r/<module>.e`, and
    * that `r` IS `inferredRoot(p)` -- so the entry the branch drops is one
    * `distinct` would have collapsed anyway.  What the branch drops is its
    * POSITION: the chain is the configured order, the same list for every
    * report under a configured root, which is what makes the session
    * survive a switch. */
  private def rootSet(reqRoots: List[String], path: Option[Path],
                      placed: Option[Placed]): List[String] = {
    // ONE call to `moduleRoots()`: it is a function the server supplies and
    // two calls could answer differently, which would make the two branches
    // below disagree about the set.
    val resident   = moduleRoots().flatMap(normalRoot)
    val configured = (resident ++ reqRoots).distinct
    val redundant  =
      (for { p <- path; pl <- placed } yield configuredPlaces(configured, p, pl.module)) == Some(true)
    if (redundant) configured
    else (resident ++ placed.map(_.root).toList ++ reqRoots).distinct
  }

  /** Q6's test, in TWO parts, and both are needed for the rule to be sound.
    *
    * (a) `Session.moduleUnder(configured, p) == Some(module)`: the name the
    * render will derive for this very path from the FINAL root set is the
    * name its header declares.  `moduleUnder` answers for the FIRST root in
    * the list that contains `p` (`Session.scala:739-744`, `collectFirst`),
    * so a root ABOVE the file's own -- `/w` before `/w/sub` for
    * `/w/sub/Rpt.e` whose header says `module Rpt` -- answers `sub.Rpt`,
    * which is not what the file says it is, and the inferred root must then
    * go in so that the file is read under its own name.
    *
    * (b) THE SOUNDNESS HALF, without which (a) alone is wrong.  The LOADER
    * does not resolve a module through `moduleUnder`; it walks the root
    * chain asking each for `<root>/A/B.e` and takes the FIRST that EXISTS
    * (`Session.SourceFile.filesystem`, `:378-382`, chained by `inOrder` at
    * `Runner.scala:415-416`).  So if a module of the SAME NAME exists under
    * an EARLIER configured root, dropping the inferred root would make the
    * render load THAT file -- a different file from the one the user picked,
    * with no error anywhere.  (b) asks the chain the loader's own question:
    * does `configured` resolve `module` back to THIS path?  When it does,
    * the inferred root cannot change the answer and is not needed; when it
    * does not, the inferred root goes in as before and, sitting ahead of
    * `req.roots`, keeps the picked file's own tree winning.
    *
    * WHAT IS NOT PINNED, stated rather than hidden: (b) covers the picked
    * report's OWN module name.  For any OTHER name -- a widget two roots
    * both define -- the configured order now decides, where the inferred
    * root used to give the picked file's directory the first say ahead of
    * `req.roots`.  §2.4 says so.
    *
    * It costs at most one `File.exists` per configured root and reads no
    * file: the header was already parsed once, by `inferredRoot`. */
  private def configuredPlaces(configured: List[String], p: Path, module: String): Boolean =
    Session.moduleUnder(configured, p) == Some(module) && (resolvedFile(configured, module) match {
      // THE SAME `sameFile` TOLERANCE Q7's shadow test needs, and for the
      // same reason (`Session.normalize` does not follow a symbolic link).
      // The stakes are lower here -- a mismatch only splices the inferred
      // root in, which is benign and costs a re-boot -- but the question
      // ("does the configured chain resolve this name back to THIS file?")
      // is the same question, and two answers to it would be the drift this
      // pair of tests exists to prevent.
      case Some(f) => f == p || sameFile(f, p)
      case None    => false
    })

  /** The file the LOADER would read for `module` over `roots`: the first
    * root that has `<root>/A/B.e`, normalised.  This is
    * `SourceFile.inOrder`'s own rule (`find (_ isDefined)`) over the very
    * `SourceFile.filesystem` loaders `Runner` chains, asked without building
    * a session.  `None` when no root has it -- and when a path cannot be
    * made, which answers "the configured roots do not resolve it here" and
    * therefore keeps today's behaviour. */
  private def resolvedFile(roots: List[String], module: String): Option[Path] =
    resolvedUnder(roots, module) map (_._2)

  /** `resolvedFile`, with the ROOT that answered beside the file it
    * answered with.  Q7's shadow message has to say WHICH root shadows the
    * pick, and this walk is the only place that knows. */
  private def resolvedUnder(roots: List[String], module: String): Option[(String, Path)] =
    try roots.iterator.map(r => (r, Session.SourceFile.filesystem(r)(module)))
             .find(_._2.isDefined)
             .flatMap {
               case (r, Some(Session.Filesystem(f, _))) => Some((r, Session.normalize(f)))
               case _                                   => None
             }
    catch { case e: Throwable => log("preview: cannot resolve " + module + ": " + messageOf(e)); None }

  /** THE 404's MESSAGE (Q5, decided by the user on 2026-09-20 as option (i):
    * keep `inferredRoot` in the root set -- it is §2.4's zero-configuration
    * promise -- and make the 404 say what is actually wrong instead).
    *
    * §2.4 puts the picked report's OWN inferred root in the root set, so any
    * readable `.e` file whose module header parses is under a root by
    * construction and this message is unreachable for it.  What reaches it
    * is a file that could not be PLACED at all, and the four ways that
    * happens are cheap to tell apart, so each says so:
    *   - the path is not an Ermine source file (`moduleUnder` requires `.e`);
    *   - the file cannot be read -- deleted, or unreadable: the case an
    *     extension holding a stale pick sends;
    *   - its module header does not parse;
    *   - its module name is deeper than the directories above it.
    * The last three are `inferredRoot`'s own three refusals, carried here
    * rather than swallowed.
    *
    * NO ABSOLUTE PATH: the file's NAME only.  The request supplied the URI
    * and the client can map a name back to it, but nothing here puts a
    * server-side directory on the wire.  `failure` scrubs the result like
    * every other message (§8 rule A5). */
  private def cannotPlace(p: Path, placed: Option[Either[String, Placed]]): String =
    if (!p.toString.endsWith(".e")) "not an Ermine source file: " + fileName(p)
    else placed match {
      case Some(Left(why)) => why
      // Unreachable as built -- an inferred root IS a root and `p` is under
      // it -- but a general sentence rather than a wrong one if it ever is.
      case _               => "cannot be placed under any module root: " + fileName(p)
    }

  /** A path's last segment, for a message.  The filesystem root has none,
    * and "null" in an answer would be worse than a vague noun. */
  private def fileName(p: Path): String =
    Option(p.getFileName).map(_.toString).getOrElse("the file")

  private def normalRoot(r: String): Option[String] =
    try Some(Session.normalize(r).toString)
    catch { case e: Throwable => log("preview: module root dropped, not a path: " + r); None }

  /** The root a file's OWN module name implies: parse the header and walk up
    * one directory per extra segment, as `Resident.checkFile` does for a
    * check's siblings.  `p` is already absolute and normalised, so what
    * comes back is too.
    *
    * A `Left`, never a guess, in three cases: the file cannot be read; its
    * header cannot be parsed; or the module name has MORE segments than the
    * path has parent directories (`module A.B.C` in `/tmp`), where the walk
    * runs out and the loop's `d.isDefined` guard ends it empty.
    * `Resident.checkFile` falls back to the file's own directory in that
    * last case; the preview does not, because a guessed root puts the file
    * under a root under a WRONG module name and the render would then fail
    * with a message about the wrong module.  A `Left` leaves the other roots
    * to answer, and a 404 if none of them does.
    *
    * Q5: THE `Left` CARRIES THE REASON, in the words the 404 says (see
    * `cannotPlace`).  It names the FILE and never its directory, and never
    * the exception's own text: `Session.Filesystem.contents` dies with
    * "File '<absolute path>' does not exist." and a parser error carries the
    * source name it was built with, so neither may be quoted.  The absolute
    * path goes to the LOG, which is the server's own and is scrubbed.
    *
    * Q6: THE `Right` CARRIES THE HEADER'S MODULE NAME BESIDE THE ROOT.
    * `rootSet` has to compare that name with what the configured roots make
    * of the path, and the header is parsed HERE; answering only the root
    * would mean reading and parsing the file a second time. */
  private def inferredRoot(p: Path): Either[String, Placed] = {
    val name = fileName(p)
    // The `SourceFile` is built INSIDE the `try` as it was before Q5: this
    // method answers a `Left`, never throws, and nothing on the way to the
    // contents may escape it.
    val opened =
      try {
        val f = Session.Filesystem(p.toString, exotic = true)
        Right((f, f.contents))
      } catch { case e: Throwable =>
        log("preview: cannot read " + p + ": " + messageOf(e))
        Left("cannot read " + name)
      }
    opened match {
      case Left(why) => Left(why)
      case Right((file, text)) =>
        val header =
          try {
            implicit val su: Supply = headerSupply
            val (_, mh) = Session.parse(
              ModuleParsers.moduleHeader(file.defaultModuleName),
              ErParseState.mk(file.toString, text, file.defaultModuleName))
            Right(mh.name)
          } catch { case e: Throwable =>
            log("preview: no module header parsed from " + p + ": " + messageOf(e))
            Left("no module header could be read from " + name)
          }
        header match {
          case Left(why) => Left(why)
          case Right(module) =>
            var d = Option(p.getParent)
            var i = module.split('.').length - 1
            while (i > 0 && d.isDefined) { d = Option(d.get.getParent); i -= 1 }
            val tooDeep =
              "the module header of " + name + " names " + module +
              ", which is deeper than the directories above it"
            if (i > 0) { log("preview: no root inferred for " + p + ": " + tooDeep); Left(tooDeep) }
            else d match {
              case Some(r) => Right(Placed(r.toString, module))
              case None    => log("preview: no root inferred for " + p + ": " + tooDeep); Left(tooDeep)
            }
        }
    }
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
    * render does BEFORE this bracket, which is `inferredRoot` and the
    * `rootSet` built from it -- and `inferredRoot` reads the report's file
    * and parses its module header.  At
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
    var seq       = 0L
    var queued    = List.empty[Job]
    try lock.synchronized {
      if ((inFlight eq job) && epoch == armEpoch && !answeredInFlight) {
        answeredInFlight = true
        stuck    = true
        stuckWhy = why
        // Q10: WHICH job this fired on, so that `runJob`'s `finally` can
        // tell "the wedged evaluation came back" from "some later job
        // ended".  Written in the same locked step as `stuck` itself, so
        // the pair is never half-set.
        stuckJob = job
        mine     = true
        // IM-1: minted HERE, inside the same locked step as the flip, so
        // that this rising edge and any later falling one are ordered by a
        // number even though they are sent by two different threads.
        stuckSeq += 1
        seq      = stuckSeq
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
      // Q8: `stuckRefusal` -- `"stuck": true` -- on the answer this
      // watchdog sends and on each of the queue's.  NOT on the `-32800`
      // branch above it: a JSON-RPC ERROR carries `{code, message}` and no
      // result object at all, so there is nowhere to put a marker and the
      // client learns the state from `ermine/preview/stuck` instead.  The
      // same is true of every other -32800 here (a displaced render, a
      // cancelled one, the shutdown drain).
      guard(if (cancelled) job.answer(Left((Rpc.RequestCancelled, "cancelled")))
            else job.answer(Right(job.stuckRefusal(why))))
      queued foreach {
        case a: Answering =>
          guard(releaseToken(a))
          guard(log("preview: queued job " + Json.print(a.id) + " refused: the preview is stuck"))
          guard(a.answer(Right(a.stuckRefusal(why))))
        // An `Invalidate` or a `DiscardSession` owes nobody an answer, and
        // a wedged session will never apply either: dropped, not kept.
        case _ => ()
      }
      // §2.5's notification, from the TIMER thread through `notify` (§4:
      // "the render watchdog therefore uses a `Timer` thread and the
      // synchronised `send`").  `window/showMessage` is the LSP's own
      // server-to-client NOTIFICATION for this, and it is KEPT because it
      // is what ANY LSP client shows without knowing this server at all.
      // `ask` -- which `window/showMessageRequest` would need for a
      // clickable item -- is dispatch-thread-only and this thread may not
      // call it; and even from the dispatch thread it would not help, for
      // the reason Q8 records: the response names the chosen action TO THE
      // SERVER, and the LSP gives a server no way to make the client run
      // the client-side `ermine.restartServer` command (*external*,
      // unverified here).  So the action is NAMED in the text, and the
      // BUTTON is the panel's, in the extension (WP-7's banner states;
      // resolution A4 says the button lands there).
      guard(notify(ShowMessage, Json.obj(
        "type"    -> Json.num(1),              // Error
        // SCRUBBED like every other thing this file sends (review nit).
        // `why` is built by `timedOutMessage` from a constant and a number
        // and carries no URL today; rule A5 is structural, not a per-site
        // judgement, and WP-13 will widen what a message may contain.
        "message" -> Json.Str(scrubUrls(why)))))
      // Q8(b): and the panel's own row (§4), BESIDE the standard one and
      // not instead of it -- `window/showMessage` has no place to carry a
      // state flag, and WP-7's banner needs the rising edge to know it may
      // offer the button at all (a refusal's `"stuck": true` only tells it
      // about requests it made).  Timer thread, `notify`, outside `lock`,
      // guarded, through the scrub.
      guard(notify(StuckNotification, Json.obj(
        "stuck"   -> Json.Bool(true),
        "message" -> Json.Str(scrubUrls(why)),
        "seq"     -> Json.num(seq.toInt))))
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
    // REWORDED once Q10 existed (review SHOULD-FIX 2).  The old text said
    // "the preview is stuck until the language server is restarted", which
    // was the whole truth before the state could clear and is now only the
    // worst case: the wedge ends by itself if the evaluation ever finishes.
    // Saying the false thing first would train a user to restart a server
    // that was about to recover.  Both substrings §2.5 and the group-D
    // property pin -- the title and the command id -- are kept.
    "evaluation did not finish after " + (millis / 1000L) + "s; the preview is stuck. " +
    "It recovers by itself if that evaluation ever finishes; if it does not, restart the " +
    "language server -- run \"" + RestartTitle + "\" (" + RestartCommand + ")"

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

  /** Q8(b), decided 2026-09-20: §4's own server-to-client notification for
    * the stuck state, `{stuck: true|false, message}`.  `true` from the
    * watchdog's `fire`, `false` from `recovered` when Q10's wedged job
    * comes back; both beside a `window/showMessage`, never instead of one.
    * WP-7's banner is the reader, and the RESTART BUTTON is its, for the
    * reason Q8 records -- an LSP client's answer to a
    * `window/showMessageRequest` names the chosen action TO THE SERVER,
    * and nothing in the protocol lets a server make the client run the
    * client-side `ermine.restartServer` (*external*). */
  private val StuckNotification = "ermine/preview/stuck"

  /** What `recovered` says, in both of its messages (Q10).  It names the
    * ONE thing the user has to do that the server cannot: re-render, because
    * every `ermine/preview/invalidated` of the stuck interval was dropped
    * unsent.  No path, no file name, nothing a scrub would have to remove --
    * and it goes through the scrub all the same. */
  private val RecoveredMessage =
    "Ermine preview: the evaluation the watchdog gave up on has finished, and the preview " +
    "is serving renders again. Files saved while it was stuck were not announced, and any " +
    "params schema asked for meanwhile was refused, so re-render the report and ask for its " +
    "schema again."

  /** The second half of `recovered`'s text, added only when the wedged job
    * ended by THROWING and the render session was therefore discarded
    * (DM-1).  True whether or not a session existed: an empty preview boots
    * on its next render either way. */
  private val RebuiltMessage =
    "The render session was discarded because that evaluation ended in an error, so the " +
    "next render boots a fresh one."
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
    /** The `window/workDoneProgress/create` token the DISPATCH thread
      * minted for this job because no session was up when it was enqueued,
      * or `null` (§2.5).  ON THE TRAIT since Q7 rather than on `Render`: a
      * SCHEMA can be the job that boots -- a first pick asks for the schema
      * before it renders -- and it mints its token through the very same
      * `mintBootToken`, under the very same at-most-one-outstanding rule.
      * It travels on the job so that the preview thread needs no shared
      * state to know which token its boot belongs to. */
    def progress: Json
    /** This job's own shape for "it did not work": §4's `{ok: false, ...}`
      * for a render, `ermine/schema`'s `{error}` for a schema.  So that a
      * client gets a failure in the shape of the request it made rather
      * than a JSON-RPC error it has no branch for.
      *
      * THE CRASH HANDLER'S SHAPE, and since Q8 that is all it is: a job
      * that RAN and failed. */
    def refusal(message: String): Json

    /** The SAME shape plus `"stuck": true` (Q8, decided 2026-09-20): the
      * marker a client reads to know this failure is §2.5's WEDGE and not
      * an ordinary one, so that WP-7's banner may offer the restart button
      * beside it.
      *
      * A SECOND METHOD AND NOT A FLAG ON `refusal`, which is the whole
      * point: `refusal` is also what the job CRASH handler answers with,
      * and a crash is a report that failed, not a preview that is stuck.
      * One shared builder with the marker in it would have put `"stuck":
      * true` on every 500 a broken report produces -- the design review
      * caught exactly that -- and no test over the stuck paths alone would
      * have seen it.  EXACTLY FOUR CALLERS: the two stuck refusals in
      * `render` and `schema`, the watchdog's own answer, and the answers
      * its queue drain sends.
      *
      * NOTHING CARRIES IT ON A `-32800` PATH -- a displaced render, a
      * cancelled one, the shutdown drain, and the watchdog's answer to a
      * request that had been CANCELLED -- because a JSON-RPC error has no
      * result object to put it in.  Those clients learn the state from
      * `ermine/preview/stuck` instead. */
    def stuckRefusal(message: String): Json
  }

  final case class Render(id: Json, req: RenderRequest, dirtyAt: Long,
                          progress: Json, answer: Rpc.Answer) extends Answering {
    def refusal(message: String): Json = failure(req.generation, 500, message, None)
    def stuckRefusal(message: String): Json = withStuck(refusal(message))
  }

  /** Q7: a schema job carries the same three things a render does -- the
    * file, the binding and the roots -- because it resolves the report the
    * way a render does (`Preview.placeAndSession`). */
  final case class Schema(id: Json, req: SchemaRequest,
                          progress: Json, answer: Rpc.Answer) extends Answering {
    def refusal(message: String): Json = Json.obj("error" -> Json.Str(scrubUrls(message)))
    // Q8: BESIDE `error`, which is the whole of `ermine/schema`'s failure
    // shape -- there is no `ok`/`status` here to hang it off.
    def stuckRefusal(message: String): Json = withStuck(refusal(message))
  }

  final case class Invalidate(paths: Set[Path]) extends Job
  case object DiscardSession extends Job

  /** Q7's answer to a SHADOWED PICK: the picked file is not the file this
    * session's root chain resolves its module to (`Preview.shadowedPick`).
    * 409 CONFLICT is the HTTP status for "the request cannot be applied to
    * the current state of the target" (*external*), which is exactly this:
    * nothing about the request is malformed (400), the module is found
    * (404), and the render could not fail either (500) because it was never
    * run.  It costs no new vocabulary anywhere -- `failure` takes a status
    * NUMBER, and `json/Runner.scala`'s `RunError`, which the HTTP server
    * shares, is not on this path and is untouched. */
  private[lsp] val ShadowedStatus = 409

  /** What the shared front half answers when it cannot serve a request:
    * ONE reason, in ONE status, which each caller then dresses in its own
    * shape -- §4's `{ok:false, status, message, generation}` for a render,
    * `{error}` for a schema.  That is the whole of "they cannot drift":
    * both know the same reasons and neither can invent one. */
  private[lsp] final case class CannotServe(status: Int, message: String)

  /** §4's failure shape.  On the companion since stage B, because each
    * `Answering` builds its own refusal. */
  private def failure(generation: Json, status: Int, message: String, path: Option[String]): Json =
    Json.Obj(List("ok" -> Json.Bool(false), "status" -> Json.num(status),
                  "message" -> Json.Str(scrubUrls(message))) ++
             path.toList.map(p => "path" -> Json.Str(p)) ++
             List("generation" -> generation))

  /** Q8's marker, APPENDED so that neither §4 shape's existing key order
    * moves: a render failure keeps `{ok, status, message, path?,
    * generation}` and gains `stuck` after it, and `ermine/schema`'s
    * `{error}` gains it beside.  A `Json` that is not an object is handed
    * back untouched -- unreachable from the two callers, and a `match` with
    * no default would be a crash on the one path in this file that must not
    * have one. */
  private def withStuck(j: Json): Json = j match {
    case Json.Obj(fs) => Json.Obj(fs ::: List("stuck" -> Json.Bool(true)))
    case other        => other
  }

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

  /** `ermine/schema`'s binding form (§4, §6), Q7's shape: THE SAME THREE
    * KEYS A RENDER IDENTIFIES ITS REPORT BY.  `module` is gone, and a
    * request that still sends `binding` without `uri` is an `{error}`
    * naming the key it is missing -- not a compatibility path back to the
    * old form, because there is no extension code to be compatible with
    * yet (WP-7/WP-8) and the old form's hazard was the point of Q7: a
    * module NAME alone cannot say which of two files of that name is
    * meant. */
  final case class SchemaRequest(uri: String, binding: String, roots: List[String])

  object SchemaRequest {
    def parse(params: Json): Either[String, SchemaRequest] =
      (params / "uri" flatMap (_.str), params / "binding" flatMap (_.str)) match {
        case (None, _) => Left("ermine/schema needs a \"uri\" naming the report's file")
        case (_, None) => Left("ermine/schema needs a \"binding\" naming the report")
        case (Some(u), Some(b)) =>
          rootEntries(params).right.map(rs => SchemaRequest(u, b, rs))
      }
  }

  /** What `Preview.inferredRoot` answers when it COULD place a file: the
    * root the header implies, and the module name the header declares.  The
    * name is carried beside the root because Q6's rule has to compare it
    * with what the CONFIGURED roots make of the same path, and the header is
    * parsed once, inside `inferredRoot`. */
  private[lsp] final case class Placed(root: String, module: String)

  /** `ermine/render`'s parameters (§4). */
  final case class RenderRequest(uri: String, binding: String, params: Json,
                                 roots: List[String], generation: Json)

  object RenderRequest {
    def parse(params: Json): Either[String, RenderRequest] =
      (params / "uri" flatMap (_.str), params / "binding" flatMap (_.str)) match {
        case (None, _) => Left("\"uri\" is a string naming the report's file")
        case (_, None) => Left("\"binding\" is a string naming the report binding to render")
        case (Some(uri), Some(binding)) =>
          rootEntries(params).right.map(rs => RenderRequest(
            uri, binding,
            params / "params" getOrElse Json.Null,
            rs,
            params / "generation" getOrElse Json.Null))
      }
  }

  /** `ermine.preview.roots`, absolutised, or WHICH ENTRY IS WRONG (S2).
    * A bad entry is a refusal naming it and not a silent drop: the value
    * comes from a per-folder setting the developer wrote, and a root that is
    * quietly ignored is a preview that mysteriously cannot find a module.
    *
    * An EMPTY string is refused for its own reason: `Paths.get("")`
    * normalises to the server's working directory, which is the checkout
    * `bin/ermine-lsp` runs in, so an empty entry would silently add a
    * whole source tree as a module root.
    *
    * IT REFUSES THE SHAPE AS WELL AS THE ENTRIES (review nit, 2026-09-20).
    * The first cut read `roots` as `_.arr getOrElse Nil` and the entries as
    * `flatMap (_.str)`, so a `roots` that was not an array, and an entry
    * that was not a string, were both SILENTLY DROPPED -- the very thing
    * the paragraph above says must not happen, and worse than a bad path,
    * because the request then renders under a root set the developer did
    * not ask for.  Both now name what is wrong and neither echoes the
    * VALUE: `jsonType` says what kind of thing it was, which is what
    * `illTyped` says about a setting.
    *
    * ON THE COMPANION since Q7, not inside `RenderRequest`: `ermine/schema`
    * carries `roots` too, and it must read them by the SAME rules -- a
    * second copy is exactly the drift Q7's shared front half exists to
    * prevent.  Each request still dresses the refusal in its own shape (a
    * 400 for a render, `{error}` for a schema). */
  private def rootEntries(params: Json): Either[String, List[String]] = {
    // ABSENT and `null` are "no roots", which is what a client that has none
    // sends; anything else must really be an array.
    val asked: Either[String, List[Json]] = params / "roots" match {
      case None | Some(Json.Null) => Right(Nil)
      case Some(j) => j.arr match {
        case Some(xs) => Right(xs)
        case None     => Left("\"roots\" is an array of absolute directory paths, not a " + jsonType(j))
      }
    }
    asked.right.flatMap { xs =>
      val each = xs.map { j =>
        j.str match {
          case None => Left("\"roots\" has an entry that is a " + jsonType(j) +
                            "; each root is a string naming an absolute directory")
          case Some(r) if r.trim.isEmpty =>
            Left("\"roots\" has an empty entry; each root is an absolute directory path")
          case Some(r) =>
            try Right(Session.normalize(r).toString)
            catch { case e: Throwable =>
              Left("\"roots\" entry \"" + r + "\" is not a path: " + messageOf(e)) }
        }
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

  /** What KIND of JSON value this is, for a message that must say what is
    * wrong without echoing what was sent.  ON THE COMPANION since the Q7
    * review: `rootEntries` needs it too, and the class reaches it through
    * `import Preview._` exactly as it reaches `failure`. */
  private def jsonType(j: Json): String = j match {
    case Json.Null    => "null"
    case Json.Bool(_) => "boolean"
    case Json.Num(_)  => "number"
    case Json.Str(_)  => "string"
    case Json.Arr(_)  => "array"
    case Json.Obj(_)  => "object"
  }

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
