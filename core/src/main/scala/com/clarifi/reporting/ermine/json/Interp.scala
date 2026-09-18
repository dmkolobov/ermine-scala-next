package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.{ Record, SortOrder }
import com.clarifi.reporting.relational.{ Ext, Scanner }
import com.clarifi.machines.{ Plan, Process }
import scala.collection.mutable.ListBuffer
import scala.util.control.NonFatal

/** One step of a report's execution (design note §3.4d).  A report is a
  * stream of these, and `Interp.run` is the only loop that consumes them:
  * the rows a `Fetch` asks for and the rows a relation puts on the wire are
  * read by the same driver, logged the same way and counted in the same
  * `WriteStats`.
  *
  * `Eval` and `Call` are the Ermine side: the driver does not know what a
  * `Runtime` is, so `Eval` is a thunk that answers the steps that follow and
  * `Call`'s continuation is a function of the rows -- both run the runner's
  * evaluation, which takes `evalLock` on its own.  `Runner` builds the
  * `Call`s; it builds no `Eval`, because its first evaluation happens before
  * the driver starts and every later one is a `Call`'s continuation (design
  * note 3.4d).  `Eval` is the arm for a stream that extends itself without a
  * scan, and `TestDoc (ip-fail)`'s generated programs are what exercise it.
  * `Emit`, `Splice` and `Token` are the document side and are built by
  * `Write.steps`.
  */
sealed abstract class Step

object Step {
  /** Evaluate and answer the steps that follow: a `Call` when the report asks
    * for rows, or the document's `Emit`/`Splice`/`Token` steps when it is
    * finished.  The thunk is the runner's, and takes `evalLock` for the
    * forcing and the walk, not for the printing.  A failure of the Ermine
    * side leaves by an exception, which the runner unwraps outside the
    * driver. */
  final case class Eval(next: () => List[Step]) extends Step

  /** Scan `ext` -- OUTSIDE any evaluation lock -- collect every record, and
    * go on with the steps the continuation answers for them.  `path` is the
    * scan's place in the report (`$.fetch[n]`, 1-based), which is what its
    * `RelationStats` and any failure are named by; the runner assigns it,
    * because the numbering is the report's, not the driver's. */
  final case class Call(order: List[(String, SortOrder)],
                        ext: Ext[Nothing, Nothing],
                        path: String,
                        k: List[Record] => List[Step]) extends Step

  /** Append text to the output verbatim. */
  final case class Emit(text: String) extends Step

  /** Scan `data.ext` into a `Rows.Sink` and write the inline relation object
    * at `data.path`.  `threshold` is what `Write.resolve` allowed for this
    * relation (`None`: read every row); a scan that yields one record past it
    * stops there and the relation goes out deferred instead. */
  final case class Splice(data: Doc.Data, threshold: Option[Long]) extends Step

  /** Mint a token for `data` and write the deferred handle; no scan. */
  final case class Token(data: Doc.Data) extends Step
}

/** The one loop (design note §3.4d; tracker/JSON-STAGE3-PLAN.md "Wire
  * contract").  `run` consumes a step stream inside ONE `G` action:
  *
  *  - `Emit(t)`: append `t`.
  *  - `Eval(next)`: force `next()` and push the steps it answers.
  *  - `Call(order, ext, path, k)`: `S.scanExt(ext, collect, order)` collects
  *    the records, a `RelationStats` for `path` is recorded and logged, and
  *    `k(rows)`'s steps are pushed.  The rows go to the report, not to the
  *    output: `bytes` is 0 and no text is written.  J3h reads EVERY row of a
  *    fetch scan -- `cfg.threshold` applies to the wire, not to a `Call`
  *    (tracker/JSON-STAGE3-PLAN.md, open list: "a cap on fetched rows").
  *  - `Splice(data, threshold)` / `Token(data)`: the delivery arms of
  *    §3.4a, exactly as J3b wrote them -- inline through a `Rows.Sink` under
  *    a threshold that defers instead, or a `cache.put` handle.
  *
  * `WriteStats.relations` holds one entry per `Call`, `Splice` and `Token`
  * IN EXECUTION ORDER, so a fetching report's scans come first (they are
  * what produced the document) and the wire relations follow in document
  * order.  Every one is logged at INFO on `ermine.json.doc` in the same
  * `relation <path> <delivery> rows=<n> bytes=<b> ms=<t>` shape.
  *
  * FAILURE.  One exception type, `WriteFailure(path, message, completed,
  * cause)`: a fetch scan that throws is `$.fetch[n]`, a wire relation that
  * throws (or a row that cannot be encoded) is the relation's document path,
  * and `completed` is every step that finished before it -- fetch scans
  * included.  A failure of the Ermine side (a report or a continuation that
  * throws) is not the driver's: it leaves an `Eval` thunk as whatever the
  * runner threw, through this loop untouched.
  *
  * STACK.  The action is a right-nested chain of binds, one per step, as
  * `Write.doc` was before J3h: for `DB` the depth grows with the number of
  * STEPS (relations and scans, not rows, not document nodes).  Steps an
  * `Eval` or a `Call` answers are pushed onto a work LIST, so a report of
  * 2,000 sequential scans is 2,000 binds and no deeper (`TestRunner
  * (ip-stack)`, `TestDoc (ip-stack)`).
  */
object Interp {
  private val log = org.apache.log4j.Logger.getLogger("ermine.json.doc")

  /** What a run has written and read so far.  One per `run`, never shared:
    * the driver is single-threaded inside its `G` action. */
  private final class State {
    var bytes = 0L
    val done = new ListBuffer[RelationStats]
    def add(rs: RelationStats): RelationStats = { done += rs; bytes += rs.bytes; rs }
  }

  /** Run `steps` against `out` inside one `G` action; see the object comment. */
  def run[G[_]](steps: List[Step], out: Appendable, cfg: WriteConfig, cache: PlanCache)
               (implicit S: Scanner[G], X: Guard[G]): G[WriteStats] = {
    val M = S.M
    def go(rest: List[Step], st: State): G[WriteStats] = rest match {
      case Nil => delay(M)(WriteStats(st.done.toList, st.bytes))
      case Step.Emit(t) :: tl =>
        M.bind(delay(M) { out.append(t); st.bytes += Rows.utf8Length(t) })(_ => go(tl, st))
      case Step.Eval(next) :: tl =>
        M.bind(delay(M)(next()))(more => go(more ++ tl, st))
      case Step.Call(order, ext, path, k) :: tl =>
        M.bind(call(order, ext, path, st, cfg.clock))(rows => go(k(rows) ++ tl, st))
      case Step.Splice(d, threshold) :: tl =>
        M.bind(inlined(d, threshold, out, cache, cfg.clock, st.done.toList))(rs => { st.add(rs); go(tl, st) })
      case Step.Token(d) :: tl =>
        M.bind(delay(M) {
          val start = cfg.clock()
          attempt(d.path, st.done.toList, start, cfg.clock)(deferred(d, out, cache, start, cfg.clock, 0L, false))
        })(rs => { st.add(rs); go(tl, st) })
    }
    M.bind(delay(M)(new State))(st => go(steps, st))
  }

  // ---------------------------------------------------------------------
  // the fetch arm: rows for the report

  private def call[G[_]](order: List[(String, SortOrder)], ext: Ext[Nothing, Nothing], path: String,
                         st: State, clock: () => Long)
                        (implicit S: Scanner[G], X: Guard[G]): G[List[Record]] = {
    val M = S.M
    M.bind(delay(M)((clock(), new ListBuffer[Record]))) { case (start, rows) =>
      val collect: Process[Record, Unit] =
        (Plan.await[Record] flatMap { (r: Record) => rows += r; Plan.emit(()) }).repeatedly
      def fail(e: Throwable): Throwable = failure(path, st.done.toList, start, clock, e)
      val scan: G[Unit] =
        try X.guard(S.scanExt(ext, collect, order)(scalaz.std.anyVal.unitInstance))(fail)
        catch { case NonFatal(e) => throw fail(e) }
      M.bind(scan) { _ =>
        delay(M) {
          val got = rows.toList
          val n = got.length.toLong
          // no columns and no bytes: nothing of this scan goes on the wire
          st.add(logged(RelationStats(path, Delivery.Fetched, 0, n, n, 0L, clock() - start, false)))
          got
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // the wire arms (J3b, unchanged but for their home)

  private def inlined[G[_]](d: Doc.Data, threshold: Option[Long], out: Appendable, cache: PlanCache,
                            clock: () => Long, completed: List[RelationStats])
                           (implicit S: Scanner[G], X: Guard[G]): G[RelationStats] = {
    val M = S.M
    M.bind(delay(M)((clock(), new Rows.Sink(d, threshold.getOrElse(Long.MaxValue))))) { case (start, sink) =>
      def fail(e: Throwable): Throwable = failure(d.path, completed, start, clock, e)
      val scan: G[Unit] =
        try X.guard(S.scanExt(d.ext, sink.process, d.order)(scalaz.std.anyVal.unitInstance))(fail)
        catch { case NonFatal(e) => throw fail(e) }
      M.bind(scan) { _ =>
        delay(M) {
          attempt(d.path, completed, start, clock) {
            // a row the encoder refused: the sink left the scan by `Stop` (so the
            // driver tore it down) and kept the error for here
            if (sink.error != null) throw sink.error
            else if (sink.over) deferred(d, out, cache, start, clock, sink.rows + 1, true)
            else {
              val head = new java.lang.StringBuilder
              head.append("{\"").append(Wire.Kind).append("\":\"").append(Wire.Inline).append("\",")
              columns(head, d)
              head.append(",\"").append(Wire.Rows).append("\":[")
              val tail = "],\"" + Wire.RowCount + "\":" + sink.rows + "}"
              val bytes = Rows.utf8Length(head) + Rows.utf8Length(sink.buffer) + tail.length
              out.append(head)
              out.append(sink.buffer)
              out.append(tail)
              logged(RelationStats(d.path, Delivery.Inline, d.columns.length, sink.rows, sink.rows,
                                   bytes, clock() - start, false))
            }
          }
        }
      }
    }
  }

  private def deferred(d: Doc.Data, out: Appendable, cache: PlanCache, start: Long, clock: () => Long,
                       scanned: Long, over: Boolean): RelationStats = {
    val (token, expires) = cache.put(d)
    val sb = new java.lang.StringBuilder
    sb.append("{\"").append(Wire.Kind).append("\":\"").append(Wire.Deferred).append("\",")
    columns(sb, d)
    sb.append(",\"").append(Wire.Token).append("\":")
    Rows.string(sb, token)
    sb.append(",\"").append(Wire.Expires).append("\":\"")
    Rows.timestampFmt.formatTo(expires, sb)
    sb.append("\"}")
    out.append(sb)
    logged(RelationStats(d.path, Delivery.Deferred, d.columns.length, 0L, scanned,
                         Rows.utf8Length(sb), clock() - start, over))
  }

  private def columns(sb: java.lang.StringBuilder, d: Doc.Data): Unit = {
    sb.append('"').append(Wire.Columns).append("\":[")
    var first = true
    d.columns.foreach { c =>
      if (!first) sb.append(',')
      first = false
      sb.append("{\"").append(Wire.Name).append("\":")
      Rows.string(sb, c.name)
      sb.append(",\"").append(Wire.Type).append("\":\"").append(c.typeName)
      sb.append("\",\"").append(Wire.Nullable).append("\":").append(c.nullable).append('}')
    }
    sb.append(']')
  }

  // ---------------------------------------------------------------------

  private def logged(rs: RelationStats): RelationStats = {
    if (log.isInfoEnabled) log.info(rs.line)
    rs
  }

  private def failure(path: String, completed: List[RelationStats], start: Long, clock: () => Long,
                      e: Throwable): WriteFailure = e match {
    case f: WriteFailure => f
    case other =>
      val msg = other match {
        case r: Rows.RowError => r.getMessage
        case _                => Option(other.getMessage).getOrElse(other.toString)
      }
      log.error("relation " + path + " failed ms=" + (clock() - start) + ": " + msg)
      WriteFailure(path, msg, completed, other)
  }

  private def attempt[A](path: String, completed: List[RelationStats], start: Long, clock: () => Long)(body: => A): A =
    try body catch { case NonFatal(e) => throw failure(path, completed, start, clock, e) }

  /** `a`, evaluated when the action runs (for a lazy `G` such as `DB`). */
  private def delay[G[_], A](M: scalaz.Monad[G])(a: => A): G[A] =
    M.map(M.point(()))(_ => a)
}
