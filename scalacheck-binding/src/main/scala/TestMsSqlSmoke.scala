package com.clarifi.reporting

import java.sql.{ Connection, DriverManager }
import java.util.Properties

import com.clarifi.reporting.backends.{ Backends, Runners }
import com.clarifi.reporting.ermine.json.RunnerConfig
import com.clarifi.reporting.sql.SqlEmitter

import org.scalacheck.{ Prop, Properties => PropSet }
import Prop._

/** WP-12(a): the vendored SQL Server driver (`build.sbt`, `mssql-jdbc`
  * `13.6.0.jre11`) and the first real connection from Scala.
  * tracker/db/SERVER.md §3 carries the recorded live run.
  *
  * Two properties.
  *
  *  - "driver resolves" needs no server and always runs: the class
  *    `Runners.MicrosoftSQLServer` loads is on the classpath, it accepts a
  *    `jdbc:sqlserver:` URL, and both dialect paths (`Backends.scannerFor`,
  *    the preview's; `RunnerConfig.backend`, `bin/ermine-serve`'s) answer
  *    `Right` for `mssql`.
  *
  *  - "live connect" needs ERMINE_DB_URL, ERMINE_DB_USER and
  *    ERMINE_DB_PASSWORD in the environment.  When any is unset it is NOT
  *    registered and one `[mssql-smoke] DB suites: not requested` line is
  *    printed instead (the `db` gate in scripts/gates.sh runs it).  When
  *    all three are set it opens ONE connection (`encrypt=true;
  *    trustServerCertificate=true` appended unless the URL already names
  *    them, decision D4), runs `SELECT 1` and `SELECT @@VERSION`, checks the
  *    dialect a profile would name for this URL, reads a `date` column
  *    through `MsSqlEmitter.sqlPrimT` (the "jtds gives varchar" comment at
  *    `SqlEmitter.scala:882`), and creates and drops a `##` temp table in
  *    `tempdb` (decision D3's grant).  The password is never printed: every
  *    message this file produces is scrubbed of it, the user and the URL.
  *
  * `tracker/tools/db-smoke.sh` runs exactly this object with the password
  * sourced from `~/.config/ermine/db.env`. */
object TestMsSqlSmoke extends PropSet("SQL Server driver smoke (WP-12a)") {

  val DriverClass = "com.microsoft.sqlserver.jdbc.SQLServerDriver"

  /** The dialect a preview profile would name for a JDBC URL.  Nothing in
    * the tree infers a dialect from a URL (the profile states it, §7.1 of
    * the playground tracker); this is the test's statement of the one
    * mapping SERVER.md §1 records as the expected profile. */
  def dialectForUrl(url: String): Option[String] = {
    val u = url.toLowerCase(java.util.Locale.ROOT)
    if (u.startsWith("jdbc:sqlserver:")) Some("mssql")
    else if (u.startsWith("jdbc:jtds:sqlserver:")) Some("mssql")
    else if (u.startsWith("jdbc:sqlite:")) Some("sqlite")
    else if (u.startsWith("jdbc:mysql:")) Some("mysql")
    else if (u.startsWith("jdbc:postgresql:")) Some("postgres")
    else if (u.startsWith("jdbc:vertica:")) Some("vertica")
    else None
  }

  /** `encrypt=true;trustServerCertificate=true` unless already present. */
  def withLocalTls(url: String): String = {
    val lower = url.toLowerCase(java.util.Locale.ROOT)
    val sep = if (url.endsWith(";")) "" else ";"
    val add = List("encrypt=true", "trustServerCertificate=true")
      .filterNot(kv => lower.contains(kv.takeWhile(_ != '=').toLowerCase(java.util.Locale.ROOT) + "="))
    if (add.isEmpty) url else url + sep + add.mkString(";")
  }

  property("driver resolves: mssql-jdbc on the classpath, both dialect paths answer mssql") = {
    val loaded = Class.forName(DriverClass)
    val accepts = DriverManager.getDriver("jdbc:sqlserver://127.0.0.1:1433")
    val scanner = Backends.scannerFor("mssql", "default")
    val noTx    = Backends.scannerFor("sqlserver", "noTransactions")
    // `RunnerConfig.backend` loads the driver class eagerly (`DB.Run`) and
    // opens nothing, so this is Right exactly when the jar is present.
    val serve   = RunnerConfig.backend("mssql", "jdbc:sqlserver://127.0.0.1:1433")
    (accepts.getClass == loaded) :| ("DriverManager picked " + accepts.getClass.getName) &&
    scanner.isRight :| ("scannerFor(mssql, default) = " + scanner) &&
    noTx.isRight :| ("scannerFor(sqlserver, noTransactions) = " + noTx) &&
    serve.isRight :| ("RunnerConfig.backend(mssql, <url>) = " + serve.left.toOption)
  }

  private val env = sys.env
  private val creds = for {
    u  <- env.get("ERMINE_DB_URL").filter(_.nonEmpty)
    us <- env.get("ERMINE_DB_USER").filter(_.nonEmpty)
    pw <- env.get("ERMINE_DB_PASSWORD").filter(_.nonEmpty)
  } yield (u, us, pw)

  creds match {
    case None =>
      // Registers NOTHING: the `suites` gate fails on any property named as
      // skipped (scripts/gates.sh), so the live property exists only when
      // requested.  One info line says why; the `db` gate fails on it.
      println("[mssql-smoke] DB suites: not requested (no ERMINE_DB_* in the environment); the `db` gate runs them")
    case Some((url0, user, password)) =>
      // ONE connection per run: the smoke is computed lazily on the first
      // evaluation (not at object initialisation) and every later sample
      // ScalaCheck asks for reuses that one answer.
      lazy val live = liveSmoke(withLocalTls(url0), user, password)
      property("live connect: SELECT 1, @@VERSION, dialect, date column, ## temp table") =
        Prop(prms => live(prms))
  }

  /** Replace every secret-bearing string with a placeholder. */
  private def scrub(s: String, url: String, user: String, password: String): String =
    if (s == null) ""
    else s.replace(password, "<password>").replace(url, "<url>").replace(user, "<user>")

  private def liveSmoke(url: String, user: String, password: String): Prop = {
    def say(s: String): Unit = println("[mssql-smoke] " + scrub(s, url, user, password))
    Class.forName(DriverClass)
    val props = new Properties
    props.setProperty("user", user)
    props.setProperty("password", password)
    val t0 = System.nanoTime
    var conn: Connection = null
    try {
      conn = DriverManager.getConnection(url, props)
      say(f"connected in ${(System.nanoTime - t0) / 1e6}%.0f ms via " +
          DriverManager.getDriver(url).getClass.getName + " " +
          conn.getMetaData.getDriverVersion)
      val st = conn.createStatement()
      def one(sql: String): String = {
        val rs = st.executeQuery(sql)
        try { rs.next(); rs.getString(1) } finally rs.close()
      }
      val sel1 = one("SELECT 1")
      say("SELECT 1 -> " + sel1)
      val version = one("SELECT @@VERSION")
      say("SELECT @@VERSION -> " + version.linesIterator.next().trim)
      val db = one("SELECT DB_NAME()")
      say("DB_NAME() -> " + db)
      // CONNECTIONPROPERTY reads the caller's own session; the DMV
      // `sys.dm_exec_connections` needs VIEW SERVER PERFORMANCE STATE, which
      // the `ermine` login rightly lacks (first live run, SERVER.md §3).
      val enc =
        try one("SELECT CAST(CONNECTIONPROPERTY('encrypt_option') AS nvarchar(10))")
        catch { case e: java.sql.SQLException => "unavailable (" + e.getErrorCode + ")" }
      say("encrypt_option -> " + enc)

      val dialect = dialectForUrl(url)
      val scanner = dialect.map(d => Backends.scannerFor(d, "default"))
      say("dialect for this URL -> " + dialect + "; scannerFor -> " +
          scanner.map(_.fold(identity, _.getClass.getSimpleName)))

      val tmp = "##wp12_smoke_" + java.util.UUID.randomUUID.toString.replace("-", "")
      st.executeUpdate("CREATE TABLE " + tmp + " (d date, n int)")
      st.executeUpdate("INSERT INTO " + tmp + " VALUES ('2026-09-24', 1)")
      val rs = st.executeQuery("SELECT d, n FROM " + tmp)
      val (dType, dName, mapped, dVal) =
        try {
          val md = rs.getMetaData
          rs.next()
          (md.getColumnType(1), md.getColumnTypeName(1),
           SqlEmitter.msSqlEmitter.sqlPrimT(md.getColumnType(1), md.getColumnTypeName(1),
                                            md.getColumnDisplaySize(1)),
           rs.getDate(1))
        } finally rs.close()
      say("## temp table " + tmp.take(14) + "...: created; date column reads as java.sql.Types " +
          dType + " \"" + dName + "\" -> sqlPrimT " + mapped + "; value " + dVal)
      st.executeUpdate("DROP TABLE " + tmp)
      val gone = one("SELECT CASE WHEN OBJECT_ID('tempdb.." + tmp + "') IS NULL THEN 'dropped' ELSE 'still there' END")
      say("## temp table " + gone)
      st.close()

      (sel1 == "1") :| "SELECT 1" &&
      version.contains("Microsoft SQL Server") :| "@@VERSION names SQL Server" &&
      (dialect == Some("mssql")) :| ("dialect " + dialect) &&
      scanner.exists(_.isRight) :| "scannerFor(mssql) is Right" &&
      (mapped == Some(com.clarifi.reporting.PrimT.DateT())) :| ("sqlPrimT(date) = " + mapped) &&
      (gone == "dropped") :| "## temp table dropped"
    } catch {
      case e: java.sql.SQLException =>
        val m = e.getClass.getSimpleName + " state=" + e.getSQLState + " code=" + e.getErrorCode +
                ": " + scrub(e.getMessage, url, user, password)
        say("FAILED " + m)
        Prop.falsified :| m
    } finally {
      if (conn != null) conn.close()
    }
  }
}
