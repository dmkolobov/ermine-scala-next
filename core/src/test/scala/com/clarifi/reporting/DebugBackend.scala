package com.clarifi.reporting

import java.sql._

import scalaparsers._
import scalaz.State
import scala.collection.mutable.ListBuffer
import scala.collection.mutable.HashSet

import com.clarifi.reporting.relational._
import com.clarifi.reporting.backends._
import com.clarifi.reporting.sql.SqlEmitter._

import SMEnv._

trait DebugBackend[DB[_]] {
  def flush: DB[Unit]

  /**
   * Returns the query plan of the given relation.  The output is formatted
   * into a single String, which may contain line breaks depending on the nature
   * of the query plan.
   */
  def explain(r: ClosedRel): DB[String]
}

object DebugBackend {
  implicit val memoLookup = new HashSet[TableName]()
  val mySqlDebug = new DebugBackend[DB] {
    def flush: DB[Unit] = (c: Connection) => {
      c.prepareStatement("FLUSH TABLES").executeUpdate
      ()
    }

    def explain(r: ClosedRel): DB[String] = (c: Connection) => {
      val mySqlBackend = Scanners.MySQL(dummySmenv)
      import mySqlBackend.SqlPrg
      implicit val sup = Supply.create
      implicit val scopeBuilder = List[() => String]()
      val SqlPrg(p, _, dq, _, _) = mySqlBackend.compileRel(r.out, (x:Nothing) => x, (x:Nothing) => x)

      if (p.isEmpty) {
        val query = "EXPLAIN EXTENDED " + dq.q(true)._2.emitSql(mySqlEmitter).run
        val resultSet = c.prepareStatement(query).executeQuery
        printRows(resultSet) // only one row returned
      } else "Tide comes in, tide goes out. You can't explain that."
    }
  }

  val msSqlDebug = new DebugBackend[DB] {
    def flush: DB[Unit] = (c: Connection) => {
      c.prepareStatement("DBCC DROPCLEANBUFFERS").executeUpdate
      c.prepareStatement("DBCC FREEPROCCACHE").executeUpdate
    }

    def explain(r: ClosedRel): DB[String] = (c: Connection) => {
      "[Can't explain in SQL Server]"
    }
  }


  val verticaDebug = new DebugBackend[DB] {
    def flush: DB[Unit] = (c: Connection) => {
      // TODO - run a bunch of stuff
      ()
    }

    def explain(r: ClosedRel): DB[String] = (c: Connection) => {
      val verticaBackend = Scanners.Vertica(dummySmenv)
      import verticaBackend.SqlPrg
      implicit val sup = Supply.create
      implicit val scopeBuilder = List[() => String]()
      val SqlPrg(p, _, dq, _, _) = verticaBackend.compileRel(r.out, (x:Nothing) => x, (x:Nothing) => x)

      if (p.isEmpty) {
        val query = "EXPLAIN " + dq.q(true)._2.emitSql(verticaSqlEmitter)
        val resultSet = c.prepareStatement(query).executeQuery
        printParagraph(resultSet)
      } else "Tide comes in, tide goes out. You can't explain that."
    }
  }

  /**
   * Converts a result set to a human-readable string with one row per line, with the form:
   * column1=val2, column2=val2, ... columnN=valN
   */
  def printRows(resultSet: ResultSet): String = {
    val metaData = resultSet.getMetaData
    val numCols = metaData.getColumnCount
    val lines = new ListBuffer[String]

    while (resultSet.next) {
      val buffer = new ListBuffer[String]
      for (i <- 1 until numCols+1) {
        buffer += metaData.getColumnLabel(i) + "=" + getColumnValue(resultSet, metaData, i)
      }
      lines += buffer.mkString("; ")
    }

    lines.mkString("\n")
  }

  /**
   * Takes a result set with a single column of type VARCHAR, and converts it into a String
   */
  def printParagraph(resultSet: ResultSet): String = {
    val lines = new ListBuffer[String]
    while (resultSet.next) {
      lines += resultSet.getString(1)
    }
    lines.mkString("\n")
  }

  def getColumnValue(resultSet: ResultSet, metaData: ResultSetMetaData, column: Int): String = {
    import java.sql.Types._
    val columnType = metaData.getColumnType(column)
    columnType match {
      case BIGINT => resultSet.getLong(column).toString
      case BIT => resultSet.getInt(column).toString
      case BOOLEAN => resultSet.getBoolean(column).toString
      case DATE => resultSet.getDate(column).toString
      case DECIMAL => resultSet.getDouble(column).toString
      case DOUBLE => resultSet.getDouble(column).toString
      case FLOAT => resultSet.getFloat(column).toString
      case INTEGER => resultSet.getInt(column).toString
      case VARCHAR => resultSet.getString(column)
      case _ => "[unknown type: + " + columnType + "]"
    }
  }
}
