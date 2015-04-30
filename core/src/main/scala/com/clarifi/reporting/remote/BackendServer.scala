package com.clarifi.reporting
package remote

import relational._
import SMEnv._

import com.clarifi.machines._

import backends.DB
import Reporting._

import f0._
import Readers._
import Writers._
import Format._

import scalaz._
import Scalaz._
import IterV._
import scalaz.std.vector._

import org.apache.log4j.Logger

class BackendServer[F[_]](B: Scanner[F])(implicit R: Run[F]) {
  private val Log: Logger = Logger.getLogger(this.getClass.getName)

  def apply(bytes: Array[Byte]): Array[Byte] = try {
    val r = tuple2R(extR[Nothing, Nothing](nothingR.erase, nothingR.erase), orderByR)
    val (rel, ord) = r(bytes)
    Log.info("received data request:\n" +
    "query: " + rel + "\n" +
    "order: " + ord.mkString(", "))
    val results: Vector[Record] = R.run(B.scanExt(rel, Process.grouping((_, _) => true), ord))
    if (Log.isDebugEnabled) Log.debug("returned rows:\n" + results.mkString("\n"))
    val bs = rowsW.toByteArray(Right(results))
    Log.info("response bytes: " + bs.length)
    bs
  } catch { case e => rowsW.toByteArray(Left(e)) }
}

object BackendServer {
  import backends._
  val testRemoteBackendServer = new BackendServer[DB](Scanners.MicrosoftSQLServer(SMEnv.dummySmenv))(Runners.cloudDB)
}
