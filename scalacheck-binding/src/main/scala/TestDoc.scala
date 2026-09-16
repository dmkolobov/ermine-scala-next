package com.clarifi.reporting

import com.clarifi.reporting.ermine.{ Runtime, Rel, Global, Bottom }
import com.clarifi.reporting.ermine.json.{ Doc, DocJson, Write, WriteConfig, WriteFailure, WriteStats, PlanCache,
                                           MemoryPlanCache, Delivery, Encode, ArgonautJson, JsonBuilder, Wire, Rows, Guard }
import com.clarifi.reporting.ermine.session.Session
import com.clarifi.reporting.relational.{ Ext, ExtRel, ExtMem, SmallLit, RelEmpty, Table, Scanner, SMEnv, Relation, Mem,
                                          EffectfulProcedure }
import com.clarifi.reporting.backends.{ DB, Scanners, ThreadLocalRunDB }
import com.clarifi.reporting.PrimT._
import com.clarifi.machines.{ Driver, Machine, Process }

import scalaz.{ Monoid, NonEmptyList, IList }
import scalaz.Id.Id

import org.scalacheck._
import Prop.{ Result => _, _ }
import Arbitrary.arbitrary
import argonaut.{ Json, Parse }

import scala.collection.mutable.ListBuffer

/** Stage J3b (tracker/json-stage3/brief-J3b-docwriter.md): the document types
  * (`modules/Layout/Doc.e`), the document tree (`json/Doc.scala`), the writer
  * and its row encoder (`json/Write.scala`) and the deferred-token cache
  * (`json/PlanCache.scala`).
  *
  * Properties (a)..(g) are the brief's; every one draws random headers,
  * records, documents or command sequences.  The pins beside them fix one
  * documented corner each.  Anti-vacuity: (a) mutates the written document and
  * requires the comparator to reject it, and (a-cov) runs (a)'s checker over a
  * fixed sample and requires every column type, nulls, empty relations and the
  * nasty strings to have occurred; (c) and (d) require every delivery outcome
  * to have occurred in their fixed samples.
  */
object TestDoc extends Properties("JSON document writer (J3b)") {
  private lazy val fixture = ErmineFixture()
  import fixture.{ session, loadStatements, all, ImportSpec, supply, con }

  // =====================================================================
  // generators: headers and records

  private val primCtors: List[Boolean => PrimT] = List(
    b => IntT(b), b => ByteT(b), b => ShortT(b), b => LongT(b), b => DoubleT(b),
    b => StringT(0, b), b => BooleanT(b), b => DateT(b), b => TimestampT(b), b => UuidT(b))

  private def primGen(ctors: List[Boolean => PrimT]): Gen[PrimT] =
    for { c <- Gen.oneOf(ctors); n <- Gen.oneOf(true, false) } yield c(n)

  val nasty: List[String] =
    List("", "\"", "\\", "\u0000", "\u0001", "\u001f", "\b\f\n\r\t", "\u007f", "\u2028", "\u2029", "/",
         "\u00e9", "\u65e5\u672c", "\uD83D\uDE00", "\uD800", "\uDC00x", "</script>", "a\"b\\c")

  private val stringGen: Gen[String] = Gen.frequency(
    (3, Gen.choose(0, 4).flatMap(k => Gen.listOfN(k, Gen.oneOf(nasty))).map(_.mkString)),
    (2, Gen.alphaNumStr),
    (1, arbitrary[String]))

  private val doubleGen: Gen[Double] = Gen.frequency(
    (1, Gen.oneOf(0.0, -0.0, 1.0, -1.5, Double.MaxValue, Double.MinValue, Double.MinPositiveValue,
                  1e-300, 1e21, 123456789.125, 0.1)),
    (3, arbitrary[Double].suchThat(d => !d.isNaN && !d.isInfinite)))

  /** Milliseconds from year 1 to year 9999, weighted towards the corners:
    * before 1970, the epoch, leap days, sub-second parts. */
  private val msGen: Gen[Long] = Gen.frequency(
    (1, Gen.oneOf(0L, -1L, -86400000L, -2208988800000L, 951782400000L, -62135596800000L, 253402300799999L, 999L)),
    (3, Gen.choose(-62135596800000L, 253402300799999L)))

  def exprGen(p: PrimT, strs: Gen[String], dbls: Gen[Double] = doubleGen): Gen[PrimExpr] = {
    val n = p.nullable
    val v: Gen[PrimExpr] = p match {
      case IntT(_)       => Gen.frequency((1, Gen.oneOf(0, Int.MinValue, Int.MaxValue)), (3, arbitrary[Int])).map(x => IntExpr(n, x))
      case ByteT(_)      => arbitrary[Byte].map(x => ByteExpr(n, x))
      case ShortT(_)     => arbitrary[Short].map(x => ShortExpr(n, x))
      case LongT(_)      => Gen.frequency((1, Gen.oneOf(0L, Long.MinValue, Long.MaxValue)), (3, arbitrary[Long])).map(x => LongExpr(n, x))
      case DoubleT(_)    => dbls.map(x => DoubleExpr(n, x))
      case StringT(_, _) => strs.map(x => StringExpr(n, x))
      case BooleanT(_)   => arbitrary[Boolean].map(x => BooleanExpr(n, x))
      case DateT(_)      => msGen.map(ms => DateExpr(n, new java.util.Date(ms)))
      case TimestampT(_) => msGen.map(ms => TimestampExpr(n, new java.sql.Timestamp(ms)))
      case UuidT(_)      => Gen.zip(arbitrary[Long], arbitrary[Long]).map(p => UuidExpr(n, new java.util.UUID(p._1, p._2)))
    }
    if (n) Gen.frequency((1, Gen.const(NullExpr(p))), (3, v)) else v
  }

  /** A generated relation: its header in generation (not sorted) order and
    * its records. */
  final case class Rel0(header: List[(String, PrimT)], records: List[Record]) {
    def sorted: List[(String, PrimT)] = header.sortBy(_._1)
    def ext: Ext[Nothing, Nothing] =
      if (records.isEmpty) ExtRel(RelEmpty(header.toMap), "")
      else ExtRel(SmallLit(NonEmptyList.nel(records.head, IList.fromList(records.tail))), "")
  }

  private val anyName: Gen[String] = Gen.frequency(
    (4, Gen.choose(1, 6).flatMap(k => Gen.listOfN(k, Gen.alphaNumChar)).map(_.mkString)),
    (1, stringGen.suchThat(_.nonEmpty)))

  /** A lower-case identifier: what a SQL column can be called. */
  private val sqlName: Gen[String] =
    Gen.choose(1, 5).flatMap(k => Gen.listOfN(k, Gen.alphaLowerChar)).map("c" + _.mkString)

  def relGen(names: Gen[String], ctors: List[Boolean => PrimT], maxCols: Int, maxRows: Int,
             strs: Gen[String] = stringGen, dbls: Gen[Double] = doubleGen): Gen[Rel0] =
    for {
      k     <- Gen.choose(1, maxCols)
      ns    <- Gen.listOfN(k, names).map(_.distinct)
      ps    <- Gen.listOfN(ns.length, primGen(ctors))
      n     <- Gen.frequency((1, Gen.const(0)), (6, Gen.choose(1, maxRows)))
      recs  <- Gen.listOfN(n, Gen.sequence[List[(String, PrimExpr)], (String, PrimExpr)](
                 ns.zip(ps).map { case (c, p) => exprGen(p, strs, dbls).map(e => (c, e)) }).map(_.toMap))
    } yield Rel0(ns.zip(ps), recs)

  /** Draw `n` samples of `g` from fixed seeds (a property that wants a fixed
    * case count and a coverage check over exactly those cases). */
  def samples[A](g: Gen[A], n: Int, seed0: Long): List[A] = {
    val p = Gen.Parameters.default.withSize(40)
    (0 until n).toList.flatMap(i => g.apply(p, rng.Seed(seed0 + i)))
  }

  // =====================================================================
  // a scanner over literal plans

  /** A `Scanner[Id]` that yields exactly the records a literal plan holds, in
    * order, through the same `EffectfulProcedure` shape the SQL scanner uses
    * (one driver pull per record), counting pulls per scan and recording the
    * scans whose TEARDOWN ran -- `withDriver` runs it in a `finally` as of
    * J3c, and the sink's `Stop` exit is what makes a refused row end the scan
    * cleanly rather than unwind through it (the SQL scanner closes its result
    * set and statement there).  A `Table` plan is a scan
    * that THROWS; `generated` supplies records for marked plans lazily. */
  final class ListScanner extends Scanner[Id]()(scalaz.Id.id) {
    val scans = new ListBuffer[(Ext[Nothing, Nothing], Long)]
    val teardowns = new ListBuffer[Ext[Nothing, Nothing]]
    var generated: PartialFunction[Ext[Nothing, Nothing], () => Iterator[Record]] = PartialFunction.empty

    private def records(r: Ext[Nothing, Nothing]): Iterator[Record] =
      if (generated.isDefinedAt(r)) generated(r)()
      else r match {
        case ExtRel(SmallLit(tups), _)           => tups.list.toList.iterator
        case ExtRel(RelEmpty(_), _)              => Iterator.empty
        case ExtMem(relational.EmptyRel(_))      => Iterator.empty
        case ExtRel(Table(_, TableName(n, _, _)), _) => throw new RuntimeException("the scan of " + n + " failed")
        case other                               => sys.error("the test scanner cannot scan " + other)
      }

    def scanExt[A: Monoid](r: Ext[Nothing, Nothing], f: Process[Record, A], order: List[(String, SortOrder)]): Id[A] = {
      val it = records(r)
      var pulled = 0L
      val proc = new EffectfulProcedure[Record] {
        type K = Record => Any
        def machine = Machine.ProcessCategory.id[Record]
        def setup = (Driver.Id((k: Record => Any) => if (it.hasNext) { pulled += 1; Some(k(it.next())) } else None),
                     () => { teardowns += r; () })
      }
      try (proc andThen f).execute
      finally scans += ((r, pulled))
    }
    def scanRel[A: Monoid](r: Relation[Nothing, Nothing], f: Process[Record, A], order: List[(String, SortOrder)]): Id[A] =
      scanExt(ExtRel(r, ""), f, order)
    def scanMem[A: Monoid](m: Mem[Nothing, Nothing], f: Process[Record, A], order: List[(String, SortOrder)]): Id[A] =
      scanExt(ExtMem(m), f, order)
  }

  private def bigCache(): MemoryPlanCache =
    new MemoryPlanCache(60000L, 100000, () => System.currentTimeMillis, new java.security.SecureRandom)

  private def dataOf(r: Rel0, delivery: Delivery, path: String): Doc.Data =
    new DocJson(Doc.noHints).rel(path, Rel(r.ext), delivery) match {
      case Right(d: Doc.Data) => d
      case other              => sys.error("DocJson.rel: " + other)
    }

  // =====================================================================
  // comparing JSON

  /** Structural equality with object keys IN ORDER and numbers compared as
    * exact decimals (the writer prints a double as `Double.toString`, argonaut
    * keeps its own number representation). */
  def jsonEq(a: Json, b: Json): Boolean = (a.number, b.number) match {
    case (Some(x), Some(y)) => x.toBigDecimal.compare(y.toBigDecimal) == 0
    case _ =>
      if (a.isArray && b.isArray) {
        val xs = a.arrayOrEmpty; val ys = b.arrayOrEmpty
        xs.length == ys.length && xs.zip(ys).forall(p => jsonEq(p._1, p._2))
      } else if (a.isObject && b.isObject) {
        val xs = a.obj.get.toList; val ys = b.obj.get.toList
        xs.length == ys.length && xs.zip(ys).forall { case ((k1, v1), (k2, v2)) => k1 == k2 && jsonEq(v1, v2) }
      } else a == b
  }

  /** What `Encode` makes of a cell: the `PrimExpr` lifted the way the runtime
    * lifts it. */
  def encodedCell(e: PrimExpr): Json =
    Encode.toArgonaut(Runtime.fromPrimExpr(e)).fold(err => sys.error(err.report), identity)

  def columnsJson(cols: List[(String, PrimT)]): Json =
    Json.array(cols.map { case (n, p) =>
      Json.obj(Wire.Name -> Json.jString(n), Wire.Type -> Json.jString(Wire.columnType(p)),
               Wire.Nullable -> Json.jBool(p.nullable)) }: _*)

  /** The inline object for `r`, built with `Encode` rather than the row
    * encoder. */
  def expectedInline(r: Rel0): Json = {
    val cols = r.sorted
    Json.obj(
      Wire.Kind     -> Json.jString(Wire.Inline),
      Wire.Columns  -> columnsJson(cols),
      Wire.Rows     -> Json.array(r.records.map(rec => Json.array(cols.map(c => encodedCell(rec(c._1))): _*)): _*),
      Wire.RowCount -> Json.jNumber(r.records.length))
  }

  private val tokenRe = "^[A-Za-z0-9_-]{22}$".r
  private val instantRe = "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$".r

  /** A deferred object for `r`: the right keys in order, the columns, a
    * well-formed token and expiry. */
  def deferredOk(r: Rel0, j: Json): Option[String] = {
    val keys = j.objectFieldsOrEmpty
    if (keys != List(Wire.Kind, Wire.Columns, Wire.Token, Wire.Expires)) Some("deferred keys " + keys)
    else if (j.field(Wire.Kind).flatMap(_.string) != Some(Wire.Deferred)) Some("kind " + j.field(Wire.Kind))
    else if (!jsonEq(j.field(Wire.Columns).get, columnsJson(r.sorted))) Some("deferred columns " + j.nospaces)
    else if (!j.field(Wire.Token).flatMap(_.string).exists(t => tokenRe.findFirstIn(t).isDefined)) Some("token " + j.nospaces)
    else if (!j.field(Wire.Expires).flatMap(_.string).exists(t => instantRe.findFirstIn(t).isDefined)) Some("expires " + j.nospaces)
    else None
  }

  // =====================================================================
  // (a) the row encoder agrees with Encode

  /** Write one bare relation through the test scanner and check the text
    * against `Encode`.  Returns a complaint or None. */
  def checkA(r: Rel0): Option[String] = {
    val S = new ListScanner
    val data = dataOf(r, Delivery.ByRequest, "$")
    val sb = new java.lang.StringBuilder
    val stats = Write.doc[Id](data, sb, WriteConfig(), bigCache())(S, Guard.id)
    val text = sb.toString
    Parse.parse(text) match {
      case Left(e) => Some("unparseable: " + e + "\n" + text.take(400))
      case Right(j) =>
        val want = expectedInline(r)
        if (data.columns.map(c => (c.name, c.prim)) != r.sorted) Some("Data.columns " + data.columns + " vs " + r.sorted)
        else if (!jsonEq(want, j)) Some("mismatch\n want " + want.nospacesWithOrder.take(600) + "\n got  " + text.take(600))
        else if (stats.relations.map(_.rows) != List(r.records.length.toLong)) Some("stats rows " + stats)
        else if (stats.bytes != text.getBytes("UTF-8").length.toLong) Some("stats bytes " + stats.bytes + " vs " + text.getBytes("UTF-8").length)
        else if (r.records.nonEmpty) {
          // anti-vacuity: the comparator must see one changed cell
          val mutated = j.withObject(o => o + (Wire.Rows, Json.array(
            (Json.array((Json.jString("mutant" + j.nospaces.length) :: j.field(Wire.Rows).get.arrayOrEmpty.head.arrayOrEmpty.tail): _*)
              :: j.field(Wire.Rows).get.arrayOrEmpty.tail): _*)))
          if (jsonEq(want, mutated)) Some("the comparator accepted a mutated cell") else None
        } else None
    }
  }

  private val relA: Gen[Rel0] = relGen(anyName, primCtors, 8, 200)

  property("(a) rows written through a scanner equal Encode of the records, all ten column types") =
    forAllNoShrink(relA) { (r: Rel0) =>
      checkA(r) match {
        case None    => proved
        case Some(m) => falsified :| m
      }
    }

  property("(a-cov) the (a) checker over 300 fixed cases saw every type, nulls, empties and the nasty strings") = secure {
    val cases = samples(relA, 300, 20260916L)
    val bad = cases.flatMap(checkA)
    val prims = cases.flatMap(_.header.map(_._2.name)).toSet
    val nulls = cases.exists(_.records.exists(_.values.exists(_.isNull)))
    val empty = cases.exists(_.records.isEmpty)
    val strs = cases.flatMap(_.records.flatMap(_.values.collect { case s: StringExpr => s.value })).mkString
    val missingNasty = nasty.filter(_.nonEmpty).filterNot(strs.contains)
    (bad.isEmpty :| bad.take(2).mkString("\n")) &&
      ((prims == Set("Int", "Byte", "Short", "Long", "Double", "String", "Bool", "Date", "Timestamp", "UUID")) :| ("types " + prims)) &&
      (nulls :| "no null") && (empty :| "no empty relation") &&
      (missingNasty.isEmpty :| ("strings never drawn: " + missingNasty.map(s => s.map(c => "\\u%04x".format(c.toInt)).mkString)))
  }

  property("(a-pin) the wire spelling of one relation, byte for byte") = secure {
    val r = Rel0(List("b" -> StringT(0, true), "a" -> IntT(false), "c" -> LongT(false)),
                 List(Map("a" -> IntExpr(false, 1), "b" -> NullExpr(StringT(0, true)), "c" -> LongExpr(false, 9007199254740993L)),
                      Map("a" -> IntExpr(false, 2), "b" -> StringExpr(true, "x\u2028\"y"), "c" -> LongExpr(false, -1L))))
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(dataOf(r, Delivery.Inline, "$.root")), sb, WriteConfig(), bigCache())(new ListScanner, Guard.id)
    sb.toString ?= ("{\"version\":1,\"settings\":{},\"root\":" +
      "{\"kind\":\"inline\",\"columns\":[{\"name\":\"a\",\"type\":\"Int\",\"nullable\":false}," +
      "{\"name\":\"b\",\"type\":\"String\",\"nullable\":true},{\"name\":\"c\",\"type\":\"Long\",\"nullable\":false}]," +
      "\"rows\":[[1,null,\"9007199254740993\"],[2,\"x\\u2028\\\"y\",\"-1\"]],\"rowCount\":2}}")
  }

  property("(a-pin) Date and Timestamp cells use Encode's formats; a DateExpr is a date even around a Timestamp") = secure {
    val ts = new java.sql.Timestamp(-86399999L) // 1969-12-31T00:00:00.001Z
    def cell(e: PrimExpr): String = { val sb = new java.lang.StringBuilder; Rows.cell(sb, e, "c"); sb.toString }
    (cell(DateExpr(false, new java.util.Date(-86399999L))) ?= encodedCell(DateExpr(false, new java.util.Date(-86399999L))).nospaces) &&
    (cell(TimestampExpr(false, ts)) ?= encodedCell(TimestampExpr(false, ts)).nospaces) &&
    (cell(TimestampExpr(false, ts)) ?= "\"1969-12-31T00:00:00.001Z\"") &&
    // the decision: the column says Date, so the cell is a date (Encode would print the timestamp)
    (cell(DateExpr(false, ts)) ?= "\"1969-12-31\"")
  }

  property("(a-pin) the Double cells: -0.0 cannot reach the encoder, and the exponent form is JSON") = secure {
    def cell(e: PrimExpr): String = { val sb = new java.lang.StringBuilder; Rows.cell(sb, e, "c"); sb.toString }
    val neg = DoubleExpr(false, -0.0)
    // `DoubleExpr.apply` tests `value == 0.0`, which is TRUE for -0.0, so the
    // canonical +0.0 instance comes back: no `PrimExpr` can carry a negative zero
    (java.lang.Double.doubleToRawLongBits(neg.value) ?= 0L) &&
      (cell(neg) ?= "0.0") &&
      (cell(DoubleExpr(false, 1e21)) ?= "1.0E21") &&
      (cell(DoubleExpr(false, -1.5)) ?= "-1.5") &&
      (cell(DoubleExpr(false, Double.MinPositiveValue)) ?= "4.9E-324") &&
      // what the encoder would write if a -0.0 ever did arrive (JSON keeps the sign)
      ({ val sb = new java.lang.StringBuilder; sb.append(-0.0); sb.toString } ?= "-0.0")
  }

  // =====================================================================
  // (b) SQLite, one connection

  /** A `Run[DB]` over fresh in-memory SQLite connections that counts them. */
  final class CountingRun extends ThreadLocalRunDB {
    val opened = new java.util.concurrent.atomic.AtomicInteger(0)
    protected def freshResource[A](a: java.sql.Connection => A): A = {
      Class.forName("org.sqlite.JDBC")
      val conn = java.sql.DriverManager.getConnection("jdbc:sqlite::memory:")
      opened.incrementAndGet()
      try a(conn) finally conn.close()
    }
  }

  /** A `Scanner[DB]` that records the connection and plan of every scan. */
  final class RecordingScanner(inner: Scanner[DB]) extends Scanner[DB]()(inner.M) {
    val seen = new ListBuffer[(java.sql.Connection, Ext[Nothing, Nothing])]
    def scanExt[A: Monoid](r: Ext[Nothing, Nothing], f: Process[Record, A], order: List[(String, SortOrder)]): DB[A] =
      (c: java.sql.Connection) => { seen += ((c, r)); inner.scanExt(r, f, order).apply(c) }
    def scanRel[A: Monoid](r: Relation[Nothing, Nothing], f: Process[Record, A], order: List[(String, SortOrder)]): DB[A] =
      scanExt(ExtRel(r, ""), f, order)
    def scanMem[A: Monoid](m: Mem[Nothing, Nothing], f: Process[Record, A], order: List[(String, SortOrder)]): DB[A] =
      scanExt(ExtMem(m), f, order)
  }

  /** What (b) may draw, measured by (b-sql) on this SQLite build:
    *  - every column type, NULLABLE GUID INCLUDED since J3c fixed
    *    `SqlEmitter.EmitUuid_Strings.getUuid` (it used to call
    *    `UUID.fromString(null)` before `SqlExecution` looked at `wasNull`, so
    *    a NULL in a GUID column threw and this list had to exclude it);
    *  - strings without a NUL or a lone surrogate (JDBC cannot carry those);
    *  - doubles of moderate magnitude (the emitter's literals lose 1e300 and
    *    1e-300; the extremes and the ordinary values survive). */
  val sqliteExact: List[Boolean => PrimT] = primCtors

  /** A string with an unpaired surrogate in it: JDBC has no UTF-8 for it. */
  def loneSurrogate(s: String): Boolean = {
    var i = 0
    var lone = false
    while (i < s.length) {
      val c = s.charAt(i)
      if (Character.isHighSurrogate(c) && i + 1 < s.length && Character.isLowSurrogate(s.charAt(i + 1))) i += 1
      else if (Character.isSurrogate(c)) lone = true
      i += 1
    }
    lone
  }

  /** Readable in a failure message whatever is in the string. */
  def esc(s: String): String =
    s.map(c => if (c >= ' ' && c <= '~') c.toString else "\\u%04x".format(c.toInt)).mkString

  /** The nasty strings minus the ones SQLite cannot carry. */
  val sqlSafe: List[String] =
    nasty.filterNot(str => str.indexOf('\u0000') >= 0 || loneSurrogate(str))

  private val sqlStringGen: Gen[String] = Gen.frequency(
    (3, Gen.choose(0, 4).flatMap(k => Gen.listOfN(k, Gen.oneOf(sqlSafe))).map(_.mkString)),
    (2, Gen.alphaNumStr))

  private val sqlDoubleGen: Gen[Double] = Gen.frequency(
    (1, Gen.oneOf(0.0, -0.0, 1.0, -1.5, 123456789.125, 0.1, 1e15, -1e-15)),
    (3, Gen.choose(-1e15, 1e15)))

  private val docB: Gen[(List[Rel0], List[List[(String, SortOrder)]])] =
    for {
      k     <- Gen.choose(2, 4)
      rels  <- Gen.listOfN(k, relGen(sqlName, sqliteExact, 4, 30, sqlStringGen, sqlDoubleGen))
      ords  <- Gen.sequence[List[List[(String, SortOrder)]], List[(String, SortOrder)]](rels.map { r =>
                 Gen.frequency((1, Gen.const(Nil: List[(String, SortOrder)])),
                               (1, Gen.oneOf(r.header.map(_._1)).flatMap(c =>
                                     Gen.oneOf(SortOrder.Asc: SortOrder, SortOrder.Desc: SortOrder).map(o => List((c, o))))))
               })
    } yield (rels, ords)

  private def cellsOf(cols: List[String], rows: Seq[Record]): List[Json] =
    rows.toList.map(rec => Json.array(cols.map(c => encodedCell(rec(c))): _*))

  property("(b) SQLite: one Run, one connection, document order, rows equal the scanner's collect") =
    forAllNoShrink(docB) { case (rels, ords) =>
      val S = new RecordingScanner(Scanners.SQLite(SMEnv.dummySmenv))
      val R = new CountingRun
      val datas = rels.zip(ords).zipWithIndex.map { case ((r, o), i) => dataOf(r, Delivery.ByRequest, "$[" + i + "]").copy(order = o) }
      val sb = new java.lang.StringBuilder
      val stats = try R.run(Write.doc[DB](Doc.DArr(datas), sb, WriteConfig(), bigCache())(S, Guard.db))
                  catch { case e: Throwable => e.printStackTrace(); throw e }
      val opened = R.opened.get
      val conns = S.seen.map(_._1).toList
      val parsed = Parse.parse(sb.toString).fold(e => sys.error(e + ": " + sb), identity).arrayOrEmpty
      val perRel = datas.zip(rels).zip(parsed).map { case ((d, r), j) =>
        val cols = d.columns.map(_.name)
        val collected: Seq[Record] =
          if (d.order.isEmpty) R.run(S.collect(d.ext))
          else R.run(S.scanExt(d.ext, Process.wrapping[Record], d.order)(scalaz.std.vector.vectorMonoid))
        val want = cellsOf(cols, collected)
        val got = j.field(Wire.Rows).map(_.arrayOrEmpty).getOrElse(Nil)
        val sameRows =
          if (d.order.nonEmpty) want.length == got.length && want.zip(got).forall(p => jsonEq(p._1, p._2))
          else want.map(_.nospaces).sorted == got.map(_.nospaces).sorted
        // the rows are the ORIGINAL records, deduplicated (the SQL scan is a set)
        // as SETS: SQL dedups by the stored value, the wire by the rendered cell,
        // and a Date keeps a time of day in the store that the wire drops
        val original = cellsOf(cols, r.records).map(_.nospaces).toSet
        (sameRows :| ("rows differ from collect at " + d.path + "\n want " + want.map(_.nospaces) + "\n got " + got.map(_.nospaces))) &&
          ((got.map(_.nospaces).toSet == original) :| ("rows differ from the records at " + d.path +
                                                         "\n want " + original + "\n got " + got.map(_.nospaces).toSet)) &&
          ((j.field(Wire.RowCount).flatMap(_.number).flatMap(_.toLong) == Some(got.length.toLong)) :| "rowCount")
      }
      ((opened == 1) :| ("connections opened by the write: " + opened)) &&
        (conns.forall(_ eq conns.head) :| "scans ran on different connections") &&
        ((S.seen.map(_._2).toList.take(datas.length).zip(datas.map(_.ext)).forall(p => p._1 eq p._2)) :| "scan order is not document order") &&
        ((stats.relations.map(_.path) == datas.map(_.path)) :| "stats order") &&
        perRel.foldLeft(proved: Prop)(_ && _)
    }

  property("(b-pin) a record from a SQL scan indexes by column name (RecordMap.get)") = secure {
    // The row encoder reads a scanned record BY COLUMN NAME, and `SqlExecution`
    // builds records as `RecordMap.createWithKeyCache`, whose `get` threw a
    // ClassCastException on Scala 3 until this stage fixed it (RecordMap.scala:172).
    val keys = Map("a" -> 0, "b" -> 1)
    val rec: Record = com.clarifi.reporting.record.RecordMap.createWithKeyCache(keys)(i =>
      if (i == 0) IntExpr(false, 7) else StringExpr(false, "s"))
    val sb = new java.lang.StringBuilder
    Rows.row(sb, rec, Array("a", "b"))
    (rec.get("a") ?= Some(IntExpr(false, 7))) && (rec.getOrElse("b", null) ?= StringExpr(false, "s")) &&
      (sb.toString ?= "[7,\"s\"]")
  }

  property("(b-pin) on SQLite: the threshold defers a bare relation and the token re-requests it inline") = secure {
    val S = Scanners.SQLite(SMEnv.dummySmenv)
    val R = new CountingRun
    val cache = bigCache()
    val big = Rel0(List("cn" -> IntT(false)), (0 until 20).toList.map(i => Map("cn" -> IntExpr(false, i)): Record))
    val small = Rel0(List("cm" -> StringT(0, false)), List(Map("cm" -> StringExpr(false, "after"))))
    val datas = List(dataOf(big, Delivery.ByRequest, "$[0]"), dataOf(small, Delivery.ByRequest, "$[1]"))
    val sb = new java.lang.StringBuilder
    val stats = R.run(Write.doc[DB](Doc.DArr(datas), sb, WriteConfig(threshold = Some(5L)), cache)(S, Guard.db))
    val arr = Parse.parse(sb.toString).fold(e => sys.error(e), identity).arrayOrEmpty
    val token = arr.head.field(Wire.Token).flatMap(_.string).getOrElse("")
    // the deferred re-request runs on its own connection and writes the inline object
    val again = new java.lang.StringBuilder
    val st2 = R.run(Write.relation[DB](token, again, cache)(S, Guard.db))
    val direct = {
      val d = new java.lang.StringBuilder
      R.run(Write.doc[DB](dataOf(big, Delivery.Inline, "$[0]"), d, WriteConfig(), bigCache())(S, Guard.db))
      d.toString
    }
    (arr.head.field(Wire.Kind).flatMap(_.string) ?= Some(Wire.Deferred)) &&
      (arr(1).field(Wire.Kind).flatMap(_.string) ?= Some(Wire.Inline)) &&  // the scan after an abandoned one still runs
      (stats.relations.map(_.delivery.name) ?= List(Wire.Deferred, Wire.Inline)) &&
      ((stats.relations.head.scanned ?= 6L) :| "the abandoned scan read one record past the threshold") &&
      (st2.map(_.relations.map(_.rows)) ?= Some(List(20L))) &&
      (again.toString ?= direct)
  }

  property("(b-sql) what SQLite can and cannot carry (measured; (b) excludes the rest)") = secure {
    val S = Scanners.SQLite(SMEnv.dummySmenv)
    val R = new CountingRun
    def carries(p: PrimT, v: PrimExpr): Boolean = {
      val r = Rel0(List("v" -> p), List(Map("v" -> v)))
      try {
        val sb = new java.lang.StringBuilder
        R.run(Write.doc[DB](dataOf(r, Delivery.Inline, "$"), sb, WriteConfig(), bigCache())(S, Guard.db))
        jsonEq(Parse.parse(sb.toString).toOption.get, expectedInline(r))
      } catch { case scala.util.control.NonFatal(_) => false }
    }
    val ms = 1234567890123L
    val types: List[(String, PrimT, PrimExpr)] = List(
      ("Int", IntT(false), IntExpr(false, -7)), ("Byte", ByteT(false), ByteExpr(false, -3)),
      ("Short", ShortT(false), ShortExpr(false, 321)), ("Long", LongT(false), LongExpr(false, Long.MinValue)),
      ("Double", DoubleT(false), DoubleExpr(false, -1.5)), ("String", StringT(0, false), StringExpr(false, "plain")),
      ("Bool", BooleanT(false), BooleanExpr(false, true)), ("Date", DateT(false), DateExpr(false, new java.util.Date(ms))),
      ("Timestamp", TimestampT(false), TimestampExpr(false, new java.sql.Timestamp(ms))),
      ("GUID", UuidT(false), UuidExpr(false, new java.util.UUID(1L, 2L))),
      ("null", IntT(true), NullExpr(IntT(true))))
    val badTypes = types.filterNot { case (_, p, v) => carries(p, v) }.map(_._1)
    val badStrings = nasty.filterNot(str => carries(StringT(0, false), StringExpr(false, str)))
    val excluded = nasty.filterNot(sqlSafe.contains)
    val badNulls = types.map(_._2).filter(_.withNull != null).map(_.withNull).distinct
      .filterNot(p => carries(p, NullExpr(p))).map(_.name)
    val wideDoubles = List(1e21, 1.5e300, -1.5e300, 4.9e-324, Double.MaxValue, Double.MinValue, 1e-300, 1e16, 1e17)
      .filterNot(d => carries(DoubleT(false), DoubleExpr(false, d)))
    val badDoubles = samples(sqlDoubleGen, 40, 7L).filterNot(d => carries(DoubleT(false), DoubleExpr(false, d)))
    println("  (b-sql) SQLite: column types it loses = " + badTypes + "; nulls it loses = " + badNulls +
            "; wide doubles it loses = " + wideDoubles + "; drawn doubles it loses = " + badDoubles +
            "; strings it loses = " + badStrings.map(esc))
    ((badStrings == excluded) :| ("SQLite loses exactly the strings " + badStrings.map(esc) +
      ", (b) excludes " + excluded.map(esc))) &&
      (badTypes.isEmpty :| ("column types lost: " + badTypes)) &&
      // was List("UUID") until J3c fixed the emitter's `getUuid`
      (badNulls.isEmpty :| ("nulls lost: " + badNulls)) &&
      (badDoubles.isEmpty :| ("(b) would draw doubles SQLite loses: " + badDoubles))
  }

  // =====================================================================
  // (c) delivery resolution

  final case class CaseC(rels: List[(Rel0, Delivery)], cfg: WriteConfig)

  private val caseC: Gen[CaseC] =
    for {
      k    <- Gen.choose(1, 6)
      rels <- Gen.listOfN(k, Gen.zip(relGen(anyName, primCtors, 3, 12),
                                    Gen.oneOf(Delivery.ByRequest: Delivery, Delivery.Inline: Delivery, Delivery.Deferred: Delivery)))
      dflt <- Gen.oneOf(Delivery.Inline: Delivery, Delivery.Deferred: Delivery)
      thr  <- Gen.frequency((1, Gen.const(None: Option[Long])), (2, Gen.choose(0L, 12L).map(Some(_))))
    } yield CaseC(rels, WriteConfig(default = dflt, threshold = thr))

  /** The resolution rules, stated independently of `Write.resolve`. */
  def expectedKind(requested: Delivery, cfg: WriteConfig, rows: Int): String = requested match {
    case Delivery.Inline   => Wire.Inline
    case Delivery.Deferred => Wire.Deferred
    case Delivery.ByRequest =>
      if (cfg.default == Delivery.Deferred) Wire.Deferred
      else if (cfg.threshold.exists(t => rows.toLong > t)) Wire.Deferred
      else Wire.Inline
  }

  /** The text inline delivery writes for a relation, on its own. */
  def inlineText(d: Doc.Data): String = {
    val sb = new java.lang.StringBuilder
    Write.doc[Id](d.copy(delivery = Delivery.Inline), sb, WriteConfig(), bigCache())(new ListScanner, Guard.id)
    sb.toString
  }

  /** Check one delivery case; the outcome tags are returned for coverage. */
  def checkC(c: CaseC): Either[String, List[String]] = {
    val S = new ListScanner
    val cache = bigCache()
    val datas = c.rels.zipWithIndex.map { case ((r, d), i) => dataOf(r, d, "$.root[" + i + "]") }
    val sb = new java.lang.StringBuilder
    val stats = Write.doc[Id](Doc.document(Doc.DArr(datas)), sb, c.cfg, cache)(S, Guard.id)
    val root = Parse.parse(sb.toString).fold(e => sys.error(e), identity).field(Wire.Root).get.arrayOrEmpty
    val problems = new ListBuffer[String]
    val tags = new ListBuffer[String]
    var scanIx = 0
    c.rels.zip(datas).zip(root).foreach { case (((r, req), d), j) =>
      val n = r.records.length
      val want = expectedKind(req, c.cfg, n)
      val got = j.field(Wire.Kind).flatMap(_.string).getOrElse("?")
      if (want != got) problems += (d.path + ": " + req + " default " + c.cfg.default + " threshold " + c.cfg.threshold +
                                    " rows " + n + ": want " + want + ", got " + got)
      else if (got == Wire.Inline) {
        tags += ("inline-" + req.name)
        if (!jsonEq(j, expectedInline(r))) problems += (d.path + ": inline object " + j.nospaces)
        val rc = j.field(Wire.RowCount).flatMap(_.number).flatMap(_.toLong)
        if (rc != Some(j.field(Wire.Rows).get.arrayOrEmpty.length.toLong)) problems += (d.path + ": rowCount " + rc)
      } else {
        val overThreshold = req == Delivery.ByRequest && c.cfg.default == Delivery.Inline
        tags += (if (overThreshold) "deferred-threshold" else "deferred-" + req.name)
        deferredOk(r, j).foreach(m => problems += (d.path + ": " + m))
        val token = j.field(Wire.Token).flatMap(_.string).getOrElse("")
        val again = new java.lang.StringBuilder
        Write.relation[Id](token, again, cache)(new ListScanner, Guard.id) match {
          case None => problems += (d.path + ": the token does not resolve")
          case Some(st) =>
            if (again.toString != inlineText(d)) problems += (d.path + ": re-request text differs\n " + again + "\n " + inlineText(d))
            if (st.relations.map(_.rows) != List(n.toLong)) problems += (d.path + ": re-request stats " + st)
        }
      }
      // what the writer scanned: only relations resolved inline before the scan,
      // and a thresholded one no further than the first record past the threshold
      val scanned = req != Delivery.Deferred && !(req == Delivery.ByRequest && c.cfg.default == Delivery.Deferred)
      if (scanned) {
        val (ext, pulled) = S.scans(scanIx)
        scanIx += 1
        if (!(ext eq d.ext)) problems += (d.path + ": scanned out of order")
        val limit = if (req == Delivery.ByRequest) c.cfg.threshold.map(_ + 1).getOrElse(n.toLong) else n.toLong
        if (pulled != math.min(n.toLong, limit)) problems += (d.path + ": pulled " + pulled + " records, want " + math.min(n.toLong, limit))
      }
    }
    if (scanIx != S.scans.length) problems += ("scans: " + S.scans.length + ", relations resolved inline: " + scanIx)
    if (stats.relations.map(_.delivery.name) != root.map(_.field(Wire.Kind).flatMap(_.string).getOrElse("?")))
      problems += ("stats deliveries " + stats.relations.map(_.delivery.name))
    if (problems.isEmpty) Right(tags.toList) else Left(problems.mkString("\n"))
  }

  property("(c) delivery: explicit wins, bare takes the default, the threshold defers only bare; tokens re-request the inline object") =
    forAllNoShrink(caseC) { (c: CaseC) =>
      checkC(c) match {
        case Right(_) => proved
        case Left(m)  => falsified :| m
      }
    }

  property("(c-cov) over 200 fixed cases every delivery outcome occurs") = secure {
    val results = samples(caseC, 200, 316L).map(checkC)
    val bad = results.collect { case Left(m) => m }
    val tags = results.collect { case Right(t) => t }.flatten.toSet
    val want = Set("inline-request", "inline-inline", "deferred-deferred", "deferred-request", "deferred-threshold")
    (bad.isEmpty :| bad.take(2).mkString("\n---\n")) && ((want -- tags).isEmpty :| ("never occurred: " + (want -- tags)))
  }

  // =====================================================================
  // (d) Node trees built in Ermine

  private val dImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Json" -> all, "List" -> all, "Maybe" -> all, "Function" -> all,
        "Int" -> all, "Num" -> all, "Layout.Doc" -> all, "Native.List" -> all) ++
    // Stage 2a (J2a) widened `TestSchema.shape` to Date, GUID, Prim, the
    // native collections and Vector; without their modules 13 of (d)'s 80
    // generated cases fail to parse with "undefined type".  `TestSchema.imps`
    // gained them in the same commit; this map did not, because the two
    // stages were built on separate branches (found by J3c on the merged tip).
    // Vector is ALIASED: a plain `import Vector` makes every `[..]` literal ambiguous.
    Map("Date" -> all, "GUID" -> all, "Prim" -> all, "Native.Maybe" -> all, "Native.Pair" -> all,
        "Vector" -> ((Some("V"), List(), false): ImportSpec))

  private val relFieldPool: List[(String, String)] =
    List(("rfInt", "Int"), ("rfStr", "String"), ("rfBool", "Bool"), ("rfDbl", "Double"), ("rfLong", "Long"))

  private def litFor(ty: String): Gen[String] = ty match {
    case "Int"    => Gen.choose(0, 99999).map(_.toString)
    case "String" => Gen.alphaNumStr.map(s => "\"" + s.take(6) + "\"")
    case "Bool"   => Gen.oneOf("True", "False")
    case "Double" => Gen.choose(0, 99999).map(n => (n / 8.0).toString)
    case "Long"   => Gen.choose(0L, Long.MaxValue).map(_.toString + "L")
  }

  final case class Src(decls: List[String], expr: String, forms: List[String])

  private val relSrc: Gen[Src] =
    for {
      k    <- Gen.choose(1, relFieldPool.length)
      fs   <- Gen.pick(k, relFieldPool).map(_.toList.sortBy(_._1))
      n    <- Gen.choose(1, 6)
      recs <- Gen.listOfN(n, Gen.sequence[List[String], String](fs.map { case (f, t) => litFor(t).map(f + " = " + _) })
                                .map(_.mkString("{ ", ", ", " }")))
      form <- Gen.oneOf("bare", "Inline", "Deferred", "rel", "relInline", "relDeferred", "Just", "list")
    } yield {
      val r = "(mkRelation# (toList# [" + recs.mkString(", ") + "]))"
      val e = form match {
        case "bare" => r
        case "Just" => "(Just " + r + ")"
        case "list" => "[" + r + ", " + r + "]"
        case other  => "(" + other + " " + r + ")"
      }
      Src(fs.map { case (f, t) => "field " + f + " : " + t }, "(widget \"table\" " + e + ")", List(form))
    }

  private val propsSrc: Gen[Src] =
    TestSchema.shape(2).flatMap(sh => sh.value.map(v => Src(sh.decls, "(widget \"w\" (" + v + " : " + sh.ty + "))", Nil)))

  private def nodeSrc(depth: Int): Gen[Src] = {
    val leaf = Gen.frequency((1, propsSrc), (2, relSrc))
    if (depth <= 0) leaf
    else {
      def kids(max: Int) = Gen.choose(0, max).flatMap(m => Gen.listOfN(m, nodeSrc(depth - 1)))
      def join(ss: List[Src]) = (ss.flatMap(_.decls), ss.flatMap(_.forms))
      Gen.frequency(
        (2, leaf),
        (1, kids(3).map { ss => val (d, f) = join(ss); Src(d, "(vflow " + ss.map(_.expr).mkString("[", ", ", "]") + ")", f) }),
        (1, kids(3).map { ss => val (d, f) = join(ss); Src(d, "(hflow " + ss.map(_.expr).mkString("[", ", ", "]") + ")", f) }),
        (1, Gen.choose(0, 2).flatMap(m => Gen.listOfN(m, kids(2))).map { rows =>
           val (d, f) = join(rows.flatten)
           Src(d, "(grid " + rows.map(_.map(_.expr).mkString("[", ", ", "]")).mkString("[", ", ", "]") + ")", f) }),
        (1, kids(3).flatMap(ss => Gen.listOfN(ss.length, Gen.alphaNumStr.map(_.take(5)))).flatMap { labels =>
           Gen.listOfN(labels.length, nodeSrc(depth - 1)).map { ss =>
             val (d, f) = join(ss)
             Src(d, "(tabbed " + labels.zip(ss).map { case (l, s) => "(\"" + l + "\", " + s.expr + ")" }.mkString("[", ", ", "]") + ")", f)
           } }))
    }
  }

  private val caseD: Gen[(Src, WriteConfig)] =
    for {
      s    <- nodeSrc(3)
      dflt <- Gen.oneOf(Delivery.Inline: Delivery, Delivery.Deferred: Delivery)
      thr  <- Gen.frequency((2, Gen.const(None: Option[Long])), (1, Gen.choose(0L, 6L).map(Some(_))))
    } yield (s, WriteConfig(default = dflt, threshold = thr))

  /** `ArgonautJson`, except that a relation becomes a marker object and is
    * remembered, in walk order. */
  final class Marking extends JsonBuilder[Json] {
    val rels = new ListBuffer[(Runtime, Delivery)]
    def nul = ArgonautJson.nul
    def bool(b: Boolean) = ArgonautJson.bool(b)
    def int(i: Int) = ArgonautJson.int(i)
    def long(l: Long) = ArgonautJson.long(l)
    def num(d: Double) = ArgonautJson.num(d)
    def str(s: String) = ArgonautJson.str(s)
    def arr(xs: List[Json]) = ArgonautJson.arr(xs)
    def obj(fields: List[(String, Json)]) = ArgonautJson.obj(fields)
    def rel(path: String, r: Runtime, delivery: Delivery) = {
      rels += ((r, delivery))
      Right(Json.obj("$relation" -> Json.jNumber(rels.length - 1)))
    }
  }

  /** Compare the written document with Encode's, each relation marker
    * standing for the relation object delivery should have produced. */
  /** A complaint that abandons the check it was raised in. */
  private final case class Complaint(why: String) extends RuntimeException(why) with scala.util.control.NoStackTrace
  private def complain(why: String): Nothing = throw Complaint(why)

  def checkD(src: Src, cfg: WriteConfig): Either[String, List[String]] = try {
    val decls = (src.decls.distinct ++ List("gv : Node", "gv = " + src.expr)).mkString("\n")
    val rt = try fixture.defAndEval(decls, "gv", dImps) catch { case e: Throwable => complain("load/eval threw " + e + "\n" + decls) }
    val mark = new Marking
    val want = Encode.encode(rt, mark).fold(e => complain("Encode refused: " + e.report + "\n" + decls), identity)
    val doc = Doc.fromRuntime(rt).fold(e => complain("Doc.fromRuntime refused: " + e.report + "\n" + decls), identity)
    val S = new ListScanner
    val cache = bigCache()
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(doc), sb, cfg, cache)(S, Guard.id)
    val got = Parse.parse(sb.toString).fold(e => complain("unparseable " + e), identity)
    val rels = mark.rels.toList.map { case (r, d) =>
      Runtime.swhnf(r) match {
        case Rel(ExtRel(SmallLit(tups), _)) =>
          val recs = tups.list.toList
          (Rel0(recordHeader(recs.head).toList, recs), d)
        case other => complain("unexpected relation value " + other)
      }
    }
    val tags = new ListBuffer[String]
    def cmp(w: Json, g: Json, path: String): Option[String] =
      w.field("$relation").flatMap(_.number).flatMap(_.toInt) match {
        case Some(i) if w.objectFieldsOrEmpty == List("$relation") =>
          val (r, d) = rels(i)
          val kind = expectedKind(d, cfg, r.records.length)
          tags += (kind + "-" + d.name)
          if (kind == Wire.Inline) { if (jsonEq(expectedInline(r), g)) None else Some(path + ": inline " + g.nospaces) }
          else deferredOk(r, g).map(path + ": " + _)
        case _ =>
          if (w.isArray && g.isArray) {
            val ws = w.arrayOrEmpty; val gs = g.arrayOrEmpty
            if (ws.length != gs.length) Some(path + ": array length")
            else ws.zip(gs).zipWithIndex.iterator.map { case ((a, b), i) => cmp(a, b, path + "[" + i + "]") }.collectFirst { case Some(m) => m }
          } else if (w.isObject && g.isObject) {
            val ws = w.obj.get.toList; val gs = g.obj.get.toList
            if (ws.map(_._1) != gs.map(_._1)) Some(path + ": keys " + ws.map(_._1) + " vs " + gs.map(_._1))
            else ws.zip(gs).iterator.map { case ((k, a), (_, b)) => cmp(a, b, path + "." + k) }.collectFirst { case Some(m) => m }
          } else if (jsonEq(w, g)) None
          else Some(path + ": " + w.nospaces + " vs " + g.nospaces)
      }
    val envelope = got.objectFieldsOrEmpty == List(Wire.Version, Wire.Settings, Wire.Root) &&
                   got.field(Wire.Version).flatMap(_.number).flatMap(_.toInt) == Some(1)
    if (!envelope) Left("envelope " + sb.toString.take(80))
    else cmp(want, got.field(Wire.Root).get, "$") match {
      case Some(m) => Left(m + "\n" + decls + "\n" + sb.toString.take(1500))
      case None    => Right(tags.toList ++ src.forms)
    }
  } catch { case Complaint(why) => Left(why) }

  property("(d) Node trees from generated Ermine: the document is Encode's with each relation written (80 cases)") = secure {
    val results = samples(caseD, 80, 42L).map { case (s, cfg) => checkD(s, cfg) }
    val bad = results.collect { case Left(m) => m }
    val tags = results.collect { case Right(t) => t }.flatten.toSet
    val forms = Set("bare", "Inline", "Deferred", "rel", "relInline", "relDeferred", "Just", "list")
    val kinds = Set("inline-request", "inline-inline", "deferred-deferred", "deferred-request")
    (bad.isEmpty :| (bad.length + " failed:\n" + bad.take(2).mkString("\n---\n"))) &&
      ((forms -- tags).isEmpty :| ("relation forms never generated: " + (forms -- tags))) &&
      ((kinds -- tags).isEmpty :| ("delivery outcomes never seen: " + (kinds -- tags)))
  }

  property("(d-pin) a header-less empty relation needs a hint; a static relation type gives one") = secure {
    session { implicit env =>
      val decls = "field hx : Int\nfield hy : Nullable String\nfield hz : GUID\nempties : [hx, hy, hz]\nempties = mkRelation# (toList# [])"
      loadStatements(decls, dImps + ("Nullable" -> all))
      val (ty, rt) = Session.eval("empties", dImps + ("Nullable" -> all))
      val refused = Doc.fromRuntime(rt)
      val h = Doc.headerOfType(ty, "Test")
      val hinted = h.right.toOption.map(hh => Doc.fromRuntime(rt, p => if (p == "$") Some(hh) else None))
      val text = hinted.flatMap(_.right.toOption).map { d =>
        val sb = new java.lang.StringBuilder
        Write.doc[Id](d, sb, WriteConfig(), bigCache())(new ListScanner, Guard.id)
        sb.toString
      }
      (refused.left.toOption.map(_.path) ?= Some("$")) &&
        (h ?= Right(Map("hx" -> IntT(false), "hy" -> StringT(0, true), "hz" -> UuidT(false)))) &&
        (text ?= Some("{\"kind\":\"inline\",\"columns\":[{\"name\":\"hx\",\"type\":\"Int\",\"nullable\":false}," +
                      "{\"name\":\"hy\",\"type\":\"String\",\"nullable\":true},{\"name\":\"hz\",\"type\":\"GUID\",\"nullable\":false}]," +
                      "\"rows\":[],\"rowCount\":0}"))
    }
  }

  // =====================================================================
  // (e) the plan cache against a model

  sealed abstract class Cmd
  final case class Put(id: Int) extends Cmd
  final case class Get(pick: Int) extends Cmd
  final case class Advance(ms: Long) extends Cmd

  private val cmdGen: Gen[Cmd] = Gen.frequency(
    (4, Gen.choose(0, 1000).map(Put(_))),
    (4, Gen.choose(-1, 50).map(Get(_))),
    (2, Gen.frequency((3, Gen.choose(0L, 40L)), (1, Gen.choose(40L, 200L))).map(Advance(_))))

  private def dummyData(id: Int): Doc.Data =
    Doc.Data(ExtRel(RelEmpty(Map()), ""), Nil, Nil, Delivery.Deferred, "p" + id)

  property("(e) MemoryPlanCache agrees with a model under random put/get/clock interleavings") =
    forAllNoShrink(Gen.choose(1L, 120L), Gen.choose(1, 12), Gen.listOf(cmdGen)) { (ttl: Long, max: Int, cmds: List[Cmd]) =>
      var now = 0L
      val cache = new MemoryPlanCache(ttl, max, () => now, new java.security.SecureRandom)
      var model = Vector.empty[(String, Int, Long)] // token, id, expires; eldest first
      val issued = new ListBuffer[String]
      val problems = new ListBuffer[String]
      cmds.foreach { c =>
        c match {
          case Put(id) =>
            val (tok, exp) = cache.put(dummyData(id))
            model = model.dropWhile(e => now >= e._3)
            if (model.exists(_._1 == tok) || issued.contains(tok)) problems += ("token reused " + tok)
            if (exp.toEpochMilli != now + ttl) problems += ("expires " + exp + " at " + now)
            model = model :+ ((tok, id, now + ttl))
            if (model.length > max) model = model.drop(model.length - max)
            issued += tok
          case Get(pick) =>
            val tok = if (pick < 0 || issued.isEmpty) "unknown-token-xxxxxxxxx" else issued(pick % issued.length)
            val real = cache.get(tok, now).map(_.data.path)
            val want = model.find(_._1 == tok) match {
              case Some((_, id, exp)) =>
                if (now >= exp) { model = model.filterNot(_._1 == tok); None } else Some("p" + id)
              case None => None
            }
            if (real != want) problems += ("get " + tok + " at " + now + ": " + real + " vs " + want)
          case Advance(ms) => now += ms
        }
        if (cache.tokens != model.map(_._1).toList) problems += ("after " + c + ": tokens " + cache.tokens.length + " vs model " + model.length)
        if (cache.size > max) problems += ("size " + cache.size + " > " + max)
      }
      problems.isEmpty :| problems.take(3).mkString("\n")
    }

  property("(e) 10,000 tokens: distinct, 128 bits, base64url without padding") = secure {
    val cache = new MemoryPlanCache(1000L, 10000, () => 0L, new java.security.SecureRandom)
    val toks = (1 to 10000).map(i => cache.put(dummyData(i))._1)
    val decoded = toks.map(t => java.util.Base64.getUrlDecoder.decode(t).length).toSet
    (toks.toSet.size ?= 10000) && (toks.forall(t => tokenRe.findFirstIn(t).isDefined) :| "format") &&
      (decoded ?= Set(16)) && (cache.size ?= 10000)
  }

  property("(e) concurrent puts and gets lose nothing") = secure {
    val threads = 8
    val per = 1500
    val cache = new MemoryPlanCache(600000L, threads * per, () => System.currentTimeMillis, new java.security.SecureRandom)
    val results = new java.util.concurrent.ConcurrentHashMap[String, String]()
    val failures = new java.util.concurrent.atomic.AtomicInteger(0)
    val start = new java.util.concurrent.CountDownLatch(1)
    val ts = (0 until threads).map { t =>
      val th = new Thread(new Runnable {
        def run(): Unit = {
          start.await()
          (0 until per).foreach { i =>
            val (tok, _) = cache.put(dummyData(t * per + i))
            if (results.putIfAbsent(tok, "p" + (t * per + i)) != null) failures.incrementAndGet()
            if (cache.get(tok, System.currentTimeMillis).map(_.data.path) != Some("p" + (t * per + i))) failures.incrementAndGet()
          }
        }
      })
      th.start(); th
    }
    start.countDown()
    ts.foreach(_.join())
    val now = System.currentTimeMillis
    val lost = scala.collection.JavaConverters.mapAsScalaMapConverter(results).asScala.count { case (tok, p) =>
      cache.get(tok, now).map(_.data.path) != Some(p) }
    (failures.get ?= 0) && (results.size ?= threads * per) && (lost ?= 0) && (cache.size ?= threads * per)
  }

  // =====================================================================
  // (f) failure

  /** Capture what `ermine.json.doc` logs (log4j 2 core under the 1.2 bridge). */
  private def capturingLog[A](body: => A): (Either[Throwable, A], List[String]) = {
    import org.apache.logging.log4j.core.{ LoggerContext, LogEvent }
    import org.apache.logging.log4j.core.appender.AbstractAppender
    import org.apache.logging.log4j.core.config.Property
    import org.apache.logging.log4j.Level
    val lines = java.util.Collections.synchronizedList(new java.util.ArrayList[String]())
    val app = new AbstractAppender("TestDoc-" + System.nanoTime, null, null, true, Property.EMPTY_ARRAY) {
      def append(e: LogEvent): Unit = lines.add(e.getLevel.toString + " " + e.getMessage.getFormattedMessage)
    }
    app.start()
    // the 1.2 bridge's loggers may live in the context of ITS class loader, not the
    // test's, so the appender goes on every context that has one
    val ctxs = List(org.apache.logging.log4j.LogManager.getContext(false),
                    org.apache.logging.log4j.LogManager.getContext(classOf[org.apache.log4j.Logger].getClassLoader, false),
                    org.apache.logging.log4j.LogManager.getContext(Write.getClass.getClassLoader, false))
      .collect { case c: LoggerContext => c }.distinct
    val configs = ctxs.map { ctx =>
      val cfg = ctx.getConfiguration
      val lc = new org.apache.logging.log4j.core.config.LoggerConfig("ermine.json.doc", Level.INFO, true)
      lc.addAppender(app, Level.INFO, null)
      cfg.addLogger("ermine.json.doc", lc)
      ctx.updateLoggers()
      (ctx, lc)
    }
    val result = try Right(body) catch { case e: Throwable => Left(e) }
    configs.foreach { case (ctx, _) => ctx.getConfiguration.removeLogger("ermine.json.doc"); ctx.updateLoggers() }
    app.stop()
    (result, scala.collection.JavaConverters.asScalaBufferConverter(lines).asScala.toList)
  }

  private val failGen: Gen[(List[Rel0], Int, Int)] =
    for {
      k    <- Gen.choose(1, 5)
      rels <- Gen.listOfN(k, relGen(sqlName, sqliteExact, 3, 8))
      at   <- Gen.choose(0, k - 1)
      how  <- Gen.choose(0, 2)
    } yield (rels, at, how)

  property("(f) a scan that throws, a non-finite Double or a missing column fails the whole write at the relation's path") =
    forAllNoShrink(failGen, Gen.choose(0, 1000000)) { (c: (List[Rel0], Int, Int), salt: Int) =>
      val (rels, at, how) = c
      val tag = "$f" + salt + "_"
      val good = rels.zipWithIndex.map { case (r, i) => dataOf(r, Delivery.Inline, tag + "[" + i + "]") }
      val badPath = tag + "[" + at + "]"
      val (bad, expectMsg): (Doc.Data, List[String]) = how match {
        case 0 =>
          (Doc.Data(ExtRel(Table(Map("x" -> IntT(false)), TableName("boom")), ""),
                    List(Doc.Column("x", IntT(false))), Nil, Delivery.Inline, badPath), List("the scan of boom failed"))
        case 1 =>
          val row = 3
          val recs = (0 to row).toList.map(i => Map("d" -> DoubleExpr(false, if (i == row) Double.NaN else i.toDouble)): Record)
          (Doc.Data(ExtRel(SmallLit(NonEmptyList.nel(recs.head, IList.fromList(recs.tail))), ""),
                    List(Doc.Column("d", DoubleT(false))), Nil, Delivery.Inline, badPath), List("row 3", "column d", "NaN"))
        case _ =>
          val recs = List(Map("a" -> IntExpr(false, 1)): Record)
          (Doc.Data(ExtRel(SmallLit(NonEmptyList.nel(recs.head, IList.fromList(recs.tail))), ""),
                    List(Doc.Column("a", IntT(false)), Doc.Column("b", IntT(false))), Nil, Delivery.Inline, badPath),
           List("row 0", "column b"))
      }
      val datas = good.updated(at, bad)
      val sb = new java.lang.StringBuilder
      val S = new ListScanner
      val (res, lines) = capturingLog(Write.doc[Id](Doc.DArr(datas), sb, WriteConfig(), bigCache())(S, Guard.id))
      // the prefix: every relation before the failed one, complete, then nothing
      val prefix = {
        val ok = new java.lang.StringBuilder
        Write.doc[Id](Doc.DArr(datas.take(at)), ok, WriteConfig(), bigCache())(new ListScanner, Guard.id)
        ok.toString.dropRight(1) + (if (at > 0) "," else "")
      }
      val mine = lines.filter(_.contains(tag))
      res match {
        case Left(f: WriteFailure) =>
          ((f.path ?= badPath)) &&
            (expectMsg.forall(f.message.contains) :| ("message " + f.message)) &&
            ((f.completed.map(_.path) ?= datas.take(at).map(_.path))) &&
            ((sb.toString ?= prefix)) &&
            ((mine.count(_.startsWith("INFO relation " + tag)) ?= at)) &&
            (mine.exists(l => l.startsWith("ERROR relation " + badPath + " failed")) :| ("log " + mine)) &&
            // EVERY scan that started was torn down, the one that refused a row
            // included: the sink leaves by `Stop` rather than by an exception
            // through `EffectfulProcedure.withDriver` (which tears down in a
            // `finally` as of J3c, so `how == 0` -- a scan that throws on its
            // own -- is now torn down too)
            ((S.teardowns.length ?= S.scans.length) :| ("scans " + S.scans.length + ", teardowns " + S.teardowns.length)) &&
            (((how == 0) || S.teardowns.exists(_ eq bad.ext)) :| "the failing scan was not torn down")
        case other => falsified :| ("expected a WriteFailure, got " + other)
      }
    }

  property("(f-db) on SQLite a failing scan names the relation and the connection is released") = secure {
    val S = Scanners.SQLite(SMEnv.dummySmenv)
    val R = new CountingRun
    val ok = Rel0(List("ca" -> IntT(false)), List(Map("ca" -> IntExpr(false, 7))))
    val missing = Doc.Data(ExtRel(Table(Map("ca" -> IntT(false)), TableName("no_such_table")), ""),
                           List(Doc.Column("ca", IntT(false))), Nil, Delivery.Inline, "$[1]")
    val sb = new java.lang.StringBuilder
    val res = try Right(R.run(Write.doc[DB](Doc.DArr(List(dataOf(ok, Delivery.Inline, "$[0]"), missing)), sb, WriteConfig(), bigCache())(S, Guard.db)))
              catch { case e: Throwable => Left(e) }
    res match {
      case Left(f: WriteFailure) =>
        (f.path ?= "$[1]") && (f.completed.map(_.path) ?= List("$[0]")) && (R.opened.get ?= 1) &&
          (sb.toString.startsWith("[{\"kind\":\"inline\"") :| sb.toString)
      case other => falsified :| ("expected a WriteFailure, got " + other)
    }
  }

  property("(f-db) a refused row leaves the connection usable: the next write on it succeeds") = secure {
    val S = Scanners.SQLite(SMEnv.dummySmenv)
    Class.forName("org.sqlite.JDBC")
    val conn = java.sql.DriverManager.getConnection("jdbc:sqlite::memory:")
    try {
      val R = com.clarifi.reporting.backends.Runners.fromPersistentConnection(conn)
      val rel = Rel0(List("ca" -> IntT(false)), List(Map("ca" -> IntExpr(false, 7))))
      // the scan yields records with `ca` only, so column `cz` is missing in row 0
      val bad = Doc.Data(rel.ext, List(Doc.Column("ca", IntT(false)), Doc.Column("cz", IntT(false))),
                         Nil, Delivery.Inline, "$[0]")
      val sb = new java.lang.StringBuilder
      val failed = try { R.run(Write.doc[DB](bad, sb, WriteConfig(), bigCache())(S, Guard.db)); None }
                   catch { case f: WriteFailure => Some(f) }
      // the SAME connection, a second write: the refused relation's scan was torn
      // down (result set, statement, temp tables) because the sink left by `Stop`,
      // so the scanner's own action ran to completion before the error was raised
      val again = new java.lang.StringBuilder
      val stats = R.run(Write.doc[DB](dataOf(rel, Delivery.Inline, "$"), again, WriteConfig(), bigCache())(S, Guard.db))
      (failed.map(_.path) ?= Some("$[0]")) &&
        (failed.exists(f => f.message.contains("row 0") && f.message.contains("column cz")) :|
           ("message " + failed.map(_.message))) &&
        ((sb.toString ?= "")) &&
        (stats.relations.map(_.rows) ?= List(1L)) &&
        (again.toString.contains("\"rows\":[[7]]") :| again.toString)
    } finally conn.close()
  }

  // =====================================================================
  // (g) scale

  property("(g) 100,000 rows x 10 columns through the test scanner") = secure {
    val header: List[(String, PrimT)] = List(
      "c0" -> IntT(false), "c1" -> LongT(false), "c2" -> DoubleT(false), "c3" -> StringT(0, false), "c4" -> BooleanT(false),
      "c5" -> DateT(false), "c6" -> TimestampT(false), "c7" -> UuidT(false), "c8" -> IntT(true), "c9" -> StringT(0, true))
    val n = 100000
    def rec(i: Int): Record = Map(
      "c0" -> IntExpr(false, i), "c1" -> LongExpr(false, i.toLong * 1000003L), "c2" -> DoubleExpr(false, i / 7.0),
      "c3" -> StringExpr(false, "row \"" + i + "\""), "c4" -> BooleanExpr(false, i % 2 == 0),
      "c5" -> DateExpr(false, new java.util.Date(i * 86400000L)), "c6" -> TimestampExpr(false, new java.sql.Timestamp(i * 1234L)),
      "c7" -> UuidExpr(false, new java.util.UUID(i, i)), "c8" -> (if (i % 3 == 0) NullExpr(IntT(true)) else IntExpr(true, i)),
      "c9" -> (if (i % 5 == 0) NullExpr(StringT(0, true)) else StringExpr(true, "\u00e9" + i)))
    val marker: Ext[Nothing, Nothing] = ExtRel(Table(header.toMap, TableName("scale")), "")
    val S = new ListScanner
    S.generated = { case e if e eq marker => () => Iterator.range(0, n).map(rec) }
    val data = Doc.Data(marker, Doc.columnsOf(header.toMap), Nil, Delivery.Inline, "$")
    val jrt = java.lang.Runtime.getRuntime
    // what the RECORDS cost on their own, through the same iterator: the rest is the writer
    val g0 = System.nanoTime
    var sink = 0
    S.generated(marker)().foreach(r => sink += r.size)
    val genMs = (System.nanoTime - g0) / 1000000
    S.scans.clear()
    System.gc()
    val before = jrt.totalMemory - jrt.freeMemory
    val t0 = System.nanoTime
    val sb = new java.lang.StringBuilder
    val stats = Write.doc[Id](data, sb, WriteConfig(), bigCache())(S, Guard.id)
    val ms = (System.nanoTime - t0) / 1000000
    System.gc()
    val after = jrt.totalMemory - jrt.freeMemory  // the text is still held
    println("  (g) 100,000 x 10: write " + ms + " ms (of which " + genMs + " ms is the records themselves), " +
            stats.bytes + " bytes, " + sb.length + " chars, heap held after the write " +
            ((after - before) / (1024 * 1024)) + " MB (sink " + sink + ")")
    val text = sb.toString
    val firstRow = text.substring(text.indexOf("\"rows\":[") + 8, text.indexOf("],[", text.indexOf("\"rows\":[")) + 1)
    (text.endsWith("],\"rowCount\":100000}") :| text.takeRight(60)) &&
      (stats.relations.map(_.rows) ?= List(100000L)) &&
      (Parse.parse(firstRow).toOption.map(_.arrayOrEmpty.length) ?= Some(10)) &&
      ((S.scans.map(_._2).toList) ?= List(100000L))
  }
}
