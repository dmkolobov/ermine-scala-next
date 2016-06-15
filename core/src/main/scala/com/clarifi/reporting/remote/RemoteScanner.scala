package com.clarifi.reporting
package remote

import Format._
import com.clarifi.reporting.relational._

import com.clarifi.machines._

import scalaz._
import scalaz.Scalaz._
import scalaz.effect._

import f0.{Source => _, _}
import Writers._

import org.apache.log4j.Logger

object RemoteScanner {
  val IO = implicitly[Monad[IO]]
  implicit val Dist : Distributive[IO] = new Distributive[IO] {
    def distributeImpl[G[_],A,B](fa: G[A])(f: A => IO[B])(implicit G : Functor[G]): IO[G[B]] =
      IO.pure(G.map(fa)(x => f(x).unsafePerformIO))
    def map[A,B](fa : IO[A])(f : A => B) = fa.map(f)
  }
}

/** Accepts an impure function which expects f0-serialized (Ext, sortOrder)
  * pairs, and returns a stream of f0-serialized records. See `RelationFormat` for
  * the definitions of these formats.
  */
import RemoteScanner.Dist

class RemoteScanner(makeRequest: Array[Byte] => Array[Byte]) extends Scanner[IO] {
  override implicit val M = RemoteScanner.IO
  private val Log: Logger = Logger.getLogger(this.getClass.getName)

  def scanExt[A](r: Ext[Nothing, Nothing],
                 f: Process[Record, A],
                 order: List[(String, SortOrder)])(implicit A: Monoid[A]) = {
    val w = tuple2W(extW[Nothing, NothingF, Nothing, NothingF](nothingW, nothingW), orderByW)
    IO(makeRequest(w.toByteArray(r -> order))) map {
      bs => rowsR(bs).fold(sys.error, rs => f.cap(com.clarifi.machines.Source(rs)).foldMap(x => x))
    }
  }

  def scanRel[A](r: Relation[Nothing, Nothing],
                 f: Process[Record, A],
                 order: List[(String, SortOrder)])(implicit A: Monoid[A]) =
    scanExt(ExtRel(r, ""), f, order) // TODO dolio : Handle the "db" in some way

  def scanMem[A](r: Mem[Nothing, Nothing],
                 f: Process[Record, A],
                 order: List[(String, SortOrder)])(implicit A: Monoid[A]) =
    scanExt(ExtMem(r), f, order)
}
