package com.clarifi.reporting
package relational

import java.lang.reflect.{ InvocationHandler, InvocationTargetException, Method, Proxy }
import java.sql.{ Connection, DriverManager, PreparedStatement, ResultSet, ResultSetMetaData }

import com.clarifi.machines.Process
import com.clarifi.reporting.backends.{ DB, Scanners }
import com.clarifi.reporting.sql.{ SqlCreateIfNotExists, SqlEmitter, SqlStatement }
import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.SortOrder.{ Asc, Desc }
import Op.{ ColumnValue, OpLiteral }

import scalaz.NonEmptyList
import scalaz.std.vector._

import org.scalacheck.{ Gen, Prop, Properties }
import Prop.{ Result => _, _ }

/** SQL audit (tracker/sql-audit/WORKLIST.md, area `scanner`): the `SqlScanner`,
  * `SqlExecution` and `Mem` fixes, each pinned by the shrunk repro of its
  * finding and covered by a property.  Two kinds of check:
  *
  *   - LIVE: the relation is scanned on an in-memory SQLite database (the
  *     default runner) and the rows are compared with a hand-written
  *     set-semantics reference or with the same rows through the other path
  *     (`Mem` against SQL);
  *   - TEXT: the SQL a scanner emits (`dumpRel`, mostly the SQL Server one,
  *     whose emitter parenthesises nothing) is checked for its SHAPE through
  *     `topLevel`, the text with every parenthesised group removed, so "the
  *     window is computed in a subquery" is "no `over` at the top level".
  *
  * Every property FAILS on the pre-fix compiler; the pre-fix answer is named. */
object TestSqlScanner extends Properties("SqlScanner (SQL audit, scanner)") {

  private def i(n: Int): PrimExpr = IntExpr(false, n)
  private def s(x: String): PrimExpr = StringExpr(false, x)
  private def nullInt: PrimExpr = NullExpr(IntT(true))

  private val sqlite = Scanners.SQLite(SMEnv.dummySmenv)
  private val mssql  = Scanners.MicrosoftSQLServer(SMEnv.dummySmenv)

  private lazy val conn: Connection = {
    Class.forName("org.sqlite.JDBC"); DriverManager.getConnection("jdbc:sqlite::memory:")
  }

  private def lit(rs: List[Record]): SmallLit = SmallLit(NonEmptyList(rs.head, rs.tail: _*))
  private def mem(rs: List[Record]): Literal = Literal(rs.head, rs.tail.toIndexedSeq)

  private def rows(r: Relation[Nothing, Nothing], order: List[(String, SortOrder)] = Nil,
                   on: Connection = conn, scanner: SqlScanner = sqlite): Vector[Record] =
    scanner.scanRel[Vector[Record]](r, Process.wrapping[Record], order)(vectorMonoid[Record])(on)

  private def memRows(m: Mem[Nothing, Nothing], order: List[(String, SortOrder)] = Nil): Vector[Record] =
    sqlite.scanMem[Vector[Record]](m, Process.wrapping[Record], order)(vectorMonoid[Record])(conn)

  /** `sql` with every parenthesised group removed. */
  private def topLevel(sql: String): String = {
    val sb = new StringBuilder
    var depth = 0
    sql.foreach { c =>
      if (c == '(') depth += 1
      else if (c == ')') depth -= 1
      else if (depth == 0) sb.append(c)
    }
    sb.toString.toLowerCase
  }
  private def count(hay: String, needle: String): Int = hay.sliding(needle.length).count(_ == needle)

  private val k  = ColumnValue("k", IntT(false))
  private val x  = ColumnValue("x", IntT(false))
  private val kA = Attribute("k", IntT(false))
  private val xA = Attribute("x", IntT(false))
  private def kx(kk: Int, xx: Int): Record = Map("k" -> i(kk), "x" -> i(xx))

  /** Rows with distinct `x` and a `k` in {1, 2}. */
  private val genKx: Gen[List[Record]] = for {
    n  <- Gen.choose(2, 6)
    ks <- Gen.listOfN(n, Gen.choose(1, 2))
  } yield ks.zipWithIndex.map { case (kk, xx) => kx(kk, xx) }

  // =================================================================== C4 (L-4)

  property("(C4) a two-row limit is two rows: the projection above it still dedupes") =
    forAll(genKx, Gen.choose(1, 3)) { (rs, f) =>
      val r = Project(Limit(lit(rs), Some(f), Some(f + 1), List("x" -> Asc)), Map(kA -> k))
      val got = rows(r).toList
      // Pre-fix: `t - f < 2` called the range one row, marked every column
      // constant, and the projection skipped its DISTINCT: [{k=1},{k=1}].
      (got.distinct ?= got) :| ("duplicates in " + got)
    }

  // =================================================================== C2 (L-3, O-3)

  private val ranked: Relation[Nothing, Nothing] =
    Combine(lit(List(kx(1, 1), kx(1, 2), kx(2, 3))), Attribute("y", IntT(false)),
            Op.Windowed(Rank, Window(List(k), List((x, Desc)), Frame(None, None))))

  property("(C2) a one-row literal joined to a windowed relation filters OUTSIDE the window") = secure {
    val text = topLevel(mssql.dumpRel(JoinOn(lit(List(Map("x" -> i(1)))), ranked, Set(), JoinMode.Inner)))
    // Pre-fix: `select ..., RANK() over (...) y, (1) x from ... where (x = 1)`:
    // the rank was computed over the filtered rows.
    (text.contains(" where ") :| ("no where at the top level: " + text)) &&
      (!text.contains("over") :| ("the window is at the top level, next to the where: " + text))
  }

  property("(C2) a one-row literal joined to a grouped aggregate filters OUTSIDE the group by") = secure {
    val agg = AggregateByGroup(lit(List(kx(1, 1), kx(1, 2), kx(2, 3))), Map(kA -> k),
                               List((Attribute("s", IntT(false)), AggFunc.Sum(x))), List(k))
    val text = topLevel(mssql.dumpRel(JoinOn(lit(List(Map("k" -> i(1)))), agg, Set(), JoinMode.Inner)))
    // Pre-fix: the predicate became a HAVING on the aggregating select and the
    // literal's constant replaced the group column in its select list.
    (text.contains(" where ") :| ("no where at the top level: " + text)) &&
      (!text.contains("having") :| ("having at the top level: " + text)) &&
      (!text.contains("group by") :| ("group by at the top level: " + text))
  }

  // =================================================================== C1 (L-2, D5)

  private val r1 = lit(List(kx(1, 1), kx(1, 2), kx(2, 3)))
  private val r2 = lit(List(kx(1, 2), kx(3, 9)))
  private val r3 = lit(List(kx(2, 3), kx(2, 5)))

  /** Random nesting of union and difference over the three literals. */
  private def genSetTree(depth: Int): Gen[Relation[Nothing, Nothing]] =
    if (depth == 0) Gen.oneOf(r1, r2, r3)
    else Gen.frequency(
      (1, Gen.oneOf(r1, r2, r3)),
      (2, for { a <- genSetTree(depth - 1); b <- genSetTree(depth - 1) } yield Union(a, b)),
      (2, for { a <- genSetTree(depth - 1); b <- genSetTree(depth - 1) } yield MinusI(a, b)))

  private def refSet(r: Relation[Nothing, Nothing]): Set[Record] = r match {
    case SmallLit(ts)   => ts.list.toList.toSet
    case Union(a, b)    => refSet(a) ++ refSet(b)
    case MinusI(a, b)   => refSet(a) -- refSet(b)
    case other          => sys.error("refSet: " + other)
  }

  property("(C1) SQL Server text: the operators at one level of a set expression are all the same") =
    forAll(genSetTree(3)) { r =>
      val text = topLevel(mssql.dumpRel(r))
      // Pre-fix: `union r1 (difference r2 r3)` was `A UNION B EXCEPT C`, which
      // T-SQL reads as (A UNION B) EXCEPT C.
      !(text.contains("union") && text.contains("except")) :| ("mixed operators at one level: " + text)
    }

  property("(C1) pins: right-nested difference is grouped, left-nested is not") = secure {
    val rightNested = topLevel(mssql.dumpRel(MinusI(r1, MinusI(r2, r3))))
    val leftNested  = topLevel(mssql.dumpRel(MinusI(MinusI(r1, r2), r3)))
    // Pre-fix: `A EXCEPT B EXCEPT C` for both; the right-nested one meant
    // A - (B - C) and answered 1 row for 2.
    ((count(rightNested, "except") ?= 1) :| ("right-nested: " + rightNested)) &&
      ((count(leftNested, "except") ?= 2) :| ("left-nested: " + leftNested))
  }

  property("(C1) SQLite live: nested set operations answer the set-semantics reference") =
    forAll(genSetTree(3)) { r => (rows(r).toSet ?= refSet(r)) :| ("relation " + r) }

  // =================================================================== C3 (O-4)

  property("(C3) a LEFT JOIN pads the right side's constant with NULL on unmatched rows") =
    forAll(genKx, Gen.choose(0, 1)) { (rs, drop) =>
      val left  = lit(rs)
      val right = Combine(lit(rs.filter(_("k") != i(1 + drop)).map(r => Map("k" -> r("k"))).distinct match {
                            case Nil => List(Map("k" -> i(99)))
                            case xs  => xs
                          }),
                          Attribute("c", IntT(true)), OpLiteral(IntExpr(true, 1)))
      val got = rows(JoinOn(left, right, Set(), JoinMode.Left))
      val matched = rows(right).map(_("k")).toSet
      // Pre-fix: the right side's select list (`(1) c`) was merged into the
      // join's, so unmatched left rows answered c = 1.
      Prop.all(got.toList.map { r =>
        val want: PrimExpr = if (matched(r("k"))) IntExpr(true, 1) else NullExpr(IntT(true))
        (r("c").isNull ?= want.isNull) :| ("row " + r + " should have c = " + want)
      }: _*) && ((got.size ?= rs.size) :| ("a left join keeps every left row: " + got))
    }

  property("(C3) a FULL JOIN pads a coalesce on either side with NULL") = secure {
    val left  = Combine(lit(List(Map("k" -> i(1)), Map("k" -> i(2)))), Attribute("l", IntT(true)),
                        Op.Coalesce(OpLiteral(NullExpr(IntT(true))), OpLiteral(IntExpr(true, 7))))
    val right = Combine(lit(List(Map("k" -> i(2)), Map("k" -> i(3)))), Attribute("r", IntT(true)),
                        Op.Coalesce(OpLiteral(NullExpr(IntT(true))), OpLiteral(IntExpr(true, 8))))
    val got = rows(JoinOn(left, right, Set(), JoinMode.Full)).map(r => (r("k"), r("l").isNull, r("r").isNull)).toSet
    // Pre-fix: (3, false, false) and (1, false, false): 7 and 8 on every row.
    got ?= Set((i(1), false, true), (i(2), false, false), (i(3), true, false))
  }

  // =================================================================== C6 (L-6, S-09, E-13; decision D2)

  private val none = Filter(r1, Predicate.Atom(false))

  property("(C6) SUM and COUNT over no rows answer 0; MIN, MAX, AVG answer no row") = secure {
    val sA = Attribute("s", IntT(false))
    val sum = rows(Aggregate(none, sA, AggFunc.Sum(x)))
    val cnt = rows(Aggregate(none, sA, AggFunc.Count))
    val mx  = rows(Aggregate(none, sA, AggFunc.Max(x)))
    val mn  = rows(Aggregate(none, sA, AggFunc.Min(x)))
    val av  = rows(Aggregate(none, Attribute("s", DoubleT(false)), AggFunc.Avg(x)))
    // Pre-fix: one NULL row into a non-nullable column, and the decoder threw
    // "Unexpected NULL in field of type IntT(false)" for every one but COUNT.
    ((sum.toList ?= List(Map("s" -> i(0)))) :| ("sum: " + sum)) &&
      ((cnt.toList ?= List(Map("s" -> i(0)))) :| ("count: " + cnt)) &&
      ((mx.toList ?= Nil) :| ("max: " + mx)) &&
      ((mn.toList ?= Nil) :| ("min: " + mn)) &&
      ((av.toList ?= Nil) :| ("avg: " + av))
  }

  property("(C6) over rows the aggregates are unchanged") =
    forAll(genKx) { rs =>
      val xs = rs.map(_("x").extractInt)
      val sA = Attribute("s", IntT(false))
      ((rows(Aggregate(lit(rs), sA, AggFunc.Sum(x))).toList ?= List(Map("s" -> i(xs.sum)))) :| "sum") &&
        ((rows(Aggregate(lit(rs), sA, AggFunc.Max(x))).toList ?= List(Map("s" -> i(xs.max)))) :| "max") &&
        ((rows(Aggregate(lit(rs), sA, AggFunc.Count)).toList ?= List(Map("s" -> i(xs.size)))) :| "count")
    }

  // =================================================================== C5 (L-7, S-11, O-8, L-9)

  private val genRange: Gen[(Option[Int], Option[Int])] = for {
    f <- Gen.option(Gen.choose(1, 5))
    t <- Gen.option(Gen.choose(1, 6))
  } yield (f, t)

  property("(C5) a limit on a Mem is 1-based and inclusive, like a limit on a Relation") =
    forAll(genKx, genRange) { case (rs, (f, t)) =>
      val byX  = List("x" -> Asc)
      val got  = memRows(LimitM(mem(rs), f, t, byX)).toList
      val sorted = rs.sortBy(_("x").extractInt)
      val from = f.getOrElse(1)
      val want = t match {
        case Some(tt) => if (tt < from) Nil else sorted.slice(from - 1, tt)
        case None     => sorted.drop(from - 1)
      }
      // Pre-fix: `dropping(start)` and `taking(stop - start)`: (Just 2, Just 3)
      // answered the third row alone and (Just 1, Just 1) no row.
      (got ?= want) :| ("limit " + (f, t) + " of " + sorted)
    }

  property("(C5) a limited Mem is delivered in the order its consumer asks for") =
    forAll(genKx) { rs =>
      val got = memRows(LimitM(mem(rs), None, Some(4), List("x" -> Asc)), List("k" -> Desc, "x" -> Desc)).toList
      val want = rs.sortBy(_("x").extractInt).take(4).sortBy(r => (-r("k").extractInt, -r("x").extractInt))
      // Pre-fix: the rows came back in the limit's own order (x ascending).
      (got ?= want) :| ("got " + got)
    }

  // =================================================================== the JDBC proxy (C7, C13)

  private def proxy[T](cls: Class[T], target: AnyRef)(hook: PartialFunction[(String, Array[AnyRef], () => AnyRef), AnyRef]): T =
    Proxy.newProxyInstance(cls.getClassLoader, Array[Class[_]](cls), new InvocationHandler {
      def invoke(p: AnyRef, m: Method, args: Array[AnyRef]): AnyRef = {
        val call = () => try m.invoke(target, (if (args == null) Array.empty[AnyRef] else args): _*)
                         catch { case e: InvocationTargetException => throw e.getCause }
        val key = (m.getName, args, call)
        if (hook.isDefinedAt(key)) hook(key) else call()
      }
    }).asInstanceOf[T]

  /** A connection whose statements report `close`, whose metadata counts
    * `getColumnLabel`, and which can reject every query at `executeQuery`
    * (SQLite itself rejects a bad query at `prepareStatement`, before a
    * statement exists). */
  private final class Probe(under: Connection, reject: Boolean = false) {
    var closed = 0
    var labels = 0
    val conn: Connection = proxy(classOf[Connection], under) {
      case ("prepareStatement", _, call) =>
        proxy(classOf[PreparedStatement], call()) {
          case ("close", _, c)        => closed += 1; c()
          case ("executeQuery", _, c) if reject => throw new java.sql.SQLException("rejected by the probe")
          case ("executeQuery", _, c) =>
            proxy(classOf[ResultSet], c()) {
              case ("getMetaData", _, cc) =>
                proxy(classOf[ResultSetMetaData], cc()) {
                  case ("getColumnLabel", _, ccc) => labels += 1; ccc()
                }
            }
        }
    }
  }

  private val hk: Header = Map("k" -> IntT(false), "x" -> IntT(false))
  private val noSuchTable = Table(hk, TableName("no_such_table"))

  // =================================================================== C7 (L-12, L-11)

  property("(C7) a query the database rejects at executeQuery has its statement closed") = secure {
    val p = new Probe(conn, reject = true)
    val threw = try { rows(r1, on = p.conn); false } catch { case _: Throwable => true }
    // Pre-fix: `executeQuery` threw before the teardown was installed and the
    // statement stayed open: closed = 0.
    (threw :| "the rejected scan did not fail") && ((p.closed ?= 1) :| ("statements closed: " + p.closed))
  }

  property("(C7) temp tables are dropped when the scan fails") = secure {
    val dropping = new SqlScanner(SMEnv.dummySmenv)(new sql.SqliteEmitter {
      override def emitDropTempTable: Option[TableName => sql.RawSql] =
        Some(t => sql.RawSql.raw("DROP TABLE " + emitTableName(t).run))
    })
    Class.forName("org.sqlite.JDBC")
    val own = DriverManager.getConnection("jdbc:sqlite::memory:")
    try {
      val r: Relation[Nothing, Nothing] =
        LetR(ExtRel(r1, ""), Nil, Union(VarR(RTop), VarR(RPop(noSuchTable))))
      val threw = try { rows(r, on = own, scanner = dropping); false } catch { case _: Throwable => true }
      val st = own.createStatement
      val rs = st.executeQuery("select count(*) from sqlite_temp_master where type = 'table'")
      rs.next()
      val left = rs.getInt(1)
      rs.close(); st.close()
      // Pre-fix: the drop ran only after a successful scan, so the let's temp
      // table was still there: left = 1.
      (threw :| "the scan did not fail") && ((left ?= 0) :| ("temp tables left after a failed scan: " + left))
    } finally own.close()
  }

  // =================================================================== C13 (W-2)

  property("(C13) column labels are read once per result set, not once per cell") =
    forAll(Gen.choose(5, 40)) { n =>
      val p = new Probe(conn)
      val rs = (1 to n).toList.map(j => kx(j % 2 + 1, j))
      val got = rows(lit(rs), on = p.conn)
      // Pre-fix: `getColumnLabel` ran for every cell: 2 + 2 * n calls.
      ((got.size ?= n) :| "rows") && ((p.labels <= 2 * hk.size) :| ("getColumnLabel calls: " + p.labels + " for " + n + " rows"))
    }

  // =================================================================== C8 (L-10, O-23)

  private def memo(v: Int): Relation[Nothing, Nothing] =
    MemoR(LetR(ExtMem(mem(List(Map("k" -> i(v))))), Nil, VarR(RTop)), Nil)

  private def memoName(r: Relation[Nothing, Nothing]): String = {
    implicit val sup = scalaparsers.Supply.create
    implicit val memoLookup = new scala.collection.mutable.HashSet[TableName]()
    implicit val scope: List[() => String] = Nil
    implicit val cache = new sqlite.LetCache
    sqlite.compileRel(Optimizer.optimize(r), (x: Nothing) => x, (x: Nothing) => x).prg.collect {
      case SqlCreateIfNotExists(tn, _, _, _) => tn.name
    }.mkString(",")
  }

  property("(C8) memo tables of relations that differ only in a literal's rows have different names") =
    forAll(Gen.choose(1, 50), Gen.choose(51, 100)) { (a, b) =>
      // Pre-fix: `Literal.toString` printed only the size, so both hashed to
      // the same `MemoHash_...` and the second read the first's rows.
      ((memoName(memo(a)) != memoName(memo(b))) :| ("same memo name for " + a + " and " + b)) &&
        ((memoName(memo(a)) ?= memoName(memo(a))) :| "the name is not a function of the rows")
    }

  // =================================================================== C9 (O-25, L-21)

  property("(C9) a closed let-bound relation referenced twice is materialised once") =
    forAll(genKx) { rs =>
      val ext = ExtRel(lit(rs), "")
      val twice: Relation[Nothing, Nothing] =
        Union(LetR(ext, Nil, VarR(RTop)), LetR(ext, Nil, VarR(RTop)))
      val text = sqlite.dumpRel(twice)
      val got = rows(twice).toSet
      // Pre-fix: two CREATEs under two fresh guids, the same rows loaded twice.
      ((count(text, "CREATE") ?= 1) :| ("temp tables in\n" + text)) && ((got ?= rs.toSet) :| ("rows " + got))
    }

  property("(C9) two let-bound literals differing only in string case, or in nullability, do not share a table") = secure {
    def letOf(v: PrimExpr): Relation[Nothing, Nothing] =
      LetR(ExtRel(lit(List(Map("s" -> v))), ""), Nil, VarR(RTop))
    val caseTree = Union(letOf(s("a")), letOf(s("A")))
    val caseText = sqlite.dumpRel(caseTree)
    val caseRows = rows(caseTree).map(_("s").toString).toSet
    val nullTree = Union(letOf(StringExpr(true, "")), letOf(NullExpr(StringT(0, true))))
    val nullRows = rows(nullTree).map(_("s").isNull).toSet
    // Pre-fix: keyed by the relation VALUE, whose `PrimExpr` equality is
    // case-insensitive and NULL == NULL, so the second let read the first's
    // table: {a} and {false}.
    ((count(caseText, "CREATE") ?= 2) :| ("tables:\n" + caseText)) &&
      ((caseRows ?= Set("a", "A")) :| ("case rows " + caseRows)) &&
      ((nullRows ?= Set(true, false)) :| ("null rows " + nullRows))
  }

  property("(C9) a let whose relation mentions the enclosing binding is still compiled in its scope") = secure {
    // let a = r1 in (let b = filter (k = 1) a in union b b)
    val inner: Relation[Nothing, RLevel[Nothing, Nothing]] =
      LetR(ExtRel(Filter(VarR(RTop), Predicate.Eq(k, OpLiteral(i(1)))), ""), Nil,
           Union(VarR(RTop), VarR(RTop)))
    val r: Relation[Nothing, Nothing] = LetR(ExtRel(r1, ""), Nil, inner)
    rows(r).toSet ?= Set(kx(1, 1), kx(1, 2))
  }

  // =================================================================== C10 (O-12, O-26, L-19)

  property("(C10) TEXT: no eager DISTINCT under a UNION arm, an EXCEPT arm, or a projection onto group keys") = secure {
    val pk1 = Project(r1, Map(kA -> k))
    val pk2 = Project(r2, Map(kA -> k))
    val agg = AggregateByGroup(r1, Map(kA -> k), List((Attribute("s", IntT(false)), AggFunc.Sum(x))), List(k))
    val union = mssql.dumpRel(Union(pk1, pk2)).toLowerCase
    val minus = mssql.dumpRel(MinusI(pk1, pk2)).toLowerCase
    val keys  = mssql.dumpRel(Project(agg, Map(kA -> k))).toLowerCase
    // Pre-fix: `select distinct` in each union arm (the union dedupes), on the
    // left arm and around the EXCEPT (EXCEPT answers a set), and over the
    // group-by (the group columns are its key).
    ((count(union, "distinct") ?= 0) :| ("union: " + union)) &&
      ((count(minus, "distinct") ?= 0) :| ("minus: " + minus)) &&
      ((count(keys, "distinct") ?= 0) :| ("group keys: " + keys))
  }

  property("(C10) LIVE: those shapes still answer the set-semantics reference") =
    forAll(genKx, genKx) { (a, b) =>
      val pa = Project(lit(a), Map(kA -> k))
      val pb = Project(lit(b), Map(kA -> k))
      val ka = a.map(r => Map("k" -> r("k"))).toSet
      val kb = b.map(r => Map("k" -> r("k"))).toSet
      val agg = AggregateByGroup(lit(a), Map(kA -> k), List((Attribute("s", IntT(false)), AggFunc.Sum(x))), List(k))
      ((rows(Union(pa, pb)).toSet ?= (ka ++ kb)) :| "union") &&
        ((rows(MinusI(pa, pb)).toSet ?= (ka -- kb)) :| "minus") &&
        ((rows(Project(agg, Map(kA -> k))).toSet ?= ka) :| "group keys") &&
        ((rows(Union(pa, pb)).toList.distinct.size ?= (ka ++ kb).size) :| "union delivers each row once")
    }

  // =================================================================== C11 (O-15)

  property("(C11) a filter over a union is pushed into each arm") =
    forAllNoShrink(genKx, genKx) { (a, b) =>
      val p = Predicate.Eq(k, OpLiteral(i(1)))
      val r = Filter(Union(lit(a), lit(b)), p)
      val full = mssql.dumpRel(r).toLowerCase
      // Pre-fix: `select ... from (A union B) t where k = 1`: the union was
      // inside a subquery under one where.  SQL Server's emitter does not
      // parenthesise union arms, so after the fix the union and both wheres
      // are at the top level.
      (topLevel(full).contains("union") :| ("the union is wrapped in a subquery: " + full)) &&
        ((count(full, " where ") ?= 2) :| ("not one where per arm: " + full)) &&
        ((rows(r).toSet ?= (a ++ b).filter(_("k") == i(1)).toSet) :| "rows")
    }

  // =================================================================== C12 (S-22)

  /** Counts every `compileMem` call, recursive ones included. */
  private final class CountingScanner extends SqlScanner(SMEnv.dummySmenv)(SqlEmitter.sqliteEmitter) {
    var compiles = 0
    override def compileMem[M, R](m: Mem[R, M], smv: M => MemPrg, srv: R => SqlPrg)
                                 (implicit sup: scalaparsers.Supply, memoLookup: scala.collection.mutable.HashSet[TableName],
                                  scopeBuilder: List[() => String], letCache: LetCache): MemPrg = {
      compiles += 1
      super.compileMem(m, smv, srv)
    }
  }

  private def groupBody(groups: Int): (CountingScanner, Vector[Record]) = {
    val rs = (1 to groups).toList.flatMap(g => List(kx(g, 2 * g), kx(g, 2 * g + 1)))
    val body: Mem[Nothing, MLevel[Nothing, Nothing]] =
      FilterM(VarM(MTop), Predicate.Gt(x, OpLiteral(i(0))))
    val g: Mem[Nothing, Nothing] = GroupByM(mem(rs), List(kA), body)
    val sc = new CountingScanner
    val out = sc.scanMem[Vector[Record]](g, Process.wrapping[Record], Nil)(vectorMonoid[Record])(conn)
    (sc, out)
  }

  property("(C12) a groupBy body is compiled once, however many groups there are") = secure {
    val (two, outTwo)     = groupBody(2)
    val (twelve, outTwelve) = groupBody(12)
    // Pre-fix: the body was instantiated and compiled per group, so the count
    // grew with the number of groups.
    ((two.compiles ?= twelve.compiles) :| ("compileMem calls: " + two.compiles + " for 2 groups, " + twelve.compiles + " for 12")) &&
      ((outTwo.size ?= 4) :| "2 groups: rows") && ((outTwelve.size ?= 24) :| "12 groups: rows") &&
      ((outTwelve.map(_("k")).distinct.size ?= 12) :| "every group keyed")
  }

  property("(C12) a groupBy with a memoised body still answers per group") = secure {
    // `letM` in the body: memo on the node, so the body is compiled per group.
    val body: Mem[Nothing, MLevel[Nothing, Nothing]] =
      LetM(ExtMem(VarM(MTop)), AggregateM(VarM(MTop), Attribute("n", IntT(false)), AggFunc.Count))
    val rs = List(kx(1, 1), kx(1, 2), kx(2, 3))
    val got = memRows(GroupByM(mem(rs), List(kA), body)).toSet
    got ?= Set(Map("k" -> i(1), "n" -> i(2)), Map("k" -> i(2), "n" -> i(1)))
  }

  // =================================================================== D4 on the wire (impl-rel's note), D1 for the hash joins (impl-prims' note)

  property("(D4) an unmatched outer-join row decodes: the padded side is typed nullable on the wire") = secure {
    val left  = lit(List(Map("k" -> i(1)), Map("k" -> i(2))))
    val right = Combine(lit(List(Map("k" -> i(1)))), Attribute("c", IntT(false)), OpLiteral(i(5)))
    val got = try Right(rows(JoinOn(left, right, Set(), JoinMode.Left)).map(r => (r("k"), r("c").isNull)).toSet)
              catch { case e: Throwable => Left(e.toString) }
    // Pre-fix: the scanner decoded with `other.h ++ h`, c typed IntT(false),
    // and the k = 2 row threw "Unexpected NULL in field of type IntT(false)".
    got ?= Right(Set((i(1), false), (i(2), true)))
  }

  property("(C22) a FULL JOIN's shared key is typed nullable when EITHER side's is: a right-only NULL key decodes") = secure {
    val left  = lit(List(Map("k" -> i(1), "a" -> i(1)), Map("k" -> i(2), "a" -> i(2))))   // k: IntT(false)
    val right = lit(List(Map("k" -> (NullExpr(IntT(true)): PrimExpr), "b" -> i(1))))       // k: IntT(true)
    val got = try Right(rows(JoinOn(left, right, Set(), JoinMode.Full)).map(r => (r("k").isNull, r("a").isNull, r("b").isNull)).toSet)
              catch { case e: Throwable => Left(e.toString) }
    // Pre-fix: the shared column took the LEFT side's non-nullable flag, and
    // the right-only row's `coalesce(l.k, r.k)` = NULL threw "Unexpected NULL".
    got ?= Right(Set((false, false, true), (true, true, false)))
  }

  private val nk: Attribute = Attribute("k", IntT(true))
  private def nkRow(kk: Option[Int], c: String, v: Int): Record =
    Map("k" -> kk.map(n => IntExpr(true, n): PrimExpr).getOrElse(NullExpr(IntT(true))), c -> i(v))

  property("(D1) NULL join keys never match in the in-memory hash joins") = secure {
    val l = mem(List(nkRow(None, "a", 1), nkRow(Some(1), "a", 2)))
    val r = mem(List(nkRow(None, "b", 1), nkRow(Some(1), "b", 2)))
    val inner = memRows(HashInnerJoin(l, r)).toList
    val left  = memRows(HashLeftJoin(l, r)).map(x => (x("k").isNull, x("b").isNull)).toSet
    // Pre-fix: `NullExpr == NullExpr`, so the two NULL-keyed rows joined: two
    // inner rows, and the left join's NULL row carried b = 1.
    ((inner ?= List(Map("k" -> IntExpr(true, 1), "a" -> i(2), "b" -> i(2)))) :| ("inner: " + inner)) &&
      ((left ?= Set((true, true), (false, false))) :| ("left: " + left))
  }

  /** A row with NULLs spelt out, so the two paths' NULLs (typed differently) compare. */
  private def shown(r: Record): Map[String, String] = r.map { case (c, v) => c -> (if (v.isNull) "NULL" else v.toString) }

  property("(C21) the in-memory merge outer join answers what SQLite's FULL JOIN answers on NULL keys") = secure {
    val l = List(nkRow(None, "a", 1), nkRow(Some(1), "a", 2), nkRow(Some(2), "a", 3))
    val r = List(nkRow(None, "b", 1), nkRow(Some(1), "b", 2), nkRow(Some(3), "b", 3))
    val inMemory = memRows(MergeOuterJoin(mem(l), mem(r))).map(shown).toSet
    val inSql    = rows(JoinOn(lit(l), lit(r), Set(), JoinMode.Full)).map(shown).toSet
    // Pre-fix: the merge matched the two NULL keys (`NullExpr == NullExpr`)
    // into one row {k=NULL, a=1, b=1}; SQL's `on (k = k)` never matches NULL.
    ((inMemory ?= inSql) :| ("memory " + inMemory + " vs sql " + inSql)) && ((inMemory.size ?= 5) :| "five rows")
  }

  // =================================================================== wave 2: C15 C16 C17 C20

  property("(C15) a projection through a non-injective op dedupes") = secure {
    val sn = ColumnValue("s", StringT(0, true))
    val in = lit(List(Map("s" -> (StringExpr(true, "b"): PrimExpr)), Map("s" -> (NullExpr(StringT(0, true)): PrimExpr))))
    val got = rows(Project(in, Map(Attribute("p", StringT(0, true)) -> Op.Coalesce(sn, OpLiteral(StringExpr(true, "b")))))).toList
    // Pre-fix: `coalesce(s, 'b')` over one column was taken as injective, no
    // DISTINCT, and 'b' came out twice.
    got ?= List(Map("p" -> (StringExpr(true, "b"): PrimExpr)))
  }

  property("(C16) a FULL JOIN over a nullable key dedupes the coalesced padding rows") = secure {
    val row: Record = Map("k" -> (NullExpr(IntT(true)): PrimExpr), "a" -> i(1))
    val got = rows(JoinOn(lit(List(row)), lit(List(row)), Set(), JoinMode.Full)).toList
    // Pre-fix: the two NULL keys did not match, the left-only and right-only
    // rows both coalesced to (NULL, 1), and the join claimed distinctness.
    (got.size ?= 1) :| ("rows: " + got)
  }

  property("(C17) a one-row limit past the first position counts positions in the SET") = secure {
    val dup = lit(List(Map("k" -> i(1)), Map("k" -> i(1)), Map("k" -> i(2))))
    val second = rows(Limit(dup, Some(2), Some(2), List("k" -> Asc))).toList
    val first  = rows(Limit(dup, Some(1), Some(1), List("k" -> Asc))).toList
    // Pre-fix: the one-row shortcut asked for a non-distinct input, so row 2
    // of the bag [1, 1, 2] was 1.
    ((second ?= List(Map("k" -> i(2)))) :| ("second: " + second)) && ((first ?= List(Map("k" -> i(1)))) :| ("first: " + first))
  }

  property("(C20) a let whose body never uses the binding makes no temp table") = secure {
    val r: Relation[Nothing, Nothing] = LetR(ExtRel(noSuchTable, ""), Nil, VarR(RPop(r1)))
    val text = sqlite.dumpRel(r)
    val got = try Right(rows(r).toSet) catch { case e: Throwable => Left(e.toString) }
    // Pre-fix: a CREATE and an INSERT from the (missing) bound relation ran
    // before the body, and the scan failed on them.
    ((count(text, "CREATE") ?= 0) :| ("temp table for an unused let:\n" + text)) && (got ?= Right(r1.tups.list.toList.toSet))
  }

  // =================================================================== oracle O-2 and O-9 (in this file's remit)

  property("(oracle O-2) a literal with duplicate rows is not claimed distinct") = secure {
    val dup = lit(List(kx(1, 1), kx(1, 1)))
    val text = mssql.dumpRel(Project(dup, Map(kA -> k))).toLowerCase
    val clean = mssql.dumpRel(Project(r1, Map(kA -> k, xA -> x))).toLowerCase
    // Pre-fix: `literal` answered distinct = true and the table-value
    // constructor delivered both rows on SQL Server.
    ((count(text, "distinct") ?= 1) :| ("no distinct over a duplicate literal: " + text)) &&
      ((count(clean, "distinct") ?= 0) :| ("a distinct literal got one: " + clean))
  }

  property("(oracle O-2) an aggregate over a literal with duplicate rows aggregates the SET") = secure {
    val dup = lit(List(kx(1, 1), kx(1, 1), kx(2, 3)))
    val n = Attribute("n", IntT(false))
    val grouped = mssql.dumpRel(AggregateByGroup(dup, Map(), List((n, AggFunc.Count)), Nil)).toLowerCase
    val plain   = mssql.dumpRel(Aggregate(dup, n, AggFunc.Count)).toLowerCase
    // Pre-fix: `select COUNT(*) from (values (1,1), (1,1), (2,3))`: the
    // literal's "not distinct" answer was ignored and SQL Server counted 3.
    ((count(grouped, "distinct") ?= 1) :| ("grouped: " + grouped)) && ((count(plain, "distinct") ?= 1) :| ("plain: " + plain)) &&
      ((rows(Aggregate(dup, n, AggFunc.Count)).toList ?= List(Map("n" -> i(2)))) :| "SQLite count")
  }

  property("(oracle O-2) a let over a literal with duplicate rows fills its table with the SET") = secure {
    val dup = lit(List(kx(1, 1), kx(1, 1), kx(2, 3)))
    val text = mssql.dumpRel(LetR(ExtRel(dup, ""), Nil, VarR(RTop))).toLowerCase
    // Pre-fix: `insert into ##t.. select [k],[x] from (values (1,1), (1,1), (2,3))`
    // filled the temp table with both copies and `table` claimed it distinct.
    (text.contains("insert into") && text.contains("distinct")) :| ("no distinct in the fill:\n" + text)
  }

  property("(oracle O-9) a projection of only constants over an ungrouped aggregate keeps ONE row") = secure {
    val p = Attribute("p", IntT(false))
    val over3 = rows(Project(Aggregate(r1, Attribute("n", IntT(false)), AggFunc.Count), Map(p -> OpLiteral(i(3)))))
    val over0 = rows(Project(Aggregate(none, Attribute("n", IntT(false)), AggFunc.Count), Map(p -> OpLiteral(i(3)))))
    // Pre-fix: `select (3) p from (...)`: the aggregate was projected away and
    // the query answered one row PER INPUT ROW (3, and none for no input).
    ((over3.toList ?= List(Map("p" -> i(3)))) :| ("over three rows: " + over3)) &&
      ((over0.toList ?= List(Map("p" -> i(3)))) :| ("over no rows: " + over0))
  }
}
