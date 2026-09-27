package com.clarifi.reporting
package sql

import scalaz._
import Scalaz._
import org.scalacheck._

import backends._
import Op._
import Predicate._
import PrimT._
import com.clarifi.reporting.relational.SMEnv._
import com.clarifi.reporting.relational._
import com.clarifi.machines.Process

import java.sql.Timestamp
import java.util.{ Calendar, TimeZone }


object SqlEmitterGens {
  import Gen.{const=>_, _}

  /** Like `Gen.listOfN` but guarantee unique elements.  Will not
    * terminate if `elts` won't produce `n` unique elements!
    */
  def setOfN[A](count: Int, elt: Gen[A]): Gen[Set[A]] = {
    def basis(xs: Set[A]): Gen[Set[A]] =
      if (xs.size == count) Gen.const(xs)
      else Gen.listOfN(count - xs.size, elt).flatMap {more => basis(xs ++ more)}
    basis(Set.empty[A])
  }

  private val nonEmptyAlphaStr = alphaStr filter (!_.isEmpty)

  /** Answer the standard Gen instance for Ts. */
  def stdGen[T](implicit ev: Arbitrary[T]): Gen[T] = ev.arbitrary

  private val allScanners = Seq(Scanners.MySQLInnoDB(dummySmenv), Scanners.MySQL(dummySmenv),
                                Scanners.MicrosoftSQLServer(dummySmenv),
                                Scanners.Postgres(dummySmenv),
                                Scanners.Vertica(dummySmenv), Scanners.SQLite(dummySmenv))
  private val allEmitters = {
    import SqlEmitter._
    Seq(mySqlInnoDBEmitter, mySqlEmitter, msSqlEmitter,
        postgreSqlEmitter, verticaSqlEmitter, sqliteEmitter)
  }

  // Engine arbs
  implicit val backendArb: Arbitrary[SqlScanner] =
    Arbitrary(oneOf(allScanners))
  implicit val emitterArb: Arbitrary[SqlEmitter] =
    Arbitrary(oneOf(allEmitters))

  // SQL arbs
  val sqlBools = stdGen[Boolean] map (SqlBool(_))
  val sqlInts = stdGen[Int] map (SqlInt(_))
  val sqlOrders = oneOf(Seq(SqlAsc, SqlDesc))
  val litSqlExprs = oneOf(sqlBools, sqlInts) map (LitSqlExpr(_))

  /** Make `OverSqlExpr`s. */
  val overSqlExprs = for {
    i <- sqlInts map (LitSqlExpr(_))
  } yield OverSqlExpr(i, SqlOver(Nil, Nil, None, None))

  /** Make FromTables exprs. */
  val fromTables = for {
    n <- nonEmptyAlphaStr
    a <- nonEmptyAlphaStr
    l <- nonEmptyListOf(nonEmptyAlphaStr)
  } yield FromTable(TableName(n), l.toSet.toList, Some(TableName(a)))

  private def trivialHeader(cols: Seq[ColumnName]): Header =
    cols.zip(Stream.continually(PrimT.IntT())).toMap

  /** Make `SqlJoinOn`s.  The right-hand column of every pair is a column
    * of the RIGHT table (the generator used to qualify both sides with the
    * left alias, so no right-table column was ever emitted: SQL audit N-1). */
  val joinOnExprs = for {
    left      <- fromTables
    right     <- fromTables
    joinColCt <- choose(1, left.cols.size min right.cols.size)
    joinLCols <- pick(joinColCt, left.cols)
    joinRCols <- pick(joinColCt, right.cols)
  } yield SqlJoinOn(left,
                    right,
                    joinLCols.map(c => ColumnSqlExpr(left.alias.getOrElse(left.table),c)).zip(
                        joinRCols.map(c => ColumnSqlExpr(right.alias.getOrElse(right.table),c))
                      ).toSet)
}

/** The SQL text each dialect emits, and, for the two live dialects, what
  * that text does when executed: SQLite through the bundled sqlite-jdbc in
  * memory (always), SQL Server when `ERMINE_DB_URL`/`_USER`/`_PASSWORD` are
  * set (`tracker/tools/db-reports.sh` shows how).  Each execution property
  * names the SQL-audit item it pins (tracker/sql-audit/WORKLIST.md, area
  * `emitter`); every one of them failed before its fix. */
object TestSqlEmitters extends Properties("emitSql") {
  import Prop._
  import SqlEmitterGens._

  implicit val overSqlExprArb: Arbitrary[OverSqlExpr] = Arbitrary(overSqlExprs)
  implicit val joinOnExprArb: Arbitrary[SqlJoinOn] = Arbitrary(joinOnExprs)

  // ------------------------------------------------------------------ text, every dialect

  /** E1: the dialects with window functions emit ` over (`; MySQL (5.x has
    * none) refuses with an exception instead of splicing placeholder text
    * into the SELECT list. */
  property("window functions are OVER or a refusal, never placeholder text") = forAll {
    (emitter: SqlEmitter, overexpr: OverSqlExpr) =>
      val attempt = scala.util.Try(overexpr.emitSql(emitter).run)
      val usesOver = attempt.toOption.exists(s => ("""(?s) over \(.*\)""".r findFirstIn s).isDefined)
      val hasTodo = attempt.toOption.exists(_ contains "TODO")
      (!hasTodo :| "placeholder text reached the SQL") &&
      ((if (emitter.isInstanceOf[MySqlEmitter]) attempt.isFailure else usesOver) :| attempt.toString)
  }

  private def danglingTable(tname: String):
    scala.util.matching.Regex =
      (java.util.regex.Pattern.quote(tname) + """\.[^A-Za-z]""").r

  property("joinOn emitters distribute columns") = forAll {
    (joinOnExpr: SqlJoinOn, emitter: SqlEmitter) =>
      val sql = joinOnExpr.emitSql(emitter)
      (sql.run + " should make sense") |: (joinOnExpr match {
        case SqlJoinOn(FromTable(ltable, _, _),
                       FromTable(rtable, _, _),
                       _, _) =>
          Seq(ltable, rtable) forall { tablechoice =>
            danglingTable(tablechoice.name).
            findFirstIn(sql.run) match {
              case None => true
              case _    => false
            }
          }
        case _ => false
      })
  }

  /** E4: `A JOIN (B JOIN C on ..) on ..` on SQLite and MySQL, which reject
    * the bare right-nested form. */
  property("a right-nested join is parenthesised where the grammar needs it") = forAll {
    (outer: SqlJoinOn, inner: SqlJoinOn, emitter: SqlEmitter) =>
      val nested = SqlJoinOn(outer.r1, inner, outer.on, outer.op)
      val sql = nested.emitSql(emitter).run
      val paren = (" JOIN(" + inner.emitSql(emitter).run + ") on (")
      val needsParens = emitter.isInstanceOf[SqliteEmitter] || emitter.isInstanceOf[MySqlEmitter]
      (needsParens ==> (sql contains paren)) :| sql
  }

  private def exactMatches(r: scala.util.matching.Regex, s: String) =
    r.findPrefixMatchOf(s).map {m => m.start === 0 && m.end === s.size}.
      getOrElse(false)

  private def matchProp(r: scala.util.matching.Regex, s: String) =
    exactMatches(r, s) :| (""""%s" must match "%s"""" format (s, r))

  property("SQL emitted stays more or less the same") = forAll {
    (emitter: SqlEmitter) =>
      // SQLite quotes identifiers since E4; Vertica still emits them bare.
      val idq = if (emitter eq SqlEmitter.verticaSqlEmitter) "" else "."
      Seq("""(?x)select\s(distinct\s)?\(.dbaquestions.\..a.\)\s.a.,
             \s\(.dbaquestions.\..n.\)\s.n.,
             \s\(.dbaquestions.\..q.\)\s.q.\sfrom
             \s.dbaquestions.\s.dbaquestions.\s
             where\s\(\(.dbaquestions.\..n.\)\s=\s\(?1\)?\)\s?"""
          -> SqlSelect(attrs=("nqa".map(_.toString)
                              .map{c=>c->ColumnSqlExpr(TableName("dbaquestions"),c)}.toMap),
                       sources=SourceList(FromTable(TableName("dbaquestions"), List("a","n","q"), Some(TableName("dbaquestions")))),
                       where=List(SqlEq(ColumnSqlExpr(TableName("dbaquestions"), "n"),
                                           LitSqlExpr(SqlInt(1))))),
          """(?x)select\s(distinct\s)?\(.yesiwilltable.\..yes.\)\s.yes.\sfrom\s.yesiwilltable."""
          -> SqlSelect(attrs=Map("yes" -> ColumnSqlExpr(TableName("yesiwilltable"), "yes")),
                       sources = SourceList(FromTable(TableName("yesiwilltable"), List("yes"), None)))).
      map {case (rs, sql) =>
        val r = rs.replaceAll("""(?<!\\)\.""", idq).r // hack out table/column quoting
        matchProp(r, sql.emitSql(emitter).run)
      }.
      foldLeft(true: Prop)(_ && _)
  }

  val if023 = {
    val x = ColumnValue("x", IntT())
    def num(n: Int) = OpLiteral(IntExpr(false, n))
    def eqx(n: Int) = Eq(x, num(n))
    If(Not(eqx(0)),
       If(eqx(2), num(2),
          If(eqx(3), num(3), Add(x, num(3)))),
       num(0))
  }

  /** E15: an `if` in the CONSEQUENT stays a nested CASE (the old
    * `case when not t then z when t2 ...` merge answered from the inner
    * branches for an unknown `t`); an `if` in the ALTERNATE still flattens. */
  property("if chains become cases") = secure {
    val b = Scanners.MicrosoftSQLServer(dummySmenv)
    val e = SqlEmitter.msSqlEmitter
    ("""(case when not (([bob].[x]) = (0)) then"""
     + """ (case when ([bob].[x]) = (2) then 2"""
     + """ when ([bob].[x]) = (3) then 3"""
     + """ else (([bob].[x]) + (3)) end)"""
     + """ else (0) end)""") =?
       b.compileOp(if023, ColumnSqlExpr(TableName("bob"), _))(e).emitSql(e).run
  }

  private val intCols = Gen.oneOf("a", "b", "c").map(c => ColumnValue(c, IntT()): Op)
  private val smallLits = Gen.choose(-3, 3).map(n => OpLiteral(IntExpr(false, n)): Op)
  private val smallOps: Gen[Op] = Gen.oneOf(intCols, smallLits)

  /** E14: `Relation.Predicate`'s `a <= b` is `a < b || a == b`; with the same
    * operands it compiles to one `<=`, with different ones it stays an OR. */
  property("<= and >= over the same operands fold to one comparison") = forAll(smallOps, smallOps, smallOps, smallOps) {
    (a: Op, b: Op, c: Op, d: Op) =>
      val sc = Scanners.SQLite(dummySmenv)
      val look = ColumnSqlExpr(TableName("t"), _: String)
      def comp(p: Predicate) = sc.compilePredicate(p, look)(SqlEmitter.sqliteEmitter)
      val same = (a == c && b == d) || (a == d && b == c)
      val le = comp(Or(Lt(a, b), Eq(c, d)))
      val ge = comp(Or(Eq(c, d), Gt(a, b)))
      val expectLe: SqlPredicate = if (same) SqlLte(sc.compileOp(a, look)(SqlEmitter.sqliteEmitter), sc.compileOp(b, look)(SqlEmitter.sqliteEmitter)) else SqlOr(comp(Lt(a, b)), comp(Eq(c, d)))
      val expectGe: SqlPredicate = if (same) SqlGte(sc.compileOp(a, look)(SqlEmitter.sqliteEmitter), sc.compileOp(b, look)(SqlEmitter.sqliteEmitter)) else SqlOr(comp(Eq(c, d)), comp(Gt(a, b)))
      (le ?= expectLe) && (ge ?= expectGe)
  }

  private val awkwardDoubles: Gen[Double] =
    Gen.oneOf(Gen.const(Double.NaN), Gen.const(Double.PositiveInfinity), Gen.const(Double.NegativeInfinity),
              Arbitrary.arbitrary[Double])

  /** E8 (decision D6): no dialect can spell NaN or an infinity. */
  property("NaN and Infinity doubles emit as NULL on every dialect") = forAll(Arbitrary.arbitrary[SqlEmitter], awkwardDoubles) {
    (emitter: SqlEmitter, d: Double) =>
      val sql = LitSqlExpr(SqlDouble(d)).emitSql(emitter).run
      if (d.isNaN || d.isInfinite) (sql ?= "NULL")
      else if (emitter.isInstanceOf[MsSqlEmitter]) (sql ?= (if (d.toString contains "E") d.toString else d.toString + "E0"))
      else (sql ?= d.toString)
  }

  /** E24: a SQL Server double literal is a float (an exponent form), so
    * `1.0 / 3.0` is not a DECIMAL division. */
  property("SQL Server double literals are floats") = forAll(Arbitrary.arbitrary[Double].filter(x => !x.isNaN && !x.isInfinite)) {
    (d: Double) =>
      val sql = LitSqlExpr(SqlDouble(d)).emitSql(SqlEmitter.msSqlEmitter).run
      ((sql contains "E") :| sql) && ((java.lang.Double.parseDouble(sql) == d) :| sql)
  }

  /** E22: a typed NULL literal is `cast(NULL as <type>)` on every dialect but
    * MySQL (whose CAST targets are not its column types). */
  property("NULL literals carry their type") = forAll(Arbitrary.arbitrary[SqlEmitter], Gen.oneOf(IntT(true), DoubleT(true), StringT(0, true), DateT(true))) {
    (emitter: SqlEmitter, t: PrimT) =>
      val sql = SqlExpr.compileLiteral(NullExpr(t)).emitSql(emitter).run
      if (emitter.isInstanceOf[MySqlEmitter]) (sql ?= "NULL")
      else (sql ?= ("cast(NULL as " + emitter.sqlTypeName(t.withNull).run + ")"))
  }

  /** E23: a `SqlSelect` is ordered by its aliases, never by its expressions. */
  property("orderBy orders a select by its aliases") = forAll(Gen.nonEmptyListOf(Gen.oneOf("a", "b", "c")), sqlOrders) {
    (cols: List[String], o: SqlOrder) =>
      val x = ColumnSqlExpr(TableName("t"), "x")
      val sel = SqlSelect(attrs = Map("a" -> x, "b" -> x, "c" -> LitSqlExpr(SqlInt(1))),
                          sources = SourceList(FromTable(TableName("t"), List("x"), None)))
      val q = SqlQuery.orderBy(sel, cols.map(c => (c, o)))
      val sql = q.emitSql(SqlEmitter.msSqlEmitter).run
      val tail = sql.substring(sql.indexOf(" order by ") + " order by ".length)
      (q.isInstanceOf[SqlOrderBy] :| q.toString) &&
        (tail ?= cols.distinct.map(c => "[" + c + "] " + o.emitSql.run).mkString(", "))
  }

  /** E21: a GROUP BY whose expressions are all constants is dropped (SQL
    * Server refuses constant group expressions) and `having count(*) > 0`
    * keeps an empty input from answering one phantom row. */
  property("an all-constant GROUP BY gets having count(*) > 0") = forAll {
    (emitter: SqlEmitter, n: Int) =>
      val t = TableName("t")
      def sel(where: List[SqlPredicate]) =
        SqlSelect(attrs = Map("s" -> FunSqlExpr("SUM", List(ColumnSqlExpr(t, "x"))), "k" -> LitSqlExpr(SqlInt(n))),
                  sources = SourceList(FromTable(t, List("x"), None)), where = where,
                  groupBy = List(LitSqlExpr(SqlInt(n))), isAggregated = true)
      val sql = sel(List()).emitSql(emitter).run
      val mixed = sel(List()).copy(groupBy = List(LitSqlExpr(SqlInt(n)), ColumnSqlExpr(t, "x"))).emitSql(emitter).run
      ((sql contains " having ((count(*)) > (0))") :| sql) && (!(sql contains " group by ") :| sql) &&
        (!(mixed contains "having") :| mixed)
  }

  /** E6: SQL Server literals carry `N`; the other dialects are unchanged. */
  property("SQL Server string literals carry the N prefix") = forAll {
    (emitter: SqlEmitter, s: String) =>
      val sql = LitSqlExpr(SqlString(s)).emitSql(emitter).run
      val body = "'" + s.replace("'", "''") + "'"
      if (emitter.isInstanceOf[MsSqlEmitter]) (sql ?= ("N" + body)) else (sql ?= body)
  }

  /** E11: a SQL Server date literal is CAST(.. AS DATE), independent of the
    * login's SET LANGUAGE / DATEFORMAT. */
  property("SQL Server date literals are CAST(.. AS DATE)") = forAll {
    (d: java.util.Date) =>
      val sql = SqlDate(d).emitSql(SqlEmitter.msSqlEmitter).run
      (sql startsWith "CAST('") && (sql endsWith "' AS DATE)")
  }

  private val headerGen: Gen[Header] = for {
    n <- Gen.choose(1, 4)
    ts <- Gen.listOfN(n, Gen.oneOf(IntT(false), DoubleT(false), StringT(0, true), DateT(false), BooleanT(true)))
  } yield ts.zipWithIndex.map { case (t, i) => ("c" + i, t) }.toMap

  /** E10: every NULL of an empty relation is cast to its column's type
    * (MySQL keeps its own FROM-DUAL form). */
  property("emitEmpty types its NULLs") = forAll(Arbitrary.arbitrary[SqlEmitter], headerGen) {
    (emitter: SqlEmitter, h: Header) =>
      val sql = SqlEmpty(h).emitSql(emitter).run
      val typed = h.keys.forall(c => sql contains ("(cast(NULL as " + emitter.sqlTypeName(h(c).withNull).run + ")) " + emitter.emitColumnName(c).run))
      (emitter.isInstanceOf[MySqlEmitter] || typed) :| sql
  }

  /** E5: an OFFSET with no upper bound gets a LIMIT before it on the
    * dialects whose grammar demands one. */
  property("an offset without a bound emits a LIMIT before it") = forAll(Arbitrary.arbitrary[SqlEmitter], Gen.choose(1, 50)) {
    (emitter: SqlEmitter, from: Int) =>
      val sql = emitter.emitLimit(Some(from), None).run
      emitter match {
        case _: SqliteEmitter => sql ?= (" limit -1 offset " + (from - 1))
        case _: MySqlEmitter => sql ?= (" limit 18446744073709551615 offset " + (from - 1))
        case _: PostgreSqlEmitter | _: VerticaSqlEmitter => sql ?= (" limit ALL offset " + (from - 1))
        case _: MsSqlEmitter => sql ?= (" offset " + (from - 1) + " rows")
        case _ => Prop.undecided
      }
  }

  /** E12: an unbounded string is `nvarchar(max)` on SQL Server, except as a
    * key column of a CREATE TABLE, which SQL Server cannot index. */
  property("SQL Server unbounded strings are nvarchar(max) except in a key") = secure {
    val e = SqlEmitter.msSqlEmitter
    import scala.collection.immutable.SortedSet
    val h: Header = Map("k" -> StringT(0, false), "v" -> StringT(0, true))
    val create = SqlCreate(TableName("t", List(), TableName.Temporary), h,
                           hints = TableHints.empty.withPK(SortedSet("k")))
    val ddl = create.emitSql(e).run
    (e.sqlTypeName(StringT(0, true)).run ?= "nvarchar(max)") &&
      ((ddl contains "[k] nvarchar(450) not null") :| ddl) &&
      ((ddl contains "[v] nvarchar(max)") :| ddl) &&
      (e.sqlPrimT(java.sql.Types.CHAR, "uniqueidentifier", 36) ?= Some(UuidT())) &&
      (e.sqlPrimT(java.sql.Types.NUMERIC, "numeric", 19) ?= Some(DoubleT()))
  }

  /** E16: SQL Server drops its temp tables after a scan. */
  property("SQL Server drops temp tables") = secure {
    val t = TableName("t1", List(), TableName.Temporary)
    SqlEmitter.msSqlEmitter.emitDropTempTable.map(_(t).run) ?= Some("DROP TABLE [##t1]")
  }

  // ------------------------------------------------------------------ execution on SQLite in memory

  private def i(n: Int): PrimExpr = IntExpr(false, n)
  private def d(x: Double): PrimExpr = DoubleExpr(false, x)
  private def s(x: String): PrimExpr = StringExpr(false, x)
  private def ns(x: Option[String]): PrimExpr = x.map(StringExpr(true, _)).getOrElse(NullExpr(StringT(0, true)))
  private def ts(millis: Long): PrimExpr = TimestampExpr(false, new Timestamp(millis))
  private def dt(millis: Long): PrimExpr = DateExpr(false, new java.util.Date(millis))
  private def lit(rows: Record*): Relation[Nothing, Nothing] = SmallLit(NonEmptyList(rows.head, rows.tail: _*))

  private val sqliteScanner = Scanners.SQLite(dummySmenv)
  private val sqliteRun = Runners.SQLite("jdbc:sqlite::memory:")

  import scalaz.std.vector._
  private def rows(r: Relation[Nothing, Nothing], order: List[(String, SortOrder)] = List()): Vector[Record] =
    sqliteRun.run(sqliteScanner.scanRel(r, Process((x: Record) => Vector(x)), order))
  private def sqlOf(r: Relation[Nothing, Nothing]): String = sqliteScanner.dumpRel(r)

  private val gmt = TimeZone.getTimeZone("GMT")
  private def gmtAdd(millis: Long, field: Int, n: Int): Long = {
    val c = Calendar.getInstance(gmt)
    c.setTimeInMillis(millis)
    c.add(field, n)
    c.getTimeInMillis
  }
  private def gmtField(millis: Long, field: Int): Int = {
    val c = Calendar.getInstance(gmt)
    c.setTimeInMillis(millis)
    c.get(field)
  }

  // a timestamp between 1990 and 2035, with milliseconds
  private val millisGen: Gen[Long] = Gen.choose(631152000000L, 2051222400000L)
  // whole days between 1990 and 2035, GMT midnight
  private val dayGen: Gen[Long] = Gen.choose(7305, 23741).map(_ * 86400000L)

  /** E4: keyword column names execute on SQLite and read back bare. */
  property("SQLite quotes column names and reads them back (E4)") = secure {
    val r = lit(Map("group" -> i(3), "order" -> i(1), "select" -> i(2), "user" -> s("u")),
                Map("group" -> i(7), "order" -> i(5), "select" -> i(6), "user" -> s("v")))
    val out = rows(Filter(r, Gt(ColumnValue("order", IntT()), OpLiteral(i(2)))))
    out ?= Vector(Map("group" -> i(7), "order" -> i(5), "select" -> i(6), "user" -> s("v")))
  }

  /** E13: a literal is ONE `select .. from (values ..)` on SQLite, and a
    * duplicate row in the literal stays one row (the oracle's O-2). */
  property("SQLite literals are one VALUES select with distinct rows (E13)") = forAll(Gen.choose(1, 6), Gen.choose(1, 3)) {
    (n: Int, dup: Int) =>
      val rs = (1 to n).map(k => Map("k" -> i(k), "s" -> s("v" + k))).toList
      val withDup = rs ++ List.fill(dup)(rs.head)
      val r = SmallLit(NonEmptyList(withDup.head, withDup.tail: _*))
      val sql = sqlOf(r)
      val selects = "select".r.findAllIn(sql.toLowerCase).size
      ((selects ?= 1) :| sql) &&
        ((sql.toLowerCase contains "from (values (") :| sql) &&
        (rows(r).toSet ?= rs.toSet) &&
        (rows(r).size ?= rs.size)
  }

  /** E1: RANK over a partition executes on SQLite. */
  property("SQLite window functions execute (E1)") = secure {
    val r = lit(Map("k" -> i(1), "x" -> i(1)), Map("k" -> i(1), "x" -> i(2)), Map("k" -> i(2), "x" -> i(3)))
    val w = Window(List(ColumnValue("k", IntT())), List((ColumnValue("x", IntT()), SortOrder.Desc)), Frame(None, None))
    val out = rows(Combine(r, Attribute("y", IntT(false)), Windowed(Rank, w)))
    out.map(rec => (rec("k").extractInt, rec("x").extractInt, rec("y").extractInt)).toSet ?=
      Set((1, 2, 1), (1, 1, 2), (2, 3, 1))
  }

  /** E3: population deviation/variance over random doubles agree with the
    * two-pass formula to 1e-9. */
  property("SQLite stddev and variance agree with the population formula (E3)") = forAll(Gen.nonEmptyListOf(Gen.choose(-100.0, 100.0))) {
    (xs: List[Double]) =>
      val r = SmallLit(NonEmptyList(xs.head, xs.tail: _*).zipWithIndex.map { case (x, k) => Map("k" -> i(k), "x" -> d(x)): Record })
      val mean = xs.sum / xs.size
      val varPop = xs.map(x => (x - mean) * (x - mean)).sum / xs.size
      val sd = rows(Aggregate(r, Attribute("sd", DoubleT(false)), AggFunc.Stddev(ColumnValue("x", DoubleT())))).head("sd").extractDouble
      val vr = rows(Aggregate(r, Attribute("vr", DoubleT(false)), AggFunc.Variance(ColumnValue("x", DoubleT())))).head("vr").extractDouble
      ((math.abs(sd - math.sqrt(varPop)) < 1e-9) :| ("stddev " + sd + " vs " + math.sqrt(varPop))) &&
        ((math.abs(vr - varPop) < 1e-9) :| ("variance " + vr + " vs " + varPop))
  }

  /** An average of an Int column is an Int, truncated toward zero, as SQL
    * Server computes it and the header types it; SQLite's REAL `avg()` is
    * cast back (differential oracle, under the E7 flag). */
  property("SQLite averages of integers are integers like SQL Server") = forAll(Gen.nonEmptyListOf(Gen.choose(-9, 9))) {
    (xs: List[Int]) =>
      val r = SmallLit(NonEmptyList(xs.head, xs.tail: _*).zipWithIndex.map { case (x, k) => Map("k" -> i(k), "x" -> i(x)): Record })
      val out = rows(Aggregate(r, Attribute("a", IntT(true)), AggFunc.Avg(ColumnValue("x", IntT()))))
      val expected = (xs.sum.toLong / xs.size).toInt // Long division truncates toward zero, as T-SQL does
      val sql = sqlOf(r)
      (out.head("a").extractInt ?= expected) :| ("avg of " + xs)
  }

  private val unitGen: Gen[TimeUnit] = Gen.oneOf(TimeUnit.Millisecond, TimeUnit.Second, TimeUnit.Day, TimeUnit.Week, TimeUnit.Month, TimeUnit.Year)
  private def calField(u: TimeUnit): (Int, Int) = u match {
    case TimeUnit.Millisecond => (Calendar.MILLISECOND, 1)
    case TimeUnit.Second => (Calendar.SECOND, 1)
    case TimeUnit.Day => (Calendar.DATE, 1)
    case TimeUnit.Week => (Calendar.DATE, 7)
    case TimeUnit.Month => (Calendar.MONTH, 1)
    case TimeUnit.Year => (Calendar.YEAR, 1)
  }

  /** E2: `dateAdd` on SQLite agrees with a GMT `Calendar#add` (what the
    * in-memory `TimeUnit.incrementTimestamp` computes, once it runs in GMT:
    * prims item P7) for every unit, including the month-end clamp. */
  property("SQLite dateAdd agrees with a GMT calendar (E2)") = forAll(millisGen, Gen.choose(-40, 40), unitGen) {
    (t: Long, n: Int, u: TimeUnit) =>
      val r = lit(Map("k" -> i(1), "ts" -> ts(t)))
      val out = rows(Combine(r, Attribute("ts2", TimestampT(false)), DateAdd(ColumnValue("ts", TimestampT()), OpLiteral(i(n)), u)))
      val (field, mult) = calField(u)
      val expected = gmtAdd(t, field, n * mult)
      (out.head("ts2").extractTimestamp.getTime ?= expected) :| (u.toString + " " + n + " from " + new Timestamp(t))
  }

  property("SQLite dateAdd clamps the month end like Calendar and DATEADD (E2)") = secure {
    val jan31 = 1706695872123L // 2024-01-31 10:11:12.123 GMT
    val r = lit(Map("k" -> i(1), "ts" -> ts(jan31)))
    val out = rows(Combine(r, Attribute("ts2", TimestampT(false)), DateAdd(ColumnValue("ts", TimestampT()), OpLiteral(i(1)), TimeUnit.Month)))
    out.head("ts2").extractTimestamp.getTime ?= 1709201472123L // 2024-02-29 10:11:12.123
  }

  /** E2: `dateDiff` counts unit boundaries crossed, as T-SQL DATEDIFF does. */
  property("SQLite dateDiff counts boundaries crossed (E2)") = forAll(millisGen, millisGen, unitGen) {
    (a: Long, b: Long, u: TimeUnit) =>
      val r = lit(Map("k" -> i(1), "s" -> ts(a), "e" -> ts(b)))
      val out = rows(Combine(r, Attribute("n", IntT(false)), DateDiff(u, ColumnValue("s", TimestampT()), ColumnValue("e", TimestampT()))))
      def floorDiv(x: Long, m: Long) = Math.floorDiv(x, m)
      def dayStart(x: Long) = floorDiv(x, 86400000L)
      // Sunday-based week number: days since the epoch (a Thursday) shifted so weeks start on Sunday
      def weekStart(x: Long) = floorDiv(dayStart(x) + 4, 7)
      val expected: Long = u match {
        case TimeUnit.Millisecond => b - a
        case TimeUnit.Second => floorDiv(b, 1000L) - floorDiv(a, 1000L)
        case TimeUnit.Day => dayStart(b) - dayStart(a)
        case TimeUnit.Week => weekStart(b) - weekStart(a)
        case TimeUnit.Month => (gmtField(b, Calendar.YEAR) - gmtField(a, Calendar.YEAR)) * 12L +
                               (gmtField(b, Calendar.MONTH) - gmtField(a, Calendar.MONTH))
        case TimeUnit.Year => (gmtField(b, Calendar.YEAR) - gmtField(a, Calendar.YEAR)).toLong
      }
      (out.head("n").extractInt.toLong ?= expected.toInt.toLong) :| (u.toString + " " + new Timestamp(a) + " .. " + new Timestamp(b))
  }

  property("SQLite dateDiff pins: 2024-01-15 .. 2024-03-01 is 46 days, 2 months, 0 years (E2)") = secure {
    val r = lit(Map("k" -> i(1), "s" -> dt(1705276800000L), "e" -> dt(1709251200000L)))
    def diff(u: TimeUnit) = rows(Combine(r, Attribute("n", IntT(false)), DateDiff(u, ColumnValue("s", DateT()), ColumnValue("e", DateT())))).head("n").extractInt
    // six Sundays lie between Monday 2024-01-15 and Friday 2024-03-01
    (diff(TimeUnit.Day) ?= 46) && (diff(TimeUnit.Month) ?= 2) && (diff(TimeUnit.Year) ?= 0) && (diff(TimeUnit.Week) ?= 6)
  }

  /** E7: `//` on doubles floors like `PrimExpr.floordiv` and SQL Server. */
  property("SQLite // on doubles agrees with the in-memory floordiv (E7)") = forAll(Gen.choose(-50.0, 50.0), Gen.oneOf(-7.0, -2.0, 1.5, 2.0, 3.0, 7.5) /* a divisor whose floor is 0 divides by zero on every path (F-4) */) {
    (x: Double, y: Double) =>
      val r = lit(Map("k" -> i(1), "x" -> d(x), "y" -> d(y)))
      val out = rows(Combine(r, Attribute("q", DoubleT(false)), FloorDiv(ColumnValue("x", DoubleT()), ColumnValue("y", DoubleT()))))
      val expected = (d(x) floordiv d(y)).extractDouble
      (out.head("q").extractDouble ?= expected) :| (x + " // " + y)
  }

  property("SQLite // on integers truncates like the in-memory floordiv (E7)") = forAll(Gen.choose(-50, 50), Gen.oneOf(-3, -2, 1, 2, 7)) {
    (x: Int, y: Int) =>
      val r = lit(Map("k" -> i(1), "x" -> i(x), "y" -> i(y)))
      val out = rows(Combine(r, Attribute("q", IntT(false)), FloorDiv(ColumnValue("x", IntT()), ColumnValue("y", IntT()))))
      (out.head("q").extractInt ?= (i(x) floordiv i(y)).extractInt) :| (x + " // " + y)
  }

  /** E9: a timestamp literal is INTEGER milliseconds like a loaded column,
    * so a comparison between them is numeric.  101 rows force the
    * temp-table load path (`SqlScanner`'s >100-row literal). */
  property("SQLite timestamp literals compare with a loaded timestamp column (E9)") = forAll(millisGen) {
    (pivot: Long) =>
      val all = (0 until 101).map(k => Map("k" -> i(k), "ts" -> ts(pivot - 50 * 60000L + k * 60000L)): Record).toList
      val r = SmallLit(NonEmptyList(all.head, all.tail: _*))
      val out = rows(Filter(r, Gt(ColumnValue("ts", TimestampT()), OpLiteral(ts(pivot)))))
      (out.size ?= 50) :| ("expected the 50 rows after " + new Timestamp(pivot))
  }

  /** E9: casts between dates and strings on SQLite are calendar
    * conversions in ISO 8601, not the milliseconds as text. */
  property("SQLite casts between dates and strings (E9)") = forAll(dayGen, millisGen) {
    (day: Long, t: Long) =>
      // two rows with different values, so no column is a constant the optimizer
      // folds into the ops (a folded cast runs in memory, the prims area's path)
      val r = lit(Map("k" -> i(1), "d" -> dt(day), "ts" -> ts(t), "s" -> s("2024-01-15"), "st" -> s("2024-01-15 10:11:12.123")),
                  Map("k" -> i(2), "d" -> dt(day + 86400000L), "ts" -> ts(t + 1), "s" -> s("2023-06-30"), "st" -> s("2023-06-30 01:02:03.004")))
      val out = rows(Project(r, Map(
        Attribute("ds", StringT(0, false)) -> Cast(ColumnValue("d", DateT()), StringT(0, false), false),
        Attribute("tss", StringT(0, false)) -> Cast(ColumnValue("ts", TimestampT()), StringT(0, false), false),
        Attribute("sd", DateT(false)) -> Cast(ColumnValue("s", StringT(0, false)), DateT(false), false),
        Attribute("stt", TimestampT(false)) -> Cast(ColumnValue("st", StringT(0, false)), TimestampT(false), false),
        Attribute("dl", LongT(false)) -> Cast(ColumnValue("d", DateT()), LongT(false), false),
        Attribute("k", IntT(false)) -> ColumnValue("k", IntT()))))
      val fmtD = new java.text.SimpleDateFormat("yyyy-MM-dd"); fmtD.setTimeZone(gmt)
      val fmtT = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS"); fmtT.setTimeZone(gmt)
      val row = out.find(_("k").extractInt == 1).get
      (row("ds").extractString ?= fmtD.format(new java.util.Date(day))) &&
        (row("tss").extractString ?= fmtT.format(new java.util.Date(t))) &&
        (row("sd").extractDate.getTime ?= 1705276800000L) &&
        (row("stt").extractTimestamp.getTime ?= 1705313472123L) &&
        (row("dl").extractLong ?= day)
  }

  /** E18: a null-on-failure cast to a number is NULL for text that is not
    * a number (SQLite's own CAST answers 0). */
  property("SQLite tryCast to a number is NULL for non-numeric text (E18)") = forAll(Gen.oneOf(
      Some("12.5"), Some("7"), Some("abc"), Some(""), Some("1e3"), Some("1."), Some(".5"), Some("1.e5"), Some("+.5e-3"), Some(" 1 "),
      // the review's five: charset-legal, not numbers (TRY_CAST answers NULL, MEASURED SQL Server 2022)
      Some("2024-01-15"), Some("1.2.3"), Some("-"), Some("1-2"), Some("e"),
      Some("1e"), Some("e5"), Some(".e5"), Some("1e+"), Some("1e.5"), Some("--1"), Some("+-1"), Some("1e5.0"), Some("."), Some("+"), None)) {
    (v: Option[String]) =>
      val r = lit(Map("k" -> i(1), "s" -> ns(v)))
      val out = rows(Combine(r, Attribute("n", DoubleT(true)), Cast(ColumnValue("s", StringT(0, true)), DoubleT(true), true)))
      // T-SQL's numeric syntax, on the trimmed text; '' is NULL (SQL Server says 0, memory says NULL)
      val numeric = """[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?""".r
      val expected: PrimExpr = v.map(_.trim).filter(x => x.nonEmpty && numeric.pattern.matcher(x).matches) match {
        case Some(x) => DoubleExpr(true, x.toDouble)
        case None => NullExpr(DoubleT(true))
      }
      (out.head("n") ?= expected) :| ("tryCast of " + v)
  }

  /** E17: concatenation with a NULL operand is the other operands, as in
    * memory and on SQL Server; the header says the result is never NULL. */
  property("SQLite concat treats NULL as the empty string (E17)") = forAll(Gen.option(Gen.alphaStr), Gen.option(Gen.alphaStr)) {
    (a: Option[String], b: Option[String]) =>
      val r = lit(Map("k" -> i(1), "a" -> ns(a), "b" -> ns(b)))
      val out = rows(Combine(r, Attribute("c", StringT(0, false)), Concat(List(ColumnValue("a", StringT(0, true)), OpLiteral(s("-")), ColumnValue("b", StringT(0, true))))))
      out.head("c") ?= StringExpr(false, a.getOrElse("") + "-" + b.getOrElse(""))
  }

  /** E10: the empty relation's typed NULLs execute; an ungrouped SUM over
    * it is one NULL row on SQLite (the header side is the scanner's C6). */
  property("SQLite emitEmpty executes with typed NULLs (E10)") = secure {
    val h: Header = Map("x" -> IntT(false), "xd" -> DoubleT(false), "s" -> StringT(0, true))
    val sql = SqlEmpty(h).emitSql(SqlEmitter.sqliteEmitter)
    val n = sqliteRun.run((c: java.sql.Connection) => {
      val st = c.createStatement
      try { val rs = st.executeQuery("select count(*) from (" + sql.run + ")"); rs.next(); rs.getInt(1) }
      finally st.close
    })
    (n ?= 0) :| sql.run
  }

  /** E5: `Limit` with a start and no end executes on SQLite. */
  property("SQLite limit with a start and no end executes (E5)") = forAll(Gen.choose(1, 6)) {
    (from: Int) =>
      val r = lit((1 to 5).map(k => Map("k" -> i(k)): Record): _*)
      val out = rows(Limit(r, Some(from), None, List(("k", SortOrder.Asc))))
      out.map(_("k").extractInt).toSet ?= (from to 5).toSet
  }

  /** E4: `join a (join b c)` executes on SQLite. */
  property("SQLite right-nested joins execute (E4)") = secure {
    val a = lit(Map("s" -> s("a")))
    val b = lit(Map("s" -> s("a"), "t" -> s("A")))
    val c = lit(Map("t" -> s("A"), "u" -> s("AA")))
    val out = rows(JoinOn(a, JoinOn(b, c, Set(("t", "t"))), Set(("s", "s"))))
    out ?= Vector(Map("s" -> s("a"), "t" -> s("A"), "u" -> s("AA")))
  }

  /** E21: a grouped aggregate over an input that matches nothing answers
    * no row, also when the group column was squashed to a constant. */
  property("SQLite grouped aggregate over no rows answers no row (E21)") = secure {
    val r = lit(Map("k" -> s("a"), "x" -> i(1)), Map("k" -> s("b"), "x" -> i(2)))
    val none = Filter(r, Eq(ColumnValue("k", StringT(0, false)), OpLiteral(s("zz"))))
    val grouped = AggregateByGroup(none, Map(Attribute("k", StringT(0, false)) -> ColumnValue("k", StringT(0, false))),
                                   List((Attribute("m", IntT(true)), AggFunc.Max(ColumnValue("x", IntT())))), List(ColumnValue("k", StringT(0, false))))
    val some = AggregateByGroup(Filter(r, Eq(ColumnValue("k", StringT(0, false)), OpLiteral(s("a")))),
                                Map(Attribute("k", StringT(0, false)) -> ColumnValue("k", StringT(0, false))),
                                List((Attribute("m", IntT(true)), AggFunc.Max(ColumnValue("x", IntT())))), List(ColumnValue("k", StringT(0, false))))
    ((rows(grouped).size ?= 0) :| sqlOf(grouped)) && (rows(some).map(_("m").extractInt) ?= Vector(1))
  }

  /** E22: an all-NULL literal column keeps its type, and MAX over it is one
    * NULL row on SQLite (SQL Server refused the untyped form). */
  property("SQLite all-NULL literal columns keep their type (E22)") = secure {
    val r = lit(Map("k" -> i(1), "xd" -> NullExpr(DoubleT(true))), Map("k" -> i(2), "xd" -> NullExpr(DoubleT(true))))
    val sql = sqlOf(r)
    ((sql contains "cast(NULL as real)") :| sql) &&
      (rows(Aggregate(r, Attribute("m", DoubleT(true)), AggFunc.Max(ColumnValue("xd", DoubleT(true))))).map(_("m")) ?= Vector(NullExpr(DoubleT(true))))
  }

  /** E23: a limit ordered by two columns that share an expression, and by a
    * computed constant column, executes. */
  property("SQLite limits ordered by aliases execute (E23)") = secure {
    val r = lit(Map("k" -> i(2), "x" -> i(20)), Map("k" -> i(1), "x" -> i(10)), Map("k" -> i(3), "x" -> i(30)))
    val p = Project(r, Map(Attribute("a", IntT(false)) -> ColumnValue("x", IntT()), Attribute("b", IntT(false)) -> ColumnValue("x", IntT()),
                           Attribute("c", IntT(false)) -> OpLiteral(i(7))))
    val out = rows(Limit(p, Some(1), Some(2), List(("a", SortOrder.Desc), ("b", SortOrder.Desc), ("c", SortOrder.Asc))))
    out.map(_("a").extractInt) ?= Vector(30, 20)
  }

  // ------------------------------------------------------------------ execution on SQL Server, when configured

  private lazy val sqlServer: Option[Run[DB]] = {
    val env = sys.env
    for {
      u  <- env.get("ERMINE_DB_URL").filter(_.nonEmpty)
      us <- env.get("ERMINE_DB_USER").filter(_.nonEmpty)
      pw <- env.get("ERMINE_DB_PASSWORD").filter(_.nonEmpty)
    } yield DB.RunUser("com.microsoft.sqlserver.jdbc.SQLServerDriver")(u, us, pw)
  }
  private val msScanner = Scanners.MicrosoftSQLServer(dummySmenv)
  private def msRows(run: Run[DB], r: Relation[Nothing, Nothing]): Vector[Record] =
    run.run(msScanner.scanRel(r, Process((x: Record) => Vector(x))))

  sqlServer match {
    case None =>
      println("[emitters] DB suites: not requested (no ERMINE_DB_* in the environment); the live SQL Server properties are skipped")
    case Some(run) =>
      /** E6: a CJK/emoji literal survives the trip to SQL Server. */
      property("(live) SQL Server string literals keep characters outside the code page (E6)") = secure {
        val r = lit(Map("k" -> i(1), "s" -> s("uni ☺ 東")))
        msRows(run, r).head("s").extractString ?= "uni ☺ 東"
      }

      /** E11: the CAST(.. AS DATE) literal parses and compares. */
      property("(live) SQL Server date literals filter (E11)") = secure {
        val r = lit(Map("k" -> i(1), "d" -> dt(1705276800000L)), Map("k" -> i(2), "d" -> dt(1709251200000L)))
        val out = msRows(run, Filter(r, Gt(ColumnValue("d", DateT()), OpLiteral(dt(1706745600000L)))))
        out.map(_("k").extractInt) ?= Vector(2)
      }

      /** E10: SUM over the typed empty relation is accepted (Msg 8117 before). */
      property("(live) SQL Server aggregates over an empty relation (E10)") = secure {
        val h: Header = Map("x" -> IntT(false), "xd" -> DoubleT(false))
        val sql = "select SUM([xd]) [xd], COUNT(*) [n] from (" + SqlEmpty(h).emitSql(SqlEmitter.msSqlEmitter).run + ") [e]"
        val n = run.run((c: java.sql.Connection) => {
          val st = c.createStatement
          try { val rs = st.executeQuery(sql); rs.next(); rs.getInt(2) } finally st.close
        })
        (n ?= 0) :| sql
      }

      /** E16: the temp table of a >100-row literal is gone after the scan. */
      property("(live) SQL Server drops the temp tables a scan created (E16)") = secure {
        val all = (0 until 101).map(k => Map("k" -> i(k)): Record).toList
        val r = SmallLit(NonEmptyList(all.head, all.tail: _*))
        val count = run.run((c: java.sql.Connection) => {
          val scan: DB[Vector[Record]] = msScanner.scanRel(r, Process((x: Record) => Vector(x)))
          val before = scan(c).size
          val st = c.createStatement
          try {
            val rs = st.executeQuery("select count(*) from tempdb.sys.tables where name like '##t%'")
            rs.next(); (before, rs.getInt(1))
          } finally st.close
        })
        ((count._1 ?= 101) :| "the literal scanned") && ((count._2 ?= 0) :| (count._2 + " ##t temp tables left in tempdb"))
      }

      /** E22: MAX over an all-NULL literal column (untyped NULLs were Msg 8117). */
      property("(live) SQL Server aggregates over an all-NULL literal column (E22)") = secure {
        val r = lit(Map("k" -> i(1), "xd" -> NullExpr(DoubleT(true))), Map("k" -> i(2), "xd" -> NullExpr(DoubleT(true))))
        msRows(run, Aggregate(r, Attribute("m", DoubleT(true)), AggFunc.Max(ColumnValue("xd", DoubleT(true))))).map(_("m")) ?= Vector(NullExpr(DoubleT(true)))
      }

      /** E23: a limit ordered by two aliases of one expression and by a constant column. */
      property("(live) SQL Server limits ordered by aliases execute (E23)") = secure {
        val r = lit(Map("k" -> i(2), "x" -> i(20)), Map("k" -> i(1), "x" -> i(10)), Map("k" -> i(3), "x" -> i(30)))
        val p = Project(r, Map(Attribute("a", IntT(false)) -> ColumnValue("x", IntT()), Attribute("b", IntT(false)) -> ColumnValue("x", IntT()),
                               Attribute("c", IntT(false)) -> OpLiteral(i(7))))
        msRows(run, Limit(p, Some(1), Some(2), List(("a", SortOrder.Desc), ("b", SortOrder.Desc), ("c", SortOrder.Asc)))).map(_("a").extractInt) ?= Vector(30, 20)
      }

      /** E24: `1.0 / 3.0` is a float division. */
      property("(live) SQL Server double literals divide as floats (E24)") = secure {
        val r = lit(Map("k" -> i(1), "x" -> d(1.0)), Map("k" -> i(2), "x" -> d(2.0)))
        val out = msRows(run, Combine(r, Attribute("q", DoubleT(false)), DoubleDiv(ColumnValue("x", DoubleT()), OpLiteral(d(3.0)))))
        out.find(_("k").extractInt == 1).map(_("q").extractDouble) ?= Some(1.0 / 3.0)
      }

      /** E21: a grouped aggregate over no rows answers no row on SQL Server too. */
      property("(live) SQL Server grouped aggregate over no rows answers no row (E21)") = secure {
        val r = lit(Map("k" -> s("a"), "x" -> i(1)), Map("k" -> s("b"), "x" -> i(2)))
        val none = Filter(r, Eq(ColumnValue("k", StringT(0, false)), OpLiteral(s("zz"))))
        val grouped = AggregateByGroup(none, Map(Attribute("k", StringT(0, false)) -> ColumnValue("k", StringT(0, false))),
                                       List((Attribute("m", IntT(true)), AggFunc.Max(ColumnValue("x", IntT())))), List(ColumnValue("k", StringT(0, false))))
        msRows(run, grouped).size ?= 0
      }

      /** the integral-average rule: SQL Server truncates toward zero. */
      property("(live) SQL Server averages of integers truncate toward zero") = secure {
        val r = lit(Map("k" -> i(1), "x" -> i(-1)), Map("k" -> i(2), "x" -> i(2)))
        msRows(run, Aggregate(r, Attribute("a", IntT(true)), AggFunc.Avg(ColumnValue("x", IntT())))).head("a").extractInt ?= 0
      }

      /** E8: a NaN in a literal reaches SQL Server as NULL. */
      property("(live) SQL Server NaN literal is NULL (E8)") = secure {
        val r = lit(Map("k" -> i(1), "xd" -> DoubleExpr(true, Double.NaN)))
        msRows(run, r).head("xd") ?= NullExpr(DoubleT(true))
      }
  }
}
