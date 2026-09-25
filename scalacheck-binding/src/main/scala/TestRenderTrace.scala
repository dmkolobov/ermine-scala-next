package com.clarifi.reporting

import com.clarifi.reporting.ermine.lsp.{ Json, Preview, TraceJson }
import com.clarifi.reporting.RenderTrace._

import java.nio.file.Paths
import java.util.concurrent.{ CountDownLatch, TimeUnit }

import org.scalacheck.{ Gen, Prop, Properties }
import Prop._

/** DB programme stage 2b (tracker/db/OBSERVABILITY.md): the render trace.
  *
  * UNIT PROPERTIES of the accumulator, on an injected nanosecond clock, so no
  * verdict depends on real time:
  *  - (cap)    the 16 KiB SQL cap: text that fits is untouched; text that does
  *             not is cut at a character boundary to at most the cap, followed
  *             by the marker naming exactly how many bytes were cut;
  *  - (sum)    for any well-nested sequence of events, `dbMs + otherMs ==
  *             wallMs`, `dbMs <= wallMs`, the phases add up to `wallMs`, and
  *             the totals are the sums of the entries;
  *  - (part)   a query whose `executeQuery` has not returned is NAMED by a
  *             partial snapshot (`running.path`, `running.sql`), and its time
  *             so far is database time;
  *  - (max)    200 entries at most, `truncated.queries` counts the rest, the
  *             totals still count everything; the whole-trace cap shortens
  *             the SQL first and says so;
  *  - (off)    `RenderTrace.Off` records nothing, `current` is `Off` outside
  *             `installed`, and `installed` restores the previous trace even
  *             when its body throws;
  *  - (json)   the JSON carries the generation it is given, rounds to 0.1 ms,
  *             and passes every SQL text and message through the scrub.
  *
  * ONE PREVIEW PROPERTY, in-memory SQLite, on a `Bench` of its own (its own
  * boot; `previewLock`, then `literalLock`, the harness's order):
  *  - (t1)  an ok render of `FetchTopN` carries `trace` as its LAST key, with
  *          the answer's generation, connection in-memory sqlite, one entry
  *          per relation in execution order, the two fetch scans' SQL, rows
  *          read 8 and 4 (the first is a Mem grouped by Ermine) and used 4, 4;
  *  - (t3)  a failing render (`DbFetchTopN`: its tables do not exist in the
  *          in-memory database) carries a trace whose LAST entry is the
  *          failing scan with `error: true` and its SQL;
  *  - (t4)  a render held INSIDE its first query (`queryStartHook`) past a
  *          300 ms watchdog is answered `stuck: true` with a PARTIAL trace
  *          naming `$.fetch[1]` and its SQL; when the query is let go the
  *          late job's trace goes to the log and not to the wire;
  *  - (t7)  a render displaced in the queue is answered -32800 with no
  *          result and so no trace; the renders that ran carry traces whose
  *          generations are their own.
  */
object TestRenderTrace extends Properties("RenderTrace (DB programme S2b)") {

  /** A clock that advances by what the test says. */
  final class FakeClock { var now = 1000L; val f: () => Long = () => now; def tick(ns: Long): Unit = now += ns }

  private val ms1 = 1000000L

  // ------------------------------------------------------------------ (cap)

  private val chars: Gen[String] = Gen.oneOf("a", "Z", " ", "\n", "é", "中", "😀", "\"", "'")
  private val texts: Gen[String] = for {
    n  <- Gen.choose(0, 400)
    cs <- Gen.listOfN(n, chars)
  } yield cs.mkString

  property("(cap) SQL over the cap is cut at a character boundary, marker names the bytes cut") =
    forAll(texts, Gen.choose(1, 300)) { (s, max) =>
      val c = capSql(s, max)
      val total = utf8Length(s)
      if (total <= max) (c ?= s)
      else {
        val m = "\n-- \\[ermine: truncated, (\\d+) more bytes\\]$".r.findFirstMatchIn(c)
        val prefix = c.substring(0, m.map(_.start).getOrElse(c.length))
        (m.isDefined :| ("no marker in " + c)) &&
        (s.startsWith(prefix) :| "the kept text is not a prefix") &&
        ((utf8Length(prefix) <= max) :| ("kept " + utf8Length(prefix) + " > " + max)) &&
        (m.map(_.group(1).toLong) ?= Some(total - utf8Length(prefix))) &&
        ((prefix.isEmpty || !Character.isHighSurrogate(prefix.last)) :| "a surrogate pair was split")
      }
    }

  // ------------------------------------------------------------------ (sum)

  /** One relation's events, with the clock ticks in between. */
  private final case class Rel(kind: Int, emit: Long, exec: Long, rows: Int, fetch: Long, enc: Long,
                               setup: List[Long], evalAfter: Long)
  private val rels: Gen[Rel] = for {
    k  <- Gen.choose(0, 2)
    e  <- Gen.choose(0L, 5 * ms1)
    x  <- Gen.choose(0L, 50 * ms1)
    r  <- Gen.choose(0, 30)
    f  <- Gen.choose(0L, 100000L)
    en <- Gen.choose(0L, 3 * ms1)
    s  <- Gen.listOf(Gen.choose(0L, 2 * ms1)).map(_.take(3))
    ev <- Gen.choose(0L, 10 * ms1)
  } yield Rel(k, e, x, r, f, en, s, ev)

  /** Drive a trace through a whole render of `rs`; answer it and the fake clock. */
  private def drive(rs: List[Rel], queue: Long, connect: Long, close: Long, timeRows: Boolean = true): (RenderTrace, FakeClock) = {
    val c = new FakeClock
    val t = new RenderTrace(c.f, timeRows)
    c.tick(queue); t.start()
    t.addPhase("session", 2 * ms1); c.tick(2 * ms1)
    t.phase("compile") { c.tick(3 * ms1) }
    t.phase("eval") { c.tick(ms1) }
    t.driveEnter(); c.tick(connect); t.driverStart()
    rs.zipWithIndex.foreach { case (r, i) =>
      val path = "$.fetch[" + (i + 1) + "]"
      val delivery = List("fetched", "inline", "deferred")(r.kind)
      t.enter(path, delivery)
      if (r.kind != 2) {
        c.tick(r.emit); t.sqlEmitted(r.emit)
        r.setup.foreach { ns => c.tick(ns); t.statement("temp", Some("t" + i), None, ns) }
        t.queryStart("SELECT " + i, "sqlite"); c.tick(r.exec); t.queryExecuted(r.exec)
        (0 to r.rows).foreach { j =>
          c.tick(r.fetch); if (timeRows) t.rowFetched(r.fetch, j < r.rows) else t.rowRead(j < r.rows)
          c.tick(r.enc / (r.rows + 1))
        }
        t.queryClosed()
      } else c.tick(r.enc)
      t.exit(path, delivery, 2, if (r.kind == 2) 0L else r.rows.toLong, r.rows.toLong, 10L, false)
      t.phase("eval") { c.tick(r.evalAfter) }
    }
    t.driverEnd(); c.tick(close); t.driveExit()
    t.phase("check") { c.tick(ms1) }
    t.finish()
    (t, c)
  }

  private def near(a: Double, b: Double, eps: Double = 1e-6): Boolean = math.abs(a - b) <= eps

  property("(sum) dbMs + otherMs == wallMs, db <= wall, phases sum to wall, totals are sums") =
    forAll(Gen.listOf(rels).map(_.take(12)), Gen.choose(0L, 5 * ms1), Gen.choose(0L, 20 * ms1),
           Gen.choose(0L, 2 * ms1), Gen.oneOf(true, false)) { (rs, q, con, cl, timed) =>
      val (t, _) = drive(rs, q, con, cl, timed)
      val s = t.snapshot()
      val tt = s.totals
      val phaseSum = s.phases.map(_.ms).sum
      val fetched = rs.filter(_.kind != 2)
      val wantDb = (con + cl + fetched.map(r => r.exec + r.setup.sum + (if (timed) r.fetch * (r.rows + 1) else 0L)).sum) / 1e6
      (near(tt.dbMs + tt.otherMs, tt.wallMs) :| s"db ${tt.dbMs} + other ${tt.otherMs} != wall ${tt.wallMs}") &&
      ((tt.dbMs <= tt.wallMs + 1e-9) :| "db > wall") &&
      (near(phaseSum, tt.wallMs) :| s"phases sum $phaseSum != wall ${tt.wallMs}: ${s.phases}") &&
      (near(tt.dbMs, wantDb) :| s"db ${tt.dbMs} != $wantDb") &&
      (near(tt.queueMs, q / 1e6) :| "queue") &&
      ((tt.relations ?= rs.length) :| "relations") &&
      ((s.queries.map(_.path) ?= rs.indices.map(i => "$.fetch[" + (i + 1) + "]").toList) :| "entries in order") &&
      ((tt.rowsRead ?= fetched.map(_.rows.toLong).sum) :| "rowsRead") &&
      ((tt.queries ?= fetched.length) :| "queries") &&
      ((s.queries.filter(_.deferred).map(_.path) ?= rs.zipWithIndex.collect { case (r, i) if r.kind == 2 => "$.fetch[" + (i + 1) + "]" }) :| "deferred") &&
      ((s.rowsTimed ?= timed) :| "rowsTimed") &&
      (!s.partial :| "partial") &&
      ((s.phases.map(_.name).filter(PhaseOrder.contains) ?= PhaseOrder.filter(n => s.phases.exists(_.name == n))) :| "phase order") &&
      ((s.phases.filter(_.attributed).map(_.name).toSet subsetOf Set("scan", "other")) :| "only scan/other are attributed")
    }

  // ------------------------------------------------------------------ (part)

  property("(part) a partial snapshot names the query still executing, and counts it as db time") = secure {
    val c = new FakeClock
    val t = new RenderTrace(c.f)
    t.start(); t.driveEnter(); c.tick(ms1); t.driverStart()
    t.enter("$.fetch[1]", "fetched"); t.queryStart("SELECT 1", "sqlite"); t.queryExecuted(2 * ms1); t.queryClosed()
    t.exit("$.fetch[1]", "fetched", 0, 1, 1, 0, false)
    t.enter("$.fetch[2]", "fetched"); c.tick(ms1)
    t.queryStart("SELECT slow", "mssql")
    c.tick(60000 * ms1)
    val p = t.snapshot(partial = true)
    val done = t.snapshot(partial = false)
    (p.partial :| "partial flag") &&
    ((p.running.flatMap(_.path) ?= Some("$.fetch[2]")) :| ("running " + p.running)) &&
    ((p.running.flatMap(_.sql) ?= Some("SELECT slow")) :| "running sql") &&
    (near(p.running.map(_.sinceMs).getOrElse(-1.0), 60001.0) :| ("since " + p.running)) &&
    ((p.queries.map(_.path) ?= List("$.fetch[1]", "$.fetch[2]")) :| "the open entry is listed last") &&
    ((p.totals.dbMs >= 60000.0) :| ("the running query is db time: " + p.totals)) &&
    (near(p.totals.dbMs + p.totals.otherMs, p.totals.wallMs) :| "sum") &&
    (done.running.isEmpty :| "a non-partial snapshot names nothing running")
  }

  property("(part) stuck in evaluation: the partial trace names the phase") = secure {
    val c = new FakeClock
    val t = new RenderTrace(c.f)
    t.start()
    val latch = new CountDownLatch(1); val entered = new CountDownLatch(1)
    val th = new Thread(() => t.phase("eval") { entered.countDown(); latch.await(10, TimeUnit.SECONDS); () })
    th.start(); entered.await(10, TimeUnit.SECONDS)
    c.tick(5 * ms1)
    val p = t.snapshot(partial = true)
    latch.countDown(); th.join(10000)
    ((p.running.flatMap(_.phase) ?= Some("eval")) :| ("running " + p.running)) && (p.running.flatMap(_.path) ?= None)
  }

  // ------------------------------------------------------------------ (max)

  property("(max) 200 entries, truncated counts the rest, totals count all; the size cap shortens SQL") = secure {
    val c = new FakeClock
    val t = new RenderTrace(c.f)
    t.start()
    (1 to 250).foreach { i =>
      t.enter("$.fetch[" + i + "]", "fetched"); t.queryStart("SELECT " + ("x" * 100), "sqlite")
      t.queryExecuted(10); t.rowFetched(1, true); t.queryClosed(); t.exit("$.fetch[" + i + "]", "fetched", 0, 1, 1, 0, false)
    }
    t.finish()
    val s = t.snapshot()
    val c2 = new FakeClock
    val big = new RenderTrace(c2.f)
    big.start()
    (1 to 40).foreach { i =>
      big.enter("$.fetch[" + i + "]", "fetched"); big.queryStart("SELECT " + ("y" * 20000), "mssql")
      big.queryExecuted(10); big.queryClosed(); big.exit("$.fetch[" + i + "]", "fetched", 0, 0, 0, 0, false)
    }
    big.finish()
    val b = big.snapshot()
    ((s.queries.length ?= 200) :| "entries kept") &&
    ((s.truncated.map(_.queries) ?= Some(50)) :| ("truncated " + s.truncated)) &&
    ((s.totals.relations ?= 250) :| "relations counted") &&
    ((s.totals.rowsRead ?= 250L) :| "rows counted") &&
    ((b.queries.length ?= 40) :| "the size cap dropped entries it did not need to") &&
    ((b.truncated.map(_.sqlShortened) ?= Some(true)) :| ("sqlShortened " + b.truncated)) &&
    (b.queries.forall(q => q.sql.exists(x => utf8Length(x) <= ShrunkSqlBytes + 64 && x.contains("[ermine: truncated,"))) :|
      "every SQL shortened to ~1 KiB with the marker") &&
    (b.queries.forall(_.sqlBytes == 20007L) :| "sqlBytes keeps the full length")
  }

  // ------------------------------------------------------------------ (off)

  property("(off) Off records nothing; current is Off outside installed; installed restores on a throw") = secure {
    val off = RenderTrace.Off
    off.start(); off.enter("$.x", "fetched"); off.queryStart("SELECT 1", "sqlite"); off.exit("$.x", "fetched", 0, 1, 1, 0, false)
    val s = off.snapshot()
    val live = new RenderTrace()
    val before = RenderTrace.current
    val inside = RenderTrace.installed(live)(RenderTrace.current)
    val threw = try { RenderTrace.installed(live)(throw new RuntimeException("x")); false } catch { case _: RuntimeException => true }
    val after = RenderTrace.current
    (s.queries.isEmpty :| "Off kept an entry") && (!off.started :| "Off started") &&
    ((before eq RenderTrace.Off) :| "current is not Off outside installed") &&
    ((inside eq live) :| "installed did not install") && threw &&
    ((after eq RenderTrace.Off) :| "installed did not restore after a throw")
  }

  // ------------------------------------------------------------------ (json)

  property("(json) generation carried, 0.1 ms rounding, SQL and messages scrubbed") = secure {
    val c = new FakeClock
    val t = new RenderTrace(c.f)
    t.start(); t.enter("$.fetch[1]", "fetched")
    t.queryStart("SELECT 'jdbc:sqlserver://db.example;password=hunter2' AS x", "mssql")
    c.tick(1234567L); t.queryExecuted(1234567L)
    t.failed("$.fetch[1]", "cannot open jdbc:sqlserver://db.example;password=hunter2")
    t.finish()
    val j = TraceJson(t.snapshot(), Json.num(42), Preview.scrubUrls)
    val text = Json.print(j)
    val q = j / "queries" flatMap (_.arr) flatMap (_.headOption)
    ((j / "generation" flatMap (_.int)) ?= Some(42)) &&
    ((q flatMap (_ / "execMs") flatMap (_.num)) ?= Some(1.2)) &&
    ((q flatMap (_ / "error") flatMap (_.bool)) ?= Some(true)) &&
    (!text.contains("jdbc:") :| ("a URL survived the scrub: " + text)) &&
    (!text.contains("hunter2") :| "a password survived the scrub") &&
    ((j / "v" flatMap (_.int)) ?= Some(TraceJson.Version))
  }

  // ------------------------------------------------------------------ the preview path

  import PreviewSupport._

  private val docDir = Paths.get("core/src/test/resources/doc").toAbsolutePath.normalize

  private def keysOf(j: Option[Json]): List[String] = resultOf(j) match { case Some(Json.Obj(fs)) => fs.map(_._1); case _ => Nil }
  private def traceOf(j: Option[Json]): Option[Json] = resultOf(j) flatMap (_ / "trace")
  private def queriesOf(t: Option[Json]): List[Json] = t flatMap (_ / "queries") flatMap (_.arr) getOrElse Nil
  private def strOf(j: Json, k: String): Option[String] = j / k flatMap (_.str)
  private def numOf(j: Option[Json], k: String): Option[Double] = j flatMap (_ / k) flatMap (_.num)

  property("(t1 t3 t4 t7) the preview path: trace last on ok, failed, stuck; displaced carries none") = secure {
    previewLock.synchronized { ErmineFixture.literalLock.synchronized {
      val b = new Bench(warm = false)
      val roots = List(docDir)
      val topN = docDir.resolve("FetchTopN.e")
      try {
        // ---- (t1) ok
        b.renderWith(1, topN, "report", "{\"keep\":2}", 11, roots)
        val a1 = b.answer(1, 300000L)
        val t1 = traceOf(a1)
        val q1 = queriesOf(t1)
        val fetches = q1.filter(q => strOf(q, "delivery") == Some("fetched"))
        val tot1 = t1 flatMap (_ / "totals")
        val conn1 = t1 flatMap (_ / "connection")
        println("[render-trace] ok FetchTopN trace: " + t1.map(Json.print).getOrElse("-").take(1500))
        // ---- (t3) failed: DbFetchTopN's tables are not in the in-memory database
        b.renderWith(2, docDir.resolve("DbFetchTopN.e"), "report", "{\"keep\":2}", 12, roots)
        val a2 = b.answer(2, 300000L)
        val t2 = traceOf(a2)
        val last2 = queriesOf(t2).lastOption
        println("[render-trace] failed DbFetchTopN (in-memory) trace: " + t2.map(Json.print).getOrElse("-").take(800))
        // ---- (t4) stuck inside its first query
        val held = new CountDownLatch(1); val release = new CountDownLatch(1)
        b.preview.timeoutMillis = 300L
        RenderTrace.queryStartHook = { (_: String) =>
          if (held.getCount > 0) { held.countDown(); release.await(120L, TimeUnit.SECONDS); () }
        }
        b.renderWith(3, topN, "report", "{\"keep\":1}", 13, roots)
        val inQuery = held.await(120L, TimeUnit.SECONDS)
        val a3 = b.answer(3, 120000L)
        RenderTrace.queryStartHook = null
        release.countDown()
        val fall = stuckNote(b, false, 120000L)
        b.preview.timeoutMillis = Preview.DefaultTimeoutSeconds * 1000L
        val t3 = traceOf(a3)
        val running = t3 flatMap (_ / "running")
        println("[render-trace] stuck trace: " + t3.map(Json.print).getOrElse("-").take(800))
        // ---- (t7) displacement: A held before it runs, B displaced by C
        val aHeld = new CountDownLatch(1); val aGo = new CountDownLatch(1)
        b.preview.beforeJob = {
          case r: Preview.Render if r.req.generation == Json.num(21) => aHeld.countDown(); aGo.await(120L, TimeUnit.SECONDS); ()
          case _ => ()
        }
        b.renderWith(4, topN, "report", "{\"keep\":2}", 21, roots)
        val aIn = aHeld.await(120L, TimeUnit.SECONDS)
        b.renderWith(5, topN, "report", "{\"keep\":2}", 22, roots)
        b.awaitQueued(1, 60000L)
        b.renderWith(6, topN, "report", "{\"keep\":2}", 23, roots)
        val aB = b.answer(5, 60000L)
        aGo.countDown()
        b.preview.beforeJob = _ => ()
        val aA = b.answer(4, 300000L)
        val aC = b.answer(6, 300000L)
        val log = b.sink.result()
        val lateLine = log.find(l => l.contains("finished after the watchdog answered it"))
        println("[render-trace] late job log line: " + lateLine.getOrElse("-"))
        ((okOf(a1) ?= Some(true)) :| ("t1 ok: " + show(a1))) &&
        ((keysOf(a1).lastOption ?= Some("trace")) :| ("t1 trace is not the last key: " + keysOf(a1))) &&
        ((t1 flatMap (_ / "generation") flatMap (_.int)) ?= Some(11)) &&
        ((conn1 flatMap (c => strOf(c, "kind"))) ?= Some("in-memory")) &&
        ((conn1 flatMap (c => strOf(c, "dialect"))) ?= Some("sqlite")) &&
        ((fetches.map(q => strOf(q, "path").getOrElse("?")) ?= List("$.fetch[1]", "$.fetch[2]")) :| ("t1 fetch entries: " + fetches.map(Json.print))) &&
        (fetches.forall(q => strOf(q, "sql").exists(_.toUpperCase.contains("SELECT")) && strOf(q, "dialect") == Some("sqlite")) :| "t1 fetch SQL/dialect") &&
        // fetch[1] is `groupBy {region} (sumBy amount) sales`: a Mem, grouped by
        // Ermine over the 8 scanned rows, so the SQL reads 8 and the report
        // gets 4; fetch[2] reads the 4 targets
        ((fetches.map(q => (q / "rowsRead").flatMap(_.int)) ?= List(Some(8), Some(4))) :| "t1 rows read: 8 sales rows, 4 targets") &&
        ((fetches.map(q => (q / "rows").flatMap(_.int)) ?= List(Some(4), Some(4))) :| "t1 rows used: 4 regions, 4 targets") &&
        (near(numOf(tot1, "dbMs").get + numOf(tot1, "otherMs").get, numOf(tot1, "wallMs").get, 0.11) :| ("t1 totals " + tot1.map(Json.print))) &&
        ((numOf(tot1, "dbMs").get <= numOf(tot1, "wallMs").get) :| "t1 db <= wall") &&
        ((okOf(a2) ?= Some(false)) :| ("t3 " + show(a2))) &&
        ((keysOf(a2).lastOption ?= Some("trace")) :| ("t3 keys " + keysOf(a2))) &&
        ((last2 flatMap (_ / "error") flatMap (_.bool)) ?= Some(true)) &&
        ((last2 flatMap (q => strOf(q, "path"))) ?= Some("$.fetch[1]")) &&
        ((last2 flatMap (q => strOf(q, "sql"))).exists(_.contains("sales")) :| ("t3 failing SQL: " + last2.map(Json.print))) &&
        (inQuery :| "t4 the render never reached its query") &&
        ((stuckOf(a3) ?= Some(true)) :| ("t4 " + show(a3))) &&
        ((keysOf(a3).lastOption ?= Some("trace")) :| ("t4 keys " + keysOf(a3))) &&
        ((t3 flatMap (_ / "partial") flatMap (_.bool)) ?= Some(true)) &&
        ((running flatMap (r => strOf(r, "path"))) ?= Some("$.fetch[1]")) &&
        ((running flatMap (r => strOf(r, "sql"))).exists(_.toUpperCase.contains("SELECT")) :| ("t4 running " + running.map(Json.print))) &&
        (fall.isDefined :| "t4 the held job never came back") &&
        (lateLine.exists(_.contains("trace wall")) :| ("t4 the late job's trace is not in the log: " + lateLine)) &&
        (aIn :| "t7 A never started") &&
        ((errCode(aB) ?= Some(Rpc32800)) :| ("t7 B was not displaced: " + show(aB))) &&
        (traceOf(aB).isEmpty :| "t7 a displaced render carried a trace") &&
        ((traceOf(aA) flatMap (_ / "generation") flatMap (_.int)) ?= Some(21)) &&
        ((traceOf(aC) flatMap (_ / "generation") flatMap (_.int)) ?= Some(23)) &&
        ((genOf(aC) ?= Some(23)) :| ("t7 C " + show(aC)))
      } finally {
        RenderTrace.queryStartHook = null
        b.preview.beforeJob = _ => ()
        b.stop(); ()
      }
    } }
  }

  private val Rpc32800 = -32800
}
