package com.clarifi.reporting
package backends

import scalaz.{Source => _, _}
//TODO: remove Scalaz._ and import single things
import Scalaz._
//import scalaz.syntax.monad._
import scalaz.effect.IO
import IO.{apply => _, _}
//import std.function._

import org.scalacheck._
import Prop._

import Reporting._
import flatteners.{Flatteners => F, TableFlattener}
import com.clarifi.reporting.util.StreamTUtils

import sql.SqlEmitterGens.stdGen

object TestPersistence extends org.scalacheck.Properties("Persistence via backends") {
  val longIntPairLists =
    Gen.choose(10000, 25000) flatMap (Gen.listOfN(_, stdGen[(Int, Int)]))

  trait Large
  type LargeList[A] = List[A] @@ Large

  implicit val arbLongIntPairList: Arbitrary[LargeList[(Int, Int)]] =
    Arbitrary(longIntPairLists map (Tag.subst[List[(Int, Int)], Id, Large]))

  type UnitR[+A] = Unit => A

  class FakePersister extends Backend[UnitR] {
    var ticker = 0                      // wow! a side effect!

    private def tick: IO[Unit] = (ticker += 1).pure[IO]

    def create(id: RefID, header: Header, hints: TableHints,
               schemaHints: Hints): G[RefID] =
      id.pure[G]

    private val sink: IO[IterVM[IO, (TableName, Record), Unit]] =
      IterV.ContM[IO, (TableName, Record), Unit]{ine =>
        ine(empty = Iteratee(sink),
            el = {_ => Iteratee(tick *> sink)},
            eof = Iteratee(IterV.DoneM((), ine).pure[IO]))
      }.pure[IO]

    def schemaPopulator(schema: Map[TableName,(RefID,Header)], s: Source,
                        batchSize: Int = 5000): UnitR[(IO[Unit], Iteratee[IO, (TableName, Record), Unit], IO[Unit])] =
      (().pure[IO],
       Iteratee(sink),
       ().pure[IO]).pure[UnitR]

    def createIndices(schema: Map[TableName, (RefID, Header)], hints: Hints): G[Unit] =
      ().pure[G]

    def newRefID: G[RefID] = RefID("abc").pure[G]

    def destroy(r: RefID): G[Unit] = ().pure[G]
  }

  val fIntPairs = (F.int("a") ++ F.int("b")) iterable TableName("sometbl")

  property("can flatten large datasets") = forAll {(xs: LargeList[(Int, Int)]) =>
    val persist = new FakePersister
    val writeAction = (TableFlattener.persistExisting
                       (persist, fIntPairs.local)(xs)(Source()))
    val before = (persist.ticker ?= 0) :| "nothing written before monadic action"
    writeAction(())
    before && ((persist.ticker ?= xs.size) :| "all written after action")
  }
}
