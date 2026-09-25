package com.clarifi.reporting

import com.clarifi.reporting.ermine.lsp.Json
import com.clarifi.reporting.ermine.json.{ Wire => DocWire }

import java.nio.file.Paths

import org.scalacheck.{ Prop, Properties }
import Prop._

/** WP-13 SERVER HALF, LIVE (DB programme stage 2a; tracker/db/SERVER.md §5):
  * the preview, over its real wire, connects to ErmineSales on the local SQL
  * Server with a PROMPTED-style password (the request's `password`), renders
  * `DbFetchTopN`, and answers the document the in-memory `FetchTopN` answers
  * through the same preview, modulo the order of inline rows; then
  * `disconnect` makes a render the 503 `not-connected`; then a connect with a
  * WRONG password answers class `auth`, reason `connect-auth`, `kept: false`.
  *
  * ENV-GATED exactly like `TestMsSqlSmoke`: without ERMINE_DB_URL,
  * ERMINE_DB_USER and ERMINE_DB_PASSWORD it registers NOTHING and prints one
  * "DB suites: not requested" line (the `db` gate fails on that line and runs
  * this suite with db.env).  The database must hold tier xs (the equality
  * pins FetchData.e's literal rows); the suite reads the loader's stamp first
  * and says so plainly if it does not.  Every printed line is scrubbed of
  * the password, the url and the user. */
object TestPreviewDbLive extends Properties("Preview profile, live on ErmineSales (WP-13 server half)") {

  import PreviewSupport._

  private val docDir = Paths.get("core/src/test/resources/doc").toAbsolutePath.normalize

  private val env = sys.env
  private val creds = for {
    u  <- env.get("ERMINE_DB_URL").filter(_.nonEmpty)
    us <- env.get("ERMINE_DB_USER").filter(_.nonEmpty)
    pw <- env.get("ERMINE_DB_PASSWORD").filter(_.nonEmpty)
  } yield (TestMsSqlSmoke.withLocalTls(u), us, pw)

  /** The document with the inline rows of every relation object sorted
    * (TestDbReports.rowSorted, over the LSP's own `Json`). */
  def rowSorted(j: Json): Json = j match {
    case Json.Arr(vs) => Json.Arr(vs map rowSorted)
    case Json.Obj(fs) =>
      val isRel = fs.exists { case (k, Json.Str(_)) => k == DocWire.Kind; case _ => false }
      Json.Obj(fs map {
        case (k, Json.Arr(rows)) if isRel && k == DocWire.Rows => k -> Json.Arr(rows.sortBy(Json.print))
        case (k, v) => k -> rowSorted(v)
      })
    case other => other
  }

  /** The tier ErmineSales holds, from the loader's stamp (tracker/db/LOADER.md §1). */
  private def tierOf(url: String, user: String, pw: String): String = {
    val props = new java.util.Properties
    props.setProperty("user", user); props.setProperty("password", pw)
    val c = java.sql.DriverManager.getConnection(url, props)
    try {
      val rs = c.createStatement().executeQuery(
        "SELECT CAST(value AS nvarchar(4000)) FROM sys.extended_properties WHERE class = 0 AND name = 'ermine.load.sales'")
      val stamp = if (rs.next()) rs.getString(1) else ""
      "\"tier\"\\s*:\\s*\"([^\"]+)\"".r.findFirstMatchIn(stamp).map(_.group(1)).getOrElse("<no stamp>")
    } finally c.close()
  }

  creds match {
    case None =>
      println("[preview-db] DB suites: not requested (no ERMINE_DB_* in the environment); the `db` gate runs them")
    case Some((url, user, password)) =>
      def scrub(s: String): String =
        if (s == null) "" else s.replace(password, "<password>").replace(url, "<url>")
      def say(s: String): Unit = println("[preview-db] " + scrub(s))
      property("live: connect ErmineSales, render DbFetchTopN == FetchTopN (row order aside), disconnect -> 503, wrong password -> auth kept:false") =
        secure { previewLock.synchronized { ErmineFixture.literalLock.synchronized {
          Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver")
          val tier = tierOf(url, user, password)
          say("ErmineSales holds tier " + tier)
          val b = new Bench(warm = false)
          def result(a: Option[Json]) = a flatMap (_ / "result")
          def f(a: Option[Json], k: String) = result(a) flatMap (_ / k)
          def show(a: Option[Json]) = scrub(a.map(Json.print).getOrElse("(no answer)")).take(700)
          val profile = Json.obj("id" -> Json.Str("sales-mssql"), "dialect" -> Json.Str("mssql"),
                                 "url" -> Json.Str(url), "user" -> Json.Str(user))
          try {
            val params = "{\"keep\":2}"
            // 1. the in-memory original, through the same preview (boots once)
            val t0 = System.nanoTime
            b.renderWith(1, docDir.resolve("FetchTopN.e"), "report", params, 1, List(docDir))
            val mem = b.answer(1, 300000L)
            say(f"in-memory FetchTopN: ok=${f(mem, "ok").flatMap(_.bool)} in ${(System.nanoTime - t0) / 1e6}%.0f ms")
            // 2. connect with the password in the request, as the extension sends it
            val t1 = System.nanoTime
            b.request(2, "ermine/preview/connect", Json.obj("profile" -> profile, "password" -> Json.Str(password)))
            val con = b.answer(2, 120000L)
            val connectMs = (System.nanoTime - t1) / 1e6
            say(f"connect answered in $connectMs%.0f ms (request to answer, over the wire): " + show(con))
            // 3. the twin on the held connection (the profile change re-boots the session)
            val t2 = System.nanoTime
            b.renderWith(3, docDir.resolve("DbFetchTopN.e"), "report", params, 2, List(docDir))
            val db = b.answer(3, 300000L)
            say(f"DbFetchTopN on ErmineSales: ok=${f(db, "ok").flatMap(_.bool)} in ${(System.nanoTime - t2) / 1e6}%.0f ms (includes the re-boot)")
            val t3 = System.nanoTime
            b.renderWith(4, docDir.resolve("DbFetchTopN.e"), "report", params, 3, List(docDir))
            val db2 = b.answer(4, 300000L)
            say(f"DbFetchTopN again (session warm): ok=${f(db2, "ok").flatMap(_.bool)} in ${(System.nanoTime - t3) / 1e6}%.0f ms")
            val d0 = f(mem, "document"); val d1 = f(db, "document"); val d2 = f(db2, "document")
            val bytesEqual = d0.isDefined && d0 == d1
            val sortedEqual = d0.isDefined && d0.map(rowSorted) == d1.map(rowSorted) && d1.map(rowSorted) == d2.map(rowSorted)
            say("document vs the in-memory twin: bytes " + (if (bytesEqual) "EQUAL" else "differ") +
                ", modulo row order " + (if (sortedEqual) "EQUAL" else "differ"))
            // 4. disconnect, then a render: the 503
            b.request(5, "ermine/preview/disconnect", Json.obj())
            val dis = b.answer(5, 60000L)
            b.renderWith(6, docDir.resolve("DbFetchTopN.e"), "report", params, 4, List(docDir))
            val r503 = b.answer(6, 60000L)
            say("disconnect: " + show(dis) + "; render after it: " + show(r503))
            // 5. a wrong password: auth, connect-auth, kept false; still disconnected
            val t5 = System.nanoTime
            b.request(7, "ermine/preview/connect", Json.obj("profile" -> profile,
                                                            "password" -> Json.Str(password + "-wrong")))
            val bad = b.answer(7, 120000L)
            say(f"wrong password answered in ${(System.nanoTime - t5) / 1e6}%.0f ms: " + show(bad))
            b.renderWith(8, docDir.resolve("DbFetchTopN.e"), "report", params, 5, List(docDir))
            val still = b.answer(8, 60000L)
            val log = b.sink.result()
            val leaked = log.exists(_.contains(password)) ||
                         b.remaining().exists(j => Json.print(j).contains(password))
            val urlInLog = log.exists(_.contains(url))
            log.filter(l => l.startsWith("preview: connect") || l.startsWith("preview: disconnect") ||
                            l.startsWith("preview: render session booted"))
               .foreach(l => say("log: " + l))
            ((tier ?= "xs") :| ("ErmineSales holds tier " + tier + "; this suite pins xs (scripts/db.sh load sales --tier xs)")) &&
            ((f(mem, "ok").flatMap(_.bool) ?= Some(true)) :| ("in-memory FetchTopN " + show(mem))) &&
            ((f(con, "ok").flatMap(_.bool) ?= Some(true)) :| ("connect " + show(con))) &&
            (f(con, "dialect").flatMap(_.str) ?= Some("mssql")) &&
            (f(con, "database").flatMap(_.str) ?= Some("ErmineSales")) &&
            (f(con, "host").flatMap(_.str) ?= Some("127.0.0.1")) &&
            ((f(db, "ok").flatMap(_.bool) ?= Some(true)) :| ("DbFetchTopN " + show(db))) &&
            ((f(db2, "ok").flatMap(_.bool) ?= Some(true)) :| ("DbFetchTopN again " + show(db2))) &&
            (sortedEqual :| ("documents differ\n in-memory " + d0.map(Json.print).getOrElse("-").take(500) +
                             "\n mssql     " + d1.map(Json.print).getOrElse("-").take(500))) &&
            (f(dis, "ok").flatMap(_.bool) ?= Some(true)) &&
            (f(r503, "status").flatMap(_.int) ?= Some(503)) &&
            (f(r503, "reason").flatMap(_.str) ?= Some("not-connected")) &&
            (f(bad, "ok").flatMap(_.bool) ?= Some(false)) &&
            (f(bad, "class").flatMap(_.str) ?= Some("auth")) &&
            (f(bad, "reason").flatMap(_.str) ?= Some("connect-auth")) &&
            (f(bad, "kept").flatMap(_.bool) ?= Some(false)) &&
            ((f(still, "reason").flatMap(_.str) ?= Some("not-connected")) :| "a failed connect reconnected") &&
            (!leaked :| "the password reached the log or the wire") &&
            (!urlInLog :| "the url reached the preview's log")
          } finally { b.stop(); () }
        } } }
  }
}
