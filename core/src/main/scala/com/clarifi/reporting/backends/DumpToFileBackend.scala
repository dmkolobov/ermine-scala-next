package com.clarifi.reporting.backends

import com.clarifi.reporting.{ Header, TableName, Source }
import com.clarifi.reporting.sql.{ SqlEmitter }
import com.clarifi.reporting.Reporting._
import org.apache.log4j.Logger

import scalaz.Kleisli
import Kleisli.kleisliApplicative
import scalaz.syntax.applicative._
import scalaz.std.function._

class DumpToFileBackend(outputFile:String="tables.bin") extends SqlBackend()(SqlEmitter.msSqlEmitter) {
  val Log = Logger.getLogger(this.getClass)
  implicit val kp: Applicative[[x] =>> Kleisli[DB, Source, x]] = kleisliApplicative[DB, Source]
  override def populateSchema(schema: Map[TableName,(RefID,Header)], records: DataSet, batchSize: Int = 5000): G[Unit] = {
      Log.info("writing data to " + outputFile)
      f0.Sinks.toFile(outputFile).using(BulkLoad.schemaRows.bind(_)((
        (BulkLoad.Metadata("PortfolioAnalytics"), schema.map { case (tn, (_, h)) => tn.name -> h } toMap),
        records.map{case (x, y) => (x.name, y)}
        )))
      Log.info("done writing " + outputFile)
  }.point[[x] =>> Kleisli[DB, Source, x]]
}
