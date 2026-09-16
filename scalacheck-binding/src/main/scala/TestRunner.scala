package com.clarifi.reporting

import argonaut.{ Json, Parse }
import com.clarifi.reporting.backends.{ DB, Runners, Scanners }
import com.clarifi.reporting.ermine.json._
import com.clarifi.reporting.relational.SMEnv
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
      ("RgBadP",   "report : (Int -> Int) -> Node\nreport _ = widget \"w\" 1\n", "function"))
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
  // (iso) a Runner boot and a fixture session in one JVM

  /** A `Runner` boots a SECOND, independent `SessionEnv` in the shared test
    * JVM -- its own `Lib.preamble`, its own module roots, its own `Supply` --
    * beside every `ErmineFixture`, and `Session.depCache` and the
    * `DataConDecl` registry are PROCESS-GLOBAL.  This pins that a fixture can
    * still load a module and type-check an expression afterwards, and that it
    * finishes in a BOUNDED time rather than diverging: the point is to fail
    * loudly instead of wedging a `core/test` run, so the work happens on a
    * daemon thread that is joined with a deadline. */
  property("(iso) after a Runner has booted, a fixture session still type-checks, within a bound") = secure {
    val bootedOk = runner.bootFailure.isEmpty && runner.loadedModules.contains("Layout.Doc")
    val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
    val answer = new java.util.concurrent.atomic.AtomicReference[String]("did not finish")
    val t0 = System.currentTimeMillis
    val th = new Thread(new Runnable {
      def run(): Unit = answer.set(
        try {
          fx.session { implicit env =>
            fx.loadStatements("import Layout.Scan as LS\n\nisoUse = removeK_LS\n", Map("Test" -> fx.all))
            fx.typeOf("isoUse", Map("Test" -> fx.all))
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
