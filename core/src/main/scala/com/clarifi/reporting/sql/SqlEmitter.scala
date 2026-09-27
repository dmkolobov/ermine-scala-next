package com.clarifi.reporting.sql

import com.clarifi.reporting._
import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.Hints._
import com.clarifi.reporting.flatteners.TableFlattener
import RawSql._

import scalaz._
import Scalaz._
import java.sql.{PreparedStatement,ResultSet,SQLException,Types}
import java.util.Date
import java.util.UUID
import java.util.Calendar

import scalaz._
import Scalaz._

/**
 * Emitters are responsible for emitting SQL statements/queries in
 * specific dialects.
 *
 * @author JAT, MSP, SMB
 */
abstract class SqlEmitter(aliasParens: Boolean = true) {
  def emitNull: RawSql = "NULL"
  def emitNull(stmt: PreparedStatement, i: Int, t: PrimT): Unit = stmt.setNull(i, sqlTypeId(t))

  /** Convenience for emitting a column name `c` qualified by a table
    * name `t`.  I ''don't'' promise to use this instead of
    * `emitTableName` and `emitColumnName`, so take care.
    */
  def emitQualifiedColumnName(t: TableName, c: String): RawSql =
    emitTableName(t) |+| "." |+| emitColumnName(c)

  def emitTableName(s: TableName): RawSql =
    (s.schema :+ s.name) map raw rawMkString "."
  def emitColumnName(s: String): RawSql = s
  def emitProcedureName(s: String, namespace: List[String]): RawSql =
    emitTableName(TableName(s, namespace))
  // These are not symmetric; unemit operates on java.sql bits, and
  // emit is part of SQL codegen.  But if you implement one, you'd
  // better implement the other.
  def unemitTableName(s: String): TableName = TableName(s)
  // TODO: This looks like a hack to me. Do we need to re-parse emitted SQL? -- Runar
  def unemitColumnName(s: String): String = s

  // boolean output - how to stuff a boolean in a PreparedStatement, and how to
  // output a literal Boolean
  def emitBoolean(stmt: PreparedStatement, i: Int, b: Boolean): Unit

  /**
   * Emits the value to use when selecting a boolean value (such as
   * 'select 1' or 'select true').
   */
  def emitBoolean(b: Boolean): RawSql

  def getBoolean(rs: ResultSet, i: Int): Boolean

  def emitUuid(stmt: PreparedStatement, i: Int, b: UUID): Unit
  def emitUuid(u: UUID): RawSql
  def getUuid(rs: ResultSet, i: Int): UUID

  def isTransactional: Boolean
  def setConstraints(enable: Boolean, t: Iterable[TableName]): List[RawSql]

  /**
   * Controls whether we try to delay inserting a distinct
   * until we know we have to, or do it immediately when we
   * can't tell that something isn't distinct.
   *
   * NOTE: this also controls whether we do distinctness in
   * memory or enforce it in SQL on scan out. The presumption
   * is that if the DB implementation is good enough to do
   * distincts low down in queries, it is also more efficient
   * than what we can do while streaming.
   */
  def distinctEagerly: Boolean

  /**
   * Used at the end of a SELECT...FROM when the list of tables is empty.
   * Returns the empty string by default.
   */
  def emitFromEmptyTable: RawSql = ""

  /**
   * Emits the CREATE TABLE... command.  The format is:
   * CREATE TABLE <tablename> (
   *   <columnname> <columntype>,
   *   ...
   *   FOREIGN KEY (<columnname>, ...) REFERENCES <foreigntablename> (<foreigncolumn>, ...),
   *   ...
   *   PRIMARY KEY(<col1>, ...)
   * )
   */
  def emitCreateTable(e: SqlCreate): RawSql = {
    val cols = e.hints.sortColumns(e.header.keySet).map((colName) =>
      emitColumnName(colName) |+| " " |+| sqlTypeName(e.header(colName)))

    val r2 = e.hints.foreignKeys.map {
      case (foreignTable, setFK) =>
        setFK.map { setCC => {
          val (localCols, foreignCols) = e.schemaHints.tables(foreignTable).sortColumns(setCC.map(_._2)).
            map(fc => setCC.find(_._2 == fc).get).unzip
          raw("FOREIGN KEY ") |+|
            localCols.map(emitColumnName).rawMkString("(", ", ", ")") |+|
            " REFERENCES " |+| emitTableName(foreignTable) |+|
            foreignCols.map(emitColumnName).rawMkString("(", ", ", ")")
      }}.rawMkString(", ")
    }
    val r3 = e.hints.primaryKey.map((colGroup) =>
      if (!colGroup.isEmpty)
        raw("PRIMARY KEY ") |+| e.hints.sortColumns(colGroup).map(emitColumnName).
          rawMkString("(", ", ", ")")
      else raw("")).filter(x => !x.isEmpty)

    (emitCreateTableStmt(e.table)
       |+| (cols ++ r2 ++ r3).rawMkString(" (\n ", ",\n ", " ) ")
       |+| emitCreateTableSuffix(e.table))
  }

  def emitCreateTableStmt(t: TableName): RawSql = {
    val tempmarker: RawSql = t.scope match {
      case TableName.Persistent => ""
      case TableName.Temporary | TableName.Variable(_) => "TEMPORARY"
    }
    raw("CREATE ") |+| tempmarker |+| " TABLE " |+| emitTableName(t)
  }

  def emitCreateTableSuffix(t: TableName): RawSql

  /** Assuming `t.scope` is `Temporary`, emit a `DROP TABLE` statement
    * that will drop the so-named table, or None if dropping temp
    * tables is not possible or desirable in this SQL implementation.
    */
  def emitDropTempTable: Option[TableName => RawSql]

  /**
   * Emits the command to create an index.  Default implementation:
   * CREATE INDEX indexName ON [tablename] ( col1, col2, ... colN )
   * Works for SQLite, MySQL, and SQL Server.  Vertica doesn't have indexes.
   */
  def emitCreateIndex(t: TableName, hints: TableHints, indexName: String, cols: ColumnGroup, c: IsCandidateKey): Option[RawSql] =
    Some(raw("create index ") |+| indexName |+| " on " |+| emitTableName(t) |+| " " |+|
         hints.sortColumns(cols).map(emitColumnName).rawMkString(" ( ", ", ", " ) "))

  def emitDropIndex(t: TableName, indexName: String): Option[RawSql] =
    Some(raw("drop index ") |+| indexName |+| " on " |+| emitTableName(t))

  // def ifNotExists(t: TableName, r: List[RawSql]) : RawSql = raw("if object_id(N") |+| emitTableName(t) |+| raw(") is not null") |+| r.rawMkString("\n") |+| raw("go")

  /** A SQL statement yielding a relation with three potential outcomes:
    *
    * 1. No rows, `t` does not exist
    * 2. At least one row, first row has NULL `col`: `t` does not exist
    * 3. At least one row, first row has non-NULL `col`: `t` exists
    *
    * Relying on that alone can yield false negatives.  So the other
    * part of the result is a predicate on [[java.sql.SQLException]]s;
    * if true on an error thrown while creating `t`, treat that as a
    * positive existence result.
    *
    * @see [[com.clarifi.reporting.relational.SqlScanner]]`#sequenceSql`
    */
  def checkExists(t: TableName, col: ColumnName) : (RawSql, SQLException => Boolean)

  /**
   * Creates the column names for a create table statement, by default.
   */
  def emitSqlColumns(header: Header): RawSql = {
    import std.iterable._
    header.keys.map(emitColumnName).rawMkString(", ")
  }

  /**
   * Generate an insert statement, using the syntax:
   * INSERT INTO <tablename> ( <col1>, <col2>, ... ) VALUES ( <val1>, <val2>, ... )
   */
  def emitInsert(e: SqlInsert): RawSql =
    (raw("insert into ") |+| emitTableName(e.table)
       // we assume query has naturally sorted col order
       |+| e.targetOrder.sorted.map(emitColumnName).rawMkString("(", ", ", ")")
       |+| " " |+| e.sql.emitSql(this))

  /** Insert the result of executing a stored procedure into the given
    * table. */
  def emitExec(e: SqlExec): RawSql =
    ((e.prep foldMap (p => (p emitSql this) |+| raw(" ; ")))
       |+| (raw("insert into ") |+| emitTableName(e.table)
              |+| e.order.map(emitColumnName).rawMkString("(", ", ", ")")
              |+| raw(" exec ") |+| emitProcedureName(e.proc, e.namespace)
              |+| raw(" ")
              |+| e.args.map(_ fold (emitTableName, _.emitSql(this)))
                        .rawMkString(", ")))

  /**
   * Emits a date value from the given Long.
   */
  def emitDate(d: Date): RawSql = {
    raw("'") |+| dateFormatter.format(d) |+| "'"
  }

  def emitTimestamp(t: java.sql.Timestamp): RawSql = {
    raw("'") |+| timestampFormatter.format(t) |+| "'"
  }

  def emitDateAddName: String

  def emitInterval(n: SqlExpr, u: TimeUnit): RawSql

  /** `d` moved by `n` units of `u`.  Default: the T-SQL/MySQL shape
    * `<emitDateAddName>(<emitInterval n u>, d)`.  SQLite overrides it (its
    * dates are epoch-millisecond INTEGERs, not a date type).  SQL audit E2. */
  def emitDateAdd(d: SqlExpr, n: SqlExpr, u: TimeUnit): SqlExpr =
    FunSqlExpr(emitDateAddName, List(IntervalExpr(n, u), d))

  /** The number of `u` boundaries crossed from `s` to `e` (T-SQL DATEDIFF's
    * meaning: 2024-01-15 to 2024-03-01 is 2 months, 23:59 to 00:01 is one
    * day).  Default: `datediff(<unit>, s, e)`.  SQL audit E2. */
  def emitDateDiff(u: TimeUnit, s: SqlExpr, e: SqlExpr): SqlExpr =
    FunSqlExpr("datediff", List(Verbatim(u.toString.toLowerCase), s, e))

  /** A string literal.  Escaping `'` as `''` is common to every dialect;
    * SQL Server prefixes `N` so that characters outside the database
    * collation's code page survive (SQL audit E6). */
  def emitString(s: String): RawSql = raw("'") |+| s.replace("'", "''") |+| "'"

  /** A double literal.  NaN and the infinities have no SQL spelling on any
    * dialect (SQLite parses `Infinity` as a column name; SQL Server `float`
    * cannot hold it), so they are NULL (SQL audit decision D6). */
  def emitDouble(d: Double): RawSql =
    if (d.isNaN || d.isInfinite) emitNull else d.toString

  val dateFormatter = {
    val fmt = new java.text.SimpleDateFormat("yyyy-MM-dd")
    fmt setTimeZone util.YMDTriple.ymdPivotTimeZone
    fmt
  }

  val timestampFormatter = {
    val fmt = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS")
    fmt setTimeZone util.YMDTriple.ymdPivotTimeZone
    fmt
  }

  def emitDateStatement(stmt: java.sql.PreparedStatement, index: Int, date: Date): Unit = {
    val gmtCalendar = Calendar.getInstance
    gmtCalendar.setTimeZone(util.YMDTriple.ymdPivotTimeZone)
    stmt.setDate(index, new java.sql.Date(date.getTime), gmtCalendar)
  }
  def emitTimestampStatement(stmt: java.sql.PreparedStatement, index: Int, timestamp: java.sql.Timestamp): Unit = {
    val gmtCalendar = Calendar.getInstance
    gmtCalendar.setTimeZone(util.YMDTriple.ymdPivotTimeZone)
    stmt.setTimestamp(index, timestamp, gmtCalendar)
  }

  /**
   * Emits union to ensure proper grouping of multiple options.
   */
  def emitNaryOp(op: SqlBinOp, rs: NonEmptyList[SqlQuery]): RawSql =
    rs.map(_.emitSql(this)).rawMkString( " " + op.emit.run + " ")

  private[sql] final def allSubqueryColumns(rs: NonEmptyList[Subquery]): RawSql = {
    implicit val so: scala.math.Ordering[TableName] = Order[TableName].toScalaOrdering

    rs.foldLeft(Map[ColumnName, TableName]()) {
      case (m, (_, t, h)) => m ++ h.map(_._1 -> t)
    }.toList.sorted.map {
      case (k, v) => emitQualifiedColumnName(v, k)
    }.rawMkString(", ")
  }

  /**
   * Emits Sql for a join on a specified set of column-pairs.
   */
  def emitJoinOn(r1: SqlSource,
                 r2: SqlSource,
                 on: Set[(SqlExpr, SqlExpr)],
                 op: SqlJoinOp): RawSql = {
    val onExpr = if (on.isEmpty) SqlTruth(true).emitSql(this)
                 else on.map {
                   case (c1, c2) => c1.emitSql(this) |+| " = " |+| c2.emitSql(this)
                 } intercalate raw(" and ")
    r1.emitSql(this) |+| raw(" ") |+| op.emit |+| raw(" ") |+| r2.emitSql(this) |+|
    " on (" |+| onExpr |+| ")"
  }

  /** Emits SQL for a Transact-SQL-style `OVER` clause.  Emitters whose
    * dialect has window functions mix in `EmitOver_UsingOver`; the default
    * refuses, because the old placeholder text ("TODO I don't yet know how
    * to play ...") was spliced into the SELECT list and reached the driver
    * as a syntax error (SQL audit E1).
    */
  def emitOver(e: SqlExpr, over: SqlOver): RawSql =
    sys.error(getClass.getName + " does not emit window functions (" +
              e.emitSql(this).run + " over ...)")

  /** Emits SQL for the opening of a Transact-SQL `CAST` or `TRY_CAST` expression.
    * If `nullIfFail` is true, emits a cast that returns null if fail.
    */
  def emitTryCast(nullIfFail: Boolean): RawSql =
    if (nullIfFail) sys.error(getClass.getName + " does not emit a null-on-failure cast (tryCast)")
    else raw("cast(")

  /** The whole cast expression: `e`, whose type is `from` when the scanner
    * could infer it, converted to `to`.  Default: `cast(e as <type>)`, or
    * the dialect's TRY_CAST when `nullIfFail`.  SQLite overrides it, since
    * its storage classes (dates are INTEGER milliseconds) make a plain
    * CAST wrong between dates and strings (SQL audit E9, E18). */
  def emitCast(e: SqlExpr, from: Option[PrimT], to: PrimT, nullIfFail: Boolean): RawSql =
    emitTryCast(nullIfFail) |+| e.emitSql(this) |+| " as " |+| sqlTypeName(to) |+| ")"

  /** Build a query that chooses a range of rows in `query` by
    * ordering them according to `order` and choosing the rows
    * numbered `from` to `to`, one-indexed and inclusive.
    *
    * For implementations with no support for this, answer `query`.
    */
  def implementLimit(query: SqlQuery.Orderable, queryHeader: Header, unQuery: TableName,
                from: Option[Int], to: Option[Int],
                order: List[(SqlColumn, SqlOrder)],
                unSurrogate: TableName): SqlQuery.Scannable with SqlQuery.Nestable = query match {
    case q: SqlQuery.Scannable with SqlQuery.Nestable => q
  }

  def implementSubquery(q: SqlQuery.Nestable, h: Header, un: TableName) : SqlSubquery =
    SqlSubquery(q, h.keys.toList, un)

  /** Emit a SqlLimit in a way appropriate for the backend */
  def emitLimit(from: Option[Int], to: Option[Int]): RawSql = ""

  /** Emit a literal relation */
  def emitLiteral(n: NonEmptyList[Map[SqlColumn, SqlExpr]]): RawSql =
    fallbackEmitLiteral(n)

  /** Emit a literal relation in a compatible way
    * (it would be on the object like all the others, but it needs 'this')
    */
  def fallbackEmitLiteral(n: NonEmptyList[Map[SqlColumn, SqlExpr]]): RawSql =
    SqlNaryOp(SqlUnion, n.map(t => SqlSelect(attrs = t))).emitSql(this)

  /** The rows of a literal relation with duplicates removed and the column
    * order fixed, for the VALUES-style emitters.  A relation literal is a
    * set; `UNION` deduplicated the fallback form by accident, a
    * table-value constructor keeps every row it is given (the oracle's O-2).
    * Answers the sorted column names and the distinct rows in that order. */
  protected final def literalRows(n: NonEmptyList[Map[SqlColumn, SqlExpr]]): (List[SqlColumn], List[List[SqlExpr]]) = {
    val cols = n.head.keys.toList.sorted
    (cols, n.list.toList.map(r => cols.map(r)).distinct)
  }

  /** Emit an empty relation.  Each NULL is cast to the column's type:
    * SQL Server refuses to aggregate an untyped NULL (`SUM(NULL)` is
    * Msg 8117), and a typed column reads back through the same getter as
    * a real one (SQL audit E10). */
  def emitEmpty(queryHeader: Header): RawSql =
    SqlSelect(attrs = queryHeader.map { case (c, t) => (c, typedNull(t)) },
              where = List(SqlTruth(false))).emitSql(this)

  protected def typedNull(t: PrimT): SqlExpr = LitSqlExpr(SqlNullOf(t))

  /** `cast(NULL as <t>)`, with `t` made nullable so that the type name
    * carries no `not null` (SQL audit E10/E22). */
  def emitTypedNull(t: PrimT): RawSql =
    raw("cast(") |+| emitNull |+| " as " |+| sqlTypeName(t.withNull) |+| ")"

  /**
   * Takes a list of SqlExprs and returns a SqlExpr representing that list
   * concatenated together.  Defers to `emitConcat_helper` for
   * non-empty `terms`.
   */
  final def emitConcat(terms: List[SqlExpr]): SqlExpr =
    terms.toNel cata (emitConcat_helper, LitSqlExpr(SqlString("")))

  protected def emitConcat_helper(terms: NonEmptyList[SqlExpr]): SqlExpr =
    terms.foldLeft1(BinSqlExpr("||", _, _))

  /** `AVG(e)`, where `ty` is `e`'s type when the scanner could infer it.
    * SQL Server's average of an integer column is an integer (the sum
    * divided by the count, truncated toward zero) and the header types it
    * so; SQLite's `avg()` is always REAL, so an integral average there is
    * cast back (SQL audit, found by the differential oracle under the
    * emitter's E7 flag). */
  def emitAvg(exp: SqlExpr, ty: Option[PrimT]): SqlExpr = FunSqlExpr("AVG", List(exp))

  /**
   * Emits the population standard deviation aggregation function.  Default
   * implementation uses STDDEV_POP(arg)
   */
  def emitStddevPop(exp: SqlExpr): SqlExpr =
    FunSqlExpr("STDDEV_POP", List(exp))

  /**
   * Emits the sample standard deviation aggregation function.  Default
   * implementation uses STDDEV_SAMP(arg)
   */
  def emitStddevSamp(un: TableName, col: SqlColumn): SqlExpr = FunSqlExpr("STDDEV_SAMP", List(ColumnSqlExpr(un, col)))

  /**
   * Emits the population variance aggregation function.  Default
   * implementation uses VAR_POP(arg)
   */
  def emitVarPop(exp: SqlExpr): SqlExpr =
    FunSqlExpr("VAR_POP", List(exp))

  /**
   * Emits the sample variance aggregation function.  Default
   * implementation uses VAR_SAMP(arg)
   */
  def emitVarSamp(un: TableName, col: SqlColumn): SqlExpr = FunSqlExpr("VAR_SAMP", List(ColumnSqlExpr(un, col)))

  /**
   * Emits the operator to use for integer division. This operator, for
   * example should give 4/3 = 1 (and not a decimal value).
   *
   * The default implementation returns /.
   */
  def emitIntegerDivision(a: SqlExpr, b: SqlExpr): SqlExpr = BinSqlExpr("/", a, b)

  /**
   * Mapping from ADT type names to SQL type names
   */
  def sqlTypeName(p: PrimT): RawSql

  /**
   * Mapping from ADT type names to SQL type IDs per java.sql.Types
   */
  def sqlTypeId(p: PrimT): Int

  /** Inverse of `sqlTypeId`; should be forgiving.
    *
    * @param dt JDBC DATA_TYPE.
    * @param tn JDBC TYPE_NAME.
    * @param cs JDBC COLUMN_SIZE. */
  def sqlPrimT(dt: Int, tn: String, cs: Int): Option[PrimT]
}

//////////////////////////////////////////////////////////////////////////////
// Traits for specific behavior overrides

/** Insert a distinct as soon as we are unable to
  * determine that the result set automatically will be.
  */
trait EagerlyDistinct extends SqlEmitter {
  val distinctEagerly = true
}

/** Delay forcing SQL queries to be distinct until
  * we are certain that we need distinctness.
  */
trait LazilyDistinct extends SqlEmitter {
  val distinctEagerly = false
}

/** Emitters for which there is no suffix after the closing ')' in
  * create table statements.
  */
trait EmitCreateTable_NoSuffix extends SqlEmitter {
  def emitCreateTableSuffix(t: TableName): RawSql = raw("")
}

/** Emitters for which there is a 'ENGINE = MEMORY' suffix for
  * temporary tables after the closing ')' in create table statements.
  */
trait EmitCreateTable_TempEngineMemory extends SqlEmitter {
  def emitCreateTableSuffix(t: TableName): RawSql = t.scope match {
    case TableName.Persistent => raw("")
    case TableName.Temporary | TableName.Variable(_) =>
      raw("ENGINE = MEMORY")
  }
}

/** Emitters for which the `DROP TABLE` syntax implicitly commits, or
  * is unsafe for some other reason, but an alternate `DROP TEMPORARY
  * TABLE` command is supplied.
  */
trait EmitDropTemporaryTable extends SqlEmitter {
  def emitDropTempTable: Option[TableName => RawSql] =
    Some(t => raw("DROP TEMPORARY TABLE ") |+| emitTableName(t))
}

/** Emitters for which the ordinary `DROP TABLE` syntax is
  * transaction-safe over temp tables.
  */
trait EmitDropTempTable_AsDropTable extends SqlEmitter {
  def emitDropTempTable: Option[TableName => RawSql] =
    Some(t => raw("DROP TABLE ") |+| emitTableName(t))
}

/** Emitters for which dropping temp tables after we're done with them
  * is undesirable.
  */
trait EmitNoDropTempTable extends SqlEmitter {
  def emitDropTempTable: Option[TableName => RawSql] = None
}

/**
 * Overrides emitFromEmptyTable to return " from dual "
 */
trait EmitFromEmptyTable_FromDual extends SqlEmitter {
  override def emitFromEmptyTable = " from dual "
}

/**
 * Overrides emitSqlColumns to include the types of each column
 */
trait EmitSqlColumns_Typed extends SqlEmitter {
  import std.iterable._
  override def emitSqlColumns(header: Header): RawSql =
    header.toIterable.
      map(t => emitColumnName(t._1) |+| " " |+| sqlTypeName(t._2)).rawMkString(", ")
}

trait EmitNary_ExceptAsJoin extends SqlEmitter {
  override def emitNaryOp(op: SqlBinOp, rs: NonEmptyList[SqlQuery]):RawSql = op match {
    case SqlExcept(ur, rh) =>
      if (rh.isEmpty)
        rs.head.emitSql(this)
      else {
        val cs = rh.keySet // column names
        val cq = rh.keys.head  // primary column ( used to exclude right results )
        val t0 = emitTableName(ur)
        val rts = rs.tail.zipWithIndex map { case (r, i) => (r, ur.copy(name = ur.name + "d" + i.toString))}
   
        val cols = cs.toList.sorted.map(t0 |+| "." |+| _).rawMkString(", ")
   
        val joins = (rts map { case (r, ut) =>
          raw("left join (") |+| r.emitSql(this) |+| raw(") ") |+| emitTableName(ut) |+| 
          raw(" on ") |+| ( cs.map(emitQualifiedColumnName(ur,_))
                          , cs.map(emitQualifiedColumnName(ut,_))).zipped
                                                                  .map({case (cl, cr) => cl |+| raw("=") |+| cr})
                                                                  .rawMkString(" and ")
        }).rawMkString(" ")
   
        val preds = (rts map { case (_, ut) => 
          emitQualifiedColumnName(ut, cq) |+| " is null"
        }).rawMkString(" and ")
   
        List( raw("select"), cols
            , raw("from"), raw("(") |+| rs.head.emitSql(this) |+| raw(")"), t0
            , joins
            , raw("where"), preds ).rawMkString(" ")
      }
    case _ => super.emitNaryOp(op, rs) 
  }
}

/** MySQL and PostgreSQL support `LIMIT`. */
trait ImplementLimit_AsLimit extends SqlEmitter {
  /** Wrap the ''rc'' in a select that duplicates ''h'', reorders the
    * relation, and limits according to ''from'' and ''to''.
    */
  override def implementLimit(rc: SqlQuery.Orderable, h: Header, un: TableName,
                              from: Option[Int], to: Option[Int],
                              order: List[(SqlColumn, SqlOrder)],
                              un2: TableName): SqlQuery.Scannable with SqlQuery.Nestable =
    SqlLimit(SqlQuery.orderBy(rc, order), from, to)
}

trait ImplementSubquery_MS extends SqlEmitter {
  override def implementSubquery(q: SqlQuery.Nestable, h: Header,
                                 un: TableName) : SqlSubquery = q match {
    case SqlLimit(SqlOrderBy(SqlNaryOp(op,rs), ord), from, to) => 
      val unInner = un.copy(name = un.name + "inner")
      val sel = SqlSelect(
        attrs = h.map(x => (x._1, ColumnSqlExpr(unInner, x._1))),
        sources = SourceList(super.implementSubquery(SqlNaryOp(op,rs), h, unInner))
      )
      super.implementSubquery(SqlLimit(SqlQuery.orderBy(sel, ord), from, to), h, un)
    case _ => super.implementSubquery(q, h, un)
  }
}

trait EmitLimit_AsLimit extends SqlEmitter {
  /** The LIMIT count meaning "no bound", for an OFFSET with no upper
    * row: SQLite and MySQL require a LIMIT before an OFFSET (SQL audit E5).
    * SQLite takes -1, MySQL its 64-bit maximum, PostgreSQL and Vertica
    * `ALL`. */
  def unboundedLimit: String = "-1"

  /** Use PostgreSQL's 0-indexed `LIMIT ''length'' OFFSET ''from''`
    * syntax, which is also supported in MySQL.
    */
  override def emitLimit(from: Option[Int], to: Option[Int]): RawSql = (from, to) match {
    case (Some(x), Some(y)) => " limit %d offset %d" format (y - x + 1, x - 1)
    case (Some(x), None) => " limit %s offset %d" format (unboundedLimit, x - 1)
    case (None, Some(y)) => " limit %d" format y
    case (None, None) => ""
  }
}

trait EmitLimit_AsOffsetFetch extends SqlEmitter {
  /** Standard SQL syntax for limited queries. Supported in new enough MS TSQL
    */
  override def emitLimit(from: Option[Int], to: Option[Int]): RawSql = {
    val o = from.map(_ - 1).getOrElse(0)
    val off = " offset %d rows" format o
    val lim = to match {
      case Some(t) => " fetch next %d rows only" format (t - o)
      case None => ""
    }
    off + lim
  }
}

trait EmitOver_UsingOver extends SqlEmitter {
  override def emitOver(e: SqlExpr, over: SqlOver): RawSql = over match {
    case SqlOver(partition, order, frameBegin, frameEnd) =>
      def frameIndex(i: Int) =
        if (i < 0) (-i).toString + " preceding"
        else if (i > 0) i.toString + " following"
        else "current row"

      def frameEx(oi: Option[Int], pos: String) = oi.map(frameIndex).getOrElse("unbounded " + pos)

      val rawPart = raw("partition by ") |+| partition.map(_ emitSql(this)).rawMkString(", ")
      val rawOrder = raw("order by ") |+| order.map{ case (e, o) => e.emitSql(this) |+| " " |+| o.emitSql }.rawMkString(", ")
      val rawFrame = raw("rows between ") |+|
                     frameEx(frameBegin, "preceding") |+|
                     " and " |+|
                     frameEx(frameEnd, "following")

      if (order.isEmpty && !(frameBegin.isEmpty && frameEnd.isEmpty))
        sys.error("Window frames may only be used with ordered window functions.")
      else {
        e.emitSql(this) |+| " over (" |+|
        (if (partition.isEmpty) raw("") else rawPart |+| " ") |+|
        (if (order.isEmpty) raw("")
          else if (frameBegin.isEmpty && frameEnd.isEmpty) rawOrder
          else rawOrder |+| " " |+| rawFrame) |+|
        ")"
      }


  }
}

/**
 * Overrides emitConcat to use the CONCAT(arg1, ... argn) function
 */
trait EmitConcat_AsConcat extends SqlEmitter {
  override protected def emitConcat_helper(terms: NonEmptyList[SqlExpr]): SqlExpr =
    FunSqlExpr("Concat", if (terms.tail.isEmpty) List(terms.head, LitSqlExpr(SqlString(""))) else terms.list.toList) // CONCAT must take at least 2 args.
}

/** Pretend UUIDS are strings. */
trait EmitUuid_Strings extends SqlEmitter {
  /** A SQL NULL reads back as a null UUID, NOT as an exception.  Every other
    * column type's getter answers a zero and leaves `rs.wasNull` set, which is
    * the only thing `SqlExecution.nextRecord` looks at -- it builds the cell
    * BEFORE it asks -- so `UUID.fromString(null)` used to throw a
    * NullPointerException for a NULL in a nullable GUID column, before anything
    * could notice it was null (J3b's ticket for J3c).  `UuidExpr` holds the
    * value without touching it, so the null never escapes: the `wasNull` test
    * two lines later replaces the cell with `NullExpr`. */
  def getUuid(rs: ResultSet, i: Int): UUID = {
    val s = rs.getString(i)
    if (s == null) null else java.util.UUID.fromString(s)
  }
  def emitUuid(u: UUID): RawSql = raw("'") |+| u.toString |+| "'"
  def emitUuid(stmt: PreparedStatement, i: Int, u: UUID): Unit =
    stmt.setString(i, u.toString)
}

trait EmitTryCast_MsSQL extends SqlEmitter {
  override def emitTryCast(nullIfFail: Boolean): RawSql =
    if (nullIfFail) { raw("TRY_CAST(") } else { raw("cast(") }
}

/**
 * Overrides the standard deviation and variance (sample and population) aggregation
 * functions for SQL Server.
 */
trait EmitStddevVar_MsSQL extends SqlEmitter {
  override def emitStddevPop(exp: SqlExpr): SqlExpr =
    FunSqlExpr("STDEVP", List(exp))
  override def emitStddevSamp(un: TableName, col: SqlColumn): SqlExpr = FunSqlExpr("STDEV", List(ColumnSqlExpr(un, col)))
  override def emitVarPop(exp: SqlExpr): SqlExpr =
    FunSqlExpr("VARP", List(exp))
  override def emitVarSamp(un: TableName, col: SqlColumn): SqlExpr = FunSqlExpr("VAR", List(ColumnSqlExpr(un, col)))
}

trait EmitName_MsSql extends SqlEmitter {
  override def emitColumnName(s: String): RawSql =
    raw("[") |+| raw(s) |+| raw("]")
  override def emitTableName(s: TableName): RawSql = {
    val name = s.scope match {
      case TableName.Persistent => emitColumnName("" + s.name)
      case TableName.Temporary => emitColumnName("##" + s.name)
      case TableName.Variable(_) => raw("@") |+| s.name
    }
    ((s.schema map emitColumnName) :+ name) rawMkString "."
  }
  override def emitProcedureName(s: String, namespace: List[String]): RawSql =
    if (namespace.isEmpty) raw(s) else
      emitTableName(TableName(s, namespace))
}

trait EmitIntDivOp_MsSql extends SqlEmitter {
  override def emitIntegerDivision(a: SqlExpr, b: SqlExpr): SqlExpr =
    FunSqlExpr("floor", List(BinSqlExpr("/", FunSqlExpr("floor", List(a)),
                                        FunSqlExpr("floor", List(b)))))
}

/**
 * Override emitIntegerDivisionOp to return 'div', which is
 * MySQL's integer division operator.
 */
trait EmitIntDivOp_MySQL extends SqlEmitter {
  override def emitIntegerDivision(a: SqlExpr, b: SqlExpr): SqlExpr =
    BinSqlExpr("div", FunSqlExpr("floor", List(a)), FunSqlExpr("floor", List(b)))
}

/** An unimplemented #checkExists. */
trait EmitCheckExists_AlwaysFails extends SqlEmitter {
  /** @todo Actually yield true sometimes. */
  def checkExists(t: TableName, col: ColumnName) : (RawSql, SQLException => Boolean) =
    (raw("select (") |+| emitNull |+| ") " |+| emitColumnName(col)
       |+| " " |+| emitFromEmptyTable,
     Function const false)
}

/** Emit a literal relation as a TVC */
trait EmitLiteralTVC extends SqlEmitter {
  /** @todo Is it possible to avoid this redundant select? */
  override def emitLiteral(n: NonEmptyList[Map[SqlColumn, SqlExpr]]): RawSql = {
    val (cols, rows) = literalRows(n)
    (raw("select ") |+| cols.map(emitColumnName _).rawMkString(",")
      |+| " from (values "
      |+| rows.map(r => r.map(_.emitSql(this)).rawMkString("(", ", ", ")"))
             .rawMkString(", ")
      |+| ") as lit"
      |+| cols.map(emitColumnName _).rawMkString("(", ",", ")"))
  }
}

/** Emit a literal relation as a TVC on a dialect that names the columns of
  * a `VALUES` table `column1`, `column2`, ... and takes no alias list on a
  * derived table (SQLite).  One SELECT per literal instead of one per row
  * chained with UNION (SQL audit E13). */
trait EmitLiteralTVC_ColumnN extends SqlEmitter {
  override def emitLiteral(n: NonEmptyList[Map[SqlColumn, SqlExpr]]): RawSql = {
    val (cols, rows) = literalRows(n)
    (raw("select ")
      |+| cols.zipWithIndex.map { case (c, i) => raw("column" + (i + 1) + " ") |+| emitColumnName(c) }
              .rawMkString(", ")
      |+| " from (values "
      |+| rows.map(r => r.map(_.emitSql(this)).rawMkString("(", ", ", ")"))
             .rawMkString(", ")
      |+| ")")
  }
}

/** Parenthesise a right operand that is itself a join: `A JOIN (B JOIN C
  * on ..) on ..`.  SQL Server re-associates the bare form, SQLite rejects
  * it (`near "on": syntax error`), MySQL always wanted the parentheses
  * (SQL audit E4). */
trait EmitJoinOn_ParenthesizeRight extends SqlEmitter {
  override def emitJoinOn(r1: SqlSource,
                          r2: SqlSource,
                          on: Set[(SqlExpr, SqlExpr)],
                          op: SqlJoinOp): RawSql = {
    val onExpr = if (on.isEmpty) SqlTruth(true).emitSql(this)
                 else on.map {
                   case (c1, c2) => c1.emitSql(this) |+| " = " |+| c2.emitSql(this)
                 } intercalate raw(" and ")
    val r2IsJoin = r2 match { case _ : SqlJoinOn => true ; case _ => false }
    val preR2 = if (r2IsJoin) raw("(") else raw(" ")
    val postR2 = if (r2IsJoin) raw(") on (") else raw(" on (")
    r1.emitSql(this) |+| raw(" ") |+| op.emit |+| preR2 |+| r2.emitSql(this) |+|
    postR2 |+| onExpr |+| ")"
  }
}

/** String concatenation with `||` where a NULL operand would make the
  * whole result NULL.  Every non-literal operand is wrapped in
  * `coalesce(.., '')`, which is what `Concat` on SQL Server and the
  * in-memory evaluator (`extractNullableString ""`) do with a NULL, and
  * what the header promises: `Concat` is typed non-nullable (SQL audit E17). */
trait EmitConcat_CoalesceNulls extends SqlEmitter {
  override protected def emitConcat_helper(terms: NonEmptyList[SqlExpr]): SqlExpr =
    terms.map {
      case t@LitSqlExpr(SqlString(_)) => t
      case t => FunSqlExpr("coalesce", List(t, LitSqlExpr(SqlString(""))))
    }.foldLeft1(BinSqlExpr("||", _, _))
}

//////////////////////////////////////////////////////////////////////////////
// SQL dialect implementations

class SqliteEmitter extends SqlEmitter
    with EmitCreateTable_NoSuffix
    with EmitNoDropTempTable
    with EmitUuid_Strings
    with ImplementLimit_AsLimit
    with EmitLimit_AsLimit
    with EagerlyDistinct
    with EmitCheckExists_AlwaysFails
    with EmitOver_UsingOver
    with EmitIntDivOp_MsSql
    with EmitJoinOn_ParenthesizeRight
    with EmitConcat_CoalesceNulls
    with EmitLiteralTVC_ColumnN {

  def isTransactional: Boolean = true
  def setConstraints(enable: Boolean, t: Iterable[TableName]): List[RawSql] =
     if (enable)
       List("PRAGMA foreign_keys = ON")
     else
       List("PRAGMA foreign_keys = OFF")

  def getBoolean(rs: ResultSet, i: Int): Boolean = rs.getInt(i) != 0
  def emitBoolean(b: Boolean): RawSql = if (b) "1" else "0"
  def emitBoolean(stmt: PreparedStatement, i: Int, b: Boolean): Unit = stmt.setInt(i, if (b) 1 else 0)

  /** Identifiers are double-quoted (`""` escapes a quote), so a field named
    * `group`, `order`, `select` or `user` is legal SQL.  sqlite-jdbc's
    * `getColumnLabel` answers the bare name, so `unemitColumnName` stays the
    * identity (SQL audit E4). */
  private[this] def quoteName(s: String): RawSql =
    raw("\"") |+| raw(s.replace("\"", "\"\"")) |+| raw("\"")
  override def emitTableName(s: TableName): RawSql =
    (s.schema :+ s.name) map quoteName rawMkString "."
  override def emitColumnName(s: String): RawSql = quoteName(s)

  /** Dates AND timestamps are epoch-millisecond INTEGERs: that is what
    * `bulkLoad`/`setTimestamp` store (sqlite-jdbc's default `DateClass`),
    * what `sqlTypeName` declares, and what `getDate`/`getTimestamp` read
    * back exactly.  A TEXT timestamp literal compared against an INTEGER
    * column would sort every INTEGER below it (SQL audit E9). */
  override def emitDate(d: Date): RawSql = d.getTime.toString
  override def emitTimestamp(t: java.sql.Timestamp): RawSql = t.getTime.toString

  // Unreachable from the scanner since `emitDateAdd` below; kept because
  // the abstract members must be defined.
  def emitDateAddName = sys.error("sqlite dateadd goes through emitDateAdd")
  def emitInterval(n: SqlExpr, u: TimeUnit) =
    sys.error("sqlite dateadd goes through emitDateAdd")

  // ---- date arithmetic over epoch milliseconds (SQL audit E2)

  private[this] def lit(l: Long): SqlExpr = LitSqlExpr(SqlLong(l))
  private[this] def str(s: String): SqlExpr = LitSqlExpr(SqlString(s))
  /** `e` as fractional seconds since the epoch, for SQLite's date functions. */
  private[this] def secs(e: SqlExpr): SqlExpr = BinSqlExpr("/", e, LitSqlExpr(SqlDouble(1000.0)))
  private[this] def unixepochOf(e: SqlExpr, mods: SqlExpr*): SqlExpr =
    FunSqlExpr("unixepoch", secs(e) :: str("unixepoch") :: mods.toList)
  private[this] def asInteger(e: SqlExpr): SqlExpr = CastSqlExpr(e, LongT(true), false, None)
  /** Fractional epoch seconds back to INTEGER milliseconds. */
  private[this] def millisOf(secsExpr: SqlExpr): SqlExpr =
    asInteger(FunSqlExpr("round", List(BinSqlExpr("*", secsExpr, lit(1000)))))
  private[this] def dayStart(e: SqlExpr): SqlExpr = unixepochOf(e, str("start of day"))
  private[this] def strfInt(fmt: String, e: SqlExpr): SqlExpr =
    asInteger(FunSqlExpr("strftime", List(str(fmt), secs(e), str("unixepoch"))))

  /** Millisecond, second, day and week steps are plain integer arithmetic
    * (dates are GMT, so a day is always 86 400 000 ms).  Month and year
    * steps go through SQLite's calendar with the `floor` modifier, which
    * clamps an overflowing day-of-month to the month's last day exactly as
    * `java.util.Calendar#add` (the in-memory evaluator) and T-SQL `DATEADD`
    * do: 2024-01-31 + 1 month = 2024-02-29.  `subsec` keeps the
    * milliseconds. */
  override def emitDateAdd(d: SqlExpr, n: SqlExpr, u: TimeUnit): SqlExpr = {
    import TimeUnit._
    def plusMillis(perUnit: Long) = BinSqlExpr("+", d, BinSqlExpr("*", n, lit(perUnit)))
    def calendar(unit: String) =
      millisOf(unixepochOf(d, BinSqlExpr("||", n, str(" " + unit)), str("floor"), str("subsec")))
    u match {
      case Millisecond => BinSqlExpr("+", d, n)
      case Second => plusMillis(1000L)
      case Day => plusMillis(86400000L)
      case Week => plusMillis(604800000L)
      case Month => calendar("months")
      case Year => calendar("years")
    }
  }

  /** T-SQL DATEDIFF's boundary count: whole units are never rounded, the
    * number of unit boundaries between `s` and `e` is.  Weeks start on
    * Sunday, as SQL Server's default DATEFIRST has it. */
  override def emitDateDiff(u: TimeUnit, s: SqlExpr, e: SqlExpr): SqlExpr = {
    import TimeUnit._
    def floorSecs(x: SqlExpr) = asInteger(FunSqlExpr("floor", List(secs(x))))
    def weekStart(x: SqlExpr) =
      unixepochOf(x, str("start of day"),
                  BinSqlExpr("||", BinSqlExpr("||", str("-"), FunSqlExpr("strftime", List(str("%w"), secs(x), str("unixepoch")))),
                             str(" days")))
    def year(x: SqlExpr) = strfInt("%Y", x)
    def month(x: SqlExpr) = strfInt("%m", x)
    u match {
      case Millisecond => BinSqlExpr("-", e, s)
      case Second => BinSqlExpr("-", floorSecs(e), floorSecs(s))
      case Day => BinSqlExpr("/", BinSqlExpr("-", dayStart(e), dayStart(s)), lit(86400L))
      case Week => BinSqlExpr("/", BinSqlExpr("-", weekStart(e), weekStart(s)), lit(604800L))
      case Month => BinSqlExpr("+", BinSqlExpr("*", BinSqlExpr("-", year(e), year(s)), lit(12L)),
                               BinSqlExpr("-", month(e), month(s)))
      case Year => BinSqlExpr("-", year(e), year(s))
    }
  }

  // ---- casts (SQL audit E9, E18)

  /** The rule: SQLite stores a Date or Timestamp as INTEGER milliseconds and
    * a String as TEXT, so a plain CAST between them is a number/text
    * conversion, not a date conversion.  Between a date and a string this
    * emits the calendar conversion in ISO 8601 (`2024-01-15`,
    * `2024-01-15 10:11:12.123`), the text SQL Server's CAST produces; a
    * string that is not a date becomes NULL.  Every other pair is a plain
    * `CAST` (dates to and from numbers are the milliseconds, as
    * `PrimExpr.cast` reads them).  A null-on-failure cast to a number is
    * guarded by a CASE, since SQLite's `CAST('abc' AS REAL)` is 0.0 rather
    * than an error. */
  override def emitCast(e: SqlExpr, from: Option[PrimT], to: PrimT, nullIfFail: Boolean): RawSql = {
    def plain = raw("cast(") |+| e.emitSql(this) |+| " as " |+| sqlTypeName(to) |+| ")"
    def isDate(t: PrimT) = t match { case DateT(_) | TimestampT(_) => true; case _ => false }
    def isNum(t: PrimT) = t match {
      case ByteT(_) | ShortT(_) | IntT(_) | LongT(_) | DoubleT(_) => true; case _ => false }
    (from, to) match {
      case (Some(DateT(_)), StringT(_, _)) =>
        FunSqlExpr("strftime", List(str("%Y-%m-%d"), secs(e), str("unixepoch"))).emitSql(this)
      case (Some(TimestampT(_)), StringT(_, _)) =>
        FunSqlExpr("strftime", List(str("%Y-%m-%d %H:%M:%f"), secs(e), str("unixepoch"))).emitSql(this)
      case (Some(StringT(_, _)), DateT(_)) =>
        millisOf(FunSqlExpr("unixepoch", List(e, str("start of day"), str("subsec")))).emitSql(this)
      case (Some(StringT(_, _)), TimestampT(_)) =>
        millisOf(FunSqlExpr("unixepoch", List(e, str("subsec")))).emitSql(this)
      case (Some(f), t) if nullIfFail && isNum(t) && !isNum(f) && !isDate(f) =>
        // typeof answers the storage class of the VALUE; a TEXT is cast only
        // when its trimmed form has T-SQL's numeric syntax
        // `[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?` -- which these GLOBs spell
        // out: a digit; the charset; one dot; one e; a sign only first or
        // right after the e; nothing trailing but a digit; no dot after the
        // e; a digit before the e.  Measured against TRY_CAST on SQL Server
        // 2022 for 24 inputs; the one difference is '' (0 there, NULL here,
        // as the in-memory tryCast answers).
        val t = raw("trim(cast(") |+| e.emitSql(this) |+| " as text))"
        def is(pat: String) = raw("(") |+| t |+| " glob '" |+| pat |+| "')"
        def not(pat: String) = raw("(") |+| t |+| " not glob '" |+| pat |+| "')"
        val numeric = List(is("*[0-9]*"), not("*[^0-9.eE+-]*"), not("*.*.*"), not("*[eE]*[eE]*"),
                           not("*[^eE][+-]*"), not("*[+-]"), not("*[eE]"), not("*[eE]*.*"),
                           not("[eE]*"), not("[+-.][eE]*"), not("[+-.][+-.][eE]*")).rawMkString(" and ")
        (raw("(case when typeof(") |+| e.emitSql(this) |+| ") in ('integer', 'real') then " |+| plain
          |+| " when " |+| numeric |+| " then cast(" |+| t |+| " as " |+| sqlTypeName(to) |+| ")"
          |+| " else NULL end)")
      case _ => plain
    }
  }

  // ---- population/sample deviation and variance (SQL audit E3)

  /** SQLite has no STDDEV/VARIANCE; these are the one-pass forms over
    * `avg`, guarded against the tiny negative a rounding error can leave
    * (sqrt of which is NULL).  One pass loses precision when the mean
    * dwarfs the spread; report data is fine. */
  private[this] def varPopOf(x: SqlExpr): SqlExpr = {
    val avg = FunSqlExpr("avg", List(x))
    FunSqlExpr("max", List(BinSqlExpr("-", FunSqlExpr("avg", List(BinSqlExpr("*", x, x))),
                                      BinSqlExpr("*", avg, avg)),
                           LitSqlExpr(SqlDouble(0.0))))
  }
  private[this] def sampleOf(x: SqlExpr): SqlExpr = {
    val n = FunSqlExpr("count", List(x))
    BinSqlExpr("/", BinSqlExpr("*", varPopOf(x), n), BinSqlExpr("-", n, LitSqlExpr(SqlDouble(1.0))))
  }
  override def emitAvg(exp: SqlExpr, ty: Option[PrimT]): SqlExpr = ty match {
    case Some(ByteT(_) | ShortT(_) | IntT(_) | LongT(_)) => asInteger(FunSqlExpr("AVG", List(exp)))
    case _ => FunSqlExpr("AVG", List(exp))
  }
  override def emitStddevPop(exp: SqlExpr): SqlExpr = FunSqlExpr("sqrt", List(varPopOf(exp)))
  override def emitVarPop(exp: SqlExpr): SqlExpr = varPopOf(exp)
  override def emitStddevSamp(un: TableName, col: SqlColumn): SqlExpr =
    FunSqlExpr("sqrt", List(sampleOf(ColumnSqlExpr(un, col))))
  override def emitVarSamp(un: TableName, col: SqlColumn): SqlExpr = sampleOf(ColumnSqlExpr(un, col))

  def sqlTypeId(p: PrimT): Int = p match {
    case StringT(_, _) => Types.VARCHAR
    case UuidT(_) => Types.VARCHAR
    case ByteT(_) => Types.INTEGER
    case ShortT(_) => Types.INTEGER
    case IntT(_) => Types.INTEGER
    case LongT(_) => Types.INTEGER
    case DoubleT(_) => Types.REAL
    case DateT(_) => Types.INTEGER
    case TimestampT(_) => Types.INTEGER
    case BooleanT(_) => Types.INTEGER
  }

  def sqlTypeName(p: PrimT): RawSql = p match {
    case StringT(_, _)  => "text"
    case UuidT(n)       => "text"
    case ByteT(n)       => "integer"
    case ShortT(n)      => "integer"
    case IntT(n)        => "integer"
    case LongT(n)       => "integer"
    case DoubleT(n)     => "real"
    case DateT(n)       => "integer"
    case TimestampT(n)  => "integer"
    case BooleanT(n)    => "integer"
  }

  def sqlPrimT(x: Int, tn: String, cs: Int) = SqlEmitter.defaultDecodeType(x)

  /* Sqlite has a weird rule where the arguments to a UNION and the like are
   * not allowed to be parenthesized. This means, it seems, that there is no
   * way to indicate the precedence of multiple distinct binary operations,
   * but the precedence matters. So, for sqlite, we wrap the arguments in a
   * select, which can have a parenthesized subquery.
   *
   * We only override this case, because this query structure is not ideal,
   * but is necessary for sqlite.
   */
  override def emitNaryOp(op: SqlBinOp, rs: NonEmptyList[SqlQuery]): RawSql =
    rs.map(r => raw("select * from (") |+| r.emitSql(this) |+| ")")
      .intercalate(raw(" ") |+| op.emit |+| " ")

  // doesn't use the "on <tablename>" part of the command
  //override def emitDropIndex(t: TableName, indexName: String): Option[String] =
  //  Some("drop index " + indexName)
}

class MySqlEmitter(innoDB: Boolean) extends SqlEmitter(false) with EmitFromEmptyTable_FromDual
                                      with EmitSqlColumns_Typed
                                      with EmitCreateTable_NoSuffix
                                      with EmitDropTemporaryTable
                                      with EmitNary_ExceptAsJoin
                                      with ImplementLimit_AsLimit
                                      with EmitLimit_AsLimit
                                      with EmitConcat_AsConcat
                                      with LazilyDistinct
                                      with EmitIntDivOp_MySQL
                                      with EmitUuid_Strings
                                      with EmitJoinOn_ParenthesizeRight {
  override def emitTableName(tn: TableName): RawSql =
    (tn.schema :+ tn.name) map emitColumnName rawMkString "."
  override def emitColumnName(cn: String): RawSql = raw("`") |+| raw(cn) |+| raw("`")
  override def unboundedLimit: String = "18446744073709551615"
  // MySQL's CAST targets (SIGNED, CHAR, ...) are not its column types; untyped, as before.
  override def emitTypedNull(t: PrimT): RawSql = emitNull

  def isTransactional: Boolean = innoDB
  def setConstraints(enable: Boolean, t: Iterable[TableName]): List[RawSql] =
     if (enable)
       List(raw("SET foreign_key_checks = 1"))
     else
       List(raw("SET foreign_key_checks = 0"))

  def getBoolean(rs: ResultSet, i: Int): Boolean = rs.getInt(i) != 0
  def emitBoolean(b: Boolean): RawSql = if (b) "TRUE" else "FALSE" // these are just aliases for 1 and 0
  def emitBoolean(stmt: PreparedStatement, i: Int, b: Boolean): Unit = stmt.setInt(i, if (b) 1 else 0)

  def emitDateAddName = "date_add"
  def emitInterval(n: SqlExpr, u: TimeUnit) =
    raw("interval ") |+| n.emitSql(this) |+| raw(" " + u.toString)

  import SqlEmitter.nn

  def sqlTypeName(p: PrimT): RawSql = p match {
    case UuidT(n)     => nn(n,"char(36)")
    case BooleanT(n)  => nn(n,"tinyint(1)")
    case DoubleT(n)   => nn(n, "double")
    case _ => SqlEmitter.fallbackSqlTypeName(p)
  }

  def sqlTypeId(p: PrimT): Int = p match {
    case StringT(_,_) => Types.VARCHAR
    case DoubleT(n)   => Types.DOUBLE
    case _ => SqlEmitter.fallbackSqlTypeId(p)
  }

  def sqlPrimT(x: Int, tn: String, cs: Int) = SqlEmitter.defaultDecodeType(x)

  def checkExists(t: TableName, col: ColumnName) : (RawSql, SQLException => Boolean) =
    (raw("select (") |+| emitColumnName("TABLE_NAME")
       |+| ") " |+| emitColumnName(col)
       |+| " from "
       |+| emitTableName(TableName("TABLES", List("INFORMATION_SCHEMA")))
       |+| " where "
       |+| emitColumnName("TABLE_NAME") |+| " = " |+| SqlString(t.name).emitSql(this)
       |+| " and " |+| emitColumnName("TABLE_SCHEMA")
       |+| " = " |+| SqlString(t.schema mkString ".").emitSql(this),
     e => e.getErrorCode == 1050)

  /** MySQL requires FROM with WHERE ;_; */
  override def emitEmpty(queryHeader: Header): RawSql =
    SqlSelect(attrs = queryHeader.mapValues(_ => LitSqlExpr(SqlNull)).toMap,
              sources = SourceList(
                SqlSubquery(cols = List("qq"),
                            alias = TableName("qq"),
                            query = SqlSelect(attrs = Map("qq" -> LitSqlExpr(SqlNull))))),
              where = List(SqlTruth(false))
             ).emitSql(this)
}

class MsSqlEmitter extends SqlEmitter with EmitSqlColumns_Typed
                                      with EmitCreateTable_NoSuffix
                                      // `DROP TABLE ##x` is transaction-safe on SQL Server; without
                                      // it every let/materialize/large-literal temp table lived in
                                      // tempdb for the connection's lifetime (SQL audit E16).
                                      with EmitDropTempTable_AsDropTable
                                      with EagerlyDistinct
                                      with EmitConcat_AsConcat
                                      with EmitIntDivOp_MsSql
                                      with ImplementLimit_AsLimit
                                      with ImplementSubquery_MS
                                      with EmitLimit_AsOffsetFetch
                                      with EmitOver_UsingOver
                                      with EmitStddevVar_MsSQL
                                      with EmitUuid_Strings
                                      with EmitLiteralTVC
                                      with EmitName_MsSql
                                      with EmitTryCast_MsSQL {

  def isTransactional: Boolean = true
  def setConstraints(enable: Boolean, t: Iterable[TableName]): List[RawSql] =
    if (enable)
      t.toList.map(raw("ALTER TABLE ") |+| emitTableName(_) |+| " WITH CHECK CHECK CONSTRAINT all")
    else
      t.toList.map(raw("ALTER TABLE ") |+| emitTableName(_) |+| " NOCHECK CONSTRAINT all")

  def getBoolean(rs: ResultSet, i: Int): Boolean = rs.getInt(i) != 0
  def emitBoolean(b: Boolean): RawSql = if (b) "1" else "0"
  def emitBoolean(stmt: PreparedStatement, i: Int, b: Boolean): Unit = stmt.setInt(i, if (b) 1 else 0)
  override def emitTimestamp(t: java.sql.Timestamp): RawSql = {
    raw("CAST('") |+| timestampFormatter.format(t) |+| raw("' AS DATETIME2)")
  }
  /** `CAST('yyyy-MM-dd' AS DATE)`: a bare `'yyyy-MM-dd'` is converted
    * through the login's `SET LANGUAGE`/`DATEFORMAT` (it is Msg 242 under
    * French or dmy), `date` parses ISO 8601 regardless (SQL audit E11). */
  override def emitDate(d: Date): RawSql =
    raw("CAST('") |+| dateFormatter.format(d) |+| raw("' AS DATE)")

  /** `N'...'`: without the prefix the literal is converted through the
    * database collation's code page and every character outside it (CJK,
    * emoji, Cyrillic under CP1252) arrives as `?` (SQL audit E6). */
  override def emitString(s: String): RawSql = raw("N") |+| super.emitString(s)

  /** A double literal is a `float`, never a DECIMAL: `1.0 / 3.0` as decimals is
    * `0.333333`, and a UNION of a literal double with a decimal aggregate
    * drops the scale.  T-SQL reads a literal with an exponent as float, so
    * one without gets `E0` (SQL audit E24). */
  override def emitDouble(d: Double): RawSql = {
    val s = super.emitDouble(d).run
    if (s.contains("E") || s == "NULL") s else s + "E0"
  }

  private def nn(n: Boolean, s: String): RawSql = if (n) s else (s |+| " not null")

  /** An unbounded string is `nvarchar(max)`: `nvarchar(1000)` truncated
    * casts silently and refused longer loads.  Inside CREATE TABLE a key
    * column cannot be `max` (SQL Server refuses to index it); `emitCreateTable`
    * gives those `nvarchar(450)`, the longest that fits a clustered key
    * (SQL audit E12). */
  def sqlTypeName(p: PrimT): RawSql = p match {
    case StringT(l,n) => nn(n,"nvarchar(" |+| (if (l == 0) "max" else l.toString) |+| ")")
    case TimestampT(n) => nn(n,"datetime2")
    case _ => SqlEmitter.fallbackSqlTypeName(p)
  }

  private[this] val keyStringLength = 450

  def sqlTypeId(p: PrimT): Int = p match {
    case StringT(_,_) => Types.VARCHAR
    case _ => SqlEmitter.fallbackSqlTypeId(p)
  }

  def emitDateAddName = "dateadd"
  def emitInterval(n: SqlExpr, u: TimeUnit) =
    raw(u.toString.toLowerCase) |+| raw(", ") |+| n.emitSql(this)

  def sqlPrimT(x: Int, tn: String, cs: Int) = tn match {
    case "date" => Some(DateT()) // jtds gives x = varchar for dates
    case "datetime" | "datetime2" => Some(TimestampT())
    case "uniqueidentifier" => Some(UuidT())
    case _ => SqlEmitter.defaultDecodeType(x)
  }

  override def emitCreateTable(s: SqlCreate): RawSql = s.table.scope match {
    case TableName.Variable(typeName) =>
      // we *assume* that `typeName` has the correct rowtype.
      raw("declare ") |+| emitTableName(s.table) |+| raw(" as ") |+| raw(typeName)
    case TableName.Persistent | TableName.Temporary =>
      val keyCols: Set[ColumnName] =
        s.hints.primaryKey.toList.flatten.toSet ++
        s.hints.indices.keys.flatten ++
        s.hints.foreignKeys.values.flatten.flatten.map(_._1)
      val bounded = s.header.map {
        case (c, StringT(0, n)) if keyCols(c) => (c, StringT(keyStringLength, n))
        case x => x
      }
      super.emitCreateTable(s.copy(header = bounded))
  }

  override def emitCreateTableStmt(t: TableName): RawSql =
    raw("CREATE ") |+| " TABLE " |+| emitTableName(t)

  def checkExists(t: TableName, col: ColumnName): (RawSql, SQLException => Boolean) =
    (raw("select object_id(N'") |+| (t.scope match {
                                       case TableName.Temporary => raw("tempdb.dbo.")
                                       case _ => raw("")
                                     })
       |+| emitTableName(t)
       |+| raw("') ") |+| emitColumnName(col) |+| emitFromEmptyTable,
     e => e.getErrorCode == 2714)
}

class MsSqlNonTransactionalEmitter extends MsSqlEmitter {
  override def isTransactional: Boolean = false
}

class VerticaSqlEmitter extends SqlEmitter(false) with EmitFromEmptyTable_FromDual
                                           with EmitSqlColumns_Typed
                                           with EmitCreateTable_NoSuffix
                                           with EmitNoDropTempTable
                                           with EmitNary_ExceptAsJoin
                                           with EagerlyDistinct
                                           with EmitUuid_Strings
                                           with EmitCheckExists_AlwaysFails
                                           // Vertica has LIMIT/OFFSET and OVER; without the limit
                                           // traits `firstK`/`topK` answered every row (SQL audit
                                           // E19).  Text-level only: no Vertica to run against.
                                           with ImplementLimit_AsLimit
                                           with EmitLimit_AsLimit
                                           with EmitOver_UsingOver {
  override def unboundedLimit: String = "ALL"

  def isTransactional: Boolean = true
  def setConstraints(enable: Boolean, t: Iterable[TableName]): List[RawSql] =
    if (enable)
      List(raw("SELECT REENABLE_DUPLICATE_KEY_ERROR()"))
    else
      List(raw("SELECT DISABLE_DUPLICATE_KEY_ERROR()"))

  def getBoolean(rs: ResultSet, i: Int): Boolean = rs.getBoolean(i)
  def emitBoolean(b: Boolean): RawSql = if (b) "TRUE" else "FALSE"
  def emitBoolean(stmt: PreparedStatement, i: Int, b: Boolean): Unit = stmt.setBoolean(i, b)
  def emitDateAddName = sys.error("todo - vertica dateadd function")
  def emitInterval(n: SqlExpr, u: TimeUnit) =
    sys.error("todo - vertica dateadd function")

  import SqlEmitter.nn

  def sqlTypeName(p: PrimT): RawSql = p match {
    case UuidT(n)     => nn(n,"char(36)")
    case BooleanT(n)  => nn(n,"boolean")
    case _ => SqlEmitter.fallbackSqlTypeName(p)
  }

  def sqlTypeId(p: PrimT): Int = SqlEmitter.fallbackSqlTypeId(p)

  def sqlPrimT(x: Int, tn: String, cs: Int) = SqlEmitter.defaultDecodeType(x)

  // Vertica doesn't have indexes
  override def emitCreateIndex(t: TableName, hints: TableHints, indexName: String, cols: ColumnGroup, c: IsCandidateKey): Option[RawSql] = None
  override def emitDropIndex(t: TableName, indexName: String): Option[RawSql] = None
}

class PostgreSqlEmitter extends SqlEmitter(false)
                        with EmitSqlColumns_Typed
                        with EmitCreateTable_NoSuffix
                        with EmitNoDropTempTable
                        with ImplementLimit_AsLimit
                        with EmitLimit_AsLimit
                        with EagerlyDistinct
                        with EmitUuid_Strings
                        with EmitCheckExists_AlwaysFails
                        with EmitOver_UsingOver // text-level only, no live PostgreSQL here
                        with EmitConcat_CoalesceNulls {
  import SqlEmitter.nn

  override def unboundedLimit: String = "ALL"

  private[this] def quoteName(s: String): RawSql =
    "\"%s\"" format (s replaceAllLiterally ("\"", "\"\""))
  override def emitTableName(s: TableName) =
    (s.schema :+ s.name) map quoteName rawMkString "."
  override def emitColumnName(s: String) = quoteName(s)

  def isTransactional: Boolean = true

  // You can't reliably disable constraints in PG, so don't try.
  def setConstraints(enable: Boolean, t: Iterable[TableName]):
      List[RawSql] = List.empty

  // Postgres has real booleans
  def getBoolean(rs: ResultSet, i: Int): Boolean = rs.getBoolean(i)
  def emitBoolean(b: Boolean): RawSql = if (b) "TRUE" else "FALSE"
  def emitBoolean(stmt: PreparedStatement, i: Int, b: Boolean): Unit = stmt.setBoolean(i, b)
  def emitDateAddName = sys.error("todo - postgres dateadd function")
  def emitInterval(n: SqlExpr, u: TimeUnit) =
    sys.error("todo - postgres dateadd function")

  // PG doesn't play fast & loose with string→date coercion
  override def emitDate(d: Date): RawSql =
    raw("date '") |+| dateFormatter.format(d) |+| "'"

  override def emitTimestamp(t: java.sql.Timestamp): RawSql =
    raw("timestamp '") |+| timestampFormatter.format(t) |+| "'"

  def sqlTypeName(p: PrimT): RawSql = p match {
    // PG has `uuid' but harder to access from JDBC.
    case UuidT(n)    => nn(n,"char(36)")
    case ByteT(n)    => sqlTypeName(ShortT(n)) // nothing smaller than short
    case DoubleT(n)  => nn(n,"double precision")
    case BooleanT(n) => nn(n, "boolean") // But, real booleans!
    case _           => SqlEmitter.fallbackSqlTypeName(p)
  }

  // See `sqlTypeName` for notes.
  def sqlTypeId(p: PrimT): Int = p match {
    case ByteT(n)    => sqlTypeId(ShortT(n))
    case DoubleT(_)  => Types.DOUBLE
    case BooleanT(_) => Types.BOOLEAN
    case _           => SqlEmitter.fallbackSqlTypeId(p)
  }

  def sqlPrimT(x: Int, tn: String, cs: Int) = SqlEmitter.defaultDecodeType(x)
}

object SqlEmitter {

  /** The fallback type decoder.  Use SqlEmitter's instead. */
  private[sql] def defaultDecodeType(x: Int): Option[PrimT] = {
    import java.sql.{Types => T}
    ((_ match {
      case T.BIT | T.BOOLEAN => BooleanT()
      case T.CHAR | T.VARCHAR | T.NCHAR | T.NVARCHAR
         | T.LONGVARCHAR | T.LONGNVARCHAR => StringT(0)
      case T.DATE => DateT()
      case T.TIMESTAMP => TimestampT()
      // mssql-jdbc reports `numeric(p,s)` as NUMERIC (2), not DECIMAL (3).
      case T.FLOAT | T.DOUBLE | T.REAL | T.DECIMAL | T.NUMERIC => DoubleT()
      case T.BIGINT => LongT()
      case T.INTEGER => IntT()
      case T.SMALLINT => ShortT()
      case T.TINYINT => ByteT()
    }): PartialFunction[Int, PrimT]).lift(x)
  }

  def nn(n: Boolean, s: String): RawSql = if (n) s else (s |+| " not null")

  def fallbackSqlTypeName(p: PrimT): RawSql = p match {
    case StringT(l,n) => nn(n,"varchar(" |+| (if (l == 0) "1000" else l.toString) |+| ")")
    case UuidT(n)     => nn(n,"uniqueidentifier")
    case ByteT(n)     => nn(n,"tinyint")
    case ShortT(n)    => nn(n,"smallint")
    case IntT(n)      => nn(n,"int")
    case LongT(n)     => nn(n,"bigint")
    case DoubleT(n)   => nn(n,"float")
    case DateT(n)     => nn(n,"date")
    case BooleanT(n)  => nn(n,"bit")
    case TimestampT(n)=> nn(n,"timestamp")
  }

  def fallbackSqlTypeId(p: PrimT): Int = p match {
    case StringT(_,_) => Types.VARCHAR
    case UuidT(_) => Types.CHAR
    case ByteT(_) => Types.TINYINT
    case ShortT(_) => Types.SMALLINT
    case IntT(_) => Types.INTEGER
    case LongT(_) => Types.BIGINT
    case DoubleT(_) => Types.FLOAT
    case DateT(_) => Types.DATE
    case BooleanT(_) => Types.BIT
    case TimestampT(_) => Types.TIMESTAMP
  }

  val sqliteEmitter = new SqliteEmitter
  val mySqlInnoDBEmitter = new MySqlEmitter(true)
  val mySqlEmitter = new MySqlEmitter(false)
  val msSqlEmitter = new MsSqlEmitter
  val msSqlNonTransactionalEmitter = new MsSqlNonTransactionalEmitter

  val verticaSqlEmitter = new VerticaSqlEmitter

  val postgreSqlEmitter = new PostgreSqlEmitter

  import std.iterable._
  /** String of the table creation statements used by the given flattener. */
  def createStatements(f: TableFlattener[_,_], emitter: SqlEmitter): RawSql =
    f.schema.map { case (tn, hdr) => SqlCreate(tn, hdr, f.hints.tables(tn), f.hints).emitSql(emitter) } rawMkString "\n\n"
}
