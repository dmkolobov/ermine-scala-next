package com.clarifi.reporting

import argonaut.{ Json, Parse }
import com.clarifi.machines.Process
import com.clarifi.reporting.backends.{ DB, Runners, Scanners }
import com.clarifi.reporting.ermine.json._
import com.clarifi.reporting.relational.{ Ext, ExtRel, Scanner, SMEnv, SmallLit }
import scalaz.Monoid
import java.io.File
import org.scalacheck.{ Gen, Prop, Properties }
import org.scalacheck.Prop._
import scala.collection.immutable.List
import scala.collection.mutable.ListBuffer
import scala.util.control.NonFatal

/** Stage J3c: the document runner (`json/Runner.scala`) and its HTTP face
  * (`json/Server.scala`).
  *
  * Everything here runs against REPORT MODULES GENERATED AS ERMINE SOURCE
  * and written into `core/target/json-runner-modules`, which the runner is
  * pointed at with `--root`: a random parameter type from
  * `TestSchema.shape`, a random value of it, and one to three literal
  * relations in a random delivery form.  The request body is random too
  * (`data.default`, `data.threshold`).
  *
  *  - (a) end to end, in process: the document parses, its envelope is the
  *    wire's, the parameters come back in the widget's props exactly as they
  *    were sent, every relation object follows the delivery rules and
  *    carries the literal rows, and every deferred token resolves through
  *    `Runner.data` to the inline object.
  *  - (b) the error paths: a mutated parameter is 400 at a path under
  *    `$.params`, an unknown module or binding 404, a report that is not
  *    `Params -> Node` 400 naming the reason, a report that throws 500, an
  *    expired token 404 (the plan cache's clock is driven by hand).
  *  - (c) over HTTP: the same random requests through
  *    `java.net.HttpURLConnection` give byte-identical bodies to the
  *    in-process render, once tokens and expiry times are masked.
  *  - (d) concurrency: the same requests fired at once answer what they
  *    answer one at a time.
  *  - (e) one connection per request, however many relations.
  *  - (ex) the example report, `core/src/test/resources/doc/Sales.e`, and
  *    the curl walkthrough in the plan.
  *  - (sql) the two DB-layer tickets J3b handed on: a NULL in a GUID column,
  *    and a scan that throws being torn down.
  */
object TestRunner extends Properties("JSON document runner (J3c)") {

  // =====================================================================
  // the modules the properties generate, and the runner they are served by

  /** Under `target/`, not the system temp directory: `sbt clean` owns it and
    * a crashed run leaves nothing behind in /tmp. */
  private val moduleRoot: File = {
    val d = new File("core/target/json-runner-modules")
    d.mkdirs()
    Option(d.listFiles).foreach(_.foreach(f => if (f.getName.endsWith(".e")) f.delete()))
    d
  }

  private val exampleRoot = "core/src/test/resources/doc"

  private def writeModule(name: String, source: String): Unit = {
    val out = new java.io.OutputStreamWriter(
      new java.io.FileOutputStream(new File(moduleRoot, name + ".e")), "UTF-8")
    try out.write(source) finally out.close()
  }

  /** The field witnesses every generated relation draws its columns from,
    * declared once so a module does not pay for them. */
  writeModule("RgFields",
    "module RgFields where\n\nfield rgKey : Int\nfield rgName : String\n" +
    "field rgAmount : Double\nfield rgFlag : Bool\n")

  /** A `Run[DB]` over fresh in-memory SQLite connections that counts them
    * (property (e)); `ThreadLocalRunDB`, so one `run` is one connection and
    * a nested `run` reuses it. */
  final class CountingRun extends com.clarifi.reporting.backends.ThreadLocalRunDB {
    val opened = new java.util.concurrent.atomic.AtomicInteger(0)
    /** ...and the count of the CALLING thread alone.  ScalaCheck runs the
      * properties of one suite concurrently over one runner, so a shared
      * total is everybody's; a connection is opened on the thread that calls
      * `run`, so a per-thread count is the one request's. */
    private val mine = new ThreadLocal[Array[Int]] {
      override def initialValue: Array[Int] = Array(0)
    }
    def openedHere: Int = mine.get()(0)
    protected def freshResource[A](a: java.sql.Connection => A): A = {
      Class.forName("org.sqlite.JDBC")
      val conn = java.sql.DriverManager.getConnection("jdbc:sqlite::memory:")
      opened.incrementAndGet()
      mine.get()(0) += 1
      try a(conn) finally conn.close()
    }
  }

  private val counting = new CountingRun

  /** The `settings` object every document carries.  The `note` is NOT
    * decoration: every other string the suite generates is alphanumeric, so
    * without it no response body in any property would contain a multi-byte
    * character and `http()`'s Content-Length assertion could not tell
    * `text.length` from `text.getBytes("UTF-8").length`.  Two bytes (e-acute),
    * three (an em dash), and four (an astral emoji, a surrogate PAIR -- a lone
    * surrogate is the case J3b's open issue says argonaut's printer would not
    * escape). */
  val settingsNote = "caf\u00e9 \u2014 \u00fcn\u00efcode \ud83d\ude42"
  val settings: Json = Json.obj("locale" -> Json.jString("en-GB"), "tz" -> Json.jString("UTC"),
                                "note" -> Json.jString(settingsNote))

  /** ONE runner for the suite: booting a session is seconds, and the
    * properties are about what a booted server does. */
  lazy val runner: Runner = new Runner(RunnerConfig(
    roots     = List(moduleRoot.getPath, exampleRoot),
    run       = counting,
    scanner   = Scanners.SQLite(SMEnv.dummySmenv),
    settings  = settings,
    ttlMillis = 600000L,
    maxTokens = 4096))

  /** A second runner whose clock the expiry property drives by hand.  A
    * `MemoryPlanCache` requires a positive TTL, so a clock is the only way
    * to reach an expired token. */
  private val handClock = new java.util.concurrent.atomic.AtomicLong(1000000L)
  lazy val clockedRunner: Runner = new Runner(RunnerConfig(
    roots     = List(moduleRoot.getPath),
    run       = new CountingRun,
    scanner   = Scanners.SQLite(SMEnv.dummySmenv),
    ttlMillis = 60000L,
    clock     = () => handClock.get))

  private val counter = new java.util.concurrent.atomic.AtomicInteger(0)
  private def freshModule(prefix: String): String = prefix + counter.incrementAndGet()

  // =====================================================================
  // generating a report module

  /** One column of a generated relation: the field, its wire type, and a
    * generator of (Ermine literal, the JSON cell it must come back as). */
  final case class Col(field: String, wire: String, cell: Gen[(String, Json)])

  private val colPool: List[Col] = List(
    Col("rgName", "String", Gen.choose(0, 6).flatMap(n => Gen.listOfN(n, Gen.alphaNumChar)).map { cs =>
      val s = cs.mkString; ("\"" + s + "\"", Json.jString(s)) }),
    // eighths: exact in binary64 AND as a decimal literal, so nothing is
    // lost on the way through SQLite's literals (J3b measured that)
    Col("rgAmount", "Double", Gen.choose(0, 99999).map(n => ((n / 8.0).toString, Json.jNumber(n / 8.0)))),
    Col("rgFlag", "Bool", Gen.oneOf(("True", Json.jBool(true)), ("False", Json.jBool(false)))))

  /** A literal relation: `rgKey` is always there and always the row index,
    * so the rows are distinct (a SQL scan is a set) and the expected rows
    * are unambiguous. */
  final case class Rel(cols: List[Col], rows: List[List[(String, Json)]], form: String) {
    def columnNames: List[String] = ("rgKey" :: cols.map(_.field)).sorted
    def wireColumns: List[Json] = {
      val byName = (("rgKey", "Int") :: cols.map(c => (c.field, c.wire))).sortBy(_._1)
      byName.map { case (n, t) => Json.obj(Wire.Name -> Json.jString(n), Wire.Type -> Json.jString(t),
                                           Wire.Nullable -> Json.jBool(false)) }
    }
    /** The expected row arrays, in column order. */
    def wireRows: List[Json] = rows.zipWithIndex.map { case (r, i) =>
      val byName = (("rgKey", Json.jNumber(i.toLong)) :: cols.map(_.field).zip(r.map(_._2))).sortBy(_._1)
      Json.array(byName.map(_._2): _*)
    }
    def source: String = {
      val recs = rows.zipWithIndex.map { case (r, i) =>
        (("rgKey = " + i) :: cols.map(_.field).zip(r.map(_._1)).map { case (f, l) => f + " = " + l })
          .mkString("{ ", ", ", " }")
      }
      val r = "(mkRelation# (toList# [" + recs.mkString(", ") + "]))"
      form match {
        case "bare"        => r
        case "Inline"      => "(Inline " + r + ")"
        case "Deferred"    => "(Deferred " + r + ")"
        case other         => "(" + other + " " + r + ")"   // rel / relInline / relDeferred
      }
    }
    /** What `Write.resolve` will do with it. */
    def delivery(cfgDefault: Delivery, threshold: Option[Long]): Delivery = form match {
      case "Inline" | "relInline"     => Delivery.Inline
      case "Deferred" | "relDeferred" => Delivery.Deferred
      case _ =>
        if (cfgDefault == Delivery.Deferred) Delivery.Deferred
        else threshold match {
          case Some(t) if rows.length.toLong > t => Delivery.Deferred
          case _                                 => Delivery.Inline
        }
    }
  }

  private val relGen: Gen[Rel] = for {
    k    <- Gen.choose(1, colPool.length)
    cols <- TestSchema.pickN(k, colPool).map(_.sortBy(_.field))
    // at least one row: `mkRelation# []` carries no header, which is an
    // encode error the runner reports as a 500 -- pinned by (b7), not mixed
    // into every other case here
    n    <- Gen.choose(1, 5)
    rows <- Gen.listOfN(n, Gen.sequence[List[(String, Json)], (String, Json)](cols.map(_.cell)))
    form <- Gen.oneOf("bare", "Inline", "Deferred", "rel", "relInline", "relDeferred")
  } yield Rel(cols, rows, form)

  /** The imports a generated report needs: TestSchema's (its shapes reach
    * into Date, GUID, Prim, the native collections and Vector) plus the
    * document vocabulary and the relation primitives. */
  private val importLines: String =
    List("import Builtin", "import Json", "import List", "import Maybe", "import Function",
         "import Int", "import Num", "import Date", "import GUID", "import Prim",
         "import Native.List", "import Native.Maybe", "import Native.Pair",
         "import Vector as V", "import Layout.Doc", "import RgFields").mkString("\n")

  final case class Case(module: String, shape: TestSchema.Shape, value: String,
                        rels: List[Rel], default: Delivery, threshold: Option[Long]) {
    def source: String =
      "module " + module + " where\n\n" + importLines + "\n\n" +
      shape.decls.distinct.mkString("\n") + "\n\n" +
      "report : " + shape.ty + " -> Node\n" +
      "report p = vflow [ widget \"params\" p" +
      rels.zipWithIndex.map { case (r, i) => ", widget \"r" + i + "\" " + r.source }.mkString +
      " ]\n"

    def body(params: Json): String = {
      val data = List(
        Some("\"" + Request.Default + "\":\"" + (if (default == Delivery.Deferred) Wire.Deferred else Wire.Inline) + "\""),
        Some("\"" + Request.StrategyK + "\":\"" + Strategy.Buffered.name + "\""),
        threshold.map(t => "\"" + Request.Threshold + "\":" + t)).flatten.mkString(",")
      "{\"" + Request.Params + "\":" + params.nospacesWithOrder + ",\"" + Request.Data + "\":{" + data + "}}"
    }
  }

  private val caseGen: Gen[Case] = for {
    sh   <- TestSchema.shape(2)
    v    <- sh.value
    k    <- Gen.choose(1, 3)
    rels <- Gen.listOfN(k, relGen)
    dflt <- Gen.oneOf(Delivery.Inline: Delivery, Delivery.Deferred: Delivery)
    thr  <- Gen.frequency((2, Gen.const(None: Option[Long])), (1, Gen.choose(0L, 4L).map(t => Some(t))))
  } yield Case(freshModule("Rg"), sh, v, rels, dflt, thr)

  // =====================================================================
  // helpers

  private final case class Complaint(why: String) extends RuntimeException(why) with scala.util.control.NoStackTrace
  private def complain(why: String): Nothing = throw Complaint(why)

  /** Equality that reads two JSON numbers by VALUE.  The stdlib `Json`
    * parameter type is the one place a round trip moves a number's
    * SPELLING (`parseJson#` makes a whole `JNum` a `JInt`, J2a §open
    * issues), and nothing in this stage is about spelling. */
  def jsonEq(a: Json, b: Json): Boolean =
    if (a.isNumber && b.isNumber)
      (for { x <- a.number.flatMap(_.toDouble); y <- b.number.flatMap(_.toDouble) } yield x == y).getOrElse(false)
    else if (a.isArray && b.isArray) {
      val (xs, ys) = (a.arrayOrEmpty, b.arrayOrEmpty)
      xs.length == ys.length && xs.zip(ys).forall(p => jsonEq(p._1, p._2))
    } else if (a.isObject && b.isObject) {
      val (xs, ys) = (a.objectFieldsOrEmpty, b.objectFieldsOrEmpty)
      xs == ys && xs.forall(k => jsonEq(a.field(k).get, b.field(k).get))
    } else a == b

  /** The parameters of a case, as the request will carry them: the value is
    * built in TestSchema's OWN session and encoded there, so the request is
    * exactly `Encode`'s document for it. */
  def paramsOf(c: Case): Json = {
    val decls = (c.shape.decls.distinct ++ List("pv : " + c.shape.ty, "pv = " + c.value)).mkString("\n")
    val rt = try TestSchema.defAndType(decls, "pv")._2
             catch { case NonFatal(e) => complain("the params value did not load: " + e + "\n" + decls) }
    Encode.toArgonaut(rt).fold(e => complain("Encode refused the params: " + e.report + "\n" + decls), identity)
  }

  def render(r: Runner, module: String, body: String): (Int, String) = {
    val out = new java.lang.StringBuilder
    r.renderText(module, body, out) match {
      case Left(e)  => (e.status, e.body)
      case Right(_) => (200, out.toString)
    }
  }

  def fetch(r: Runner, token: String): (Int, String) = {
    val out = new java.lang.StringBuilder
    r.data(token, out) match {
      case Left(e)  => (e.status, e.body)
      case Right(_) => (200, out.toString)
    }
  }

  def parsed(text: String): Json =
    Parse.parse(text).fold(m => complain("unparseable (" + m + "): " + text.take(400)), identity)

  /** Every `{"kind":..}` object in a document, in document order. */
  def relationObjects(j: Json): List[Json] = {
    val acc = new ListBuffer[Json]
    def go(x: Json): Unit =
      if (x.isObject && x.field(Wire.Kind).flatMap(_.string).isDefined) acc += x
      else if (x.isArray) x.arrayOrEmpty.foreach(go)
      else if (x.isObject) x.objectFieldsOrEmpty.foreach(k => go(x.field(k).get))
    go(j)
    acc.toList
  }

  private val tokenRe = ("\"" + Wire.Token + "\":\"[A-Za-z0-9_-]{22}\"").r
  private val expiresRe = ("\"" + Wire.Expires + "\":\"[^\"]*\"").r

  /** A document with its tokens and expiry times blanked, so two renders of
    * the same request can be compared byte for byte. */
  def masked(text: String): String =
    expiresRe.replaceAllIn(tokenRe.replaceAllIn(text, "\"" + Wire.Token + "\":\"T\""),
                           "\"" + Wire.Expires + "\":\"E\"")

  // =====================================================================
  // (a) end to end, in process

  /** Check one generated case against one runner.  `Right` is the tags it
    * covered (for the anti-vacuity assertions), `Left` the first complaint. */
  def checkA(c: Case, post: (String, String) => (Int, String),
             get: String => (Int, String)): Either[String, List[String]] = try {
    val params = paramsOf(c)
    writeModule(c.module, c.source)
    val (status, text) = post(c.module, c.body(params))
    if (status != 200) complain("status " + status + ": " + text + "\n" + c.source)
    val doc = parsed(text)
    val tags = new ListBuffer[String]

    // (i) the envelope
    if (doc.objectFieldsOrEmpty != List(Wire.Version, Wire.Settings, Wire.Root))
      complain("envelope keys " + doc.objectFieldsOrEmpty)
    if (doc.field(Wire.Version).flatMap(_.number).flatMap(_.toInt) != Some(Wire.version))
      complain("version " + doc.field(Wire.Version))
    if (doc.field(Wire.Settings) != Some(settings)) complain("settings " + doc.field(Wire.Settings))

    // (ii) the parameters came back in the first widget's props
    val root = doc.field(Wire.Root).getOrElse(complain("no root"))
    val kids = root.field("children").map(_.arrayOrEmpty).getOrElse(complain("root is not a VFlow: " + root.nospaces))
    val props = kids.headOption.flatMap(_.field("props")).getOrElse(complain("no params widget"))
    if (!jsonEq(props, params))
      complain("props differ from the params sent\n want " + params.nospaces + "\n got  " + props.nospaces)
    tags += ("shape-" + c.shape.ty.takeWhile(ch => ch != ' ' && ch != '('))

    // (iii) the relations
    val objs = relationObjects(root)
    if (objs.length != c.rels.length) complain("relation objects " + objs.length + " for " + c.rels.length)
    val deferred = new ListBuffer[(Rel, String)]
    c.rels.zip(objs).zipWithIndex.foreach { case ((rel, obj), i) =>
      val want = rel.delivery(c.default, c.threshold)
      val kind = obj.field(Wire.Kind).flatMap(_.string).getOrElse("")
      val wantKind = if (want == Delivery.Deferred) Wire.Deferred else Wire.Inline
      if (kind != wantKind) complain("relation " + i + " (" + rel.form + ", default " + c.default.name +
                                     ", threshold " + c.threshold + ") is " + kind + ", wanted " + wantKind)
      tags += (wantKind + "-" + rel.form)
      if (obj.field(Wire.Columns).map(_.arrayOrEmpty) != Some(rel.wireColumns))
        complain("relation " + i + " columns " + obj.field(Wire.Columns).map(_.nospaces))
      if (kind == Wire.Inline) {
        if (obj.objectFieldsOrEmpty != List(Wire.Kind, Wire.Columns, Wire.Rows, Wire.RowCount))
          complain("inline keys " + obj.objectFieldsOrEmpty)
        sameRows(rel, obj, "relation " + i)
      } else {
        if (obj.objectFieldsOrEmpty != List(Wire.Kind, Wire.Columns, Wire.Token, Wire.Expires))
          complain("deferred keys " + obj.objectFieldsOrEmpty)
        val tok = obj.field(Wire.Token).flatMap(_.string).getOrElse(complain("no token"))
        if (!tok.matches("[A-Za-z0-9_-]{22}")) complain("token " + tok)
        deferred += ((rel, tok))
      }
    }

    // (iv) every token resolves to the inline object
    deferred.foreach { case (rel, tok) =>
      val (st, body) = get(tok)
      if (st != 200) complain("token " + tok + " gave " + st + ": " + body)
      val obj = parsed(body)
      if (obj.field(Wire.Kind).flatMap(_.string) != Some(Wire.Inline)) complain("re-request kind " + body.take(80))
      if (obj.field(Wire.Columns).map(_.arrayOrEmpty) != Some(rel.wireColumns)) complain("re-request columns")
      sameRows(rel, obj, "re-request of " + tok)
      tags += "resolved"
    }
    Right(tags.toList)
  } catch { case Complaint(why) => Left(why) }

  /** The rows of an inline object, as a SET: a SQL scan carries no order,
    * and `rgKey` makes every generated row distinct. */
  private def sameRows(rel: Rel, obj: Json, what: String): Unit = {
    val got = obj.field(Wire.Rows).map(_.arrayOrEmpty).getOrElse(complain(what + ": no rows"))
    val want = rel.wireRows
    val matched = want.length == got.length &&
      want.forall(w => got.exists(g => jsonEq(w, g))) && got.forall(g => want.exists(w => jsonEq(w, g)))
    if (!matched)
      complain(what + " rows\n want " + want.map(_.nospaces) + "\n got  " + got.map(_.nospaces))
    if (obj.field(Wire.RowCount).flatMap(_.number).flatMap(_.toInt) != Some(want.length))
      complain(what + " rowCount " + obj.field(Wire.RowCount))
  }

  private def inProcess: (String, String) => (Int, String) = (m, b) => render(runner, m, b)
  private def inProcessGet: String => (Int, String) = t => fetch(runner, t)

  private val aCases = 24

  property("(a) end to end: the document echoes the params and delivers every relation as asked") = secure {
    val results = TestSchema.samples(caseGen, aCases, 9110L).map(c => checkA(c, inProcess, inProcessGet))
    val bad = results.collect { case Left(m) => m }
    val tags = results.collect { case Right(t) => t }.flatten.toSet
    val forms = Set("bare", "Inline", "Deferred", "rel", "relInline", "relDeferred")
    val kinds = forms.map(f => Wire.Inline + "-" + f) ++ forms.map(f => Wire.Deferred + "-" + f)
    (bad.isEmpty :| (bad.length + " of " + aCases + " failed:\n" + bad.take(2).mkString("\n---\n"))) &&
      (tags.contains("resolved") :| "no deferred token was ever re-requested") &&
      ((kinds.filter(k => k.startsWith(Wire.Deferred)).exists(tags.contains)) :| "nothing was ever deferred") &&
      ((kinds.filter(k => k.startsWith(Wire.Inline)).exists(tags.contains)) :| "nothing was ever inline") &&
      (forms.forall(f => tags.exists(_.endsWith("-" + f))) :|
        ("relation forms never generated: " + forms.filterNot(f => tags.exists(_.endsWith("-" + f)))))
  }

  // =====================================================================
  // (b) the error paths

  /** One mutation of a JSON document, and the path it is at. */
  private def mutations(j: Json): List[(String, Json, String)] = {
    val acc = new ListBuffer[(String, Json, String)]
    def go(x: Json, path: String): Unit = {
      if (x.isObject) {
        val ks = x.objectFieldsOrEmpty
        ks.foreach { k =>
          acc += (("drop " + k, Json.jObject(x.obj.get - k), path))
          go(x.field(k).get, path + "." + k)
        }
        acc += (("add key", Json.jObject((x.obj.get + ("zzUnknown", Json.jNumber(1)))), path))
      } else if (x.isArray) {
        x.arrayOrEmpty.zipWithIndex.foreach { case (e, i) => go(e, path + "[" + i + "]") }
      } else if (x.isString) acc += (("string -> number", Json.jNumber(42), path))
      else acc += (("-> string", Json.jString("zzz"), path))
    }
    go(j, "$")
    acc.toList
  }

  private def replaceAt(j: Json, path: String, v: Json): Json = {
    // the mutations above are built with the path they apply at; rebuild
    def go(x: Json, at: String): Json =
      if (at == path) v
      else if (x.isObject)
        x.objectFieldsOrEmpty.foldLeft(x)((acc, k) => acc.withObject(_ + (k, go(x.field(k).get, at + "." + k))))
      else if (x.isArray)
        Json.array(x.arrayOrEmpty.zipWithIndex.map { case (e, i) => go(e, at + "[" + i + "]") }: _*)
      else x
    go(j, "$")
  }

  property("(b1) a mutated parameter is a 400 at a path under $.params") = secure {
    val cases = TestSchema.samples(caseGen, 12, 4242L)
    val checks = cases.map { c =>
      try {
        val params = paramsOf(c)
        writeModule(c.module, c.source)
        // a working request first, so the 400s are about the mutation
        val (ok, okText) = render(runner, c.module, c.body(params))
        if (ok != 200) complain("the unmutated request gave " + ok + ": " + okText)
        val ms = mutations(params).take(12)
        val verdicts = ms.map { case (what, v, at) =>
          val mutated = replaceAt(params, at, v)
          if (mutated == params) None // the mutation was a no-op
          else {
            val (st, body) = render(runner, c.module, c.body(mutated))
            if (st == 200) None // the type accepted it: not every mutation is invalid
            else {
              val e = parsed(body).field("error").getOrElse(complain("no error object: " + body))
              val p = e.field("path").flatMap(_.string).getOrElse(complain("no path: " + body))
              if (st != 400) complain(what + " at " + at + " gave " + st + ": " + body)
              else if (!p.startsWith("$." + Request.Params))
                complain(what + " at " + at + " reported " + p)
              else Some(p)
            }
          }
        }
        Right(verdicts.flatten.length)
      } catch { case Complaint(why) => Left(why + "\n" + c.source) }
    }
    val bad = checks.collect { case Left(m) => m }
    val refusals = checks.collect { case Right(n) => n }.sum
    (bad.isEmpty :| bad.take(2).mkString("\n---\n")) &&
      ((refusals > 20) :| ("only " + refusals + " mutations were refused: the property is near-vacuous"))
  }

  property("(b2) an unknown module or binding is 404") = secure {
    writeModule("RgNoReport", "module RgNoReport where\n\nimport Int\n\nnotAReport : Int\nnotAReport = 3\n")
    val cases = List(
      ("RgAbsent",      "{}"),
      ("RgNoReport",    "{}"),
      ("../etc/passwd", "{}"),
      ("rgLowercase",   "{}"))
    cases.foldLeft(proved: Prop) { case (acc, (m, b)) =>
      val (st, body) = render(runner, m, b)
      acc && ((st ?= 404) :| (m + " gave " + st + ": " + body)) &&
        ((parsed(body).field("error").flatMap(_.field("path")) ?= Some(Json.jNull)) :| ("path of " + m))
    } && {
      val (st, body) = fetch(runner, "notatokenatallnope00")
      ((st ?= 404) :| ("an unknown token gave " + st + ": " + body))
    }
  }

  property("(b3) a report that is not Params -> Node is a 400 naming the reason") = secure {
    val head = "module %s where\n\nimport Builtin\nimport Int\nimport Json\nimport List\nimport Layout.Doc\n\n"
    val cases = List(
      ("RgPoly",   "report : a -> Node\nreport _ = widget \"w\" 1\n",            "polymorphic"),
      ("RgNotFn",  "report : Node\nreport = widget \"w\" 1\n",                   "not"),
      ("RgWrongR", "report : Int -> Int\nreport n = n\n",                        "Layout.Doc.Node"),
      ("RgBadP",   "report : (Int -> Int) -> Node\nreport _ = widget \"w\" 1\n", "function"),
      // J3f: a fetching report must still end in a Node
      ("RgFetchI", "import Layout.Fetch\nreport : Int -> Fetch Int\nreport n = done n\n", "Layout.Doc.Node"))
    cases.foldLeft(proved: Prop) { case (acc, (m, body, want)) =>
      writeModule(m, head.format(m) + body)
      val (st, text) = render(runner, m, "{}")
      val msg = parsed(text).field("error").flatMap(_.field("message")).flatMap(_.string).getOrElse("")
      acc && ((st ?= 400) :| (m + " gave " + st + ": " + text)) &&
        (msg.contains(want) :| (m + ": message does not name " + want + ": " + msg))
    }
  }

  property("(b4) a report that throws is a 500, and the runner still serves the next request") = secure {
    writeModule("RgBoom",
      "module RgBoom where\n\nimport Builtin\nimport Error\nimport Int\nimport Json\nimport List\n" +
      "import Layout.Doc\n\nreport : Int -> Node\nreport n = widget \"w\" (error \"boom\")\n")
    val (st, text) = render(runner, "RgBoom", "{\"" + Request.Params + "\":1}")
    val err = parsed(text).field("error").getOrElse(Json.jNull)
    val msg = err.field("message").flatMap(_.string).getOrElse("")
    // a refusal is NOT cached: the same module answers the same way twice
    val (st2, _) = render(runner, "RgBoom", "{\"" + Request.Params + "\":2}")
    ((st ?= 500) :| ("status " + st + ": " + text)) &&
      (msg.contains("boom") :| ("message " + msg)) &&
      ((err.field("path").flatMap(_.string).isDefined) :| ("a document path was expected: " + text)) &&
      ((st2 ?= 500) :| "the second request answered differently")
  }

  property("(b5) an expired token is 404; the same token resolves before it expires") = secure {
    val m = freshModule("RgExp")
    val rel = Rel(List(colPool.head), List(List(("\"a\"", Json.jString("a")))), "Deferred")
    writeModule(m, "module " + m + " where\n\n" + importLines + "\n\n" +
                   "report : Int -> Node\nreport n = widget \"r\" " + rel.source + "\n")
    val (st, text) = render(clockedRunner, m, "{\"" + Request.Params + "\":1}")
    if (st != 200) falsified :| ("render " + st + ": " + text)
    else {
      val tok = relationObjects(parsed(text)).head.field(Wire.Token).flatMap(_.string).getOrElse("")
      val before = fetch(clockedRunner, tok)._1
      handClock.addAndGet(59000L)
      val stillOk = fetch(clockedRunner, tok)._1
      handClock.addAndGet(2000L)
      val after = fetch(clockedRunner, tok)
      handClock.set(1000000L)
      ((before ?= 200) :| "a fresh token did not resolve") &&
        ((stillOk ?= 200) :| "the token expired early") &&
        ((after._1 ?= 404) :| ("an expired token gave " + after._1 + ": " + after._2))
    }
  }

  property("(b6) the request body itself: shape, unknown keys, and the streamed strategy") = secure {
    val m = freshModule("RgReq")
    writeModule(m, "module " + m + " where\n\n" + importLines + "\n\n" +
                   "report : Int -> Node\nreport n = widget \"w\" n\n")
    def at(body: String): (Int, Option[String], String) = {
      val (st, text) = render(runner, m, body)
      val e = parsed(text).field("error").getOrElse(Json.jNull)
      (st, e.field("path").flatMap(_.string), e.field("message").flatMap(_.string).getOrElse(""))
    }
    val p = "\"" + Request.Params + "\":1"
    val bad = List(
      ("[]",                                          "$"),
      ("{" + p + ",\"nope\":1}",                      "$.nope"),
      ("{" + p + ",\"data\":3}",                      "$.data"),
      ("{" + p + ",\"data\":{\"nope\":1}}",           "$.data.nope"),
      ("{" + p + ",\"data\":{\"default\":\"maybe\"}}","$.data.default"),
      ("{" + p + ",\"data\":{\"strategy\":\"streamed\"}}", "$.data.strategy"),
      ("{" + p + ",\"data\":{\"threshold\":-1}}",     "$.data.threshold"),
      ("{" + p + ",\"data\":{\"threshold\":1.5}}",    "$.data.threshold"))
    val shapes = bad.foldLeft(proved: Prop) { case (acc, (body, path)) =>
      val (st, got, msg) = at(body)
      acc && ((st ?= 400) :| (body + " gave " + st)) && ((got ?= Some(path)) :| (body + " reported " + got + " (" + msg + ")"))
    }
    val notJson = at("{\"params\":")
    // a body nested past argonaut's recursive parser is a 400, not a crash
    val deep = at("{\"params\":" + ("[" * 60000) + ("]" * 60000) + "}")
    val streamed = at("{" + p + ",\"data\":{\"strategy\":\"streamed\"}}")
    shapes &&
      ((notJson._1 ?= 400) :| "a truncated body was not a 400") &&
      ((deep._1 ?= 400) :| ("a deeply nested body gave " + deep._1)) &&
      (streamed._3.contains("streamed") :| ("the streamed refusal reads " + streamed._3)) &&
      // an empty body is an empty object, and this report takes Int, so it is a params error
      ((at("{}")._2 ?= Some("$." + Request.Params)) :| "a missing params was not reported at $.params")
  }

  property("(b7) a header-less empty relation is a 500 naming the hint, not a broken document") = secure {
    val m = freshModule("RgEmpty")
    writeModule(m, "module " + m + " where\n\n" + importLines + "\n\n" +
                   "report : Int -> Node\nreport n = widget \"r\" (mkRelation# (toList# []))\n")
    val (st, text) = render(runner, m, "{\"" + Request.Params + "\":1}")
    val e = parsed(text).field("error").getOrElse(Json.jNull)
    val msg = e.field("message").flatMap(_.string).getOrElse("")
    // `Doc.fromRuntime(node, hints)` could take a header per walker path, but
    // the runner has only the report's RESULT type (`Layout.Doc.Node`), never
    // the type of a relation buried in a widget's props, so there is nothing
    // to build a hint from: the report must use `mkRelationWithHeader#`.
    ((st ?= 500) :| ("status " + st + ": " + text)) &&
      (msg.contains("carries no columns") :| ("message " + msg)) &&
      ((e.field("path").flatMap(_.string) ?= Some("$.props")) :| ("path " + text))
  }

  // =====================================================================
  // (c) over HTTP

  /** A server for the duration of one property, ALWAYS stopped again.  It used
    * to be a suite-lifetime `lazy val` that nothing ever stopped, which left
    * the JDK server's non-daemon dispatcher thread, up to eight non-daemon
    * pool threads and a listening socket alive in the shared `core/test` JVM
    * for every suite that ran after this one. */
  def withServer[A](f: Int => A): A = {
    val s = Server(runner, 0, 8, 1024 * 1024)
    s.start()
    try f(s.boundPort) finally s.stop(0)
  }

  def http(port: Int, method: String, path: String, body: Option[String]): (Int, String) = {
    val url = new java.net.URL("http://127.0.0.1:" + port + path)
    val c = url.openConnection.asInstanceOf[java.net.HttpURLConnection]
    c.setRequestMethod(method)
    c.setConnectTimeout(20000)
    c.setReadTimeout(180000)
    body.foreach { b =>
      c.setDoOutput(true)
      c.setRequestProperty("Content-Type", "application/json")
      val bs = b.getBytes("UTF-8")
      c.setFixedLengthStreamingMode(bs.length)
      val os = c.getOutputStream
      try os.write(bs) finally os.close()
    }
    val status = c.getResponseCode
    val in = if (status < 400) c.getInputStream else c.getErrorStream
    val out = new java.io.ByteArrayOutputStream
    if (in ne null) {
      val buf = new Array[Byte](8192)
      var n = in.read(buf)
      while (n >= 0) { out.write(buf, 0, n); n = in.read(buf) }
      in.close()
    }
    val ct = Option(c.getHeaderField("Content-Type")).getOrElse("")
    if (!ct.startsWith("application/json"))
      complain(method + " " + path + " answered Content-Type " + ct)
    val text = new String(out.toByteArray, "UTF-8")
    val len = Option(c.getHeaderField("Content-Length")).map(_.toInt)
    if (len != Some(text.getBytes("UTF-8").length))
      complain(method + " " + path + " Content-Length " + len + " for " + text.getBytes("UTF-8").length + " bytes")
    c.disconnect()
    (status, text)
  }

  /** A HEAD, which by RFC 7230 carries the Content-Length a GET would and no
    * body; `http()` cannot check it because it asserts header == body bytes. */
  def httpHead(port: Int, path: String): (Int, Option[Int], Int) = {
    val url = new java.net.URL("http://127.0.0.1:" + port + path)
    val c = url.openConnection.asInstanceOf[java.net.HttpURLConnection]
    c.setRequestMethod("HEAD")
    c.setConnectTimeout(20000)
    c.setReadTimeout(60000)
    val status = c.getResponseCode
    val len = Option(c.getHeaderField("Content-Length")).map(_.toInt)
    val in = if (status < 400) c.getInputStream else c.getErrorStream
    val body = if (in eq null) 0 else { var n = 0; while (in.read() >= 0) n += 1; in.close(); n }
    c.disconnect()
    (status, len, body)
  }

  private def overHttp(port: Int): (String, String) => (Int, String) =
    (m, b) => http(port, "POST", Server.ReportPrefix + m, Some(b))
  private def overHttpGet(port: Int): String => (Int, String) =
    t => http(port, "GET", Server.DataPrefix + t, None)

  property("(c) over HTTP: the same requests, byte-identical bodies and the right statuses") = secure {
   withServer { port =>
    val cases = TestSchema.samples(caseGen, 10, 7717L)
    val checks = cases.map { c =>
      try {
        val params = paramsOf(c)
        writeModule(c.module, c.source)
        val (s1, t1) = render(runner, c.module, c.body(params))
        val (s2, t2) = http(port, "POST", Server.ReportPrefix + c.module, Some(c.body(params)))
        if (s1 != 200 || s2 != 200) complain("statuses " + s1 + " / " + s2 + "\n" + t1.take(300) + "\n" + t2.take(300))
        if (masked(t1) != masked(t2))
          complain("bodies differ\n in-process " + masked(t1).take(400) + "\n over HTTP  " + masked(t2).take(400))
        Right(())
      } catch { case Complaint(why) => Left(why) }
    }
    val bad = checks.collect { case Left(m) => m }
    // the same case run through checkA, but every call over the socket
    val end2end = TestSchema.samples(caseGen, 6, 3313L).map(c => checkA(c, overHttp(port), overHttpGet(port)))
    val bad2 = end2end.collect { case Left(m) => m }
    (bad.isEmpty :| bad.take(2).mkString("\n---\n")) &&
      (bad2.isEmpty :| bad2.take(2).mkString("\n---\n"))
   }
  }

  property("(c-routes) health, method and size limits, and unknown routes") = secure {
   withServer { port =>
    val health = http(port, "GET", Server.Health, None)
    val hj = parsed(health._2)
    val wrongMethod = http(port, "GET", Server.ReportPrefix + "RgAbsent", None)
    val unknownRoute = http(port, "GET", "/nope", None)
    val unknownModule = http(port, "POST", Server.ReportPrefix + "RgAbsent", Some("{}"))
    val tooBig = http(port, "POST", Server.ReportPrefix + "RgAbsent",
                      Some("{\"params\":\"" + ("x" * (1024 * 1024 + 16)) + "\"}"))
    // The length pin goes against an UNKNOWN ROUTE, not against /health.
    // /health's body lists the loaded modules, ScalaCheck runs this suite's
    // properties concurrently over the one `runner`, and half of them compile
    // a fresh module -- so the GET and the HEAD can legitimately see different
    // module sets and different lengths (this pin failed exactly that way on
    // the landing's full core/test).  The 404 body of `/nope` is a pure
    // function of the path, so GET and HEAD agree whenever they are taken.
    val headRoute  = httpHead(port, "/nope")
    val headHealth = httpHead(port, Server.Health)
    val doc = http(port, "POST", Server.ReportPrefix + "Sales",
                   Some("{\"" + Request.Params + "\":{\"fromDay\":\"2026-01-05\",\"toDay\":\"2026-02-20\"," +
                        "\"orderBy\":\"ByDay\"}}"))
    ((health._1 ?= 200) :| ("health " + health._2)) &&
      // every `http()` call above already asserted Content-Length == the body's
      // UTF-8 byte count; this says the two really differ, so that assertion is
      // not comparing a number with itself
      ((doc._1 ?= 200) :| doc._2.take(200)) &&
      (doc._2.contains(settingsNote) :| "the non-ASCII settings note did not reach the wire") &&
      ((doc._2.getBytes("UTF-8").length > doc._2.length) :|
        ("the response is pure ASCII (" + doc._2.length + " chars), so the Content-Length pin is vacuous")) &&
      // HEAD: the length a GET would have carried, and no body
      ((headRoute._1 ?= 404) :| ("HEAD /nope " + headRoute)) &&
      ((headRoute._2 ?= Some(unknownRoute._2.getBytes("UTF-8").length)) :|
        ("HEAD Content-Length " + headRoute + " for a GET body of " + unknownRoute._2.getBytes("UTF-8").length +
         " bytes: " + unknownRoute._2)) &&
      ((headRoute._3 ?= 0) :| ("HEAD sent a body of " + headRoute._3 + " bytes")) &&
      // the 200 route too, but only that a length is there and the body is not:
      // its exact value is not stable across concurrent properties
      ((headHealth._1 ?= 200) :| ("HEAD /health " + headHealth)) &&
      (headHealth._2.exists(_ > 0) :| ("HEAD /health carried no Content-Length: " + headHealth)) &&
      ((headHealth._3 ?= 0) :| ("HEAD /health sent a body of " + headHealth._3 + " bytes")) &&
      ((hj.field("status").flatMap(_.string) ?= Some("ok")) :| health._2) &&
      ((hj.field(Wire.Version).flatMap(_.number).flatMap(_.toInt) ?= Some(Wire.version)) :| health._2) &&
      ((wrongMethod._1 ?= 405) :| ("GET /report gave " + wrongMethod._1)) &&
      ((unknownRoute._1 ?= 404) :| ("an unknown route gave " + unknownRoute._1)) &&
      ((unknownModule._1 ?= 404) :| ("an unknown module gave " + unknownModule._1)) &&
      ((tooBig._1 ?= 413) :| ("an oversized body gave " + tooBig._1 + ": " + tooBig._2.take(200)))
   }
  }

  /** Capture what a logger says while `body` runs (log4j 2 core under the
    * 1.2 bridge, exactly as TestDoc's does for `ermine.json.doc`). */
  private def capturingLog[A](names: List[String])(body: => A): (Either[Throwable, A], List[String]) = {
    import org.apache.logging.log4j.core.{ LoggerContext, LogEvent }
    import org.apache.logging.log4j.core.appender.AbstractAppender
    import org.apache.logging.log4j.core.config.Property
    import org.apache.logging.log4j.Level
    val lines = java.util.Collections.synchronizedList(new java.util.ArrayList[String]())
    val app = new AbstractAppender("TestRunner-" + System.nanoTime, null, null, true, Property.EMPTY_ARRAY) {
      def append(e: LogEvent): Unit =
        lines.add(e.getLevel.toString + " " + e.getLoggerName + " " + e.getMessage.getFormattedMessage)
    }
    app.start()
    val ctxs = List(org.apache.logging.log4j.LogManager.getContext(false),
                    org.apache.logging.log4j.LogManager.getContext(classOf[org.apache.log4j.Logger].getClassLoader, false),
                    org.apache.logging.log4j.LogManager.getContext(Server.getClass.getClassLoader, false))
      .collect { case c: LoggerContext => c }.distinct
    val added = ctxs.flatMap { ctx =>
      val cfg = ctx.getConfiguration
      names.map { n =>
        val lc = new org.apache.logging.log4j.core.config.LoggerConfig(n, Level.INFO, true)
        lc.addAppender(app, Level.INFO, null)
        cfg.addLogger(n, lc)
        (ctx, n)
      }
    }
    ctxs.foreach(_.updateLoggers())
    val result = try Right(body) catch { case e: Throwable => Left(e) }
    added.foreach { case (ctx, n) => ctx.getConfiguration.removeLogger(n) }
    ctxs.foreach(_.updateLoggers())
    app.stop()
    (result, scala.collection.JavaConverters.asScalaBufferConverter(lines).asScala.toList)
  }

  property("(log) one INFO line per request beside J3b's per-relation lines") = secure {
    val m = freshModule("RgLog")
    val rel = Rel(List(colPool.head), List(List(("\"a\"", Json.jString("a")))), "bare")
    writeModule(m, "module " + m + " where\n\n" + importLines + "\n\n" +
                   "report : Int -> Node\nreport n = widget \"r\" " + rel.source + "\n")
    // warm the report up outside the capture, so the load's own chatter is not in it
    render(runner, m, "{\"" + Request.Params + "\":1}")
    val (res, lines) = capturingLog(List("ermine.json.http", "ermine.json.doc")) {
      withServer { port =>
        val ok = http(port, "POST", Server.ReportPrefix + m, Some("{\"" + Request.Params + "\":1}"))
        val no = http(port, "GET", "/nope", None)
        (ok._1, no._1)
      }
    }
    val mine = lines.filter(l => l.contains(Server.ReportPrefix + m) || l.contains("/nope") ||
                                l.contains("relation $.props "))
    val request = mine.filter(_.contains("ermine.json.http"))
    ((res.right.toOption ?= Some((200, 404)))) &&
      (request.exists(l => l.startsWith("INFO ermine.json.http POST " + Server.ReportPrefix + m) &&
                           l.contains("status=200") && l.contains("ms=") && l.contains("bytes=")) :|
        ("no request line: " + mine)) &&
      (request.exists(l => l.contains("GET /nope") && l.contains("status=404")) :| ("no 404 line: " + mine)) &&
      // J3b's per-relation line is still there, on its own logger
      (mine.exists(l => l.startsWith("INFO ermine.json.doc relation $.props inline rows=1 bytes=")) :|
        ("no relation line among " + lines))
  }

  // =====================================================================
  // (d) concurrency

  property("(d) concurrent requests answer what the same requests answer one at a time") = secure {
   withServer { port =>
    val cases = TestSchema.samples(caseGen, 8, 5150L)
    val bodies = cases.map { c =>
      writeModule(c.module, c.source)
      (c, c.body(paramsOf(c)))
    }
    // serially first, so every module is compiled and cached
    val serial = bodies.map { case (c, b) => masked(render(runner, c.module, b)._2) }
    val results = new java.util.concurrent.ConcurrentHashMap[Int, String]
    val errors = new java.util.concurrent.ConcurrentLinkedQueue[String]
    val start = new java.util.concurrent.CountDownLatch(1)
    val threads = bodies.zipWithIndex.map { case ((c, b), i) =>
      val t = new Thread(new Runnable {
        def run(): Unit =
          try {
            start.await()
            // twice over, and through the socket: the pool is what serves them
            (0 until 2).foreach { _ =>
              val (st, text) = http(port, "POST", Server.ReportPrefix + c.module, Some(b))
              if (st != 200) errors.add(c.module + " gave " + st + ": " + text.take(200))
              results.put(i, masked(text))
            }
          } catch { case NonFatal(e) => errors.add(c.module + " threw " + e) }
      })
      t.start(); t
    }
    start.countDown()
    threads.foreach(_.join(180000L))
    val mismatched = serial.zipWithIndex.filter { case (want, i) => results.get(i) != want }
    (errors.isEmpty :| ("errors: " + scala.collection.JavaConverters.collectionAsScalaIterableConverter(errors).asScala.take(2).mkString("; "))) &&
      ((results.size ?= bodies.length) :| ("only " + results.size + " of " + bodies.length + " answered")) &&
      (mismatched.isEmpty :| ("concurrent bodies differ for " + mismatched.map(_._2) +
                              mismatched.headOption.map(p => "\n want " + p._1.take(300) +
                                "\n got  " + Option(results.get(p._2)).map(_.take(300))).getOrElse("")))
   }
  }

  // =====================================================================
  // (e) one connection per request

  property("(e) one connection per POST /report however many relations, one per GET /data") = secure {
    val c = TestSchema.samples(caseGen, 1, 99L).head
    // a case with several relations, at least one of them deferred
    val rels = List(Rel(List(colPool.head), List(List(("\"a\"", Json.jString("a")))), "bare"),
                    Rel(List(colPool(1)), List(List(("1.5", Json.jNumber(1.5)))), "Inline"),
                    Rel(List(colPool(2)), List(List(("True", Json.jBool(true)))), "Deferred"))
    val cc = c.copy(module = freshModule("RgConn"), rels = rels, default = Delivery.Inline, threshold = None)
    val params = paramsOf(cc)
    writeModule(cc.module, cc.source)
    // compile the report first: the lookup itself opens no connection
    val warm = render(runner, cc.module, cc.body(params))
    val before = counting.openedHere
    val (st, text) = render(runner, cc.module, cc.body(params))
    val afterPost = counting.openedHere
    val tok = relationObjects(parsed(text)).find(_.field(Wire.Kind).flatMap(_.string) == Some(Wire.Deferred))
                .flatMap(_.field(Wire.Token)).flatMap(_.string).getOrElse("")
    val (gst, _) = fetch(runner, tok)
    val afterGet = counting.openedHere
    ((warm._1 ?= 200) :| ("the warm-up request failed: " + warm._2.take(200))) &&
      ((st ?= 200) :| ("status " + st + ": " + text.take(200))) &&
      ((gst ?= 200) :| "the token did not resolve") &&
      ((afterPost - before ?= 1) :| ("a POST over 3 relations opened " + (afterPost - before) + " connections")) &&
      ((afterGet - afterPost ?= 1) :| ("a GET /data opened " + (afterGet - afterPost) + " connections"))
  }

  // =====================================================================
  // (ex) the example report and the curl walkthrough

  property("(ex) core/src/test/resources/doc/Sales.e answers the walkthrough's requests") = secure {
    val params = "{\"fromDay\":\"2026-01-05\",\"toDay\":\"2026-02-20\"," +
                 "\"onlyRegion\":\"north\",\"orderBy\":\"ByAmount\"}"
    val (st, text) = render(runner, "Sales", "{\"" + Request.Params + "\":" + params + "}")
    if (st != 200) falsified :| ("status " + st + ": " + text)
    else {
      val doc = parsed(text)
      val root = doc.field(Wire.Root).get
      val kids = root.field("children").map(_.arrayOrEmpty).getOrElse(Nil)
      val heading = kids.head.field("props").get
      val objs = relationObjects(root)
      // north, in range: 2026/1/5, 2026/1/19 and 2026/2/14
      val byDay = objs.head
      val deferred = objs(2)
      val (gst, gbody) = fetch(runner, deferred.field(Wire.Token).flatMap(_.string).getOrElse(""))
      val items = parsed(gbody)
      // no filter at all: every region, every sale
      val (st2, text2) = render(runner, "Sales",
        "{\"" + Request.Params + "\":{\"fromDay\":\"2026-01-01\",\"toDay\":\"2026-12-31\"," +
        "\"orderBy\":\"ByDay\"},\"" + Request.Data + "\":{\"threshold\":4}}")
      val all = relationObjects(parsed(text2).field(Wire.Root).get)
      ((root.field("tag").flatMap(_.string) ?= Some("VFlow")) :| text.take(200)) &&
        ((heading.field("title").flatMap(_.string) ?= Some("Sales")) :| heading.nospaces) &&
        ((heading.field("sortColumn").flatMap(_.string) ?= Some("amount")) :| heading.nospaces) &&
        ((heading.field("matched").flatMap(_.number).flatMap(_.toInt) ?= Some(3)) :| heading.nospaces) &&
        ((heading.field("total").flatMap(_.number).flatMap(_.toDouble) ?= Some(4350.75)) :| heading.nospaces) &&
        ((objs.length ?= 3) :| ("relation objects " + objs.length)) &&
        ((byDay.field(Wire.Kind).flatMap(_.string) ?= Some(Wire.Inline)) :| byDay.nospaces) &&
        ((byDay.field(Wire.RowCount).flatMap(_.number).flatMap(_.toInt) ?= Some(3)) :| byDay.nospaces) &&
        ((byDay.field(Wire.Columns).map(_.arrayOrEmpty.flatMap(_.field(Wire.Name)).flatMap(_.string)) ?=
            Some(List("amount", "day", "region", "units"))) :| byDay.nospaces) &&
        // a Deferred wrapper is deferred whatever the request asked
        ((deferred.field(Wire.Kind).flatMap(_.string) ?= Some(Wire.Deferred)) :| deferred.nospaces) &&
        ((gst ?= 200) :| "the line items did not resolve") &&
        ((items.field(Wire.RowCount).flatMap(_.number).flatMap(_.toInt) ?= Some(8)) :| gbody.take(200)) &&
        ((st2 ?= 200) :| text2.take(200)) &&
        // 8 sales over a threshold of 4: the bare relation defers instead
        ((all.head.field(Wire.Kind).flatMap(_.string) ?= Some(Wire.Deferred)) :| all.head.nospaces) &&
        // the regions relation has only 4 rows, so it stays inline
        ((all(1).field(Wire.RowCount).flatMap(_.number).flatMap(_.toInt) ?= Some(4)) :| all(1).nospaces)
    }
  }

  // =====================================================================
  // (fx) fetching reports (J3f): core/src/test/resources/doc/Fetch*.e over
  // `Layout.Fetch`, each a report that a pure `Params -> Node` cannot be

  /** The relation objects of a document: `relationObjects` takes every
    * object with a "kind" key, and a table's column descriptors have one too
    * (`Layout.Widgets.Table.ColumnKind`), so this keeps the delivery kinds only. */
  def rels(j: Json): List[Json] =
    relationObjects(j).filter(o => str(o.field(Wire.Kind)).exists(k => k == Wire.Inline || k == Wire.Deferred))

  /** The inline rows of a relation object as maps keyed by column name. */
  def rowMaps(rel: Json): List[Map[String, Json]] = {
    val cols = rel.field(Wire.Columns).map(_.arrayOrEmpty.flatMap(_.field(Wire.Name)).flatMap(_.string)).getOrElse(Nil)
    rel.field(Wire.Rows).map(_.arrayOrEmpty).getOrElse(Nil).map(r => cols.zip(r.arrayOrEmpty).toMap)
  }
  private def num(j: Option[Json]): Option[Double] = j.flatMap(_.number).flatMap(_.toDouble)
  private def str(j: Option[Json]): Option[String] = j.flatMap(_.string)
  private def params(p: String): String = "{\"" + Request.Params + "\":" + p + "}"

  property("(fx1) FetchHeadline: the headline widget scans for its own numbers, and an empty scan changes the layout") = secure {
    val (st, text) = render(runner, "FetchHeadline", params("{\"onlyRegion\":\"north\"}"))
    val (st2, text2) = render(runner, "FetchHeadline", params("{\"onlyRegion\":\"nowhere\"}"))
    val (st3, text3) = render(runner, "FetchHeadline", params("{}"))
    if (st != 200 || st2 != 200 || st3 != 200) falsified :| ("statuses " + st + "/" + st2 + "/" + st3 + ": " + text.take(300) + text2.take(300) + text3.take(300))
    else {
      val root = parsed(text).field(Wire.Root).get
      val kids = root.field("children").map(_.arrayOrEmpty).getOrElse(Nil)
      val head = kids.head.field("props").get
      val table = rels(kids(1))
      val root2 = parsed(text2).field(Wire.Root).get
      val head3 = parsed(text3).field(Wire.Root).get.field("children").get.arrayOrEmpty.head.field("props").get
      ((str(root.field("tag")) ?= Some("VFlow")) :| text.take(200)) &&
        // J3g: the numbers come from `headlineOf`, a widget constructor that
        // scans, INSIDE the vflowF -- not from a scan hoisted above the layout
        ((str(kids.head.field("name")) ?= Some("headline")) :| kids.head.nospaces) &&
        ((str(head.field("scope")) ?= Some("in north")) :| head.nospaces) &&
        ((num(head.field("rowCount")) ?= Some(3.0)) :| head.nospaces) &&
        ((num(head.field("total")) ?= Some(4350.75)) :| head.nospaces) &&
        ((num(head.field("largest")) ?= Some(2310.25)) :| head.nospaces) &&
        // the table under the headline is the same plan, delivered as a relation object
        ((table.length ?= 1) :| ("relation objects under the headline: " + table.length)) &&
        ((num(table.head.field(Wire.RowCount)) ?= Some(3.0)) :| table.head.nospaces) &&
        // an empty scan: no table at all, a headline of zeros built by the PURE
        // constructor (there is nothing to scan)
        ((str(root2.field("tag")) ?= Some("Widget")) :| text2.take(200)) &&
        ((str(root2.field("name")) ?= Some("headline")) :| text2.take(200)) &&
        ((num(root2.field("props").flatMap(_.field("rowCount"))) ?= Some(0.0)) :| text2.take(300)) &&
        ((num(root2.field("props").flatMap(_.field("total"))) ?= Some(0.0)) :| text2.take(300)) &&
        ((str(root2.field("props").flatMap(_.field("scope"))) ?= Some("in nowhere")) :| text2.take(300)) &&
        ((rels(root2).length ?= 0) :| text2.take(200)) &&
        ((num(head3.field("rowCount")) ?= Some(8.0)) :| head3.nospaces) &&
        ((num(head3.field("total")) ?= Some(12682.0)) :| head3.nospaces) &&
        ((num(head3.field("largest")) ?= Some(4100.0)) :| head3.nospaces) &&
        ((str(head3.field("scope")) ?= Some("everywhere")) :| head3.nospaces)
    }
  }

  property("(fx2) FetchRunning: rows in day order, running total and sequence folded in Ermine, joined back in SQL") = secure {
    val (st, text) = render(runner, "FetchRunning", params("{\"newestFirst\":false}"))
    val (st2, text2) = render(runner, "FetchRunning", params("{\"newestFirst\":true}"))
    if (st != 200 || st2 != 200) falsified :| ("statuses " + st + "/" + st2 + ": " + text.take(300) + text2.take(300))
    else {
      val rel = rels(parsed(text).field(Wire.Root).get).head
      val rows = rowMaps(rel)
      def at(rs: List[Map[String, Json]], n: Int) = rs.find(r => num(r.get("seqNo")) == Some(n.toDouble)).getOrElse(Map())
      val first = at(rows, 1)
      val last = at(rows, 8)
      val rows2 = rowMaps(rels(parsed(text2).field(Wire.Root).get).head)
      val first2 = at(rows2, 1)
      ((rel.field(Wire.Columns).map(_.arrayOrEmpty.flatMap(_.field(Wire.Name)).flatMap(_.string)) ?=
          Some(List("amount", "day", "region", "runningAmount", "seqNo", "target"))) :| rel.nospaces) &&
        ((rows.length ?= 8) :| ("rows " + rows.length + ": " + rel.nospaces.take(300))) &&
        ((str(first.get("day")) ?= Some("2026-01-05")) :| first.toString) &&
        ((num(first.get("runningAmount")) ?= Some(1200.5)) :| first.toString) &&
        // the join brought the region's target from the OTHER relation
        ((num(first.get("target")) ?= Some(4000.0)) :| first.toString) &&
        ((str(last.get("region")) ?= Some("west")) :| last.toString) &&
        ((num(last.get("runningAmount")) ?= Some(12682.0)) :| last.toString) &&
        ((num(last.get("target")) ?= Some(2500.0)) :| last.toString) &&
        // descending: the newest sale is first and starts the running total
        ((str(first2.get("day")) ?= Some("2026-03-17")) :| first2.toString) &&
        ((num(first2.get("runningAmount")) ?= Some(1550.0)) :| first2.toString)
    }
  }

  property("(fx3) FetchTabs: one tab per region found by a scan, each over a plan that still defers") = secure {
    val (st, text) = render(runner, "FetchTabs", params("{\"showUnits\":true}"))
    val (st2, text2) = render(runner, "FetchTabs",
      params("{\"showUnits\":false}") .dropRight(1) + ",\"" + Request.Data + "\":{\"default\":\"deferred\"}}")
    if (st != 200 || st2 != 200) falsified :| ("statuses " + st + "/" + st2 + ": " + text.take(300) + text2.take(300))
    else {
      val root = parsed(text).field(Wire.Root).get
      val tabs = root.field("tabs").map(_.arrayOrEmpty).getOrElse(Nil)
      val labels = tabs.flatMap(t => str(t.field("label")))
      val counts = tabs.map(t => num(rels(t.field("content").get).head.field(Wire.RowCount)))
      val tabs2 = parsed(text2).field(Wire.Root).get.field("tabs").map(_.arrayOrEmpty).getOrElse(Nil)
      val kinds2 = tabs2.map(t => str(rels(t.field("content").get).head.field(Wire.Kind)))
      val northTok = tabs2.find(t => str(t.field("label")) == Some("north"))
        .flatMap(t => str(rels(t.field("content").get).head.field(Wire.Token))).getOrElse("")
      val (gst, gbody) = fetch(runner, northTok)
      ((str(root.field("tag")) ?= Some("Tabbed")) :| text.take(200)) &&
        ((labels ?= List("east", "north", "south", "west")) :| labels.toString) &&
        ((counts ?= List(Some(2.0), Some(3.0), Some(2.0), Some(1.0))) :| counts.toString) &&
        // the request asked for deferred delivery: every tab's relation is a token
        ((kinds2 ?= List.fill(4)(Some(Wire.Deferred))) :| kinds2.toString) &&
        ((gst ?= 200) :| "the north tab's token did not resolve") &&
        ((num(parsed(gbody).field(Wire.RowCount)) ?= Some(3.0)) :| gbody.take(200))
    }
  }

  property("(fx4) FetchTopN: two scans in one do block: top N plus an Other slice, and a count over both") = secure {
    val (st, text) = render(runner, "FetchTopN", params("{\"keep\":2}"))
    val (st2, text2) = render(runner, "FetchTopN", params("{\"keep\":0}"))
    if (st != 200 || st2 != 200) falsified :| ("statuses " + st + "/" + st2 + ": " + text.take(300) + text2.take(300))
    else {
      val root = parsed(text).field(Wire.Root).get
      val kids = root.field("children").map(_.arrayOrEmpty).getOrElse(Nil)
      val rows = rowMaps(rels(kids.head).head)
      val labels = rows.flatMap(r => str(r.get("region")))
      val total = rows.flatMap(r => num(r.get("amount"))).sum
      val other = rows.find(r => str(r.get("region")) == Some("Other")).flatMap(r => num(r.get("amount")))
      val met = num(kids(1).field("props"))
      val rows2 = rowMaps(rels(parsed(text2).field(Wire.Root).get).head)
      // a literal relation's rows come back in the scanner's order, not the list's
      ((labels.toSet ?= Set("north", "east", "Other")) :| labels.toString) &&
        ((other ?= Some(4155.75)) :| rows.toString) &&
        ((math.abs(total - 12682.0) < 1e-9) :| ("the slices do not add up: " + total)) &&
        ((met ?= Some(2.0)) :| kids(1).nospaces) &&
        ((rows2.length ?= 1) :| rows2.toString) &&
        ((rows2.headOption.flatMap(r => num(r.get("amount"))) ?= Some(12682.0)) :| rows2.toString)
    }
  }

  property("(fx-conn) a fetching report opens ONE connection, however many scans and relations") = secure {
    val warm = render(runner, "FetchTopN", params("{\"keep\":1}"))
    val before = counting.openedHere
    val (st, text) = render(runner, "FetchTopN", params("{\"keep\":1}"))
    val afterPost = counting.openedHere
    ((warm._1 ?= 200) :| ("the warm-up request failed: " + warm._2.take(200))) &&
      ((st ?= 200) :| ("status " + st + ": " + text.take(200))) &&
      ((afterPost - before ?= 1) :| ("a fetching POST opened " + (afterPost - before) + " connections"))
  }

  property("(fx-err) a fetching report whose continuation throws is a 500 naming the report, and the next request works") = secure {
    writeModule("RgFetchBad",
      "module RgFetchBad where\n\nimport Error\nimport Layout.Doc\nimport Layout.Fetch\nimport FetchData\n\n" +
      "report : Int -> Fetch Node\nreport n = scanRelation sales (rows -> error \"boom after the scan\")\n")
    val (st, text) = render(runner, "RgFetchBad", params("1"))
    val msg = parsed(text).field("error").flatMap(_.field("message")).flatMap(_.string).getOrElse("")
    val (st2, _) = render(runner, "FetchTabs", params("{\"showUnits\":false}"))
    ((st ?= 500) :| ("status " + st + ": " + text.take(300))) &&
      (msg.contains("RgFetchBad") :| ("message does not name the report: " + msg)) &&
      ((st2 ?= 200) :| "the runner did not serve the next request")
  }

  // =====================================================================
  // (fxl) J3g: `Fetch Node` IS the report type -- the lifts, the order they
  // scan in, the laws of `map_Fetch`/`bind_Fetch`, `Params -> Node` as sugar,
  // what a failing report costs in connections, and the scanning widget.

  /** A `Scanner[DB]` that delegates to SQLite and records, per thread, a mark
    * per scan IN THE ORDER THE SCANS HAPPEN.  A literal relation reaches the
    * scanner as `ExtRel(SmallLit(rows), _)` -- the shape `TestDoc.ListScanner`
    * matches -- so the `rgName` of its first row is the mark, and a generated
    * leaf that carries a distinct one says which leaf this scan is. */
  final class RecordingScanner(under: Scanner[DB]) extends Scanner[DB]()(under.M) {
    private val seen = new ThreadLocal[ListBuffer[String]] {
      override def initialValue: ListBuffer[String] = new ListBuffer[String]
    }
    /** The marks of this thread's scans since `clear()`, in scan order. */
    def marks: List[String] = seen.get.toList
    def clear(): Unit = seen.get.clear()

    private def note(r: Ext[Nothing, Nothing]): Boolean = r match {
      case ExtRel(SmallLit(tups), _) =>
        val mark = tups.list.toList.headOption.flatMap(_.get("rgName")).map(_.extractNullableString(""))
        mark.foreach(m => seen.get += m)
        mark == Some(RecordingScanner.Boom)
      case _ => false
    }
    /** A literal relation whose first row's `rgName` is `Boom` is a scan that
      * THROWS WHEN THE ACTION RUNS.  It is the only way a generated Ermine
      * report can fail a scan -- the stdlib has no `table` primitive, so a
      * plan over a table that is not there cannot be written in Ermine -- and
      * (ip-fail) needs one on both sides of the driver (a `Call` and a
      * `Splice`).  No other property generates that name. */
    def scanExt[A: Monoid](r: Ext[Nothing, Nothing], f: Process[Record, A],
                           order: List[(String, SortOrder)]): DB[A] =
      if (note(r)) (_ => throw new RuntimeException("the scan of " + RecordingScanner.Boom + " failed"))
      else under.scanExt(r, f, order)
    def scanRel[A: Monoid](r: com.clarifi.reporting.relational.Relation[Nothing, Nothing], f: Process[Record, A],
                           order: List[(String, SortOrder)]): DB[A] = under.scanRel(r, f, order)
    def scanMem[A: Monoid](m: com.clarifi.reporting.relational.Mem[Nothing, Nothing], f: Process[Record, A],
                           order: List[(String, SortOrder)]): DB[A] = under.scanMem(m, f, order)
  }

  object RecordingScanner {
    /** The `rgName` of the first row of a literal relation whose scan throws. */
    val Boom = "BOOM"
  }

  private val recording = new RecordingScanner(Scanners.SQLite(SMEnv.dummySmenv))

  /** A third runner, whose scanner records what it scanned and in what order.
    * Its own `CountingRun`, so the connection counts of (e) and (fxl-conn)
    * are not this one's. */
  lazy val orderRunner: Runner = new Runner(RunnerConfig(
    roots     = List(moduleRoot.getPath, exampleRoot),
    run       = new CountingRun,
    scanner   = recording,
    settings  = settings,
    ttlMillis = 600000L,
    maxTokens = 4096))

  /** The imports a generated `Fetch` report needs: the document vocabulary,
    * the lifts, the widget prop types (TestWidgets' generator writes their
    * constructors) and the relation primitives. */
  private val fetchImports: String =
    List("import Builtin", "import Json", "import List", "import Maybe", "import Function",
         "import Int", "import Num", "import Field", "import Prim",
         "import Native.List", "import Native.Relation", "import Native.Pair",
         "import Layout.Doc", "import Layout.Fetch",
         "import Layout.Widgets.Format", "import Layout.Widgets.Table",
         "import Layout.Widgets.Drilldown", "import Layout.Widgets.Scorecard",
         "import Layout.Widgets.Headline", "import Layout.Widgets.Chart",
         "import Layout.Widgets.AxisChart", "import Layout.Widgets.PieChart",
         "import Layout.Widgets.StyleBox", "import Layout.Widgets.DrilldownBar",
         "import RgFields").mkString("\n")

  /** The leaf marks, "Lf00".."Lf99", as they appear in a rendered document. */
  private val markRe = "Lf[0-9][0-9]".r
  private def marksIn(text: String): List[String] = markRe.findAllIn(text).toList

  /** One leaf of an (fxl-order) tree: a scan of a one-row literal relation
    * whose `rgName` is the leaf's mark, and whose continuation puts the mark
    * IT RECEIVED into a widget.  So the document says which rows reached
    * which continuation, and `RecordingScanner` says in what order the scans
    * ran; the property is that the two agree with the source order. */
  private def leafDecl(i: Int): String = {
    val m = "Lf%02d".format(i)
    "leaf" + i + " : Fetch Node\n" +
    "leaf" + i + " = scanRelation (mkRelation# (toList# [{ rgKey = " + i + ", rgName = \"" + m + "\" }]))\n" +
    "                             (rows -> done (widget \"leaf\" (map_List (r -> r ! rgName) rows)))\n"
  }

  /** A composition of leaves.  Every node preserves the order of its
    * children, which is what (fxl-order) checks. */
  sealed abstract class FTree {
    def leaves: List[Int]
    def src: String
    def kinds: List[String]
  }
  final case class FLeaf(i: Int) extends FTree {
    def leaves = List(i); def src = "leaf" + i; def kinds = List("leaf")
  }
  final case class FVflow(kids: List[FTree]) extends FTree {
    def leaves = kids.flatMap(_.leaves)
    def src = "(vflowF [" + kids.map(_.src).mkString(", ") + "])"
    def kinds = "vflowF" :: kids.flatMap(_.kinds)
  }
  final case class FSeq(kids: List[FTree]) extends FTree {
    def leaves = kids.flatMap(_.leaves)
    def src = "(map_Fetch hflow (sequence_Fetch [" + kids.map(_.src).mkString(", ") + "]))"
    def kinds = "sequence_Fetch" :: kids.flatMap(_.kinds)
  }
  final case class FHflow(kids: List[FTree]) extends FTree {
    def leaves = kids.flatMap(_.leaves)
    def src = "(hflowF [" + kids.map(_.src).mkString(", ") + "])"
    def kinds = "hflowF" :: kids.flatMap(_.kinds)
  }
  final case class FGrid(rows: List[List[FTree]]) extends FTree {
    def leaves = rows.flatten.flatMap(_.leaves)
    def src = "(gridF [" + rows.map(r => r.map(_.src).mkString("[", ", ", "]")).mkString(", ") + "])"
    def kinds = "gridF" :: rows.flatten.flatMap(_.kinds)
  }
  final case class FTabs(kids: List[FTree]) extends FTree {
    def leaves = kids.flatMap(_.leaves)
    def src = "(tabbedF [" + kids.zipWithIndex.map { case (k, i) => "(\"t" + i + "\", " + k.src + ")" }.mkString(", ") + "])"
    def kinds = "tabbedF" :: kids.flatMap(_.kinds)
  }
  final case class FBind(a: FTree, b: FTree) extends FTree {
    def leaves = a.leaves ++ b.leaves
    def src = "(bind_Fetch " + a.src + " (x -> map_Fetch (y -> grid [[x], [y]]) " + b.src + "))"
    def kinds = "bind_Fetch" :: a.kinds ++ b.kinds
  }

  /** Random trees, numbering their leaves left to right. */
  private def ftree(depth: Int, next: () => Int): Gen[FTree] = {
    val leaf = Gen.const(()).map(_ => FLeaf(next()))
    if (depth <= 0) leaf
    else {
      def kids(max: Int): Gen[List[FTree]] =
        Gen.choose(2, max).flatMap(n => Gen.sequence[List[FTree], FTree]((0 until n).toList.map(_ => ftree(depth - 1, next))))
      Gen.frequency(
        (3, leaf),
        (2, kids(3).map(ks => FVflow(ks))),
        (2, kids(3).map(ks => FSeq(ks))),
        (2, kids(3).map(ks => FHflow(ks))),
        (1, Gen.zip(kids(2), kids(2)).map(p => FGrid(List(p._1, p._2)))),
        (1, kids(2).map(ks => FTabs(ks))),
        (2, Gen.zip(ftree(depth - 1, next), ftree(depth - 1, next)).map(p => FBind(p._1, p._2))))
    }
  }

  /** A tree with its leaves numbered 0..n-1 from the left. */
  private val orderCase: Gen[FTree] = Gen.choose(1, 3).flatMap { d =>
    Gen.const(()).flatMap { _ =>
      val c = new java.util.concurrent.atomic.AtomicInteger(0)
      ftree(d, () => c.getAndIncrement())
    }
  }

  property("(fxl-order) a tree of vflowF/hflowF/tabbedF/sequence_Fetch/bind_Fetch scans left to right") = secure {
    val trees = TestDoc.samples(orderCase, 24, 77101L)
    val bad = new ListBuffer[String]
    val sizes = new ListBuffer[Int]
    val kinds = new ListBuffer[String]
    trees.zipWithIndex.foreach { case (t, i) =>
      val want = t.leaves.map(n => "Lf%02d".format(n))
      sizes += want.length
      kinds ++= t.kinds
      val m = freshModule("RgOrd")
      writeModule(m, "module " + m + " where\n\n" + fetchImports + "\n\n" +
                     t.leaves.map(leafDecl).mkString("\n") + "\n" +
                     "report : Int -> Fetch Node\nreport p = " + t.src + "\n")
      recording.clear()
      val (st, text) = render(orderRunner, m, params("1"))
      val scanned = recording.marks
      val inDoc = marksIn(text)
      if (st != 200) bad += ("status " + st + ": " + text.take(300) + "\n" + t.src)
      else if (scanned != want) bad += ("scan order " + scanned + " for " + want + "\n" + t.src)
      else if (inDoc != want) bad += ("document order " + inDoc + " for " + want + "\n" + t.src)
    }
    // the distribution, once: a tree of one leaf could not tell an order from
    // its reverse, so most cases must have several
    val dist = sizes.toList.groupBy(identity).map(p => (p._1, p._2.length)).toList.sortBy(_._1)
    val kindCount = kinds.toList.groupBy(identity).map(p => (p._1, p._2.length)).toList.sortBy(_._1)
    val multi = sizes.count(_ >= 2)
    // the distribution, once, so the reader can see the property is not passing
    // on trees of one leaf (which could not tell an order from its reverse)
    println("  (fxl-order) " + trees.length + " trees, " + sizes.sum + " leaf scans; leaves per tree " +
            dist.map(p => p._1 + "x" + p._2).mkString(" ") + "; nodes " +
            kindCount.map(p => p._1 + "=" + p._2).mkString(" "))
    (bad.isEmpty :| (bad.length + " of " + trees.length + " failed:\n" + bad.take(2).mkString("\n---\n"))) &&
      ((multi >= 18) :| ("only " + multi + " of " + trees.length + " trees had two or more leaves; sizes " + dist)) &&
      (List("vflowF", "hflowF", "gridF", "sequence_Fetch", "tabbedF", "bind_Fetch").forall(k => kindCount.exists(_._1 == k)) :|
        ("a combinator never occurred: " + kindCount)) &&
      ((sizes.sum >= 40) :| ("only " + sizes.sum + " leaf scans in all; sizes " + dist))
  }

  /** A pure document body from TestWidgets' generator, with the `field`
    * declarations it needs. */
  private val bodyGen: Gen[TestWidgets.DocSrc] = TestWidgets.docSrc(1)

  private def fetchModule(name: String, decls: List[String], reportTy: String, body: String): String =
    "module " + name + " where\n\n" + fetchImports + "\n\n" +
    decls.distinct.mkString("\n") + "\n\n" +
    "report : Int -> " + reportTy + "\nreport p = " + body + "\n"

  /** Render two generated reports against the same request and compare the
    * bodies byte for byte, tokens and expiry times masked. */
  private def sameDocument(declsA: List[String], tyA: String, bodyA: String,
                           declsB: List[String], tyB: String, bodyB: String,
                           req: String): Option[String] = {
    val a = freshModule("RgLawA")
    val b = freshModule("RgLawB")
    writeModule(a, fetchModule(a, declsA, tyA, bodyA))
    writeModule(b, fetchModule(b, declsB, tyB, bodyB))
    val (sa, ta) = render(runner, a, req)
    val (sb, tb) = render(runner, b, req)
    if (sa != 200) Some("left status " + sa + ": " + ta.take(300) + "\n" + bodyA)
    else if (sb != 200) Some("right status " + sb + ": " + tb.take(300) + "\n" + bodyB)
    else if (masked(ta) != masked(tb)) Some("documents differ\n left  " + masked(ta).take(400) +
                                            "\n right " + masked(tb).take(400))
    else None
  }

  /** The request body for the (fxl) comparisons: a random delivery default and
    * threshold, so the deferred arm is compared too. */
  private val reqGen: Gen[String] = for {
    dflt <- Gen.oneOf(Wire.Inline, Wire.Deferred)
    thr  <- Gen.frequency((2, Gen.const(None: Option[Long])), (1, Gen.choose(0L, 3L).map(t => Some(t))))
  } yield "{\"" + Request.Params + "\":1,\"" + Request.Data + "\":{\"" + Request.Default + "\":\"" + dflt + "\"" +
          thr.map(t => ",\"" + Request.Threshold + "\":" + t).getOrElse("") + "}}"

  property("(fxl-laws) map_Fetch/bind_Fetch over done are the document their right-hand sides are") = secure {
    val cases = TestDoc.samples(Gen.zip(bodyGen, bodyGen, reqGen), 12, 90211L)
    val bad = new ListBuffer[String]
    val kinds = new ListBuffer[String]
    cases.foreach { case (s1, s2, req) =>
      val decls = s1.decls ++ s2.decls
      // (1) map_Fetch f (done a) == done (f a)
      sameDocument(decls, "Fetch Node", "map_Fetch (n -> vflow [n, " + s2.expr + "]) (done " + s1.expr + ")",
                   decls, "Fetch Node", "done (vflow [" + s1.expr + ", " + s2.expr + "])", req)
        .foreach(w => bad += ("(map/done) " + w))
      // (2) bind_Fetch (done a) k == k a
      sameDocument(decls, "Fetch Node", "bind_Fetch (done " + s1.expr + ") (x -> vflowF [done x, done " + s2.expr + "])",
                   decls, "Fetch Node", "vflowF [done " + s1.expr + ", done " + s2.expr + "]", req)
        .foreach(w => bad += ("(bind/done) " + w))
      // (3) bind_Fetch m done == m, over an m that scans
      val m = "(scanRelation (mkRelation# (toList# [{ rgKey = 1, rgName = \"Lf00\" }])) " +
              "(rows -> done (vflow [" + s1.expr + ", widget \"leaf\" (map_List (r -> r ! rgName) rows)])))"
      sameDocument(decls, "Fetch Node", "bind_Fetch " + m + " done", decls, "Fetch Node", m, req)
        .foreach(w => bad += ("(bind/right) " + w))
      kinds += (if (req.contains("\"" + Wire.Deferred + "\"")) "deferred" else "inline")
    }
    val ks = kinds.toList.toSet
    (bad.isEmpty :| (bad.length + " of " + (cases.length * 3) + " comparisons failed:\n" + bad.take(2).mkString("\n---\n"))) &&
      ((ks == Set("inline", "deferred")) :| ("only these request defaults occurred: " + ks))
  }

  property("(fxl-sugar) a pure `Params -> Node` report and the same body under `done` render the same bytes") = secure {
    val cases = TestDoc.samples(Gen.zip(bodyGen, reqGen), 20, 55507L)
    val bad = new ListBuffer[String]
    val tags = new ListBuffer[String]
    cases.foreach { case (s, req) =>
      sameDocument(s.decls, "Node", s.expr, s.decls, "Fetch Node", "done (" + s.expr + ")", req) match {
        case Some(w) => bad += w
        case None    =>
          val a = freshModule("RgSugar")
          writeModule(a, fetchModule(a, s.decls, "Node", s.expr))
          val (_, text) = render(runner, a, req)
          if (text.contains("\"" + Wire.Deferred + "\"")) tags += "deferred"
          if (text.contains("\"" + Wire.Inline + "\"")) tags += "inline"
      }
    }
    val seen = tags.toList.toSet
    (bad.isEmpty :| (bad.length + " of " + cases.length + " differed:\n" + bad.take(2).mkString("\n---\n"))) &&
      ((seen == Set("inline", "deferred")) :| ("delivery arms compared: " + seen))
  }

  property("(fxl-conn) a report that fails to evaluate opens NO connection, pure or fetching") = secure {
    val pure = freshModule("RgNoConnP")
    writeModule(pure, "module " + pure + " where\n\nimport Error\nimport Layout.Doc\n\n" +
                      "report : Int -> Node\nreport n = error \"boom before any row\"\n")
    val fetch = freshModule("RgNoConnF")
    writeModule(fetch, "module " + fetch + " where\n\nimport Error\nimport Layout.Doc\nimport Layout.Fetch\n\n" +
                       "report : Int -> Fetch Node\nreport n = error \"boom before any scan\"\n")
    // warm both: the FIRST request for a module loads and evaluates it, which
    // is not what is being counted
    render(runner, pure, params("1")); render(runner, fetch, params("1"))
    val before = counting.openedHere
    val (stP, textP) = render(runner, pure, params("1"))
    val afterPure = counting.openedHere
    val (stF, textF) = render(runner, fetch, params("1"))
    val afterFetch = counting.openedHere
    // ...and one that does scan opens exactly one
    render(runner, "FetchFragments", params("{\"tabsFor\":[\"north\"],\"topN\":1}"))
    val beforeOk = counting.openedHere
    val (stOk, textOk) = render(runner, "FetchFragments", params("{\"tabsFor\":[\"north\"],\"topN\":1}"))
    val afterOk = counting.openedHere
    ((stP ?= 500) :| ("pure status " + stP + ": " + textP.take(200))) &&
      ((stF ?= 500) :| ("fetching status " + stF + ": " + textF.take(200))) &&
      ((afterPure - before ?= 0) :| ("a failing pure report opened " + (afterPure - before) + " connections")) &&
      ((afterFetch - afterPure ?= 0) :| ("a failing fetching report opened " + (afterFetch - afterPure) + " connections")) &&
      ((stOk ?= 200) :| ("FetchFragments status " + stOk + ": " + textOk.take(300))) &&
      ((afterOk - beforeOk ?= 1) :| ("a scanning report opened " + (afterOk - beforeOk) + " connections"))
  }

  /** A literal relation of `rgKey`/`rgAmount` rows, with the three numbers
    * `headlineOf` must produce computed here in Scala.
    *
    * The ALL-NEGATIVE arm is explicit (R1): with the mixed arm alone about a
    * tenth of the values are negative, so 20 samples never held a non-empty
    * relation whose values are all below zero -- and that is exactly the shape
    * in which a `largest` folded from 0.0 rather than from a row reports a
    * number that is in no row. */
  private val headlineCase: Gen[(List[Double], String)] = {
    val mixed  = Gen.choose(0, 6).flatMap(n => Gen.listOfN(n, Gen.choose(-9999, 99999).map(_ / 8.0)))
    val allNeg = Gen.choose(1, 4).flatMap(n => Gen.listOfN(n, Gen.choose(-9999, -1).map(_ / 8.0)))
    Gen.frequency((3, mixed), (1, allNeg)).map { xs =>
      (xs, xs.zipWithIndex.map { case (x, i) => "{ rgKey = " + i + ", rgAmount = " + x + " }" }.mkString(", "))
    }
  }

  property("(fxl-headline) headlineOf's three numbers are the scanned rows'") = secure {
    val cases = TestDoc.samples(headlineCase, 20, 31337L)
    val bad = new ListBuffer[String]
    var empties = 0
    cases.foreach { case (xs, rows) =>
      if (xs.isEmpty) empties += 1
      val m = freshModule("RgHead")
      writeModule(m, "module " + m + " where\n\n" + fetchImports + "\n\n" +
                     "report : Int -> Fetch Node\n" +
                     "report p = headlineOf \"T\" \"everywhere\" rgAmount (mkRelation# (toList# [" + rows + "]))\n")
      val (st, text) = render(runner, m, params("1"))
      if (st != 200) bad += ("status " + st + ": " + text.take(300))
      else {
        val props = parsed(text).field(Wire.Root).flatMap(_.field("props")).getOrElse(Json.jNull)
        val wantCount = xs.length.toDouble
        val wantTotal = xs.foldLeft(0.0)(_ + _)
        // the maximum of the rows, and 0.0 only when there are none
        val wantLargest = if (xs.isEmpty) 0.0 else xs.max
        if (num(props.field("rowCount")) != Some(wantCount)) bad += ("rowCount " + props.nospaces + " for " + xs)
        else if (num(props.field("total")).map(t => math.abs(t - wantTotal) < 1e-9) != Some(true))
          bad += ("total " + props.nospaces + " for " + xs)
        else if (num(props.field("largest")).map(t => math.abs(t - wantLargest) < 1e-9) != Some(true))
          bad += ("largest " + props.nospaces + " for " + xs)
        else if (str(props.field("scope")) != Some("everywhere")) bad += ("scope " + props.nospaces)
      }
    }
    (bad.isEmpty :| (bad.length + " of " + cases.length + " wrong:\n" + bad.take(3).mkString("\n"))) &&
      ((empties >= 1) :| "no empty relation was generated: the 0-row case is untested") &&
      (cases.exists(c => c._1.nonEmpty && c._1.forall(_ < 0)) :|
        "no all-negative relation was generated: a `largest` folded from 0.0 would pass unseen") &&
      ((cases.count(_._1.length >= 2) >= 10) :| "too few multi-row cases")
  }

  property("(fx5) FetchFragments: three fragments, five scans, one document") = secure {
    val (st, text) = render(runner, "FetchFragments", params("{\"tabsFor\":[\"north\",\"south\"],\"topN\":2}"))
    if (st != 200) falsified :| ("status " + st + ": " + text.take(400))
    else {
      val root = parsed(text).field(Wire.Root).get
      val kids = root.field("children").map(_.arrayOrEmpty).getOrElse(Nil)
      val heads = kids.headOption.map(_.field("children").map(_.arrayOrEmpty).getOrElse(Nil)).getOrElse(Nil)
      val tabs = kids.lift(1).flatMap(_.field("tabs")).map(_.arrayOrEmpty).getOrElse(Nil)
      val running = tabs.headOption.flatMap(_.field("content")).map(c => rowMaps(rels(c).head)).getOrElse(Nil)
      val pie = tabs.lift(1).flatMap(_.field("content")).map(c => rowMaps(rels(c).head)).getOrElse(Nil)
      def headProps(i: Int) = heads.lift(i).flatMap(_.field("props")).getOrElse(Json.jNull)
      ((str(root.field("tag")) ?= Some("VFlow")) :| text.take(200)) &&
        ((heads.length ?= 2) :| ("headlines: " + heads.length)) &&
        // fragment 1, twice: north has 3 sales of 4350.75, south 2 of 2605.75
        ((str(headProps(0).field("scope")) ?= Some("north")) :| headProps(0).nospaces) &&
        ((num(headProps(0).field("rowCount")) ?= Some(3.0)) :| headProps(0).nospaces) &&
        ((num(headProps(0).field("total")) ?= Some(4350.75)) :| headProps(0).nospaces) &&
        ((num(headProps(1).field("rowCount")) ?= Some(2.0)) :| headProps(1).nospaces) &&
        ((num(headProps(1).field("total")) ?= Some(2605.75)) :| headProps(1).nospaces) &&
        // fragment 2: eight rows, the running total closing at the whole total
        ((running.length ?= 8) :| running.toString) &&
        ((running.flatMap(r => num(r.get("runTotal"))).max ?= 12682.0) :| running.toString) &&
        // fragment 3: two regions and an Other slice
        ((pie.flatMap(r => str(r.get("region"))).toSet ?= Set("north", "east", "Other")) :| pie.toString)
    }
  }

  // =====================================================================
  // (ip) J3h: ONE step interpreter.  The rows a `Fetch` asks for and the rows
  // a relation puts on the wire are read by the same driver (`Interp.run`),
  // so they are counted in one `WriteStats`, logged the same way, and fail
  // the same way.

  /** `render`, keeping the `WriteStats` the runner answered: what a `Call`, a
    * `Splice` and a `Token` each leave in `relations` is what (ip-stats) is
    * about, and nothing else in the suite looks at it. */
  def renderStats(r: Runner, module: String, body: String): (Int, String, Option[WriteStats]) = {
    val out = new java.lang.StringBuilder
    r.renderText(module, body, out) match {
      case Left(e)   => (e.status, e.body, None)
      case Right(st) => (200, out.toString, Some(st))
    }
  }

  /** A report with N scans and M wire relations: the scans are
    * `scanRelation`s of literal relations (1-5 rows each), and the widgets
    * that carry the wire relations follow them in the same `vflowF`.  So the
    * document is `{"tag":"VFlow","children":[<N leaf widgets>, <M relation
    * widgets>]}` and the wire relations sit at `$.children[N+j].props`. */
  final case class StatsCase(fetches: List[Rel], wires: List[Rel], dflt: Delivery, threshold: Option[Long]) {
    def source(module: String): String = {
      val leaves = fetches.zipWithIndex.map { case (r, i) =>
        "(scanRelation " + r.source + " (rows -> done (widget \"f" + i + "\" (map_List (x -> x ! rgKey) rows))))" }
      val widgets = wires.zipWithIndex.map { case (r, j) =>
        "(done (widget \"w" + j + "\" " + r.source + "))" }
      "module " + module + " where\n\n" + fetchImports + "\n\n" +
      "report : Int -> Fetch Node\nreport p = vflowF [ " +
      (leaves ++ widgets).mkString("\n                  , ") + " ]\n"
    }

    def body: String = {
      val data = List(
        Some("\"" + Request.Default + "\":\"" +
             (if (dflt == Delivery.Deferred) Wire.Deferred else Wire.Inline) + "\""),
        threshold.map(t => "\"" + Request.Threshold + "\":" + t)).flatten.mkString(",")
      "{\"" + Request.Params + "\":1,\"" + Request.Data + "\":{" + data + "}}"
    }

    /** What `WriteStats.relations` must be, as (path, delivery, rows).  The
      * fetch entries carry the rows the CONTINUATION received, which is every
      * row of the relation whatever `data.threshold` says: the threshold is
      * the wire's, not the report's (J3h decision 3). */
    def want: List[(String, String, Long)] =
      fetches.zipWithIndex.map { case (r, i) =>
        ("$.fetch[" + (i + 1) + "]", Delivery.Fetched.name, r.rows.length.toLong) } ++
      wires.zipWithIndex.map { case (r, j) =>
        val d = r.delivery(dflt, threshold)
        ("$.children[" + (fetches.length + j) + "].props", d.name,
         if (d == Delivery.Deferred) 0L else r.rows.length.toLong) }
  }

  private val statsCase: Gen[StatsCase] = for {
    nf <- Gen.choose(1, 3)
    fs <- Gen.listOfN(nf, relGen.map(r => Rel(r.cols, r.rows, "bare")))
    nw <- Gen.choose(1, 3)
    ws <- Gen.listOfN(nw, relGen)
    d  <- Gen.oneOf(Delivery.Inline: Delivery, Delivery.Deferred: Delivery)
    t  <- Gen.frequency((2, Gen.const(None: Option[Long])), (1, Gen.choose(0L, 4L).map(x => Some(x))))
  } yield StatsCase(fs, ws, d, t)

  property("(ip-stats) one WriteStats: a $.fetch[n] entry per scan in scan order, then the wire relations in document order") = secure {
    val cases = TestDoc.samples(statsCase, 16, 60607L)
    val bad = new ListBuffer[String]
    val arms = new ListBuffer[String]
    var scans = 0
    var fetchRows = 0L
    var multi = 0
    cases.foreach { c =>
      val m = freshModule("RgStats")
      writeModule(m, c.source(m))
      val (st, text, stats) = renderStats(runner, m, c.body)
      scans += c.fetches.length
      fetchRows += c.fetches.map(_.rows.length.toLong).sum
      if (c.fetches.length >= 2) multi += 1
      arms ++= c.wires.map(r => r.delivery(c.dflt, c.threshold).name)
      if (st != 200) bad += ("status " + st + ": " + text.take(300) + "\n" + c.source(m))
      else stats match {
        case None => bad += "a 200 with no stats"
        case Some(s) =>
          val got = s.relations.map(rs => (rs.path, rs.delivery.name, rs.rows))
          val fetched = s.relations.take(c.fetches.length)
          val wire = s.relations.drop(c.fetches.length)
          if (got != c.want) bad += ("relations\n want " + c.want + "\n got  " + got)
          else if (fetched.exists(_.bytes != 0L)) bad += ("a fetch scan wrote bytes: " + fetched)
          else if (wire.exists(_.bytes <= 0L)) bad += ("a wire relation wrote no bytes: " + wire)
          else if (s.bytes != text.getBytes("UTF-8").length.toLong)
            bad += ("stats bytes " + s.bytes + " vs " + text.getBytes("UTF-8").length)
      }
    }
    val seen = arms.toList.toSet
    println("  (ip-stats) " + cases.length + " reports, " + scans + " fetch scans over " + fetchRows +
            " rows, " + arms.length + " wire relations " + arms.toList.groupBy(identity).map(p => p._1 + "x" + p._2.length).toList.sorted.mkString(" "))
    (bad.isEmpty :| (bad.length + " of " + cases.length + " wrong:\n" + bad.take(2).mkString("\n---\n"))) &&
      ((multi >= 6) :| ("only " + multi + " reports scanned more than once: the order of the fetch entries is barely tested")) &&
      ((fetchRows >= 30L) :| ("only " + fetchRows + " rows were fetched in all")) &&
      ((seen == Set(Wire.Inline, Wire.Deferred)) :| ("wire deliveries seen: " + seen))
  }

  property("(ip-fail) a scan that throws is one `cannot write <path>` 500: $.fetch[n] for a fetch scan, the document path for a wire relation") = secure {
    val boom = "(mkRelation# (toList# [{ rgKey = 0, rgName = \"" + RecordingScanner.Boom + "\" }]))"
    val good = "(mkRelation# (toList# [{ rgKey = 1, rgName = \"Lf01\" }]))"
    def leaf(r: String) = "(scanRelation " + r + " (rows -> done (widget \"leaf\" (map_List (x -> x ! rgName) rows))))"
    def mod(name: String, body: String) =
      "module " + name + " where\n\n" + fetchImports + "\n\nreport : Int -> Fetch Node\nreport p = " + body + "\n"
    // the SECOND scan of the report throws
    val mf = freshModule("RgBoomF")
    writeModule(mf, mod(mf, "vflowF [ " + leaf(good) + ", " + leaf(boom) + " ]"))
    val (stF, textF) = render(orderRunner, mf, params("1"))
    val eF = parsed(textF).field("error").getOrElse(Json.jNull)
    // ...and a WIRE relation that throws, after a fetch scan that did not
    val mw = freshModule("RgBoomW")
    writeModule(mw, mod(mw, "vflowF [ " + leaf(good) + ", done (widget \"w\" " + boom + ") ]"))
    val (stW, textW) = render(orderRunner, mw, params("1"))
    val eW = parsed(textW).field("error").getOrElse(Json.jNull)
    def msg(e: Json) = e.field("message").flatMap(_.string).getOrElse("")
    def at(e: Json) = e.field("path").flatMap(_.string).getOrElse("")
    ((stF ?= 500) :| ("fetch-scan status " + stF + ": " + textF.take(300))) &&
      ((at(eF) ?= "$.fetch[2]") :| ("fetch-scan path " + textF.take(300))) &&
      ((msg(eF).startsWith("cannot write $.fetch[2]: ") && msg(eF).contains(RecordingScanner.Boom)) :|
        ("fetch-scan message " + msg(eF))) &&
      ((stW ?= 500) :| ("wire-scan status " + stW + ": " + textW.take(300))) &&
      ((at(eW) ?= "$.children[1].props") :| ("wire-scan path " + textW.take(300))) &&
      ((msg(eW).startsWith("cannot write $.children[1].props: ")) :| ("wire-scan message " + msg(eW)))
  }

  property("(ip-stack) a report of 2,000 sequential scans renders: the driver's work list, not the JVM stack") = secure {
    val n = 2000
    val m = freshModule("RgDeep")
    writeModule(m, "module " + m + " where\n\n" + fetchImports + "\nimport Bool\nimport Eq\n\n" +
      "one : Fetch Node\n" +
      "one = scanRelation (mkRelation# (toList# [{ rgKey = 1, rgName = \"Lf00\" }]))\n" +
      "                   (rows -> done (widget \"leaf\" (map_List (x -> x ! rgKey) rows)))\n\n" +
      "deep : Int -> Fetch Node\n" +
      "deep k = if (k == 0) one (bind_Fetch one (x -> deep (k - 1)))\n\n" +
      "report : Int -> Fetch Node\nreport p = deep " + (n - 1) + "\n")
    val t0 = System.nanoTime
    val (st, text, stats) = renderStats(runner, m, params("1"))
    val ms = (System.nanoTime - t0) / 1000000
    val paths = stats.map(_.relations.map(_.path)).getOrElse(Nil)
    println("  (ip-stack) " + n + " sequential scans in " + ms + " ms, " + paths.length + " fetch entries")
    ((st ?= 200) :| ("status " + st + ": " + text.take(300))) &&
      ((paths.length ?= n) :| ("relations " + paths.length)) &&
      ((paths.take(3) ?= List("$.fetch[1]", "$.fetch[2]", "$.fetch[3]")) :| paths.take(3).toString) &&
      ((paths.lastOption ?= Some("$.fetch[" + n + "]")) :| paths.lastOption.toString) &&
      (stats.exists(_.relations.forall(_.rows == 1L)) :| "a scan did not deliver its one row")
  }

  // =====================================================================
  // (iso) a Runner boot and a fixture session in one JVM

  private val isoCounter = new java.util.concurrent.atomic.AtomicInteger(0)

  /** A `Runner` boots a SECOND, independent `SessionEnv` in the shared test
    * JVM -- its own `Lib.preamble`, its own module roots, its own `Supply` --
    * beside every `ErmineFixture`, and `Session.depCache` and the
    * `DataConDecl` registry are PROCESS-GLOBAL.  This pins that a fixture can
    * still load a module and type-check an expression afterwards, and that it
    * finishes in a BOUNDED time rather than diverging: the point is to fail
    * loudly instead of wedging a `core/test` run, so the work happens on a
    * daemon thread that is joined with a deadline.
    *
    * WHY `loadNamed` AND NOT `loadStatements` (changed 2026-09-17, M2).  The first version
    * loaded through `ErmineFixture.loadStatements`, which names every program `module Test`
    * and therefore takes the process-global `ErmineFixture.literalLock`
    * (`TestErmine.scala:152`) to serialise the shared dep-cache key.  `TestDateAndScan`'s
    * `underZone` and its B1 refutation hold that same lock through library-scale loads, and
    * ScalaCheck runs the suites on a pool -- so in a full `core/test` this deadline bounded
    * the QUEUE, not the check, and it expired at 180,004 ms with nothing wrong
    * (`tracker/satterm/SUBSUME-M2.md` §4.2: green alone 17/17, green with the contending
    * suites in one JVM, green on the next full run).  That is exactly the red S2 found inside
    * its own first deadline pin and wrote down as a rule -- *"a deadline pin that wraps
    * `loadStatements` is measuring lock contention"*, `tracker/satterm/SUBSUME-STAGE2.md`
    * §2.3.  `loadNamed` gives this pin its own module name and takes no lock, so the 180 s
    * bounds the load and the type-check.  The assertions are unchanged. */
  property("(iso) after a Runner has booted, a fixture session still type-checks, within a bound") = secure {
    val bootedOk = runner.bootFailure.isEmpty && runner.loadedModules.contains("Layout.Doc")
    val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
    // a module name is a PROCESS-global dep-cache key; this property is evaluated once, but
    // count anyway so that a re-evaluation could never collide with itself
    val mod = "IsoUse" + isoCounter.incrementAndGet()
    val answer = new java.util.concurrent.atomic.AtomicReference[String]("did not finish")
    val t0 = System.currentTimeMillis
    val th = new Thread(new Runnable {
      def run(): Unit = answer.set(
        try {
          fx.session { implicit env =>
            fx.loadNamed(mod, "import Layout.Scan as LS\n\nisoUse = removeK_LS\n")
            fx.typeOf("isoUse", Map(mod -> fx.all))
          }
          "ok"
        } catch { case e: Throwable => "threw " + e })
    })
    th.setDaemon(true)
    th.start()
    th.join(180000L)
    val ms = System.currentTimeMillis - t0
    (bootedOk :| ("the runner did not boot: " + runner.bootFailure)) &&
      ((answer.get ?= "ok") :| ("a fixture type-check after a Runner boot: " + answer.get + ", " + ms + " ms"))
  }

  // =====================================================================
  // (sql) the two DB-layer tickets J3b handed to this stage

  /** Round-trip random relations with a NULLABLE GUID column through the
    * SQLite scanner.  Before the fix in `SqlEmitter.EmitUuid_Strings.getUuid`
    * this threw a NullPointerException on the first NULL, because
    * `SqlExecution.nextRecord` builds the cell before it asks `rs.wasNull`. */
  property("(sql-guid) a NULL in a GUID column reads back as null, not an NPE") =
    forAllNoShrink(Gen.listOfN(6, Gen.frequency((1, Gen.const(None: Option[java.util.UUID])),
                                                (1, Gen.const(()).map(_ => Some(java.util.UUID.randomUUID)))))) {
      (us: List[Option[java.util.UUID]]) =>
        val S = Scanners.SQLite(SMEnv.dummySmenv)
        val R = Runners.liteDB
        val recs = us.zipWithIndex.map { case (u, i) =>
          Map("gk" -> IntExpr(false, i),
              "gu" -> u.map(x => UuidExpr(true, x): PrimExpr).getOrElse(NullExpr(PrimT.UuidT(true)))): Record
        }
        val ext = com.clarifi.reporting.relational.ExtRel(
          com.clarifi.reporting.relational.SmallLit(
            scalaz.NonEmptyList.nel(recs.head, scalaz.IList.fromList(recs.tail))), "")
        val data = Doc.Data(ext, List(Doc.Column("gk", PrimT.IntT(false)), Doc.Column("gu", PrimT.UuidT(true))),
                            Nil, Delivery.Inline, "$")
        val sb = new java.lang.StringBuilder
        val cache = new MemoryPlanCache(60000L, 8, WriteConfig.systemClock, new java.security.SecureRandom)
        val res = try Right(R.run(Write.doc[DB](data, sb, WriteConfig(), cache)(S, Guard.db)))
                  catch { case e: Throwable => Left(e.toString) }
        res match {
          case Left(m) => falsified :| ("the scan failed: " + m)
          case Right(_) =>
            val rows = parsed(sb.toString).field(Wire.Rows).map(_.arrayOrEmpty).getOrElse(Nil)
            val got = rows.map { r =>
              val a = r.arrayOrEmpty
              (a.head.number.flatMap(_.toInt).getOrElse(-1), a(1).string)
            }.sortBy(_._1)
            val want = us.zipWithIndex.map { case (u, i) => (i, u.map(_.toString)) }
            (got ?= want) :| ("rows " + sb.toString)
        }
    }

  /** A scan that throws ON ITS OWN -- not a row the encoder refused -- must
    * still be torn down.  `EffectfulProcedure.withDriver` had no `finally`
    * around `teardown()`, so the result set and statement leaked. */
  property("(sql-teardown) a procedure whose machine throws is still torn down") =
    forAllNoShrink(Gen.choose(0, 5)) { (at: Int) =>
      val torn = new java.util.concurrent.atomic.AtomicInteger(0)
      val boom = new RuntimeException("boom")
      val proc = new com.clarifi.reporting.relational.EffectfulProcedure[Int] {
        type K = Int => Any
        def machine = com.clarifi.machines.Machine.ProcessCategory.id
        def setup: (com.clarifi.machines.Driver[scalaz.Id.Id, K], () => Unit) = {
          var i = 0
          (com.clarifi.machines.Driver.Id((k: Int => Any) => { i += 1; Some(k(i)) }),
           () => { torn.incrementAndGet(); () })
        }
      }
      val thrown = try {
        proc.foldLeftM(0)((acc: Int, x: Int) => if (x > at) throw boom else acc + x)
        None
      } catch { case e: Throwable => Some(e) }
      ((thrown.map(_.getMessage) ?= Some("boom")) :| "the fold did not throw") &&
        ((torn.get ?= 1) :| ("teardowns " + torn.get + ": the scan leaked its result set"))
    }
}
