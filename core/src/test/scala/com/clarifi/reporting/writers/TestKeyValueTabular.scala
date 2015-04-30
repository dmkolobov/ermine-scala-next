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

object TestKeyValueTabular extends Properties("tables w/dynamic schema") {
  /*val tripleBasis = aaPlusBb fold (Combine(aabbTable, _, _))
  val presentB: Set[ColumnName] = Set("colBB")
  val presentC = Presentation unit (NonEmptyList("colCC" -> IntT()))
  def withAllForward(p: Presentation)(m: Tuple) =
    (p, SortStrategy allForward p.columnReferences.toSeq)

  property("no keys, data irrelevant") = secure {
    implicit val scan = new ConstScanner[Id](Stream continually Map.empty)
    def valPres(m: Tuple) = {assert(m isEmpty)
                             withAllForward(presentC)(m)}
    dynamicSchema(tripleBasis, Set("colAA", "colBB"),
                  Set.empty, dsort(), valPres) match {
      case (`tripleBasis`, Legend(Seq((`presentC`, _, _)))) => true: Prop
    }
  }*/

  /*property("0 key values") = secure {
    implicit val scan = new ConstScanner[Id, Tag](Seq.empty)
    val colaa: Set[ColumnName] = Set("colAA")
    dynamicSchema(tripleBasis, colaa,
                  presentB, dsort(presentB.toSeq:_*), withAllForward(presentC)) match {
      case (R(_, RI.Project(`tripleBasis`, `colaa`)),
            Legend(Seq())) => true: Prop
    }
  }

  property("1 key value") = secure {
    val thekey: Tuple = Map("colBB" -> IntExpr(false, 33))
    implicit val scan = new ConstScanner[Id, Tag](Seq(thekey))
    dynamicSchema(tripleBasis, Set("colAA"), presentB,
                  dsort(presentB.toSeq:_*), withAllForward(presentC)) match {
      case (R(_, RI.Project(R(_, RI.Join(R(_, RI.Rename(`tripleBasis`, "colCC", gencc)),
                                         R(_, RI.Literal(nelTheKey)))),
                            elim)),
            Legend(Seq((genPres, SortStrategy(Seq((gencc2, SortDirection.Forward))),
                        `thekey`)))) =>
        ((elim ?= Set("colAA", gencc))
         && (genPres.columnReferences ?= Set(gencc))
         && (gencc ?= gencc2)
         && (nelTheKey ?= NonEmptyList(thekey)))
    }
  }

  property("2 key values") = secure {
    val key1 = Map("colBB" -> IntExpr(false, 33))
    val key2 = Map("colBB" -> IntExpr(false, 66))
    implicit val scan = new ConstScanner[Id, Tag](Seq(key1, key2))
    var capturedKeys = Vector.empty[Tuple]
    (dynamicSchema(tripleBasis, Set("colAA"),
                   presentB, dsort(presentB.toSeq:_*),
                   {(m: Tuple) =>
                     capturedKeys :+= m
                     (presentC, SortStrategy(presentC.columnReferences.toSeq
                                             map (_ -> SortDirection.Reverse)))
                   }) match {
      case (r@R(_, RI.Join(
        R(_, RI.Project(R(_, RI.Join(R(_, RI.Rename(`tripleBasis`, "colCC", gencc1)),
                                     R(_, RI.Literal(nelKey1)))),
                        elim1)),
        R(_, RI.Project(R(_, RI.Join(R(_, RI.Rename(`tripleBasis`, "colCC", gencc2)),
                                     R(_, RI.Literal(nelKey2)))),
                        elim2)))),
            Legend(Seq((genPres1, SortStrategy(Seq((gencc1p, SortDirection.Reverse))),
                        `key1`),
                       (genPres2, SortStrategy(Seq((gencc2p, SortDirection.Reverse))),
                        `key2`)))) =>
        ((elim1 ?= Set("colAA", gencc1))
         && (elim2 ?= Set("colAA", gencc2))
         && (genPres1.columnReferences ?= Set(gencc1))
         && (genPres2.columnReferences ?= Set(gencc2))
         && (gencc1 ?= gencc1p)
         && (gencc2 ?= gencc2p)
         && (nelKey1 ?= NonEmptyList(key1))
         && (nelKey2 ?= NonEmptyList(key2))
         && (gencc1 != gencc2)
         && (header(r) ?= Map("colAA" -> IntT(), gencc1 -> IntT(), gencc2 -> IntT())))
    }) && (capturedKeys ?= Vector(key1, key2))
  }*/
}
