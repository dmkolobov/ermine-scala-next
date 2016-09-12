package com.clarifi.reporting
package relational

import com.clarifi.reporting.{ SortOrder }

import com.clarifi.machines._

import scalaz._
import Scalaz._

abstract class Scanner[G[_]](implicit G: Monad[G]) { self =>

  /** Scan a relation r, iterating over its records by f in the order specified.
    * The order is given by a list of pairs where the first element specifies
    * the column name and the second element specifies the order.
    */
  def scanRel[A: Monoid](r: Relation[Nothing, Nothing],
                         f: Process[Record, A],
                         order: List[(String, SortOrder)] = List()): G[A]

  def scanMem[A: Monoid](r: Mem[Nothing, Nothing],
                         f: Process[Record, A],
                         order: List[(String, SortOrder)] = List()): G[A]

  def scanExt[A: Monoid](r: Ext[Nothing, Nothing],
                         f: Process[Record, A],
                         order: List[(String, SortOrder)] = List()): G[A]

  def dumpRel(r: Relation[Nothing, Nothing],
              order: List[(String, SortOrder)] = List()): String =
    sys.error("Don't know how to dump a relation.")

  def dumpMem(m: Mem[Nothing, Nothing],
              order: List[(String, SortOrder)] = List()): String =
    sys.error("Don't know how to dump a mem.")

  def dumpExt(m: Ext[Nothing, Nothing],
              order: List[(String, SortOrder)] = List()): String = m match {
      case ExtRel(r, db) => dumpRel(r, order)
      case ExtMem(mem) => dumpMem(mem, order)
      case ExtSM(sm) => sys.error("Don't know how to dump a SM.")
    }

  def dumpClosed(c: ClosedExt,
                 order: List[(String, SortOrder)] = List()): String = dumpExt(c.out, order)

  def collect(r: Ext[Nothing, Nothing]): G[Vector[Record]] =
    scanExt(r, Process.wrapping[Record], List())

  val M = G
}
