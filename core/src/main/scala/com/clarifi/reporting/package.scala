package com.clarifi

import scalaz.{Enumerator, IterV, Order, ValidationNel}
import scalaz.std.map._
import scalaz.std.string._

import java.math.BigInteger

package object reporting {
  /** Relational algebra. */
  type Projection = Map[Attribute, Op]

  /** A relational rowtype at the Scala level. */
  type Header = Map[ColumnName, PrimT]

  import java.util.UUID._
  def guid = randomUUID.toString.replaceAll("-", "")

  def sguid = new BigInteger(randomUUID.toString.replaceAll("-", ""), 16).toString(36)

  type ColumnName = String

  type Record = Map[ColumnName, PrimExpr]

  /** Force all the implicit threading here, so Ermine can get at it to
    * sort tuples, and we have an easy way to talk about it.
    *
    * @todo SMRC Optimize for common l.keySet == r.keySet case?
    */
  val RecordOrder: Order[Record] = implicitly
  //   implicitly[Order[IndexedSeq[(ColumnName, PrimExpr)]]].contramap((r:Record) =>
  //    r.toIndexedSeq.sortBy((p: (ColumnName, PrimExpr)) => p._1))

  def recordHeader(t: Record): Header = t.mapValues( _.typ )

  type TypeError = List[String]

  type TypeTag = ValidationNel[String, Header]

  type SourceWith[A] = (Set[Source], A)
  type Sourced = SourceWith[TypeTag]

  import IterV._
  implicit val StreamEnumerator: Enumerator[Stream] = new Enumerator[Stream] {
    @annotation.tailrec
    def apply[E, A](e: Stream[E], i: IterV[E, A]): IterV[E, A] = e match {
      case Stream() => i
      case x #:: xs => i match {
        case Done(_,_) => i
        case Cont(k) => apply(xs, k(El(x)))
      }
    }
  }
}
