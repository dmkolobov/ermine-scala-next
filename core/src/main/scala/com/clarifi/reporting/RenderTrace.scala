package com.clarifi.reporting

/** What ONE render did, collected while it runs (DB programme stage 2b;
  * tracker/db/OBSERVABILITY.md).  The preview makes one per `ermine/render`
  * job and appends its `snapshot` to the answer as `trace`.
  *
  * HOW IT TRAVELS (design D1).  Explicitly from the preview to `Runner` (an
  * argument) and from `Runner` to `Interp` (`WriteConfig.trace`); then, for
  * the LAST hop only, through a thread-local: `Runner.drive` installs the
  * trace with `RenderTrace.installed` for the length of the one
  * `Run[DB].run`, and `SqlExecution.scanQuery` / `SqlScanner.sequenceSql`
  * read `RenderTrace.current`.  The `Scanner` interface does not change, so
  * the scanners (`SqlScanner`, `StateScanner`, `RemoteScanner`,
  * `ReferencingScanner`) and every other caller of them are untouched.
  *
  * WHY A THREAD-LOCAL IS ACCEPTABLE HERE.  A `DB` action runs on the thread
  * that calls `Run[DB].run` (`DB.Run`, `ThreadLocalRunDB`,
  * `fromPersistentConnection`): the preview's whole render, scans included,
  * runs on the one `ermine-preview` thread, and the thread-local is set and
  * restored around exactly that call (`installed`'s `finally`).  Every other
  * caller -- `bin/ermine-serve`'s HTTP route (`Runner.render` without a
  * trace), the legacy writers, `Runner.data`'s token re-fetch, the tests --
  * never installs one, so `current` answers `Off`: every recording method
  * returns at its first test and the per-row path takes no clock at all.
  * NOTHING IS CAPTURED ON THE HTTP PATH AND IT COSTS ONE `ThreadLocal.get`
  * PER QUERY.
  *
  * THREADS.  Only the preview thread WRITES (one job at a time).  The
  * watchdog's TIMER thread may READ, through `snapshot(partial = true)`,
  * while the preview thread is wedged inside a query: every value it reads
  * is an immutable object behind a `@volatile` field, replaced (never
  * mutated) at each event -- a relation entered or left, a query started or
  * executed, a statement run, a phase ended.  The per-row counters are plain
  * fields folded into the entry when the query closes, so the timer thread
  * sees a running query's rows as of its last event, which is all a partial
  * trace promises.
  *
  * WHAT IS MEASURED AND WHAT IS ATTRIBUTED.  Every `ms` is a
  * `System.nanoTime` difference taken around the work it names, EXCEPT:
  *  - `scan` (ATTRIBUTED): a relation's wall time minus its database time
  *    and its SQL generation time, summed -- what Ermine does WITH the rows
  *    while they arrive: decoding them, any relational work the SQL did not
  *    do (a `Mem` such as `groupBy ... (sumBy ...)` runs in Ermine over the
  *    scanned rows: MEASURED, `DbFetchTopN`'s first scan reads 388 rows at
  *    tier s to hand the report 8), and JSON-encoding inline rows.  These
  *    interleave with `rs.next()` and are not clocked apart;
  *  - `other` (ATTRIBUTED): the job's wall time minus every phase above --
  *    the unbracketed remainder, so a gap shows up instead of vanishing;
  *  - `totals.otherMs` is `wallMs - dbMs` by construction, never a sum.
  */
final class RenderTrace private (val on: Boolean, clock: () => Long, val timeRows: Boolean) {
  import RenderTrace._

  /** The live accumulator for one render: `clock` is nanoseconds (injected
    * by the unit properties); `timeRows` takes the per-row clock around
    * `rs.next()` (the one per-row cost, measured by the stage-2b A/B). */
  def this(clock: () => Long = RenderTrace.nanoClock, timeRows: Boolean = true) = this(true, clock, timeRows)

  // ------------------------------------------------------------- state

  /** When the job was created (enqueued): the queue time is `start - created`. */
  private val createdNs: Long = if (on) clock() else 0L
  @volatile private var startNs: Long = -1L
  @volatile private var endNs: Long   = -1L

  @volatile private var phaseList: Vector[PhaseAcc] = Vector.empty
  /** The phase in progress, for a partial trace: `(name, since)`. */
  @volatile private var inPhase: (String, Long) = null

  @volatile private var doneList: Vector[Entry] = Vector.empty
  @volatile private var open: Entry = null
  @volatile private var dropped: Int = 0
  @volatile private var tot: Tot = Tot.zero

  @volatile private var connectNs: Long = 0L
  private var driveEnterNs: Long = -1L
  private var driverEndNs: Long  = -1L

  /** The query whose `executeQuery` has not returned yet: its start. */
  @volatile private var execSince: Long = -1L
  // per-row counters of the OPEN entry (preview thread only), folded in at close
  private var rowsReadNow: Long = 0L
  private var fetchNsNow: Long  = 0L

  @volatile private var conn: Connection = Connection.InMemory
  @volatile private var docBytes: Long = -1L

  // ------------------------------------------------------------- phases

  /** The job starts running on the preview thread (queue time ends here). */
  def start(): Unit = if (on && startNs < 0L) startNs = clock()

  /** Whether `start` was called: a job refused before it ran has no trace. */
  def started: Boolean = on && startNs >= 0L

  /** The answer is being built: the wall clock stops here. */
  def finish(): Unit = if (on && endNs < 0L) endNs = clock()

  def connection_=(c: Connection): Unit = if (on) conn = c
  def connection: Connection = conn

  def documentBytes(n: Long): Unit = if (on) docBytes = n

  /** Time `body` as phase `name`, ADDED to what the phase already holds
    * (`eval` runs once per fetch step). */
  def phase[A](name: String)(body: => A): A =
    if (!on) body
    else {
      val t0 = clock()
      inPhase = (name, t0)
      try body
      finally { inPhase = null; addPhase(name, clock() - t0) }
    }

  def addPhase(name: String, ns: Long, cached: Option[Boolean] = None): Unit = if (on) {
    val i = phaseList.indexWhere(_.name == name)
    phaseList =
      if (i < 0) phaseList :+ PhaseAcc(name, ns, cached)
      else phaseList.updated(i, PhaseAcc(name, phaseList(i).ns + ns, cached orElse phaseList(i).cached))
  }

  /** `Runner.drive` is about to call `Run[DB].run` (the connection opens inside). */
  def driveEnter(): Unit = if (on) { driveEnterNs = clock(); driverEndNs = -1L }
  /** `Interp.run`'s first action ran: the connection is open. */
  def driverStart(): Unit = if (on && driveEnterNs >= 0L) {
    connectNs += clock() - driveEnterNs
    driveEnterNs = -1L
  }
  /** `Interp.run`'s last step finished: what follows is the run's commit/close. */
  def driverEnd(): Unit = if (on) driverEndNs = clock()
  /** `Run[DB].run` returned (or threw). */
  def driveExit(): Unit = if (on) {
    val now = clock()
    if (driveEnterNs >= 0L) connectNs += now - driveEnterNs      // it failed before the driver started
    else if (driverEndNs >= 0L) connectNs += now - driverEndNs   // close / commit
    driveEnterNs = -1L; driverEndNs = -1L
  }

  // ------------------------------------------------------------- relations (Interp)

  /** A relation's scan (or token) starts: `delivery` is `fetched`, `inline`
    * or `deferred`. */
  def enter(path: String, delivery: String): Unit = if (on) {
    if (open ne null) close(None)
    rowsReadNow = 0L; fetchNsNow = 0L
    open = Entry(path, delivery, clock())
  }

  /** The relation finished; the figures are `RelationStats`'s. */
  def exit(path: String, delivery: String, columns: Int, rows: Long, scanned: Long, bytes: Long,
           overThreshold: Boolean): Unit = if (on) {
    val e = if ((open ne null) && open.path == path) open else Entry(path, delivery, clock())
    open = e.copy(delivery = delivery, columns = columns, rows = rows, scanned = scanned,
                  bytes = bytes, overThreshold = overThreshold)
    close(None)
  }

  /** The relation at `path` failed with `message`: its entry is kept, last,
    * with the SQL that was running. */
  def failed(path: String, message: String): Unit = if (on) {
    if ((open eq null) || open.path != path) open = Entry(path, "fetched", clock())
    close(Some(message))
  }

  private def close(error: Option[String]): Unit = {
    val e0 = open
    val now = clock()
    val running = if (execSince >= 0L) now - execSince else 0L
    execSince = -1L
    val e = e0.copy(rowsRead = e0.rowsRead + rowsReadNow, fetchNs = e0.fetchNs + fetchNsNow,
                    execNs = e0.execNs + running, endNs = now, error = error orElse e0.error)
    rowsReadNow = 0L; fetchNsNow = 0L
    tot = tot.add(e)
    if (doneList.length < MaxQueries) doneList = doneList :+ e else dropped += 1
    open = null
  }

  private def ensureOpen(): Unit =
    if (open eq null) { rowsReadNow = 0L; fetchNsNow = 0L; open = Entry(OutsidePath, "statement", clock()) }

  // ------------------------------------------------------------- SQL (the thread-local hop)

  /** `SqlScanner` compiled a relation to SQL in `ns`. */
  def sqlEmitted(ns: Long): Unit = if (on) { ensureOpen(); open = open.copy(emitNs = open.emitNs + ns) }

  /** `SqlExecution.scanQuery` is about to prepare and execute `sql`. */
  def queryStart(sql: String, dialect: String): Unit = if (on) {
    ensureOpen()
    val e = open
    open = if (e.sql.isEmpty) e.copy(dialect = Some(dialect), sql = Some(capSql(sql, MaxSqlBytes)),
                                      sqlBytes = utf8Length(sql), queries = e.queries + 1)
           else e.copy(queries = e.queries + 1)
    execSince = clock()
    val h = queryStartHook
    if (h ne null) h(sql)
  }

  /** `executeQuery` returned after `ns` (prepare + execute). */
  def queryExecuted(ns: Long): Unit = if (on) {
    execSince = -1L
    if (open ne null) open = open.copy(execNs = open.execNs + ns)
  }

  /** One `rs.next()` that took `ns`, and whether it answered a row. */
  def rowFetched(ns: Long, row: Boolean): Unit = { fetchNsNow += ns; if (row) rowsReadNow += 1 }
  /** The same without the clock (`timeRows` off). */
  def rowRead(row: Boolean): Unit = if (row) rowsReadNow += 1

  /** The result set was closed: fold the row counters into the entry. */
  def queryClosed(): Unit = if (on && (open ne null)) {
    open = open.copy(rowsRead = open.rowsRead + rowsReadNow, fetchNs = open.fetchNs + fetchNsNow)
    rowsReadNow = 0L; fetchNsNow = 0L
  }

  /** A setup statement (`sequenceSql`) or a temp-table drop ran, timed when
    * it RAN.  `kind`: `temp` (CREATE of a temporary table), `load` (a bulk
    * load), `memo` (a memo table: `created` tells made from reused),
    * `drop`, or `statement`. */
  def statement(kind: String, table: Option[String], created: Option[Boolean], ns: Long,
                error: Boolean = false): Unit = if (on) {
    ensureOpen()
    val e = open
    open = e.copy(setup = e.setup :+ Setup(kind, table, created, ns / 1e6, error), setupNs = e.setupNs + ns)
  }

  // ------------------------------------------------------------- the snapshot

  /** The trace as an immutable value.  `partial`: the watchdog's form, from
    * the TIMER thread, while the job may still be running; it names what is
    * running.  Safe on any thread. */
  def snapshot(partial: Boolean = false): Snapshot = {
    val now    = clock()
    val st     = if (startNs >= 0L) startNs else now
    val end    = if (!partial && endNs >= 0L) endNs else now
    val wallNs = math.max(0L, end - st)
    val queueNs = math.max(0L, st - createdNs)
    val op     = open
    val t      = tot
    val phs    = phaseList
    val runExec = { val s = execSince; if (partial && s >= 0L) math.max(0L, now - s) else 0L }
    // the open entry (a partial trace, or a failure nothing closed) is shown and counted
    val openTot = if (op ne null) Tot.zero.add(op.copy(execNs = op.execNs + runExec)) else Tot.zero
    val all     = t.plus(openTot)
    val dbNs    = math.min(wallNs, connectNs + all.dbNs)
    val emitNs  = all.emitNs
    val encNs   = math.max(0L, all.relNs - all.dbNs - all.emitNs)
    val measured = phs.map(p => Phase(p.name, ms(p.ns), false, p.cached)).toList
    val derived  = List(
      Phase("connect", ms(connectNs), false, None),
      Phase("sql-emit", ms(emitNs), false, None),
      Phase("db-execute", ms(all.setupNs + all.execNs), false, None),
      Phase("db-fetch", ms(all.fetchNs), false, None),
      Phase("scan", ms(encNs), true, None)).filter(_.ms > 0.0)
    val accounted = phs.map(_.ns).sum + connectNs + emitNs + all.setupNs + all.execNs + all.fetchNs + encNs
    val otherPh  = Phase("other", ms(math.max(0L, wallNs - accounted)), true, None)
    val entries  = (doneList ++ (if (op ne null) Vector(op.copy(execNs = op.execNs + runExec)) else Vector.empty))
                     .map(_.toQuery).toList
    val running  =
      if (!partial) None
      else if (op ne null) Some(Running(Some(op.path), None, op.sql, ms(now - op.startNs)))
      else { val p = inPhase; if (p ne null) Some(Running(None, Some(p._1), None, ms(now - p._2))) else None }
    val totals = Totals(dbMs = ms(dbNs), otherMs = ms(wallNs - dbNs), wallMs = ms(wallNs), queueMs = ms(queueNs),
                        relations = all.relations, queries = all.queries,
                        rowsRead = all.rowsRead, rows = all.rows, bytes = all.bytes,
                        documentBytes = if (docBytes >= 0L) Some(docBytes) else None)
    val ordered = (measured ++ derived :+ otherPh).sortBy(p => { val i = PhaseOrder.indexOf(p.name); if (i < 0) PhaseOrder.indexOf("layout") else i })
    fit(Snapshot(ordered, entries, totals, conn, partial, running,
                 if (dropped > 0) Some(Truncated(dropped, false)) else None, on && timeRows))
  }
}

object RenderTrace {
  val nanoClock: () => Long = () => System.nanoTime

  /** The pipeline order phases are listed in (a stable sort: a name not
    * here sits with `layout`). */
  val PhaseOrder: List[String] = List("session", "boot", "parse", "compile", "decode", "eval", "layout",
                                      "connect", "sql-emit", "db-execute", "db-fetch", "scan", "check", "other")

  /** TEST SEAM ONLY (`TestRenderTrace`'s stuck property): called on the
    * scanning thread with the SQL text after a LIVE trace records a query
    * start and before it is prepared, so a test can hold a render inside
    * its query the way `Preview.beforeJob` holds one before it starts.
    * `null` (one volatile read per query) everywhere else. */
  @volatile private[reporting] var queryStartHook: String => Unit = null

  /** The no-op every caller that installs nothing gets. */
  val Off: RenderTrace = new RenderTrace(false, () => 0L, false)

  private val tl = new ThreadLocal[RenderTrace] { override def initialValue(): RenderTrace = Off }

  /** The trace of the render running on THIS thread, or `Off`. */
  def current: RenderTrace = tl.get

  /** Run `body` with `t` as this thread's trace, restoring what was there. */
  def installed[A](t: RenderTrace)(body: => A): A =
    if (!t.on) body
    else {
      val was = tl.get
      tl.set(t)
      try body finally tl.set(was)
    }

  /** Caps (design §2.2): SQL text per query, entries per trace, the whole
    * trace; and what the SQL is cut to when the whole trace is over. */
  val MaxSqlBytes: Int      = 16 * 1024
  val MaxQueries: Int       = 200
  val MaxTraceBytes: Long   = 256L * 1024L
  val ShrunkSqlBytes: Int   = 1024
  /** The path of statements that ran outside any relation (none do today). */
  val OutsidePath = "$"

  def truncationMarker(more: Long): String = "\n-- [ermine: truncated, " + more + " more bytes]"

  /** `s` cut to at most `max` UTF-8 bytes at a character boundary, plus the
    * marker naming how many bytes were cut; `s` itself when it fits. */
  def capSql(s: String, max: Int): String = capSqlOf(s, max, utf8Length(s))

  /** `capSql` of a text whose FULL length is `full` bytes: the text may
    * already be a capped prefix (it then ends in a marker, which is dropped
    * first), and the new marker counts from the full length. */
  def capSqlOf(s0: String, max: Int, full: Long): String = {
    val m = s0.indexOf(MarkerHead)
    val s = if (m >= 0) s0.substring(0, m) else s0
    if (full <= max && m < 0) s
    else {
      var bytes = 0L; var i = 0; var stop = false
      while (i < s.length && !stop) {
        val c = s.charAt(i)
        val (w, n) =
          if (c < 0x80) (1, 1) else if (c < 0x800) (2, 1)
          else if (Character.isHighSurrogate(c) && i + 1 < s.length && Character.isLowSurrogate(s.charAt(i + 1))) (4, 2)
          else (3, 1)
        if (bytes + w > max) stop = true else { bytes += w; i += n }
      }
      s.substring(0, i) + truncationMarker(full - bytes)
    }
  }
  private val MarkerHead = "\n-- [ermine: truncated, "

  def utf8Length(s: CharSequence): Long = {
    var n = 0L; var i = 0
    while (i < s.length) {
      val c = s.charAt(i)
      if (c < 0x80) n += 1
      else if (c < 0x800) n += 2
      else if (Character.isHighSurrogate(c) && i + 1 < s.length && Character.isLowSurrogate(s.charAt(i + 1))) { n += 4; i += 1 }
      else n += 3
      i += 1
    }
    n
  }

  private def ms(ns: Long): Double = ns / 1e6

  /** The whole-trace cap: an estimate of the printed size (the SQL texts
    * plus a fixed allowance per entry); over it, every SQL text is cut to
    * `ShrunkSqlBytes`, then entries are dropped from the end, and
    * `truncated` says so.  The totals always count everything. */
  def fit(s: Snapshot): Snapshot = {
    def size(qs: List[Query]): Long = 1024L + qs.map(q => 400L + q.sql.map(x => utf8Length(x)).getOrElse(0L) +
                                                         q.setup.length * 80L).sum
    if (size(s.queries) <= MaxTraceBytes) s
    else {
      val shrunk = s.queries.map(q => q.copy(sql = q.sql.map(x => if (utf8Length(x) > ShrunkSqlBytes)
                                                                     capSqlOf(x, ShrunkSqlBytes, q.sqlBytes) else x)))
      var kept = shrunk
      while (kept.nonEmpty && size(kept) > MaxTraceBytes) kept = kept.init
      val cut = shrunk.length - kept.length
      s.copy(queries = kept, truncated = Some(Truncated(s.truncated.map(_.queries).getOrElse(0) + cut, true)))
    }
  }

  // ------------------------------------------------------------- values

  /** Where the render's rows came from.  `kind`: `in-memory` (stage A's
    * per-render SQLite, nothing held) or `profile`.  No URL, user, host or
    * password is ever held here (design §2.3). */
  final case class Connection(kind: String, dialect: String, database: Option[String], profile: Option[String])
  object Connection {
    val InMemory: Connection = Connection("in-memory", "sqlite", None, None)
  }

  final case class Phase(name: String, ms: Double, attributed: Boolean, cached: Option[Boolean])
  final case class Setup(kind: String, table: Option[String], created: Option[Boolean], ms: Double, error: Boolean)
  final case class Query(path: String, delivery: String, dialect: Option[String], sql: Option[String],
                         sqlBytes: Long, queries: Int, setup: List[Setup],
                         sqlEmitMs: Double, execMs: Double, fetchMs: Double, dbMs: Double, ms: Double,
                         rowsRead: Long, rows: Long, scanned: Long, columns: Int, bytes: Long,
                         deferred: Boolean, overThreshold: Boolean, error: Option[String])
  final case class Totals(dbMs: Double, otherMs: Double, wallMs: Double, queueMs: Double,
                          relations: Int, queries: Int, rowsRead: Long, rows: Long, bytes: Long,
                          documentBytes: Option[Long])
  final case class Running(path: Option[String], phase: Option[String], sql: Option[String], sinceMs: Double)
  final case class Truncated(queries: Int, sqlShortened: Boolean)
  final case class Snapshot(phases: List[Phase], queries: List[Query], totals: Totals, connection: Connection,
                            partial: Boolean, running: Option[Running], truncated: Option[Truncated],
                            rowsTimed: Boolean)

  private final case class PhaseAcc(name: String, ns: Long, cached: Option[Boolean])

  private final case class Entry(path: String, delivery: String, startNs: Long,
                                 endNs: Long = -1L, dialect: Option[String] = None, sql: Option[String] = None,
                                 sqlBytes: Long = 0L, queries: Int = 0, setup: Vector[Setup] = Vector.empty,
                                 emitNs: Long = 0L, setupNs: Long = 0L, execNs: Long = 0L, fetchNs: Long = 0L,
                                 rowsRead: Long = 0L, rows: Long = 0L, scanned: Long = 0L, columns: Int = 0,
                                 bytes: Long = 0L, overThreshold: Boolean = false, error: Option[String] = None) {
    def dbNs: Long = setupNs + execNs + fetchNs
    def relNs: Long = if (endNs >= 0L) math.max(0L, endNs - startNs) else dbNs + emitNs
    def toQuery: Query =
      Query(path, delivery, dialect, sql, sqlBytes, queries, setup.toList, ms(emitNs), ms(execNs),
            ms(fetchNs), ms(dbNs), ms(relNs), rowsRead, rows, scanned, columns, bytes,
            deferred = delivery == "deferred", overThreshold = overThreshold, error = error)
  }

  private final case class Tot(relations: Int, queries: Int, rowsRead: Long, rows: Long, bytes: Long,
                               dbNs: Long, emitNs: Long, relNs: Long, setupNs: Long, execNs: Long, fetchNs: Long) {
    def add(e: Entry): Tot =
      Tot(relations + 1, queries + e.queries, rowsRead + e.rowsRead, rows + e.rows, bytes + e.bytes,
          dbNs + e.dbNs, emitNs + e.emitNs, relNs + e.relNs, setupNs + e.setupNs, execNs + e.execNs,
          fetchNs + e.fetchNs)
    def plus(o: Tot): Tot =
      Tot(relations + o.relations, queries + o.queries, rowsRead + o.rowsRead, rows + o.rows, bytes + o.bytes,
          dbNs + o.dbNs, emitNs + o.emitNs, relNs + o.relNs, setupNs + o.setupNs, execNs + o.execNs,
          fetchNs + o.fetchNs)
  }
  private object Tot { val zero = Tot(0, 0, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L) }
}
