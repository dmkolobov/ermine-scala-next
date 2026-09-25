package com.clarifi.reporting

import argonaut.{ Json, Parse }
import com.clarifi.reporting.backends.{ DB, Runners, Scanners }
import com.clarifi.reporting.ermine.json._
import com.clarifi.reporting.relational.SMEnv
import java.io.File
import org.scalacheck.{ Prop, Properties }
import org.scalacheck.Prop._

/** DB-PLAN stage 1, reports role (tracker/db/REPORTS.md): the DB-backed twins
  * of the previewable Doc fixtures, run through the document runner against a
  * real database, and compared with the in-memory originals.
  *
  * The twins are `doc/DbFetch{Crosstab,Fragments,Headline,Running,Tabs,TopN}.e`
  * (over `doc/DbFetchData.e`, two `table` statements) and
  * `modules/Doc/DbSalesReport.e` (one `table`).  Each is rendered with the
  * requests of TestRunner's (fx*) and (b3z) properties on
  *
  *  - SQL Server: `RunnerConfig(run = DB.RunUser(mssql driver)(url, user,
  *    password), scanner = Scanners.MicrosoftSQLServer)` -- one connection per
  *    request, as the in-memory runner opens one; needs ERMINE_DB_URL,
  *    ERMINE_DB_USER and ERMINE_DB_PASSWORD (tracker/tools/db-reports.sh
  *    reads the password from ~/.config/ermine/db.env).  Without them NO
  *    property of this set is registered; one `[db-reports] DB suites: not
  *    requested` line says so (the `db` gate in scripts/gates.sh runs them).
  *  - the SQLite twin (D13): `jdbc:sqlite:<file>` with the SQLite scanner,
  *    the file from ERMINE_DB_SQLITE or `data/out/sales/xs/sales.sqlite`;
  *    not registered (one "not requested" line) when the file does not exist.
  *
  * and the original (`FetchTopN`, ..., `Doc.SalesReport`) on in-memory
  * SQLite, the runner's default.  The database must hold tier xs.
  *
  * Two properties per backend and report:
  *
  *  - "same document": the twin's document equals the original's after
  *    masking deferred tokens and expiry times AND sorting the inline rows
  *    of every relation object (a relation is a set: the scanner delivers
  *    an unordered scan in the database's order, TestRunner (fx4)'s note).
  *    Whether the bytes were equal WITHOUT the row sort is printed as a
  *    `[db-reports]` line, so a dialect's row order is recorded, not hidden.
  *  - "totals": the numbers pinned in FetchData.e's comment and in the
  *    fixtures' headers, read from the TWIN's document: north 4350.75,
  *    south 2605.75, east 4175.5, west 1550.0, all 12682.0, 8 rows, 34
  *    units, Other = 4155.75 at keep 2, 2 targets met, the running total
  *    closing at 12682.0, srSales 529.5 over 3 rows.
  */
object TestDbReports extends Properties("DB-backed report twins (DB-PLAN S1)") {

  private val exampleRoot = "core/src/test/resources/doc"
  private val MsSqlDriver = "com.microsoft.sqlserver.jdbc.SQLServerDriver"

  private def params(p: String): String = "{\"" + Request.Params + "\":" + p + "}"
  private def deferred(p: String): String =
    "{\"" + Request.Params + "\":" + p + ",\"" + Request.Data + "\":{\"default\":\"deferred\"}}"

  /** (twin, original, request bodies): the requests TestRunner's fx*
    * properties and (b3z) send to the originals. */
  val cases: List[(String, String, List[String])] = List(
    ("DbFetchTopN",       "FetchTopN",       List(params("{\"keep\":2}"), params("{\"keep\":0}"))),
    ("DbFetchHeadline",   "FetchHeadline",   List(params("{\"onlyRegion\":\"north\"}"),
                                                  params("{\"onlyRegion\":\"nowhere\"}"), params("{}"))),
    ("DbFetchCrosstab",   "FetchCrosstab",   List(params("{\"measureUnits\":false}"),
                                                  params("{\"measureUnits\":true}"))),
    ("DbFetchRunning",    "FetchRunning",    List(params("{\"newestFirst\":false}"),
                                                  params("{\"newestFirst\":true}"))),
    ("DbFetchTabs",       "FetchTabs",       List(params("{\"showUnits\":true}"),
                                                  deferred("{\"showUnits\":false}"))),
    ("DbFetchFragments",  "FetchFragments",  List(params("{\"tabsFor\":[\"north\",\"south\"],\"topN\":2}"))),
    ("Doc.DbSalesReport", "Doc.SalesReport", List("{}")))

  // ---------------------------------------------------------------------
  // the runners

  private def runnerOn(run: com.clarifi.reporting.Run[DB],
                       scanner: com.clarifi.reporting.relational.Scanner[DB]): Runner =
    new Runner(RunnerConfig(roots = List(exampleRoot), run = run, scanner = scanner,
                            ttlMillis = 600000L, maxTokens = 4096))

  /** The originals, on the runner's default: in-memory SQLite per request. */
  lazy val memory: Runner =
    runnerOn(Runners.SQLite("jdbc:sqlite::memory:"), Scanners.SQLite(SMEnv.dummySmenv))

  /** Renders are serialised: one runner per backend, one request at a time. */
  private val lock = new Object

  def render(r: Runner, module: String, body: String): (Int, String) = lock.synchronized {
    val out = new java.lang.StringBuilder
    r.renderText(module, body, out) match {
      case Left(e)  => (e.status, e.body)
      case Right(_) => (200, out.toString)
    }
  }

  // ---------------------------------------------------------------------
  // comparing documents

  private val tokenRe = ("\"" + Wire.Token + "\":\"[A-Za-z0-9_-]{22}\"").r
  private val expiresRe = ("\"" + Wire.Expires + "\":\"[^\"]*\"").r

  /** TestRunner.masked, restated so this object does not initialise
    * TestRunner (which writes and deletes generated modules). */
  def masked(text: String): String =
    expiresRe.replaceAllIn(tokenRe.replaceAllIn(text, "\"" + Wire.Token + "\":\"T\""),
                           "\"" + Wire.Expires + "\":\"E\"")

  /** The document with the inline rows of every relation object sorted. */
  def rowSorted(j: Json): Json =
    if (j.isArray) Json.jArray(j.arrayOrEmpty.map(rowSorted))
    else if (j.isObject) {
      val isRel = j.field(Wire.Kind).flatMap(_.string).isDefined
      Json.jObjectFields(j.objectFieldsOrEmpty.map { k =>
        val v = j.field(k).get
        if (isRel && k == Wire.Rows && v.isArray) k -> Json.jArray(v.arrayOrEmpty.sortBy(_.nospaces))
        else k -> rowSorted(v)
      }: _*)
    } else j

  def parsed(text: String): Option[Json] = Parse.parse(text).toOption

  /** Every `{"kind":..}` object in a document, in document order. */
  def relationObjects(j: Json): List[Json] =
    if (j.isObject && j.field(Wire.Kind).flatMap(_.string).isDefined) List(j)
    else if (j.isArray) j.arrayOrEmpty.flatMap(relationObjects)
    else if (j.isObject) j.objectFieldsOrEmpty.flatMap(k => relationObjects(j.field(k).get))
    else Nil

  def rowMaps(rel: Json): List[Map[String, Json]] = {
    val cols = rel.field(Wire.Columns).map(_.arrayOrEmpty.flatMap(_.field(Wire.Name)).flatMap(_.string)).getOrElse(Nil)
    rel.field(Wire.Rows).map(_.arrayOrEmpty).getOrElse(Nil).map(r => cols.zip(r.arrayOrEmpty).toMap)
  }
  private def num(j: Option[Json]): Option[Double] = j.flatMap(_.number).flatMap(_.toDouble)
  private def str(j: Option[Json]): Option[String] = j.flatMap(_.string)
  private def near(a: Option[Double], b: Double): Boolean = a.exists(x => math.abs(x - b) < 1e-9)

  // ---------------------------------------------------------------------
  // the two property shapes

  private def sameDocument(backend: String, db: Runner, scrub: String => String)
                          (twin: String, original: String, bodies: List[String]): Prop =
    bodies.zipWithIndex.map { case (body, i) =>
      val (st0, t0) = render(memory, original, body)
      val (st1, t1raw) = render(db, twin, body)
      val t1 = scrub(t1raw)
      val bytes = st0 == 200 && st1 == 200 && masked(t0) == masked(t1)
      val sorted = st0 == 200 && st1 == 200 &&
        parsed(masked(t0)).map(rowSorted) == parsed(masked(t1)).map(rowSorted)
      println("[db-reports] " + backend + " " + twin + " request " + (i + 1) + ": status " + st1 +
              ", bytes " + (if (bytes) "EQUAL" else "differ") +
              ", modulo row order " + (if (sorted) "EQUAL" else "differ") +
              (if (st1 != 200) "; " + t1.take(600) else ""))
      if (!sorted && st1 == 200 && st0 == 200) {
        println("[db-reports]   original " + masked(t0).take(700))
        println("[db-reports]   twin     " + masked(t1).take(700))
      }
      ((st0 ?= 200) :| (original + " on in-memory SQLite: " + t0.take(300))) &&
        ((st1 ?= 200) :| (twin + " on " + backend + ": " + t1.take(600))) &&
        (sorted :| (twin + " request " + (i + 1) + ": documents differ\n original " +
                    masked(t0).take(400) + "\n twin     " + masked(t1).take(400)))
    }.reduce(_ && _)

  private def totals(backend: String, db: Runner, scrub: String => String): Prop = {
    def doc(m: String, b: String): Option[Json] = {
      val (st, t) = render(db, m, b)
      if (st == 200) parsed(t) else { println("[db-reports] " + backend + " " + m + ": " + scrub(t).take(400)); None }
    }
    def root(m: String, b: String) = doc(m, b).flatMap(_.field(Wire.Root))
    // the crosstab: the four region totals, the whole, and the units
    val xt   = root("DbFetchCrosstab", params("{\"measureUnits\":false}"))
                 .flatMap(_.field("children")).flatMap(_.arrayOrEmpty.headOption).flatMap(_.field("props"))
    val xtU  = root("DbFetchCrosstab", params("{\"measureUnits\":true}"))
                 .flatMap(_.field("children")).flatMap(_.arrayOrEmpty.headOption).flatMap(_.field("props"))
    val rowLabels = xt.flatMap(_.field("crosstabRowLabels")).map(_.arrayOrEmpty.flatMap(_.string)).getOrElse(Nil)
    val rowTotals = xt.flatMap(_.field("rowTotals")).map(_.arrayOrEmpty.flatMap(_.number).flatMap(_.toDouble)).getOrElse(Nil)
    val byRegion = rowLabels.zip(rowTotals).toMap
    // the headline over every region
    val head = root("DbFetchHeadline", params("{}"))
                 .flatMap(_.field("children")).flatMap(_.arrayOrEmpty.headOption).flatMap(_.field("props"))
    // top 2 + Other, and the targets met
    val topKids = root("DbFetchTopN", params("{\"keep\":2}")).flatMap(_.field("children")).map(_.arrayOrEmpty).getOrElse(Nil)
    val slices = topKids.headOption.map(k => relationObjects(k).flatMap(rowMaps)).getOrElse(Nil)
    val other = slices.find(r => str(r.get("region")) == Some("Other")).flatMap(r => num(r.get("amount")))
    val met = num(topKids.lift(1).flatMap(_.field("props")))
    // the running total, day order
    val running = root("DbFetchRunning", params("{\"newestFirst\":false}"))
                    .map(r => relationObjects(r).flatMap(rowMaps)).getOrElse(Nil)
    val lastRun = running.find(r => num(r.get("seqNo")) == Some(8.0)).flatMap(r => num(r.get("runningAmount")))
    // the SalesReport scorecard's relation: three rows summing to 529.5
    val sr = root("Doc.DbSalesReport", "{}").map(relationObjects).getOrElse(Nil).headOption.map(rowMaps).getOrElse(Nil)
    val srTotal = sr.flatMap(r => num(r.get("srSales"))).sum
    println("[db-reports] " + backend + " totals: regions " + byRegion + ", all " + num(xt.flatMap(_.field("grandTotal"))) +
            ", units " + num(xtU.flatMap(_.field("grandTotal"))) + ", headline rows " + num(head.flatMap(_.field("rowCount"))) +
            " total " + num(head.flatMap(_.field("total"))) + ", Other " + other + ", met " + met +
            ", running ends " + lastRun + ", srSales " + srTotal + " over " + sr.length + " rows")
    (near(byRegion.get("north"), 4350.75) :| ("north " + byRegion)) &&
      (near(byRegion.get("south"), 2605.75) :| ("south " + byRegion)) &&
      (near(byRegion.get("east"), 4175.5) :| ("east " + byRegion)) &&
      (near(byRegion.get("west"), 1550.0) :| ("west " + byRegion)) &&
      (near(num(xt.flatMap(_.field("grandTotal"))), 12682.0) :| ("all " + xt.map(_.nospaces))) &&
      (near(num(xtU.flatMap(_.field("grandTotal"))), 34.0) :| ("units " + xtU.map(_.nospaces))) &&
      (near(num(head.flatMap(_.field("rowCount"))), 8.0) :| ("headline " + head.map(_.nospaces))) &&
      (near(num(head.flatMap(_.field("total"))), 12682.0) :| ("headline " + head.map(_.nospaces))) &&
      (near(other, 4155.75) :| ("Other " + slices)) &&
      (near(met, 2.0) :| ("met " + met)) &&
      (near(lastRun, 12682.0) :| ("running " + running)) &&
      ((sr.length ?= 3) :| ("SalesReport rows " + sr)) &&
      (near(Some(srTotal), 529.5) :| ("srSales " + sr))
  }

  private def register(backend: String, db: => Runner, scrub: String => String): Unit = {
    lazy val r = db
    cases.foreach { case (twin, original, bodies) =>
      property(backend + ": " + twin + " renders the same document as " + original + " (tier xs)") =
        secure { sameDocument(backend, r, scrub)(twin, original, bodies) }
    }
    property(backend + ": the pinned totals (FetchData.e's comment, the fixtures' headers)") =
      secure { totals(backend, r, scrub) }
  }

  // ---------------------------------------------------------------------
  // SQL Server: env-gated, like TestMsSqlSmoke

  private val env = sys.env
  private val creds = for {
    u  <- env.get("ERMINE_DB_URL").filter(_.nonEmpty)
    us <- env.get("ERMINE_DB_USER").filter(_.nonEmpty)
    pw <- env.get("ERMINE_DB_PASSWORD").filter(_.nonEmpty)
  } yield (TestMsSqlSmoke.withLocalTls(u), us, pw)

  creds match {
    case None =>
      // Registers NOTHING (the `suites` gate fails on a property named as
      // skipped, scripts/gates.sh); one info line says why, and the `db` gate
      // fails if it ever sees this line.
      println("[db-reports] DB suites: not requested (no ERMINE_DB_* in the environment); the `db` gate runs them")
    case Some((url, user, password)) =>
      def scrub(s: String): String =
        if (s == null) "" else s.replace(password, "<password>").replace(url, "<url>")
      register("mssql", runnerOn(DB.RunUser(MsSqlDriver)(url, user, password),
                                 Scanners.MicrosoftSQLServer(SMEnv.dummySmenv)), scrub)
  }

  // ---------------------------------------------------------------------
  // the SQLite twin (D13): gated on the loader's file

  private val sqliteFile: File =
    new File(env.get("ERMINE_DB_SQLITE").filter(_.nonEmpty).getOrElse("data/out/sales/xs/sales.sqlite"))

  if (!sqliteFile.isFile)
    println("[db-reports] DB suites: sqlite twin not requested (no file at " + sqliteFile.getPath +
            "; set ERMINE_DB_SQLITE); the `db` gate runs it")
  else
    register("sqlite-twin", runnerOn(Runners.SQLite("jdbc:sqlite:" + sqliteFile.getAbsolutePath),
                                     Scanners.SQLite(SMEnv.dummySmenv)), identity)
}
