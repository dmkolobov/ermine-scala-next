package com.clarifi.reporting.backends

import java.sql._
import java.util.UUID

import math.Ordering
import org.apache.log4j.Logger
import scalaz._
//import scalaz.Scalaz._
import scalaz.IterV._
import scalaz.effect.IO
import IO._
import syntax.monad._
import syntax.traverse.{ToFunctorOps => _, _} // ToFunctorOps is already imported by syntax.monad
import syntax.semigroup._
import scalaz.NaturalTransformation.{id => ident}
import std.function._
import std.list._

import com.clarifi.reporting.Reporting._
import com.clarifi.reporting._
import com.clarifi.reporting.util.StreamTUtils
import com.clarifi.reporting.backends.DB._
import com.clarifi.reporting.PrimT._

import com.clarifi.reporting.sql._
import SqlExpr.{ columns, compileLiteral }

class SqlBackend(implicit emitter: SqlEmitter) extends Backend[DB] {
  import RawSql.raw
  import Kleisli._
  import syntax.kleisli._

  type S = Int
  type SqlState[+A] = State[S, A]

  private[this] def logger = Logger getLogger classOf[SqlBackend]

  /**
   * Error message to show (in addition to extraction informamtion) when an
   * unexpected type is encountered when extracting data from a ResultSet.
   */
  private val BadColumnOrder: String =
    "The column ordering between statements (natural join, union, intersection, etc) is likely not consistent."

  def uniqueName: SqlState[String] = State {
    case i => (i + 1, "t" + i.toString)
  }

  def newRefID: G[RefID] =
    RefID("lf" + guid).pure[G]

  def destroy(r: RefID): G[Unit] = {
    val s = SqlDrop(r).emitSql
    //println(s)
    executeUpdate(s).liftKleisli
  }

  /**
   * Creates an error string detailing information for why a data in a
   * column could not be extracted.
   */
  private def scanErrorMsg(md: ResultSetMetaData, col: Int, sqlT: Int, label: String, o: Object): String = {
    "Unsupported SQL Type " + md.getColumnTypeName(col) +
    " (" + sqlT +
    "); for (column, value): (" + label + ", " + o + ")"
  }

  def create(id: RefID, header: Header, hints: TableHints, schemaHints: Hints): G[RefID] = {
    val sq = SqlCreate(id, header, hints, schemaHints).emitSql
    executeUpdate(sq).map(_ => id).liftKleisli
  }

  /** The operational bracket for performing `act` efficiently. */
  private def transactionBracket[A](act: DB[A]): DB[A] =
    if (emitter.isTransactional) DB.transaction(act)
    else act

  private def populateSchemaImpl(schema: Map[TableName,(RefID,Header)], batchSize: Int = 5000): DB[Iteratee[IO, (TableName, Record), Unit]] = {
    val keysList: Map[TableName,List[ColumnName]] =
      schema.mapValues(v => v._2.keys.toList).toMap // commit to an order of columns

    // 1-based indexing because prepared statement has 1-based indexing for setting variables
    val keys: Map[TableName, Map[ColumnName,Int]] =
      keysList.mapValues(ks => ks.zip(Stream.from(1)).toMap).toMap

    def indexOf(cols: Map[ColumnName,Int], columnName: ColumnName) = {
      cols.getOrElse(columnName, sys.error("column not mentioned in header"))
    }

    import scala.collection.mutable.OpenHashMap
    val preppedStmts = (cx: Connection) => keysList.toList.map(tks =>
        (tks._1, prepStmt(
          raw("INSERT INTO ") |+| emitter.emitTableName(schema(tks._1)._1) |+| " ( " |+|
            tks._2.map(emitter.emitColumnName).rawMkString(", ") |+|
          " ) VALUES ( " |+| List.fill(tks._2.size)("?").mkString(", ") |+|
          " )")(cx)
        )).toMap
    preppedStmts.flatMap{stmts => cx =>
      lazy val it: Iteratee[IO, (TableName, Record), Unit] = Iteratee[IO, (TableName, Record), Unit]{
        val counts = new OpenHashMap[TableName,Int]
        counts ++= stmts.mapValues(v => 0)
        ContM[IO, (TableName, Record), Unit]((e: Input[(TableName, Record)]) => e.apply(
          empty = it,
          el = tt => {
            val stmt = stmts.getOrElse(tt._1, sys.error("reference to table not in schema"))
            val hdr = keys.getOrElse(tt._1, sys.error("reference to table not in schema"))
            def set(k: Int, v: PrimExpr): Unit = v match {
              case IntExpr(_, l) => stmt.setInt(k, l)
              case DoubleExpr(_, d) =>
                            if (!d.isInfinity && !d.isNaN) stmt.setDouble(k, d)
              case DateExpr(_, d) => emitter.emitDateStatement(stmt, k, d)
              case StringExpr(_, s) =>
                val l = v.typ.asInstanceOf[StringT].len
                stmt.setString(k, if (l == 0) s else s.substring(0,l))
              case BooleanExpr(_, b) => stmt.setBoolean(k, b)
              case ByteExpr(_, b) => stmt.setByte(k, b)
              case LongExpr(_, l) => stmt.setLong(k, l)
              case ShortExpr(_, s) => stmt.setShort(k, s)
              case UuidExpr(_, u) => stmt.setString(k, u.toString)
              case TimestampExpr(_, t) => emitter.emitTimestampStatement(stmt, k, t)
              case NullExpr(t) => stmt.setNull(k, emitter.sqlTypeId(t))
            }
            tt._2.foreach { case (k, v) => set(indexOf(hdr, k), v) }
            stmt.addBatch()
            val count2 = counts(tt._1) + 1
            if (count2 == batchSize) {
              try transactionBracket(_ => stmt.executeBatch())(cx)
              catch { case e: Exception => throw new Exception(
                "failed sending batch to table: " + tt._1, e) }
              counts(tt._1) = 0
            }
            else
              counts(tt._1) = count2
            it
          },
          eof = {
            // flush the buffered inserts
            stmts.foreach {kv =>
              if (counts(kv._1) != 0) {
                try transactionBracket(_ => kv._2.executeBatch())(cx)
                catch { case e: Exception => throw new Exception(
                  "failed flushing final rows to table: " + kv._1, e) }
              }
              else ()
            }
            Iteratee[IO, (TableName, Record), Unit](DoneM((), EOF[(TableName, Record)]).pure[IO])
          }
        )).pure[IO]
      }
      it
    }
  }

  def constraints[A](tables: List[TableName]): DB[(IO[Unit], IO[Unit])] =
    (cx: Connection) =>
      (emitter.setConstraints(false, tables).traverse_(executeUpdate).apply(cx).pure[IO],
       emitter.setConstraints(true, tables).traverse_(executeUpdate).apply(cx).pure[IO])

  def schemaPopulator(schema: Map[TableName,(RefID,Header)], s: Source, batchSize: Int = 5000): DB[(IO[Unit], Iteratee[IO, (TableName, Record), Unit], IO[Unit])] =
    for {
      prepost <- constraints(schema.values.map(x => TableName(x._1.toString)).toList)
      (pre, post) = prepost
      iv <- populateSchemaImpl(schema, batchSize)
    } yield (pre, iv, post)

  def createIndices(schema: Map[TableName, (RefID, Header)], hints: Hints): G[Unit] = {
      val tables = hints.tables
      tables.foreach { case (tableName, tableHints) =>
        tableHints.indices.zipWithIndex foreach { case ((columnGroup, isCandidateKey),i) =>
          emitter.emitCreateIndex(tableName, tableHints, tableName.toString+"_index"+i, columnGroup, isCandidateKey).
          foreach(executeUpdate)
        }}}.pure[G]
}

object SqlBackend {
  def apply(emitter: SqlEmitter) = {
    implicit val e = emitter
    new SqlBackend
  }
}
