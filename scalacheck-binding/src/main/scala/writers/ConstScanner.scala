package com.clarifi.reporting
package writers

import scalaz._
import scalaz.syntax.std.all.ToTuple2Ops
import scalaz.std.list._
import scalaz.syntax.monad._

import org.scalacheck.{Arbitrary, Gen, Prop, Properties}
import Arbitrary.arbitrary
import Prop.{AnyOperators, secure}

import com.clarifi.reporting.relational._

import com.clarifi.machines._

import PrimT.IntT

/** A scanner that always yields the same records. */
class ConstScanner[G[_]: Monad: Distributive](data: Traversable[Record])
      extends Scanner[G] {
  def scanRel[A:Monoid](r: Relation[Nothing, Nothing], f: Process[Record, A],
                        order: List[(String, SortOrder)]): G[A] =
    f.cap(com.clarifi.machines.Source(data.toList)).foldMap(x => x).pure[G]
  def scanMem[A:Monoid](r: Mem[Nothing, Nothing], f: Process[Record, A],
                        order: List[(String, SortOrder)]): G[A] =
    f.cap(com.clarifi.machines.Source(data.toList)).foldMap(x => x).pure[G]
  def scanExt[A:Monoid](r: Ext[Nothing, Nothing], f: Process[Record, A],
                        order: List[(String, SortOrder)]): G[A] =
    f.cap(com.clarifi.machines.Source(data.toList)).foldMap(x => x).pure[G]
}

object ConstScanner {
  /** Traversable scalaz6-iteratee-enumerator. */
  implicit val travEnum: Enumerator[Traversable] = new Enumerator[Traversable] {
    def apply[E, A](f: Traversable[E], i: IterV[E, A]) =
      f.foldLeft(i){(i, elt) => i feed IterV.El(elt)} feed IterV.EOF.apply
  }
}
