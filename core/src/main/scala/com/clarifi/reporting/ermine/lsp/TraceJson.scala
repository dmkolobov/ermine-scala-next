package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.RenderTrace
import com.clarifi.reporting.RenderTrace._

/** The `trace` key of an `ermine/render` answer (DB programme stage 2b;
  * tracker/db/OBSERVABILITY.md §3 has the schema as a table).  Built from a
  * `RenderTrace.Snapshot` and the answer's own `generation`, so a trace can
  * be checked against the answer it rides on.
  *
  * DECODE-SHAPED (design D5): records, lists, numbers, strings and booleans
  * only; an absent optional key is left out, never `null`.  Times are
  * milliseconds rounded to 0.1; counts are integers.
  *
  * `scrub` is applied to every string that can carry user text -- the SQL,
  * an error message, a running query's SQL -- as the backstop design §2.3
  * asks for (`scrubUrls`, and the active profile's url/user/host). */
object TraceJson {
  val Version = 1

  def apply(s: Snapshot, generation: Json, scrub: String => String): Json = {
    def str(x: String) = Json.Str(scrub(x))
    val q = s.queries.map { e =>
      Json.Obj(
        List("path" -> Json.Str(e.path), "delivery" -> Json.Str(e.delivery)) ++
        e.dialect.toList.map(d => "dialect" -> Json.Str(d)) ++
        e.sql.toList.map(x => "sql" -> str(x)) ++
        (if (e.sql.isDefined) List("sqlBytes" -> long(e.sqlBytes), "statements" -> Json.num(e.queries)) else Nil) ++
        (if (e.setup.nonEmpty) List("setup" -> Json.Arr(e.setup.map(setup))) else Nil) ++
        List("sqlEmitMs" -> ms(e.sqlEmitMs), "execMs" -> ms(e.execMs)) ++
        (if (s.rowsTimed) List("fetchMs" -> ms(e.fetchMs)) else Nil) ++
        List("dbMs" -> ms(e.dbMs), "ms" -> ms(e.ms),
             "rowsRead" -> long(e.rowsRead), "rows" -> long(e.rows), "scanned" -> long(e.scanned),
             "columns" -> Json.num(e.columns), "bytes" -> long(e.bytes),
             "deferred" -> Json.Bool(e.deferred)) ++
        (if (e.overThreshold) List("overThreshold" -> Json.Bool(true)) else Nil) ++
        e.error.toList.flatMap(m => List("error" -> Json.Bool(true), "message" -> str(m))))
    }
    val t = s.totals
    val totals = Json.Obj(List(
      "dbMs" -> ms(t.dbMs), "otherMs" -> ms(t.otherMs), "wallMs" -> ms(t.wallMs), "queueMs" -> ms(t.queueMs),
      "relations" -> Json.num(t.relations), "queries" -> Json.num(t.queries),
      "rowsRead" -> long(t.rowsRead), "rows" -> long(t.rows), "bytes" -> long(t.bytes)) ++
      t.documentBytes.toList.map(b => "documentBytes" -> long(b)))
    val c = s.connection
    val conn = Json.Obj(List("kind" -> Json.Str(c.kind), "dialect" -> Json.Str(c.dialect)) ++
                        c.database.toList.map(d => "database" -> str(d)) ++
                        c.profile.toList.map(p => "profile" -> Json.Str(p)))
    Json.Obj(
      List("v" -> Json.num(Version), "generation" -> generation, "partial" -> Json.Bool(s.partial),
           "wallMs" -> ms(t.wallMs),
           "phases" -> Json.Arr(s.phases.map(p => Json.Obj(
             List("name" -> Json.Str(p.name), "ms" -> ms(p.ms)) ++
             (if (p.attributed) List("attributed" -> Json.Bool(true)) else Nil) ++
             p.cached.toList.map(b => "cached" -> Json.Bool(b))))),
           "queries" -> Json.Arr(q),
           "totals" -> totals,
           "connection" -> conn) ++
      s.running.toList.map(r => "running" -> Json.Obj(
        r.path.toList.map(p => "path" -> Json.Str(p)) ++
        r.phase.toList.map(p => "phase" -> Json.Str(p)) ++
        r.sql.toList.map(x => "sql" -> str(x)) ++
        List("sinceMs" -> ms(r.sinceMs)))) ++
      s.truncated.toList.map(x => "truncated" -> Json.obj(
        "queries" -> Json.num(x.queries), "sqlShortened" -> Json.Bool(x.sqlShortened))))
  }

  /** One line for the server log (a job the watchdog already answered). */
  def summary(s: Snapshot): String = {
    val t = s.totals
    f"trace wall ${t.wallMs}%.1f ms, db ${t.dbMs}%.1f ms, ${t.queries} queries, ${t.rowsRead} rows read" +
      s.queries.lastOption.filter(_.error.isDefined).map(e => ", failed at " + e.path).getOrElse("")
  }

  private def setup(x: Setup): Json =
    Json.Obj(List("kind" -> Json.Str(x.kind)) ++
             x.table.toList.map(t => "table" -> Json.Str(t)) ++
             x.created.toList.map(b => "created" -> Json.Bool(b)) ++
             List("ms" -> ms(x.ms)) ++
             (if (x.error) List("error" -> Json.Bool(true)) else Nil))

  private def ms(d: Double): Json = Json.Num(math.round(d * 10.0) / 10.0)
  private def long(n: Long): Json = Json.Num(n.toDouble)
}
