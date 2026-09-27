package com.clarifi.reporting
package relational

import java.sql.{ Connection, DriverManager, Timestamp }
import java.util.{ Calendar, GregorianCalendar, TimeZone }

import com.clarifi.machines.Process
import com.clarifi.reporting.backends.Scanners
import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.Predicate._
import com.clarifi.reporting.Op._
import com.clarifi.reporting.AggFunc._

import scala.collection.immutable.{ HashMap, HashSet }
import scalaz.NonEmptyList
import scalaz.std.vector._

import org.scalacheck.{ Gen, Prop, Properties, Shrink }
import org.scalacheck.Prop.{ Result => _, _ }

/** SQL audit 2026-09-26, area `prims` (tracker/sql-audit/WORKLIST.md P1-P7, decisions
  * D1-D3): the in-memory evaluator (`Op.eval`, `Predicates.toFn`, `AggFunc`,
  * `PrimExpr`) is made to agree with SQL, which is the reference (D1).
  *
  * The oracle, where one exists, is the SQLite scanner on the SAME literal relation:
  * `ExtMem(Literal(rows))` runs the operation in Ermine, `ExtRel(SmallLit(rows), "")`
  * runs it in SQL (`TestInMemoryScan`'s and `TestSqlDifferential`'s idiom).  Where
  * SQLite has no twin yet (variance/stddev, `logBase`'s argument order, `dateDiff`,
  * and the empty-input aggregate whose SQL half is the scanner's item C6), the
  * property states the SQL rule directly.
  *
  * Every property here fails on the pre-fix compiler and names the wrong answer, except
  * the two that say so in their name ("guards"): they hold pre-fix as well and are kept
  * because they would break if a later change made them false.  Where a property is
  * about `hashCode` it uses an explicitly hashing structure (`HashSet`/`HashMap`): a
  * `Set` or `Map` of up to four elements compares by `==` alone and never hashes.
  * The string domain is lower-case ASCII, so SQLite's binary collation and memory's
  * case-insensitive order (D3, kept) cannot be what a property is about.
  */
object TestPrimSemantics extends Properties("prim semantics (SQL audit P1-P7)") {

  private def i(n: Int): PrimExpr = IntExpr(false, n)
  private def d(x: Double): PrimExpr = DoubleExpr(false, x)
  private def s(x: String): PrimExpr = StringExpr(false, x)
  private val nullI: PrimExpr = NullExpr(IntT(true))
  private val nullD: PrimExpr = NullExpr(DoubleT(true))
  private val nullS: PrimExpr = NullExpr(StringT(0, true))

  private val nCol = ColumnValue("n", IntT(true))
  private val dCol = ColumnValue("d", DoubleT(true))
  private val sCol = ColumnValue("s", StringT(0, true))

  // ------------------------------------------------------------------ the backends

  private lazy val scanner = Scanners.SQLite(SMEnv.dummySmenv)
  private lazy val conn: Connection = {
    Class.forName("org.sqlite.JDBC"); DriverManager.getConnection("jdbc:sqlite::memory:")
  }
  /** sbt runs properties concurrently; one scan at a time on the one connection. */
  private val lock = new Object

  private def scan(e: Ext[Nothing, Nothing]): Vector[Record] = lock.synchronized {
    scanner.scanExt[Vector[Record]](e, Process((r: Record) => Vector(r)))(vectorMonoid[Record]).apply(conn)
  }

  private def nel(rows: List[Record]): NonEmptyList[Record] =
    NonEmptyList.nel(rows.head, scalaz.IList.fromList(rows.tail))
  private def mem(rows: List[Record]): Ext[Nothing, Nothing] = ExtMem(Literal(nel(rows)))
  private def sql(rows: List[Record]): Ext[Nothing, Nothing] = ExtRel(SmallLit(nel(rows)), "")

  private def showRows(rs: Iterable[Record]): String =
    rs.map(_.toList.sortBy(_._1).map { case (k, v) => k + "=" + (if (v.isNull) "NULL" else v.toString) }.mkString("{", ", ", "}")).mkString("[", " ", "]")

  // ------------------------------------------------------------------ generators

  /** Rows over `n: Int?`, `d: Double?`, `s: String?`, distinct so the literal is a set.  The
    * values carry the nullable flag, as a scan of a nullable column delivers them: `SmallLit`
    * types its header from the values, and a strict header over a NULL throws on the read. */
  private val genRow: Gen[Record] = for {
    n <- Gen.frequency(3 -> Gen.choose(0, 4).map(k => IntExpr(true, k): PrimExpr), 1 -> Gen.const(nullI))
    dd <- Gen.frequency(3 -> Gen.choose(0, 12).map(k => DoubleExpr(true, k * 0.25): PrimExpr), 1 -> Gen.const(nullD))
    ss <- Gen.frequency(3 -> Gen.oneOf("a", "b", "c").map(x => StringExpr(true, x): PrimExpr), 1 -> Gen.const(nullS))
  } yield Map("n" -> n, "d" -> dd, "s" -> ss)

  /** Rows are not shrunk: a shrunk row loses columns and the SQL side then has no table. */
  private implicit val noShrinkRows: Shrink[List[Record]] = Shrink.shrinkAny

  private val genRows: Gen[List[Record]] =
    Gen.choose(1, 7).flatMap(k => Gen.listOfN(k, genRow)).map(_.distinct)

  private val genOpN: Gen[Op] = Gen.frequency(
    3 -> Gen.const(nCol: Op),
    2 -> Gen.choose(0, 4).map(k => OpLiteral(i(k)): Op),
    1 -> Gen.const(OpLiteral(nullI): Op))
  private val genOpS: Gen[Op] = Gen.frequency(
    3 -> Gen.const(sCol: Op),
    2 -> Gen.oneOf("a", "b", "c").map(x => OpLiteral(s(x)): Op))

  private val cmpOps: Seq[(Op, Op) => Predicate] = Seq(Lt(_, _), Gt(_, _), Eq(_, _))

  private def genPred(depth: Int): Gen[Predicate] = {
    val leaf: Gen[Predicate] = Gen.oneOf(
      for { a <- genOpN; b <- genOpN; f <- Gen.oneOf(cmpOps) } yield f(a, b),
      for { a <- genOpS; b <- genOpS; f <- Gen.oneOf(cmpOps) } yield f(a, b),
      Gen.oneOf(nCol, dCol, sCol).map(c => IsNull(c): Predicate),
      Gen.oneOf(true, false).map(Atom(_): Predicate))
    if (depth == 0) leaf
    else Gen.frequency(
      3 -> leaf,
      2 -> genPred(depth - 1).map(Not(_)),
      2 -> (for { a <- genPred(depth - 1); b <- genPred(depth - 1) } yield And(a, b)),
      2 -> (for { a <- genPred(depth - 1); b <- genPred(depth - 1) } yield Or(a, b)))
  }

  // ------------------------------------------------------------------ P3: three-valued filters (S-14, D1)

  property("P3: an in-memory filter keeps the rows SQLite keeps (three-valued logic)") =
    forAll(genRows, genPred(3)) { (rows, p) => rows.nonEmpty ==> {
      val m = scan(FilterE(mem(rows), p)).toSet
      val q = scan(FilterE(sql(rows), p)).toSet
      (m == q) :| ("predicate " + p + "\nrows " + showRows(rows) + "\nmemory " + showRows(m) + "\nsqlite " + showRows(q))
    } }

  property("P3 pin: `n < 2` and `not (n == 1)` drop a NULL row in memory") = secure {
    val rows = List(Map("n" -> nullI), Map("n" -> i(1)), Map("n" -> i(3)))
    val lt = scan(FilterE(mem(rows), Lt(nCol, OpLiteral(i(2)))))
    val ne = scan(FilterE(mem(rows), Not(Eq(nCol, OpLiteral(i(1))))))
    // Pre-fix: `n < 2` answered {NULL, 1} (NULL sorted before everything) and
    // `not (n == 1)` answered {NULL, 3} (`not false`); SQL answers {1} and {3}.
    (lt.toSet ?= Set(Map("n" -> i(1)))) && (ne.toSet ?= Set(Map("n" -> i(3))))
  }

  property("P3: `if` takes the alternate when its test is unknown, like CASE WHEN") = secure {
    val op = If(Lt(nCol, OpLiteral(i(2))), OpLiteral(s("yes")), OpLiteral(s("no")))
    op.eval(Map("n" -> nullI)) ?= s("no")
  }

  // ------------------------------------------------------------------ P4/P5: aggregates (S-13, S-12, D1, D2)

  private def agg(rows: List[Record], f: AggFunc, t: PrimT, e: List[Record] => Ext[Nothing, Nothing]): Vector[PrimExpr] =
    scan(AggregateE(e(rows), Attribute("r", t), f)).map(_("r"))

  private def close(a: PrimExpr, b: PrimExpr): Boolean =
    (a.isNull && b.isNull) || (!a.isNull && !b.isNull && math.abs(a.extractDouble - b.extractDouble) < 1e-9)

  private val aggsWithTwins: List[(String, AggFunc, PrimT)] = List(
    ("sum d", Sum(dCol), DoubleT(true)), ("avg d", Avg(dCol), DoubleT(true)),
    ("min d", Min(dCol), DoubleT(true)), ("max d", Max(dCol), DoubleT(true)),
    ("sum n", Sum(nCol), IntT(true)),   ("min n", Min(nCol), IntT(true)), ("max n", Max(nCol), IntT(true)),
    ("count", Count, IntT(false)))

  property("P4: sum/avg/min/max/count in memory equal SQLite's over rows with NULLs") =
    forAll(genRows, Gen.oneOf(aggsWithTwins)) { (rows, a) =>
      val (name, f, t) = a
      // The SQL side of the all-NULL and empty inputs is the scanner's item C6
      // (`coalesce`/`having`); the two evaluators are compared where SQL is settled.
      val someValue = rows.nonEmpty && rows.exists(r => !r("d").isNull && !r("n").isNull)
      someValue ==> {
        val m = agg(rows, f, t, mem)
        val q = agg(rows, f, t, sql)
        (m.size == 1 && q.size == 1 && close(m.head, q.head)) :|
          (name + " over " + showRows(rows) + ": memory " + m + " sqlite " + q)
      }
    }

  property("P4 pin: sum and avg skip NULLs (memory)") = secure {
    val rows = List(Map("d" -> d(1.5)), Map("d" -> nullD), Map("d" -> d(3.0)))
    // Pre-fix: sum = NULL (`+` propagates it), avg = NULL / 3.
    (agg(rows, Sum(dCol), DoubleT(true), mem) ?= Vector(d(4.5))) &&
    (agg(rows, Avg(dCol), DoubleT(true), mem) ?= Vector(d(2.25)))
  }

  private def empty(e: Ext[Nothing, Nothing]): Ext[Nothing, Nothing] = FilterE(e, Atom(false))

  property("P4 (D2): over an EMPTY input, sum is 0 and count is 0; avg/min/max/stddev/variance are NO row") =
    forAll(genRows) { rows => rows.nonEmpty ==> {
      val none = empty(mem(rows))
      def one(f: AggFunc, t: PrimT) = scan(AggregateE(none, Attribute("r", t), f)).map(_("r"))
      (one(Sum(dCol), DoubleT(true)) ?= Vector(d(0.0))) &&
      (one(Sum(nCol), IntT(true)) ?= Vector(i(0))) &&
      (one(Count, IntT(false)) ?= Vector(i(0))) &&
      (one(Avg(dCol), DoubleT(true)) ?= Vector()) &&
      (one(Min(nCol), IntT(true)) ?= Vector()) &&
      (one(Max(sCol), StringT(0, true)) ?= Vector()) &&
      (one(Stddev(dCol), DoubleT(true)) ?= Vector()) &&
      (one(Variance(dCol), DoubleT(true)) ?= Vector())
      // Pre-fix: avg divided 0 by 0 (an exception for Ints), min/max/stddev/variance
      // answered one row (NULL, NULL, sqrt(0) and 0).
    } }

  property("P4 (D2): over rows that are all NULL, avg/min/max are one NULL (SQL with `having count(*) > 0`)") = secure {
    val rows = List(Map("d" -> nullD, "n" -> nullI))
    (agg(rows, Avg(dCol), DoubleT(true), mem) ?= Vector(nullD)) &&
    (agg(rows, Min(nCol), IntT(true), mem) ?= Vector(nullI)) &&
    (agg(rows, Sum(dCol), DoubleT(true), mem) ?= Vector(d(0.0)))
  }

  private def popVariance(xs: List[Double]): Double = {
    val n = xs.size; val mean = xs.sum / n
    xs.map(x => (x - mean) * (x - mean)).sum / n
  }

  property("P5: in-memory variance is the population variance of the non-NULL values, stddev its root") =
    forAll(genRows) { rows =>
      val xs = rows.map(_("d")).filter(!_.isNull).map(_.extractDouble)
      (rows.nonEmpty && xs.nonEmpty) ==> {
        val v = agg(rows, Variance(dCol), DoubleT(true), mem)
        val sd = agg(rows, Stddev(dCol), DoubleT(true), mem)
        (v.size == 1 && close(v.head, d(popVariance(xs))) &&
         sd.size == 1 && close(sd.head, d(math.sqrt(popVariance(xs))))) :|
          ("rows " + showRows(rows) + " variance " + v + " expected " + popVariance(xs) + " stddev " + sd)
      }
    }

  property("P5 pin: variance of 1,2,3,4 is 1.25 (was -890: Σx - (Σx²)²)") = secure {
    val rows = List(1, 2, 3, 4).map(k => Map("d" -> d(k.toDouble)))
    val v = agg(rows, Variance(dCol), DoubleT(true), mem)
    (v.size == 1 && close(v.head, d(1.25))) :| ("variance " + v)
  }

  property("P4: the weighted mean skips a row whose value or weight is NULL") = secure {
    val rows = List(Map("d" -> d(2.0), "w" -> d(1.0)), Map("d" -> nullD, "w" -> d(100.0)),
                    Map("d" -> d(4.0), "w" -> d(3.0)), Map("d" -> d(9.0), "w" -> nullD))
    val wCol = ColumnValue("w", DoubleT(true))
    // (2*1 + 4*3) / (1 + 3) = 3.5
    agg(rows, WMean(dCol, wCol), DoubleT(true), mem) ?= Vector(d(3.5))
  }

  // ------------------------------------------------------------------ P2: equals/hashCode, NULL keys, string order (D3, S-16, S-18, S-29, L-13)

  private val genPrim: Gen[PrimExpr] = Gen.oneOf(
    for { n <- Gen.oneOf(true, false); v <- Gen.choose(-3, 3) } yield IntExpr(n, v): PrimExpr,
    for { n <- Gen.oneOf(true, false); v <- Gen.choose(-3, 3) } yield DoubleExpr(n, v.toDouble): PrimExpr,
    for { n <- Gen.oneOf(true, false); v <- Gen.oneOf("a", "A", "b", "B", "ab", "Ab") } yield StringExpr(n, v): PrimExpr,
    Gen.oneOf(nullI, nullD, nullS))

  /** A value and a twin that `equals` (= `Order[PrimExpr]`) says is the same: the other
    * case, the other nullable flag, or the one NULL of the type again. */
  private val genEqualPair: Gen[(PrimExpr, PrimExpr)] = Gen.oneOf(
    for { n <- Gen.oneOf(true, false); m <- Gen.oneOf(true, false); v <- Gen.oneOf("a", "ab", "Zed", "MiXed") }
      yield (StringExpr(n, v): PrimExpr, StringExpr(m, if (v.head.isUpper) v.toLowerCase else v.toUpperCase): PrimExpr),
    for { n <- Gen.oneOf(true, false); v <- Gen.choose(-3, 3) } yield (IntExpr(n, v): PrimExpr, IntExpr(!n, v): PrimExpr),
    for { n <- Gen.oneOf(true, false); v <- Gen.choose(-3, 3) } yield (DoubleExpr(n, v.toDouble): PrimExpr, DoubleExpr(!n, v.toDouble): PrimExpr),
    Gen.oneOf(IntT(true), DoubleT(true), StringT(0, true), DateT(true)).map(t => (NullExpr(t): PrimExpr, NullExpr(t): PrimExpr)))

  property("P2: equal PrimExprs hash alike (deliberately equal pairs, then random pairs)") =
    forAll(genEqualPair, genPrim, genPrim) { (ab, c, d) =>
      val (a, b) = ab
      // Pre-fix: "a"/"A" and the strict/nullable twins of one value hashed apart
      // (`(nullable, value).hashCode`); `a.equals(b)` was false for two NULLs.
      (a.equals(b) && a.hashCode == b.hashCode) :| ("" + a + " and " + b + ": equals " + a.equals(b) + ", hashes " + a.hashCode + " vs " + b.hashCode) &&
      ((!c.equals(d)) || (c.hashCode == d.hashCode)) :| ("" + c + " == " + d + " but hashes " + c.hashCode + " vs " + d.hashCode)
    }

  property("P2 pin: in a HASHED set or map, \"a\" and \"A\" are one key, a nullable-typed 1 and a strict 1 are one key, and NULL equals NULL of its type") = secure {
    // `HashSet`/`HashMap` explicitly: `Set(..)`/`Map(..)` of up to four elements never hash.
    val strings = HashSet[PrimExpr](s("a"), StringExpr(true, "A"), s("A"), StringExpr(true, "a"))
    val ints = HashSet[PrimExpr](i(1), IntExpr(true, 1))
    val byString = HashMap[PrimExpr, Int](s("a") -> 1)
    val byInt = HashMap[PrimExpr, Int](IntExpr(true, 1) -> 1)
    // Pre-fix: sizes 2 and 2 (hash `(nullable, value)`), lookups None (other bucket),
    // `equals`/`canEqual` false for a NULL against itself, `HashSet(nullI, nullI)` of size 2.
    (strings.size ?= 1) && (ints.size ?= 1) &&
    (byString.get(StringExpr(true, "A")) ?= Some(1)) && (byInt.get(i(1)) ?= Some(1)) &&
    (nullI.equals(NullExpr(IntT(true))) ?= true) && (nullI.canEqual(nullI) ?= true) &&
    (HashSet[PrimExpr](nullI, nullI, NullExpr(IntT(true))).size ?= 1) &&
    (nullI.equals(nullS) ?= false) && (nullI.equals(i(1)) ?= false) &&
    (HashSet[PrimExpr](nullI, nullS, nullD).size ?= 3)
  }

  property("P2 guard (holds pre-fix too): the string cache never hands back a differently-cased or differently-typed value") =
    forAll(Gen.oneOf("x", "X", "xy", "XY", "Xy"), Gen.oneOf(true, false)) { (v, n) =>
      // Build the case variants first so the cache holds them, then the value itself.
      StringExpr(!n, v.toLowerCase); StringExpr(n, v.toUpperCase); StringExpr(!n, v)
      val e = StringExpr(n, v)
      (e.value == v && e.nullable == n) :| ("got " + e.value + "/" + e.nullable + " for " + v + "/" + n)
    }

  property("P2 guard (S-18; holds pre-fix too, by NullExpr's one instance per type): projecting onto a NULL-able key puts every NULL in one row, in memory as in SQL") =
    forAll(genRows) { rows => rows.nonEmpty ==> {
      val keep = Map(Attribute("n", IntT(true)) -> (nCol: Op))
      val m = scan(ProjectE(mem(rows), keep))
      val q = scan(ProjectE(sql(rows), keep))
      (m.size == m.toSet.size && m.toSet == q.toSet) :|
        ("rows " + showRows(rows) + "\nmemory " + showRows(m) + "\nsqlite " + showRows(q))
      // S-18 as READ predicted one row PER NULL key; MEASURED pre-fix it was already one
      // row: `NullExpr.apply` returns one instance per type and generic `==` finds it by
      // reference before asking `equals`.  Kept as the SQL-agreement guard.
    } }

  property("P2 (S-29): in-memory minBy/maxBy on strings use the same case-insensitive order as `<`") = secure {
    val rows = List(Map("s" -> s("B")), Map("s" -> s("a")))
    // Pre-fix: Java `<=` on the raw strings, so min = "B" and max = "a".
    (agg(rows, Min(sCol), StringT(0, true), mem) ?= Vector(s("a"))) &&
    (agg(rows, Max(sCol), StringT(0, true), mem) ?= Vector(s("B")))
  }

  // ------------------------------------------------------------------ P1: logBase (S-04, O-2)

  property("P1: `logBase x b` folds and evaluates to log x / log b for every base") =
    forAll(Gen.choose(1, 400).map(_ / 4.0), Gen.oneOf(2.0, 10.0, 0.5, 3.7, 1.0)) { (x, b) =>
      val op = BuiltinCall(LogBase, List(OpLiteral(d(x)), OpLiteral(d(b))))
      val folded = op.simplify(Map())   // pre-fix: scala.MatchError(OpLiteral(2.0)) for every base but 1
      val expected = math.log(x) / math.log(b)
      folded match {
        case OpLiteral(DoubleExpr(_, v)) =>
          (v == expected || (v.isNaN && expected.isNaN)) :| ("folded to " + v + ", expected " + expected)
        case other => falsified :| ("did not fold: " + other)
      }
    }

  property("P1 pin: logBase 8 2 = 3, also when the base is a column") = secure {
    val op = BuiltinCall(LogBase, List(OpLiteral(d(8.0)), ColumnValue("b", DoubleT(false))))
    (op.simplify(Map()).eval(Map("b" -> d(2.0))) ?= d(3.0)) &&
    (BuiltinCall(LogBase, List(OpLiteral(d(8.0)), OpLiteral(d(2.0)))).simplify(Map()) ?= (OpLiteral(d(3.0)): Op))
  }

  // ------------------------------------------------------------------ P6: cast to Byte (S-17)

  property("P6: `cast x Byte` builds a Byte") = forAll(Gen.choose(-128, 127)) { k =>
    (i(k).cast(ByteT(false)) ?= (ByteExpr(false, k.toByte): PrimExpr)) &&
    (i(k).cast(ByteT(false)).typ ?= (ByteT(false): PrimT))   // pre-fix: ShortT(false)
  }

  // ------------------------------------------------------------------ P7: dateDiff / dateAdd on the GMT calendar (S-19, S-28)

  private val gmt = TimeZone.getTimeZone("GMT")
  private def ts(y: Int, mo: Int, day: Int, h: Int = 0, mi: Int = 0): Timestamp = {
    val c = new GregorianCalendar(gmt); c.clear(); c.set(y, mo - 1, day, h, mi, 0); new Timestamp(c.getTimeInMillis)
  }
  private def T(t: Timestamp): PrimExpr = TimestampExpr(false, t)
  private def diff(u: TimeUnit, a: Timestamp, b: Timestamp): PrimExpr =
    DateDiff(u, OpLiteral(T(a)), OpLiteral(T(b))).eval(Map())

  private val genInstant: Gen[Timestamp] =
    Gen.choose(-40000L * 86400000L, 40000L * 86400000L).map(new Timestamp(_))   // ~1860..2079
  private val units: List[TimeUnit] = List(TimeUnit.Second, TimeUnit.Day, TimeUnit.Week, TimeUnit.Month, TimeUnit.Year)

  property("P7: dateDiff in memory answers every unit, antisymmetrically, and NULL for a NULL end") =
    forAll(genInstant, genInstant, Gen.oneOf(units)) { (a, b, u) =>
      val ab = diff(u, a, b); val ba = diff(u, b, a)   // pre-fix: sys.error("datediff is meant to be used from SQL ...")
      (ab.extractInt ?= -ba.extractInt) &&
      (DateDiff(u, OpLiteral(T(a)), OpLiteral(NullExpr(TimestampT(true)))).eval(Map()).isNull ?= true)
    }

  property("P7: dateDiff day = GMT midnights crossed; month/year = calendar boundaries; week = Sundays") =
    forAll(genInstant, genInstant) { (a, b) =>
      def cal(t: Timestamp) = { val c = new GregorianCalendar(gmt); c.setTime(t); c }
      val dayA = Math.floorDiv(a.getTime, 86400000L); val dayB = Math.floorDiv(b.getTime, 86400000L)
      val (ca, cb) = (cal(a), cal(b))
      (diff(TimeUnit.Day, a, b).extractInt ?= (dayB - dayA).toInt) &&
      (diff(TimeUnit.Week, a, b).extractInt ?= (Math.floorDiv(dayB - 3, 7L) - Math.floorDiv(dayA - 3, 7L)).toInt) &&
      (diff(TimeUnit.Month, a, b).extractInt ?=
        (cb.get(Calendar.YEAR) * 12 + cb.get(Calendar.MONTH)) - (ca.get(Calendar.YEAR) * 12 + ca.get(Calendar.MONTH))) &&
      (diff(TimeUnit.Year, a, b).extractInt ?= cb.get(Calendar.YEAR) - ca.get(Calendar.YEAR))
    }

  property("P7 pins: SQL Server's datediff answers on known dates") = secure {
    (diff(TimeUnit.Day, ts(2024, 1, 15), ts(2024, 3, 1)).extractInt ?= 46) &&
    (diff(TimeUnit.Day, ts(2024, 1, 1, 23), ts(2024, 1, 2, 1)).extractInt ?= 1) &&      // a boundary, not 24 hours
    (diff(TimeUnit.Month, ts(2024, 1, 31), ts(2024, 2, 1)).extractInt ?= 1) &&
    (diff(TimeUnit.Year, ts(2023, 12, 31), ts(2024, 1, 1)).extractInt ?= 1) &&
    (diff(TimeUnit.Week, ts(2024, 1, 6), ts(2024, 1, 7)).extractInt ?= 1) &&            // Saturday -> Sunday
    (diff(TimeUnit.Week, ts(2024, 1, 7), ts(2024, 1, 13)).extractInt ?= 0) &&           // Sunday -> Saturday
    (diff(TimeUnit.Second, ts(2024, 1, 1), ts(2024, 1, 1, 0, 1)).extractInt ?= 60)
  }

  property("P7 (S-28): dateAdd by days is exact multiples of 86400000 ms whatever the machine's zone") =
    forAll(genInstant, Gen.choose(-400, 400)) { (t, n) =>
      // Pre-fix under a DST zone (this machine is America/Denver): an hour off across a change.
      TimeUnit.Day.incrementTimestamp(t, n).getTime ?= t.getTime + n * 86400000L
    }

  property("P7 pins: dateAdd across the 2024-03-10 DST change, and a month onto January 31st") = secure {
    (TimeUnit.Day.incrementTimestamp(ts(2024, 3, 9, 12), 1) ?= ts(2024, 3, 10, 12)) &&
    (TimeUnit.Month.incrementTimestamp(ts(2024, 1, 31), 1) ?= ts(2024, 2, 29)) &&
    (TimeUnit.Week.increment(ts(2024, 3, 9), 1).getTime ?= ts(2024, 3, 16).getTime) &&
    (DateAdd(OpLiteral(T(ts(2024, 3, 9, 12))), OpLiteral(i(1)), TimeUnit.Day).eval(Map()) ?= T(ts(2024, 3, 10, 12)))
  }
}
