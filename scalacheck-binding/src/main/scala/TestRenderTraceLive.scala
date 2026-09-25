package com.clarifi.reporting

import com.clarifi.reporting.backends.{ Runners, Scanners }
import com.clarifi.reporting.ermine.json.{ Runner, RunnerConfig }
import com.clarifi.reporting.ermine.lsp.{ Json, Preview, TraceJson }
import com.clarifi.reporting.relational.SMEnv

import java.io.File
import java.nio.file.{ Path, Paths }

import org.scalacheck.{ Prop, Properties }
import Prop._

/** DB programme stage 2b, LIVE (tracker/db/OBSERVABILITY.md §5): the render
  * trace through the preview's real wire, on ErmineSales and on the SQLite
  * twin.
  *
  * ENV-GATED like `TestPreviewDbLive`: without ERMINE_DB_URL, ERMINE_DB_USER
  * and ERMINE_DB_PASSWORD it registers NOTHING and prints one "DB suites: not
  * requested" line (the `db` gate fails on that line and runs this suite with
  * db.env).  TIER-AGNOSTIC: every row count is checked against the database
  * itself, not against a pinned number, so it holds at xs (the gate) and at s
  * (the morning example).
  *
  * (live) The seven in-memory originals are rendered first, then the preview
  * connects `sales-mssql` and renders the seven twins.  For each twin:
  *  - the answer carries `trace` as its LAST key, its generation the answer's;
  *  - connection {kind profile, dialect mssql, database ErmineSales, profile
  *    sales-mssql}; every entry that ran SQL says dialect mssql;
  *  - AT TIER xs, the twin's entries are the original's: the same paths and
  *    deliveries in the same order (the report is the same and so are the
  *    rows), so the expected query count is the original's; above xs a
  *    parameter can name a region the tier lacks and the report scans less;
  *  - every query that needed no setup statement, re-run by hand over JDBC
  *    from the trace's own SQL text, returns exactly `rowsRead` rows -- the
  *    dogfood step "copy the SQL, run it, the rows match";
  *  - `dbMs <= wallMs` and `dbMs + otherMs == wallMs` within the 0.1 ms
  *    rounding; `totals.rowsRead` is the entries' sum.
  * Then `sales-sqlite` (the twin at ERMINE_DB_SQLITE, default the loader's
  * xs file) is connected and `DbFetchTopN` rendered: its trace says dialect
  * sqlite, kind profile.
  *
  * (ab) ONLY with ERMINE_TRACE_AB=1 (not in the gate): the interleaved cost
  * comparison of the stage-2b brief -- `Runner` directly, on ONE held MSSQL
  * connection, `DbFetchRunning` and `DbFetchTopN`, rounds of {Off, trace
  * with the per-row clock, trace without it} in rotating order, wall time
  * per render; medians printed as `[render-trace-ab]` lines.  Its only
  * verdict is that every render succeeded; the numbers are the result.
  */
object TestRenderTraceLive extends Properties("RenderTrace, live on ErmineSales (DB programme S2b)") {

  import PreviewSupport._

  /** ONE evaluation per property, whatever its status: a live render pass is
    * minutes at tier m, and a conjunction that ends `True` rather than
    * `Proof` would otherwise be re-run until 100 successes (MEASURED: the
    * first tier-m run re-ran the live property 100 times, 914 s). */
  override def overrideParameters(p: org.scalacheck.Test.Parameters): org.scalacheck.Test.Parameters =
    p.withMinSuccessfulTests(1).withWorkers(1)

  private val docDir  = Paths.get("core/src/test/resources/doc").toAbsolutePath.normalize
  private val modDir  = Paths.get("core/src/test/resources/modules").toAbsolutePath.normalize

  private val env = sys.env
  private val creds = for {
    u  <- env.get("ERMINE_DB_URL").filter(_.nonEmpty)
    us <- env.get("ERMINE_DB_USER").filter(_.nonEmpty)
    pw <- env.get("ERMINE_DB_PASSWORD").filter(_.nonEmpty)
  } yield (TestMsSqlSmoke.withLocalTls(u), us, pw)

  private val sqliteFile: File =
    new File(env.get("ERMINE_DB_SQLITE").filter(_.nonEmpty).getOrElse("data/out/sales/xs/sales.sqlite")).getAbsoluteFile

  /** (twin, original, file of the twin, file of the original, roots, params) */
  private val cases: List[(String, String, Path, Path, List[Path], String)] =
    List(("DbFetchTopN", "FetchTopN", "{\"keep\":2}"),
         ("DbFetchHeadline", "FetchHeadline", "{\"onlyRegion\":\"north\"}"),
         ("DbFetchCrosstab", "FetchCrosstab", "{\"measureUnits\":false}"),
         ("DbFetchRunning", "FetchRunning", "{\"newestFirst\":false}"),
         ("DbFetchTabs", "FetchTabs", "{\"showUnits\":true}"),
         ("DbFetchFragments", "FetchFragments", "{\"tabsFor\":[\"north\",\"south\"],\"topN\":2}"))
      .map { case (t, o, p) => (t, o, docDir.resolve(t + ".e"), docDir.resolve(o + ".e"), List(docDir), p) } :+
    (("Doc.DbSalesReport", "Doc.SalesReport", modDir.resolve("Doc/DbSalesReport.e"),
      modDir.resolve("Doc/SalesReport.e"), List(modDir), "{}"))

  private def res(a: Option[Json]): Option[Json] = a flatMap (_ / "result")
  private def keys(a: Option[Json]): List[String] = res(a) match { case Some(Json.Obj(fs)) => fs.map(_._1); case _ => Nil }
  private def trace(a: Option[Json]): Option[Json] = res(a) flatMap (_ / "trace")
  private def entries(t: Option[Json]): List[Json] = t flatMap (_ / "queries") flatMap (_.arr) getOrElse Nil
  private def s(j: Json, k: String): Option[String] = j / k flatMap (_.str)
  private def n(j: Option[Json], k: String): Double = j flatMap (_ / k) flatMap (_.num) getOrElse Double.NaN
  private def shape(t: Option[Json]): List[(String, String)] =
    entries(t).map(e => (s(e, "path").getOrElse("?"), s(e, "delivery").getOrElse("?")))

  /** The tier ErmineSales holds, from the loader's stamp (tracker/db/LOADER.md §1). */
  private def tierOf(c: java.sql.Connection): String = {
    val st = c.createStatement()
    try {
      val rs = st.executeQuery(
        "SELECT CAST(value AS nvarchar(4000)) FROM sys.extended_properties WHERE class = 0 AND name = 'ermine.load.sales'")
      val stamp = if (rs.next()) rs.getString(1) else ""
      "\"tier\"\\s*:\\s*\"([^\"]+)\"".r.findFirstMatchIn(stamp).map(_.group(1)).getOrElse("<no stamp>")
    } finally st.close()
  }

  private def countRows(conn: java.sql.Connection, sql: String): Long = {
    val st = conn.createStatement()
    try { val rs = st.executeQuery(sql); var k = 0L; while (rs.next()) k += 1; k } finally st.close()
  }

  creds match {
    case None =>
      println("[render-trace-live] DB suites: not requested (no ERMINE_DB_* in the environment); the `db` gate runs them")
    case Some((url, user, password)) =>
      def scrub(x: String): String = if (x == null) "" else x.replace(password, "<password>").replace(url, "<url>")
      def say(x: String): Unit = println("[render-trace-live] " + scrub(x))
      Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver")

      property("live: twins on ErmineSales carry traces whose SQL, rows and times agree with the database") =
        secure { previewLock.synchronized { ErmineFixture.literalLock.synchronized {
          val b = new Bench(warm = false)
          val props = new java.util.Properties
          props.setProperty("user", user); props.setProperty("password", password)
          val jdbc = java.sql.DriverManager.getConnection(url, props)
          val profile = Json.obj("id" -> Json.Str("sales-mssql"), "dialect" -> Json.Str("mssql"),
                                 "url" -> Json.Str(url), "user" -> Json.Str(user))
          try {
            var id = 0
            def render(p: Path, roots: List[Path], params: String): Option[Json] = {
              id += 1
              b.renderWith(id, p, "report", params, 100 + id, roots)
              b.answer(id, 300000L)
            }
            val originals = cases.map { case (_, o, _, op, roots, params) => o -> render(op, roots, params) }.toMap
            id += 1
            b.request(id, "ermine/preview/connect", Json.obj("profile" -> profile, "password" -> Json.Str(password)))
            val con = b.answer(id, 120000L)
            say("connect: " + res(con).map(Json.print).getOrElse("-"))
            // the profile change re-boots the session: pay it here, so the
            // twins below (and the printed example) are warm renders
            render(docDir.resolve("DbFetchTopN.e"), List(docDir), "{\"keep\":2}")
            val tier = tierOf(jdbc)
            say("ErmineSales holds tier " + tier)
            val twins = cases.map { case (t, _, tp, _, roots, params) => t -> (render(tp, roots, params), 100 + id) }
            // the SQLite twin
            val lite = if (!sqliteFile.isFile) None else {
              id += 1
              b.request(id, "ermine/preview/connect", Json.obj("profile" -> Json.obj(
                "id" -> Json.Str("sales-sqlite"), "dialect" -> Json.Str("sqlite"),
                "url" -> Json.Str("jdbc:sqlite:" + sqliteFile.getPath))))
              val c2 = b.answer(id, 120000L)
              say("connect sqlite twin: " + res(c2).map(Json.print).getOrElse("-"))
              Some(render(docDir.resolve("DbFetchTopN.e"), List(docDir), "{\"keep\":2}"))
            }
            val checks: List[Prop] = cases.map { case (t, o, _, _, _, _) =>
              val (a, _) = twins.find(_._1 == t).get._2
              val tr = trace(a)
              val orig = trace(originals(o))
              val tot = tr flatMap (_ / "totals")
              val conn = tr flatMap (_ / "connection")
              val es = entries(tr)
              val reruns = es.filter(e => (e / "sql").isDefined).filter(e => (e / "setup").isEmpty)
                             .filterNot(e => (e / "error").isDefined)
                             .map(e => (s(e, "path").get, (e / "rowsRead").flatMap(_.num).map(_.toLong).getOrElse(-1L),
                                        countRows(jdbc, s(e, "sql").get)))
              say(f"$t: ok=${res(a).flatMap(_ / "ok").flatMap(_.bool)} wall ${n(tot, "wallMs")}%.1f ms db ${n(tot, "dbMs")}%.1f ms " +
                  f"queries ${n(tot, "queries")}%.0f rowsRead ${n(tot, "rowsRead")}%.0f; reruns " +
                  reruns.map { case (p, r, j) => p + " trace=" + r + " jdbc=" + j }.mkString(", "))
              if (t == "DbFetchTopN") say("EXAMPLE trace (DbFetchTopN): " + tr.map(Json.print).getOrElse("-"))
              val label = t + ": "
              ((res(a).flatMap(_ / "ok").flatMap(_.bool) ?= Some(true)) :| (label + scrub(a.map(Json.print).getOrElse("-")).take(600))) &&
              ((keys(a).lastOption ?= Some("trace")) :| (label + "trace not last: " + keys(a))) &&
              (((tr flatMap (_ / "generation") flatMap (_.int)) == (res(a) flatMap (_ / "generation") flatMap (_.int))) :| (label + "generation")) &&
              ((conn.flatMap(c => s(c, "dialect")) ?= Some("mssql")) :| (label + "connection " + conn.map(Json.print))) &&
              ((conn.flatMap(c => s(c, "kind")) ?= Some("profile")) :| label) &&
              ((conn.flatMap(c => s(c, "database")) ?= Some("ErmineSales")) :| (label + "connection " + conn.map(Json.print))) &&
              ((conn.flatMap(c => s(c, "profile")) ?= Some("sales-mssql")) :| label) &&
              (es.filter(e => (e / "sql").isDefined).forall(e => s(e, "dialect") == Some("mssql")) :| (label + "an entry's dialect")) &&
              // at xs the twin's data ARE the original's literals, so the
              // report takes the same path; above xs a parameter may name a
              // region that is not there (DbFetchHeadline "north") and the
              // report legitimately scans less
              (if (tier == "xs") (shape(tr) ?= shape(orig)) :| (label + "the twin's entries differ from the original's")
               else (es.nonEmpty :| (label + "no entries"))) &&
              (reruns.nonEmpty || es.forall(e => (e / "sql").isEmpty)) :| (label + "no query could be re-run") &&
              (reruns.forall { case (_, r, j) => r == j } :| (label + "rows read != rows by JDBC: " + reruns)) &&
              ((n(tot, "dbMs") <= n(tot, "wallMs")) :| (label + "db > wall")) &&
              ((math.abs(n(tot, "dbMs") + n(tot, "otherMs") - n(tot, "wallMs")) <= 0.11) :| (label + "db + other != wall")) &&
              ((n(tot, "rowsRead") == es.map(e => (e / "rowsRead").flatMap(_.num).getOrElse(0.0)).sum) :| (label + "rowsRead sum"))
            }
            val liteProp: Prop = lite match {
              case None => Prop.passed :| "no SQLite twin file"
              case Some(a) =>
                val tr = trace(a)
                val conn = tr flatMap (_ / "connection")
                say("sqlite twin DbFetchTopN trace: " + tr.map(Json.print).getOrElse("-").take(1500))
                ((res(a).flatMap(_ / "ok").flatMap(_.bool) ?= Some(true)) :| ("sqlite twin " + scrub(a.map(Json.print).getOrElse("-")).take(600))) &&
                ((conn.flatMap(c => s(c, "dialect")) ?= Some("sqlite")) :| ("sqlite connection " + conn.map(Json.print))) &&
                ((conn.flatMap(c => s(c, "kind")) ?= Some("profile")) :| "sqlite kind") &&
                (entries(tr).filter(e => (e / "sql").isDefined).forall(e => s(e, "dialect") == Some("sqlite")) :| "sqlite entry dialect") &&
                ((shape(tr) ?= shape(trace(twins.head._2._1))) :| "the sqlite twin's entries")
            }
            val log = b.sink.result()
            val leaked = log.exists(_.contains(password)) || b.remaining().exists(j => Json.print(j).contains(password))
            ((res(con).flatMap(_ / "ok").flatMap(_.bool) ?= Some(true)) :| "connect failed") &&
            checks.reduce(_ && _) && liteProp && (!leaked :| "the password reached the log or the wire")
          } finally { try jdbc.close() catch { case _: Throwable => () }; b.stop(); () }
        } } }

      if (env.get("ERMINE_TRACE_AB").contains("1"))
        property("ab: interleaved cost of the trace (Off / per-row clock / no row clock), wall per render") = secure {
          ErmineFixture.literalLock.synchronized {
            val props = new java.util.Properties
            props.setProperty("user", user); props.setProperty("password", password)
            val conn = java.sql.DriverManager.getConnection(url, props)
            try {
              val r = new Runner(RunnerConfig(roots = List(docDir.toString), run = Runners.fromPersistentConnection(conn),
                                              scanner = Scanners.MicrosoftSQLServer(SMEnv.dummySmenv)))
              val modes = List("off", "rows", "norows")
              def once(module: String, params: String, mode: String): (Double, Boolean, Option[RenderTrace.Snapshot]) = {
                val t = mode match { case "off" => RenderTrace.Off; case "rows" => new RenderTrace(); case _ => new RenderTrace(timeRows = false) }
                val out = new java.lang.StringBuilder
                t.start()
                val t0 = System.nanoTime
                val ok = r.renderText(module, "report", "{\"params\":" + params + "}", out, t).isRight
                val ms = (System.nanoTime - t0) / 1e6
                t.finish()
                (ms, ok, if (t.on) Some(t.snapshot()) else None)
              }
              val reports = List(("DbFetchRunning", "{\"newestFirst\":false}"), ("DbFetchTopN", "{\"keep\":2}"))
              var allOk = true
              reports.foreach { case (m, p) =>
                (1 to 3).foreach(_ => allOk &= once(m, p, "rows")._2)   // warm: compile, JIT, plan cache
                val got = scala.collection.mutable.Map[String, List[Double]]().withDefaultValue(Nil)
                var example: Option[RenderTrace.Snapshot] = None
                (0 until 5).foreach { round =>
                  val order = modes.drop(round % 3) ++ modes.take(round % 3)
                  order.foreach { mode =>
                    val (ms, ok, snap) = once(m, p, mode)
                    allOk &= ok
                    got(mode) = ms :: got(mode)
                    if (mode == "rows") example = snap
                  }
                }
                def median(xs: List[Double]) = { val v = xs.sorted; v(v.length / 2) }
                val off = median(got("off"))
                val rows = example.map(_.totals.rowsRead).getOrElse(-1L)
                println(f"[render-trace-ab] $m rowsRead=$rows off ${median(got("off"))}%.1f ms (" + got("off").reverse.map(x => f"$x%.1f").mkString(",") + ")")
                List("rows", "norows").foreach { mode =>
                  val md = median(got(mode))
                  println(f"[render-trace-ab] $m $mode $md%.1f ms (" + got(mode).reverse.map(x => f"$x%.1f").mkString(",") +
                          f") delta ${(md - off) / off * 100}%+.1f%% vs off")
                }
                example.foreach(sn => println(f"[render-trace-ab] $m trace: wall ${sn.totals.wallMs}%.1f db ${sn.totals.dbMs}%.1f fetch " +
                  f"${sn.queries.map(_.fetchMs).sum}%.1f ms over ${sn.totals.rowsRead} rows; phases " +
                  sn.phases.map(ph => f"${ph.name}=${ph.ms}%.1f").mkString(" ")))
              }
              allOk :| "a render failed"
            } finally conn.close()
          }
        }
  }
}
