package com.clarifi.reporting.backends

import org.apache.log4j.Logger
import com.clarifi.reporting.{ Header, TableName, Source }
import com.clarifi.reporting.sql.{ SqlEmitter }
import com.clarifi.reporting.Reporting._
import java.sql.Connection

import scalaz._
import Kleisli._

class DebuggingBackend extends SqlBackend()(SqlEmitter.msSqlEmitter) {
  val Log = Logger.getLogger(this.getClass)
  override def populateSchema(schema: Map[TableName,(RefID,Header)], records: DataSet, batchSize: Int): G[Unit] =
    kleisli[DB, Source, Unit]((s: Source) => (conn: Connection) => {
      Log.info(schema)
      records.foreach(t => Log.info(t))
    })
}

