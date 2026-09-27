package com.clarifi.reporting
package sql

import com.clarifi.reporting.backends._
import com.clarifi.reporting.util.PimpedLogger._
import PrimT._
import DB._

import org.apache.log4j.Logger
import java.sql.{Driver => _, _}
import java.util.Calendar

import com.clarifi.machines._
import scalaz._
import Scalaz._

import relational.EffectfulProcedure

// Replacement for SqlBackend
class SqlExecution(implicit emitter: SqlEmitter) {
  private[this] def logger = Logger getLogger this.getClass

  import Machine.ProcessCategory._

  def scanQuery[A](sql: SqlQuery, h: Header, notes: List[String] = List()): DB[Procedure[Id,Record]] = conn => {
    new EffectfulProcedure[Record] {

      type K = Record => Any

      def machine = id

      def setup: (Driver[Id, K], () => Unit) = {
        // generate the SQL from the SqlQuery
        // S2b (RenderTrace): the preview's render installs a trace on this
        // thread for its one `Run[DB].run`; everyone else gets `Off`, whose
        // methods return at once, and the row driver below takes no clock.
        val tr = RenderTrace.current
        val eStart = if (tr.on) System.nanoTime else 0L
        val query = sql.emitSql
        if (tr.on) {
          tr.sqlEmitted(System.nanoTime - eStart)
          tr.queryStart(query.run, SqlExecution.dialectOf(emitter))
        }
        val qStartNs = if (tr.on) System.nanoTime else 0L
        val qStart = System.currentTimeMillis
        logger ltrace ("Executing query " |+| query.run)
        notes foreach { n => logger ltrace ("Note: " |+| n) }

        /*  For mySQL connections, to enable streamed resultsets, 
            stmt = conn.createStatement(java.sql.ResultSet.TYPE_FORWARD_ONLY, java.sql.ResultSet.CONCUR_READ_ONLY);
            stmt.setFetchSize(Integer.MIN_VALUE);        
            
            The combination of a forward-only, read-only result set, with a fetch size of Integer.MIN_VALUE serves 
            as a signal to the driver to stream result sets row-by-row. After this, any result sets created with the statement will be retrieved row-by-row.
            
        */
        val stmt = conn.prepareStatement(query.run)
        logger.debug("prepared statement fetch size: " + stmt.getFetchSize)
        stmt.setFetchSize(10000)
        stmt.setQueryTimeout(300) // 5 minutes
        // A query the database REJECTS used to leave its statement open: the
        // teardown below is only installed once `setup` returns (audit L-12).
        val rs = try stmt.executeQuery catch { case t: Throwable => stmt.close(); throw t }
        val md = rs.getMetaData

        val cc = md.getColumnCount
        val gmtCalendar = Calendar.getInstance
        gmtCalendar.setTimeZone(util.YMDTriple.ymdPivotTimeZone)

        if (tr.on) tr.queryExecuted(System.nanoTime - qStartNs)
        val qEnd = System.currentTimeMillis
        val qDelta = qEnd - qStart
        logger trace ("Finished executing query -- took " + qDelta + "ms")

        // Column labels, names and types are resolved ONCE per result set;
        // they were looked up (a native call on sqlite-jdbc) for every cell
        // of every row (audit W-2).
        val labels = Range(0, cc).map(i => md.getColumnLabel(i + 1))
        val keyCache = labels.zipWithIndex.toMap
        val columnTypes: IndexedSeq[PrimT] = labels.map(l => h(emitter.unemitColumnName(l)))

        def nextRecord: Record =
          record.RecordMap.createWithKeyCache(keyCache){ i =>
            val x = i + 1
            val columnType = columnTypes(i)
            val simpleExpr = columnType match {
              case DateT(n) => DateExpr(n, rs.getDate(x, gmtCalendar))
              case DoubleT(n) => DoubleExpr(n, rs.getDouble(x))
              case ByteT(n) => ByteExpr(n, rs.getByte(x))
              case ShortT(n) => ShortExpr(n, rs.getShort(x))
              case IntT(n) => IntExpr(n, rs.getInt(x))
              case LongT(n) => LongExpr(n, rs.getLong(x))
              case StringT(l, n) => StringExpr(n, rs.getString(x))
              case BooleanT(n) => BooleanExpr(n, emitter.getBoolean(rs, x))
              case UuidT(n) => UuidExpr(n, emitter.getUuid(rs, x))
              case TimestampT(n) => TimestampExpr(n, rs.getTimestamp(x, gmtCalendar))
            }
            if (rs.wasNull) {
              if (columnType.nullable) NullExpr(columnType)
              else sys.error("Unexpected NULL in field of type " + columnType)
            } else simpleExpr
          }

        // S2b: the per-row clock (`fetchMs`) is taken around `rs.next()` ONLY,
        // so decoding and encoding the row are not in it; `timeRows` off
        // counts rows without a clock; `Off` is the original line.
        val next: (Record => Any) => Option[Any] =
          if (!tr.on) (x: Record => Any) => if (rs.next) Some(x(nextRecord)) else None
          else if (tr.timeRows) (x: Record => Any) => {
            val t0 = System.nanoTime
            val more = rs.next
            tr.rowFetched(System.nanoTime - t0, more)
            if (more) Some(x(nextRecord)) else None
          }
          else (x: Record => Any) => {
            val more = rs.next
            tr.rowRead(more)
            if (more) Some(x(nextRecord)) else None
          }
        ( Driver.Id(next)
        , () => { try { rs.close ; stmt.close } finally tr.queryClosed() }
        )
      }
    }
  }

  def prepInsert(tn: TableName, columns: List[String]) =
    prepStmt(RawSql.raw("INSERT INTO ") |+| emitter.emitTableName(tn) |+| " ( " |+|
      columns.map(emitter.emitColumnName).rawMkString(", ") |+|
      " ) VALUES ( " |+| List.fill(columns.size)("?").mkString(", ") |+| " )")

  private def transactionBracket[A](act: DB[A]): DB[A] =
    if (emitter.isTransactional) DB.transaction(act)
    else act

  def bulkLoad(h: Header, name: TableName, tuples: DB[Procedure[Id, Record]], batchSize: Int = 5000): DB[Unit] = conn => {
    var count = 0
    val keyList = h.keys.toList
    val keys = keyList.zip(Stream.from(1)).toMap
    def indexOf(n: ColumnName) = keys.getOrElse(n, sys.error("column not mentioned in header"))

    val stmt = prepInsert(name, keyList)(conn)
    val proc = tuples(conn)
    try {
      proc.foreach { x =>
        x.foreach { case (k, v) => setCol(indexOf(k), v, stmt)(conn) }
        stmt.addBatch
        count += 1
        if (count == batchSize) {
          logger ltrace ("insert " + count + " rows with stmt: " + stmt)
          count = 0
          transactionBracket(_ => stmt.executeBatch)(conn)
        }
      }
      if (count != 0) transactionBracket(_ => {
        logger ltrace ("flushing " + count + " rows with stmt " + stmt)
        stmt.executeBatch
      })(conn)
    } finally stmt.close
  }

  def setCol(k: Int, v: PrimExpr, stmt: PreparedStatement): DB[Unit] = cx => v match {
    case IntExpr(_, l) => stmt.setInt(k, l)
    case DoubleExpr(_, d) => stmt.setDouble(k, d)
    case DateExpr(_, d) => emitter.emitDateStatement(stmt, k, d)
    case StringExpr(_, s) => stmt.setString(k, s)
    case BooleanExpr(_, b) => stmt.setBoolean(k, b)
    case ByteExpr(_, b) => stmt.setByte(k, b)
    case LongExpr(_, l) => stmt.setLong(k, l)
    case ShortExpr(_, s) => stmt.setShort(k, s)
    case UuidExpr(_, u) => stmt.setString(k, u.toString)
    case TimestampExpr(_, t) => emitter.emitTimestampStatement(stmt, k, t)
    case NullExpr(t) => stmt.setNull(k, emitter.sqlTypeId(t))
  }

  def destroy(tableName: TableName): DB[Unit] = {
    val s = SqlDrop(tableName).emitSql
    //println(s)
    executeUpdate(s)
  }
}

object SqlExecution {
  /** The dialect name a trace shows for an emitter (S2b): the names
    * `RunnerConfig.dialects` and the profiles use. */
  def dialectOf(e: SqlEmitter): String = e match {
    case _: MsSqlEmitter      => "mssql"
    case _: SqliteEmitter     => "sqlite"
    case _: MySqlEmitter      => "mysql"
    case _: PostgreSqlEmitter => "postgres"
    case _: VerticaSqlEmitter => "vertica"
    case other                => other.getClass.getSimpleName.stripSuffix("Emitter").toLowerCase
  }
}
