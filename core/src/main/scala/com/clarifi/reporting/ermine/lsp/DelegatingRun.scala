package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.Run
import com.clarifi.reporting.backends.{ DB, RunDB }

/** WP-4: the `Run[DB]` a preview `Runner` is CONFIGURED with, so that the
  * database underneath it can be swapped without building another one.
  *
  * `RunnerConfig.run` is an immutable case-class field
  * (`json/Runner.scala`), and discarding a `Runner` costs a session boot --
  * the preamble, `Layout.Doc`, `Layout.Fetch` and the report's closure
  * (JSON-WIDGET-PLAYGROUND §2.4).  Connect, disconnect and recycle must not
  * cost that: they are changes of CONNECTION, not of module roots or
  * settings.  So the runner is given one of these, whose `run` forwards to
  * whatever `Run[DB]` is current, and the preview swaps the target
  * (`Runners.fromPersistentConnection(conn)` on connect, nothing on
  * disconnect).  A profile or roots change still discards the `Runner`, as
  * §7.2 step 4 says: those ARE config.
  *
  * WHAT THIS IS NOT.  It holds no connection, opens none, closes none,
  * starts no thread and knows no profile: the preview thread, the
  * connection's lifetime and the wire methods are WP-5, WP-13 and WP-14.
  * This is the forwarding object and its swap, and nothing else.
  *
  * THREADING.  `target` is `@volatile`, so a swap on any thread is seen by
  * the next `run` on the preview thread.  A swap does NOT interrupt a `run`
  * already in flight: it reads the field once and the scan it is driving
  * finishes on the connection it started with, which is what §2.5's "the
  * running one finishes" wants.  One `Run[DB]` is used by one thread
  * (§2.5), so nothing here serialises anything.
  *
  * WHEN NOTHING IS SET, and the one thing WP-4 could not give WP-5.  §4
  * wants a render with no connection answered `{ok: false, status: 503,
  * message: "not connected"}`.  `RunError` is a sealed vocabulary of 400 /
  * 404 / 405 / 413 / 500 (`json/Runner.scala`) with no 503 member, and
  * `Abort` -- the one channel that carries a chosen `RunError` out of a
  * driver run -- is `private[json]`.  A throw from here therefore reaches
  * the client as `Runner.drive`'s `NonFatal` catch, i.e. **500** with this
  * exception's message, not 503.  Rather than add a status to that
  * vocabulary for a caller that does not exist yet, WP-4 offers `connected`:
  * WP-5 asks BEFORE it renders and answers 503 itself, and the throw is the
  * backstop for the race (a disconnect between the question and the scan),
  * which is a genuine failure and 500 is a fair name for it. */
final class DelegatingRun extends RunDB {

  @volatile private var target: Option[Run[DB]] = None

  /** Whether a `run` would reach a database.  WP-5's 503 test. */
  def connected: Boolean = target.isDefined

  /** Point every later `run` at `r`, and ANSWER THE ONE IT REPLACED.  This
    * object owns no connection and closes nothing, so a caller that swaps a
    * live target in (a reconnect after a recycle, §7.2) would otherwise have
    * to remember the old one to close its `Connection`; the previous target
    * is returned rather than dropped so that it cannot be leaked by
    * forgetting. */
  def use(r: Run[DB]): Option[Run[DB]] = {
    val was = target
    target = Some(r)
    was
  }

  /** Point at nothing: every later `run` fails until `use` is called again.
    * Answers the target it removed, for the same reason `use` does. */
  def clear(): Option[Run[DB]] = {
    val was = target
    target = None
    was
  }

  def run[A](a: DB[A]): A = target match {
    case Some(r) => r.run(a)
    case None    => throw new DelegatingRun.NotConnected
  }
}

object DelegatingRun {
  /** What an unset `DelegatingRun` throws.  The message is §4's, so that
    * even through `Runner.drive`'s 500 the client is told which of the two
    * failures it is; `connected` is how a caller avoids meeting it. */
  final class NotConnected
      extends IllegalStateException("not connected")
      with scala.util.control.NoStackTrace
}
