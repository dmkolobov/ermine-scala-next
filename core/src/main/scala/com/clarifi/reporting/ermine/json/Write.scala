package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.{ Record, PrimExpr, NullExpr, IntExpr, ShortExpr, ByteExpr, LongExpr, DoubleExpr,
                               BooleanExpr, StringExpr, DateExpr, TimestampExpr, UuidExpr }
import com.clarifi.reporting.backends.DB
import com.clarifi.reporting.relational.Scanner
import com.clarifi.machines.{ Plan, Process, Stop }
import scala.util.control.{ NonFatal, NoStackTrace }
import java.time.{ Instant, ZoneOffset }
import java.time.format.DateTimeFormatter

/** The inlining strategy (design note §3.4a, "switch 2").  v1 has one:
  * `Buffered` -- a relation's rows go to a per-relation text buffer during
  * its scan and the finished relation object is appended to the output only
  * after the scan succeeds.  (`Streamed`, with its `errors` trailer, is not
  * in v1; the runner refuses it.) */
sealed abstract class Strategy(val name: String)
object Strategy {
  case object Buffered extends Strategy("buffered")
}

/** How a document write resolves its relations.
  *
  *  - `default`: the delivery of a BARE relation (`Delivery.ByRequest`);
  *    `Inline` or `Deferred`, never `ByRequest`.
  *  - `threshold`: a bare relation delivered inline whose row count is
  *    GREATER than this goes out deferred instead.  An explicit `Inline`
  *    wrapper ignores it.
  *  - `clock`: epoch milliseconds, for the per-relation `ms` figure.
  *
  * The deferred tokens' time to live belongs to the `PlanCache`, which mints
  * them, not to this configuration. */
final case class WriteConfig(default: Delivery = Delivery.Inline,
                             strategy: Strategy = Strategy.Buffered,
                             threshold: Option[Long] = None,
                             clock: () => Long = WriteConfig.systemClock) {
  require(default != Delivery.ByRequest, "the default delivery is inline or deferred")
  require(threshold.forall(_ >= 0L), "a threshold is a row count")
}
object WriteConfig {
  val systemClock: () => Long = () => System.currentTimeMillis
}

/** One relation as it was written.  `delivery` is what was actually used
  * (`Inline` or `Deferred`); `rows` the rows written (0 when deferred);
  * `scanned` the records read from the scan (for a relation deferred by the
  * threshold, `threshold + 1`: the scan is abandoned there); `bytes` the
  * UTF-8 length of the relation object; `millis` the wall time from the start
  * of its scan (or of its cache entry) to the object being appended. */
final case class RelationStats(path: String, delivery: Delivery, columns: Int, rows: Long,
                               scanned: Long, bytes: Long, millis: Long, overThreshold: Boolean) {
  /** The log line, `relation <path> <delivery> rows=<n> bytes=<b> ms=<t>`. */
  def line: String =
    "relation " + path + " " + delivery.name + " rows=" + rows + " bytes=" + bytes + " ms=" + millis +
      (if (overThreshold) " scanned=" + scanned + " (over the threshold)" else "")
}

/** A whole write: every relation in document order, and the UTF-8 length of
  * everything appended to the output. */
final case class WriteStats(relations: List[RelationStats], bytes: Long)

/** How a write fails: the path of the relation that failed (or `$` outside
  * any relation), what went wrong, and the relations completed before it.
  * Thrown when the `G` action RUNS (`Run[G].run`), never returned. */
final case class WriteFailure(path: String, message: String, completed: List[RelationStats], cause: Throwable)
    extends RuntimeException("cannot write " + path + ": " + message, cause)

/** Turning an exception raised while a `G` action runs into a `WriteFailure`
  * that names the relation.  `Scanner[G]` only gives a `Monad`, which cannot
  * see exceptions, so the writer asks for this beside it.  Instances: `DB`
  * (the SQL scanners) and `Id` (strict scanners, e.g. over literal rows). */
trait Guard[G[_]] {
  def guard[A](ga: G[A])(h: Throwable => Throwable): G[A]
}
object Guard {
  implicit val db: Guard[DB] = new Guard[DB] {
    def guard[A](ga: DB[A])(h: Throwable => Throwable): DB[A] =
      c => try ga(c) catch { case NonFatal(e) => throw h(e) }
  }
  /** A strict effect has already run when the action exists; the writer
    * guards the construction itself, which covers it. */
  implicit val id: Guard[scalaz.Id.Id] = new Guard[scalaz.Id.Id] {
    def guard[A](ga: A)(h: Throwable => Throwable): A = ga
  }
}

/** The document writer (design note §3.4a; tracker/JSON-STAGE3-PLAN.md "Wire
  * contract").  `Write.doc` turns a `Doc` into text inside ONE `G` action:
  * pure nodes are appended as they come, and each relation, in document
  * order, is resolved by the delivery policy:
  *
  *  - explicit `Inline`/`Deferred` wins; `ByRequest` takes `cfg.default`;
  *  - INLINE (Buffered): `S.scanExt(ext, rows, order)` appends each record
  *    as a JSON array to a per-relation buffer; once the scan has returned,
  *    `{"kind":"inline","columns":[..],"rows":[..],"rowCount":n}` goes to
  *    `out`;
  *  - a bare relation resolved inline with `cfg.threshold = Some(t)` whose
  *    scan yields a (t+1)-th record stops there: the process STOPS, which
  *    ends the scan (the SQL driver closes its result set; the text buffered
  *    so far is dropped) and the relation goes out deferred;
  *  - DEFERRED: no scan; `cache.put` mints a token and
  *    `{"kind":"deferred","columns":[..],"token":..,"expires":..}` is
  *    written.
  *
  * For `G = DB` the whole write is one `Connection => WriteStats`, so every
  * relation scans on the one connection `Run[DB].run` supplies, sequentially.
  *
  * FAILURE.  Any exception while the action runs -- a scan that throws, a
  * non-finite Double in a row, a record lacking a declared column -- is
  * rethrown as a `WriteFailure` naming the relation's path (and, for a row,
  * the row index and column), after an ERROR log line.  A row the encoder
  * refuses ends its scan by `Stop`, exactly as the threshold does, so the
  * scan is torn down (result set, statement, temp tables) before the failure
  * is raised; a scan that throws on its own is the scanner's to tear down.
  * `out` then holds a
  * PREFIX of the document that ends before the failed relation's object:
  * nothing of that relation, nothing after it.  The prefix is not valid JSON
  * on its own; a runner that wants HTTP error semantics writes into a buffer
  * and sends it only when the action returns (which is what Buffered
  * promises: no partial document reaches the client).
  *
  * Every relation is logged at INFO on `ermine.json.doc` as
  * `relation <path> <delivery> rows=<n> bytes=<b> ms=<t>`.
  *
  * Stack: the action is a right-nested chain of binds, one per text run and
  * per relation, so for `DB` its depth grows with the number of RELATIONS
  * (not rows, not nodes); thousands are fine.
  */
object Write {
  private val log = org.apache.log4j.Logger.getLogger("ermine.json.doc")

  // ---------------------------------------------------------------------
  // the document as text runs and relations

  sealed abstract class Segment
  final case class Text(text: String) extends Segment
  final case class Relation(data: Doc.Data) extends Segment

  /** The document in order: maximal runs of pure text between relations.
    * Iterative (an explicit work stack), so neither size nor depth of the
    * tree touches the JVM stack. */
  def segments(d: Doc): List[Segment] = {
    import Doc._
    val out = new scala.collection.mutable.ListBuffer[Segment]
    val sb = new java.lang.StringBuilder
    // work items: a Doc to print, or a String to append verbatim
    var stack: List[Any] = List(d)
    while (stack.nonEmpty) {
      val top = stack.head
      stack = stack.tail
      top match {
        case s: String => sb.append(s)
        case DNull     => sb.append("null")
        case DBool(b)  => sb.append(b)
        case DLong(l)  => sb.append(l)
        case DNum(x)   => sb.append(x)
        case DStr(s)   => Rows.string(sb, s)
        case DRaw(j)   => sb.append(j.nospacesWithOrder)
        case DArr(xs)  =>
          val items = new scala.collection.mutable.ListBuffer[Any]
          items += "["
          var first = true
          xs.foreach { x => if (!first) items += ","; first = false; items += x }
          items += "]"
          stack = items.toList ++ stack
        case DObj(fs)  =>
          val withSep = new scala.collection.mutable.ListBuffer[Any]
          withSep += "{"
          var first = true
          fs.foreach { case (k, v) =>
            val key = new java.lang.StringBuilder
            if (!first) key.append(',')
            first = false
            Rows.string(key, k)
            key.append(':')
            withSep += key.toString
            withSep += v
          }
          withSep += "}"
          stack = withSep.toList ++ stack
        case x: Data =>
          if (sb.length > 0) { out += Text(sb.toString); sb.setLength(0) }
          out += Relation(x)
      }
    }
    if (sb.length > 0) out += Text(sb.toString)
    out.toList
  }

  // ---------------------------------------------------------------------
  // the writer

  /** Write `d` to `out` inside one `G` action; see the object comment. */
  def doc[G[_]](d: Doc, out: Appendable, cfg: WriteConfig, cache: PlanCache)
               (implicit S: Scanner[G], X: Guard[G]): G[WriteStats] = {
    val M = S.M
    val segs = segments(d)
    final class State { var bytes = 0L; val done = new scala.collection.mutable.ListBuffer[RelationStats] }
    def go(rest: List[Segment], st: State): G[WriteStats] = rest match {
      case Nil => delay(M)(WriteStats(st.done.toList, st.bytes))
      case Text(t) :: tl =>
        M.bind(delay(M) { out.append(t); st.bytes += Rows.utf8Length(t) })(_ => go(tl, st))
      case Relation(data) :: tl =>
        M.bind(one(data, out, cfg, cache, st.done.toList))({ rs =>
          st.done += rs
          st.bytes += rs.bytes
          go(tl, st)
        })
    }
    M.bind(delay(M)(new State))(st => go(segs, st))
  }

  /** The deferred re-request: exactly the inline object the relation behind
    * `token` would have been written as (no threshold: the client asked for
    * the rows), or `None` when the token is unknown or has expired.  The
    * clock is read when the action runs. */
  def relation[G[_]](token: String, out: Appendable, cache: PlanCache, clock: () => Long = WriteConfig.systemClock)
                    (implicit S: Scanner[G], X: Guard[G]): G[Option[WriteStats]] = {
    val M = S.M
    M.bind(delay(M)(cache.get(token, clock())))({
      case None    => M.point(None: Option[WriteStats])
      case Some(e) =>
        M.map(inlined(e.data, None, out, cache, clock, Nil))(rs => Some(WriteStats(List(rs), rs.bytes)): Option[WriteStats])
    })
  }

  /** The delivery a relation gets before any scan, and the threshold that
    * applies to it: an explicit wrapper wins, a bare relation takes the
    * default, and only a bare relation resolved inline is thresholded. */
  def resolve(requested: Delivery, cfg: WriteConfig): (Delivery, Option[Long]) = requested match {
    case Delivery.ByRequest =>
      if (cfg.default == Delivery.Inline) (Delivery.Inline, cfg.threshold) else (cfg.default, None)
    case explicit => (explicit, None)
  }

  private def one[G[_]](d: Doc.Data, out: Appendable, cfg: WriteConfig, cache: PlanCache,
                        completed: List[RelationStats])
                       (implicit S: Scanner[G], X: Guard[G]): G[RelationStats] =
    resolve(d.delivery, cfg) match {
      case (Delivery.Deferred, _) => delay(S.M) {
        val start = cfg.clock()
        attempt(d.path, completed, start, cfg.clock)(deferred(d, out, cache, start, cfg.clock, 0L, false))
      }
      case (_, threshold) => inlined(d, threshold, out, cache, cfg.clock, completed)
    }

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

/** The row encoder: one `Record` as a JSON array in column order, appended
  * straight to a buffer with no `Json` nodes in between.  The cell mapping is
  * `Encode`'s on the value the runtime would lift the `PrimExpr` to
  * (`Runtime.fromPrimExpr`):
  *
  *   Int/Short/Byte  number          Long       decimal string
  *   Double          number (NaN and the infinities are an error)
  *   Bool            true/false      String     string (RFC 8259 escaping)
  *   Date            "yyyy-MM-dd"    Timestamp  "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"  (UTC)
  *   GUID            canonical string
  *   NullExpr, or a value that is a JVM null   null
  *
  * One decision of this encoder: a `DateExpr` is a date by its CASE, even
  * when the value inside is a `java.sql.Timestamp` (`PrimExpr.mapDate` makes
  * those); `Encode` dispatches on the JVM class and would print a timestamp,
  * which the column's `"type":"Date"` contradicts. */
object Rows {
  // the same patterns as Encode's (TestDoc property (a) pins the agreement);
  // DateTimeFormatter is immutable and thread-safe
  val dateFmt: DateTimeFormatter      = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneOffset.UTC)
  val timestampFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

  /** A row the encoder cannot write; the message names the row and column. */
  final class RowError(msg: String) extends RuntimeException(msg) with NoStackTrace

  private val hex = "0123456789abcdef".toCharArray

  /** A JSON string literal: `"` `\` and the controls escaped (`\b \f \n \r
    * \t` by name, the rest as `\u00XX`), plus U+2028/U+2029 (legal JSON,
    * but line terminators to JavaScript) and any UNPAIRED surrogate (which
    * no UTF-8 encoder could carry) as `\uXXXX`. */
  def string(sb: java.lang.StringBuilder, s: String): Unit = {
    sb.append('"')
    val n = s.length
    var from = 0
    var i = 0
    while (i < n) {
      val c = s.charAt(i)
      if (c >= 0x20 && c != '"' && c != '\\' && c != '\u2028' && c != '\u2029' && !Character.isSurrogate(c)) i += 1
      else if (Character.isHighSurrogate(c) && i + 1 < n && Character.isLowSurrogate(s.charAt(i + 1))) i += 2
      else {
        sb.append(s, from, i)
        c match {
          case '"'  => sb.append("\\\"")
          case '\\' => sb.append("\\\\")
          case '\b' => sb.append("\\b")
          case '\f' => sb.append("\\f")
          case '\n' => sb.append("\\n")
          case '\r' => sb.append("\\r")
          case '\t' => sb.append("\\t")
          case _    =>
            sb.append("\\u").append(hex((c >> 12) & 0xf)).append(hex((c >> 8) & 0xf))
              .append(hex((c >> 4) & 0xf)).append(hex(c & 0xf))
        }
        i += 1
        from = i
      }
    }
    sb.append(s, from, n)
    sb.append('"')
  }

  /** The UTF-8 length of `cs` (a surrogate pair is 4 bytes; a lone surrogate,
    * which this module never writes unescaped, would be 3). */
  def utf8Length(cs: CharSequence): Long = {
    var bytes = 0L
    val n = cs.length
    var i = 0
    while (i < n) {
      val c = cs.charAt(i)
      if (c < 0x80) bytes += 1
      else if (c < 0x800) bytes += 2
      else if (Character.isHighSurrogate(c) && i + 1 < n && Character.isLowSurrogate(cs.charAt(i + 1))) { bytes += 4; i += 1 }
      else bytes += 3
      i += 1
    }
    bytes
  }

  /** Append one cell.  Throws `RowError` (without the row index; the sink
    * adds it) for a non-finite Double. */
  def cell(sb: java.lang.StringBuilder, v: PrimExpr, column: String): Unit = v match {
    case e: IntExpr     => sb.append(e.value)
    case e: StringExpr  => if (e.value == null) sb.append("null") else string(sb, e.value)
    case e: DoubleExpr  =>
      val d = e.value
      if (java.lang.Double.isNaN(d) || java.lang.Double.isInfinite(d))
        throw new RowError("column " + column + ": the number " + d + " has no JSON representation")
      sb.append(d)
    case e: LongExpr    => sb.append('"').append(e.value).append('"')
    case _: NullExpr    => sb.append("null")
    case e: BooleanExpr => sb.append(e.value)
    case e: DateExpr    =>
      if (e.value == null) sb.append("null")
      else { sb.append('"'); dateFmt.formatTo(Instant.ofEpochMilli(e.value.getTime), sb); sb.append('"') }
    case e: TimestampExpr =>
      if (e.value == null) sb.append("null")
      else { sb.append('"'); timestampFmt.formatTo(Instant.ofEpochMilli(e.value.getTime), sb); sb.append('"') }
    case e: ShortExpr   => sb.append(e.value.toInt)
    case e: ByteExpr    => sb.append(e.value.toInt)
    case e: UuidExpr    => if (e.value == null) sb.append("null") else sb.append('"').append(e.value.toString).append('"')
  }

  /** Append one record as an array in the order of `columns`.  A column the
    * header declares and the record lacks is an error, not a null. */
  def row(sb: java.lang.StringBuilder, rec: Record, columns: Array[String]): Unit = {
    sb.append('[')
    var j = 0
    while (j < columns.length) {
      if (j > 0) sb.append(',')
      val c = columns(j)
      val v = rec.getOrElse(c, null)
      if (v == null) throw new RowError("column " + c + ": the record has no such column (it has " +
                                        rec.keys.toList.sorted.mkString(", ") + ")")
      cell(sb, v, c)
      j += 1
    }
    sb.append(']')
  }

  /** The Buffered sink of one inline relation: a `Process` that appends each
    * record to `buffer` and STOPS once more than `limit` records have come
    * (`over`) or a row cannot be encoded (`error`), which ends the scan.
    *
    * A row error LEAVES BY `Stop` and is kept for the caller rather than
    * thrown here.  Throwing out of the machine would unwind through
    * `EffectfulProcedure.withDriver` (`relational/package.scala:121-128`),
    * which has no `finally`: the scan's `teardown` (`rs.close; stmt.close`,
    * `sql/SqlExecution.scala:90`) and `SqlScanner.scanRel`'s
    * `cleanTempTables` would both be skipped, and under a pooled `Run[DB]`
    * every refused row would leak a server-side cursor.  `Stop` is the exit
    * the driver tears down correctly; `Write.inlined` rethrows the error once
    * the scan has returned, so the failure, its message and its ERROR log
    * line are unchanged. */
  final class Sink(d: Doc.Data, limit: Long) {
    private val cols: Array[String] = d.columns.map(_.name).toArray
    var buffer = new java.lang.StringBuilder
    var rows = 0L
    var over = false
    var error: RowError = null

    def push(r: Record): Boolean =
      if (rows >= limit) { over = true; buffer = new java.lang.StringBuilder(0); false }
      else {
        if (rows > 0) buffer.append(',')
        try { row(buffer, r, cols); rows += 1; true }
        catch { case e: RowError =>
          error = new RowError("row " + rows + ", " + e.getMessage)
          buffer = new java.lang.StringBuilder(0)
          false
        }
      }

    val process: Process[Record, Unit] =
      (Plan.await[Record] flatMap { (r: Record) => if (push(r)) Plan.emit(()) else Stop }).repeatedly
  }
}
