package com.clarifi.reporting
package remote

import relational._

import com.clarifi.machines._

import backends.DB

import f0._
import Readers._
import Format._

import scala.util.control.NonFatal
import scalaz.std.vector._

import org.apache.log4j.Logger

class BackendServer[F[_]](B: Scanner[F])(implicit R: Run[F]) {
  private val Log: Logger = Logger.getLogger(this.getClass.getName)

  def apply(bytes: Array[Byte]): Array[Byte] = try {
    val r = tuple2R(extR(nothingR, nothingR), orderByR)
    val (rel, ord) = r(bytes)
    Log.info("received data request:\n" +
    "query: " + rel + "\n" +
    "order: " + ord.mkString(", "))
    val results: Vector[Record] = R.run(B.scanExt(rel, Process.grouping((_, _) => true), ord))
    if (Log.isDebugEnabled) Log.debug("returned rows:\n" + results.mkString("\n"))
    val bs = rowsW.toByteArray(Right(results))
    Log.info("response bytes: " + bs.length)
    bs
  } catch { case NonFatal(e) => rowsW.toByteArray(Left(e)) }
}

object BackendServer {
  import backends._
  val testRemoteBackendServer = new BackendServer[DB](Scanners.MicrosoftSQLServer(SMEnv.dummySmenv))(Runners.cloudDB)
}
