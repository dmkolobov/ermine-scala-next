package com.clarifi.reporting.flatteners

import java.util.Date
import java.util.UUID

import collection.immutable.SortedSet

import scalaz._
import scalaz.Scalaz._
import Leibniz.===

import com.clarifi.reporting.PrimType._
import com.clarifi.reporting.{ PrimType, ColumnName, Record, Header, TableName }
import com.clarifi.reporting.Reporting._
import com.clarifi.reporting.{Hints,TableHints}

/** Base flattener trait, purely for code reuse - see `RowFlattener` and `TableFlattener`. */
abstract class Flattener[T[_,-_] , S, -A] {
  def contramap[B](f: B => A) : T[S,B]
  def localState(s: S): T[Unit,A]
  def schema: Map[TableName, Header]
  def hints: Hints
  def mapRootColumnNames(f: ColumnName => ColumnName): T[S, A]
  def lens[R](l: Lens[R,S]): T[R, A]
  def trivial[R](implicit witness: Unit === S): T[R, A] = {
    val lwitness: Lens[R,Unit] === Lens[R,S] =
      Leibniz.lift[⊥, ⊥, ⊤, ⊤, [x] =>> Lens[R,x], Unit, S](witness)
    lens(Leibniz.subst(Lens.trivialLens[R])(lwitness))
  }
  def local(implicit Z : Monoid[S]) = localState(zeroState)
  def zeroState(implicit Z : Monoid[S]): S = mzero[S]
  def mapNames(f: TableName => TableName): T[S, A]
}

object Flatteners {
  /** Create a Flatten accepting records matching a Header to be put in a named table. */
  // Combinators
  def raw[S](h: Header, th : TableHints = TableHints.empty): RowFlattener[S, Record] = {
    type M[X] = State[S,X]
    RowFlattener(
      a => State[S, (Record, DataSetS[S])](
        s => (s, (a, StreamT.empty[M,(TableName,Record)]))
      ),
      h,
      Map.empty,
      th,
      Hints.empty
    )
  }

  def defaultLen = 80

  // RowFlattener for non-nullable primitives -
  //   these RowFlatteners do not have their columns added to the PK of the table
  def byte(colName: ColumnName) = primitive(primByte)(colName)
  def short(colName: ColumnName) = primitive(primShort)(colName)
  def int(colName: ColumnName) = primitive(primInt)(colName)
  def long(colName: ColumnName) = primitive(primLong)(colName)
  def boolean(colName: ColumnName) = primitive(primBoolean)(colName)
  def date(colName: ColumnName) = primitive(primDate)(colName)
  def timestamp(colName: ColumnName) = primitive(primTimestamp)(colName)
  def double(colName: ColumnName) = primitive(primDouble)(colName)
  def string(colName: ColumnName, len: Int = defaultLen) = primitive(primString(len))(colName)
  def uuid(colName: ColumnName) = primitive(primUuid)(colName)

  // RowFlatteners for nullable primitives - None gets mapped to Null in the DB
  //   these RowFlatteners do not have their columns added to the PK of the table
  def byteOption(colName: ColumnName) = primitive(primOption(primByte))(colName)
  def shortOption(colName: ColumnName) = primitive(primOption(primShort))(colName)
  def intOption(colName: ColumnName) = primitive(primOption(primInt))(colName)
  def longOption(colName: ColumnName) = primitive(primOption(primLong))(colName)
  def booleanOption(colName: ColumnName) = primitive(primOption(primBoolean))(colName)
  def dateOption(colName: ColumnName) = primitive(primOption(primDate))(colName)
  def timestampOption(colName: ColumnName) = primitive(primOption(primTimestamp))(colName)
  def doubleOption(colName: ColumnName) = primitive(primOption(primDouble))(colName)
  def stringOption(colName: ColumnName, len: Int = defaultLen) = primitive(primOption(primString(len)))(colName)
  def uuidOption(colName: ColumnName) = primitive(primOption(primUuid))(colName)

  // RowFlatteners for non-nullable primitives -
  //   these RowFlatteners get their columns added to the PK of the table
  def byteKey(colName: ColumnName) = primitiveKey(primByte)(colName)
  def shortKey(colName: ColumnName) = primitiveKey(primShort)(colName)
  def intKey(colName: ColumnName) = primitiveKey(primInt)(colName)
  def longKey(colName: ColumnName) = primitiveKey(primLong)(colName)
  def booleanKey(colName: ColumnName) = primitiveKey(primBoolean)(colName)
  def dateKey(colName: ColumnName) = primitiveKey(primDate)(colName)
  def timestampKey(colName: ColumnName) = primitiveKey(primTimestamp)(colName)
  def stringKey(colName: ColumnName, len: Int = defaultLen) = primitiveKey(primString(len))(colName)
  def uuidKey(colName: ColumnName) = primitiveKey(primUuid)(colName)

  def primitive[A](pt: PrimType[A])(colName: ColumnName): RowFlattener[Unit,A] =
    raw(
      Map(colName -> pt.typ),
      TableHints.empty.withPK(SortedSet[ColumnName]())
    ).contramap((a:A) => Map(colName -> pt.expr(a)))

  def primitiveKey[A](pt: PrimType[A])(colName: ColumnName): RowFlattener[Unit,A] =
    raw(
      Map(colName -> pt.typ),
      TableHints.empty.withPK(SortedSet(colName))
    ).contramap((a:A) => Map(colName -> pt.expr(a)))

  def bias3Fn[A,B,C](t: (A,B,C)): ((A,B),C) = ((t._1, t._2), t._3)
  def bias3rFn[A,B,C](t: (A,B,C)): (A,(B,C)) = (t._1, (t._2, t._3))
  def bias4Fn[A,B,C,D](t: (A,B,C,D)): (((A,B),C),D) = (((t._1, t._2), t._3), t._4)
  def bias5Fn[A,B,C,D,E](t: (A,B,C,D,E)): ((((A,B),C),D),E) = ((((t._1, t._2), t._3), t._4), t._5)
  def bias6Fn[A,B,C,D,E,F](t: (A,B,C,D,E,F)): (((((A,B),C),D),E),F) = (((((t._1,t._2),t._3),t._4),t._5),t._6)
  def unbias3Fn[A,B,C](t: ((A,B),C)): (A,B,C) = (t._1._1, t._1._2, t._2)
  def unbias4Fn[A,B,C,D](t: (((A,B),C),D)): (A,B,C,D) = t match { case (((a,b),c),d) => (a,b,c,d) }
  def unbias5Fn[A,B,C,D,E](t: ((((A,B),C),D),E)): (A,B,C,D,E) = t match { case ((((a,b),c),d),e) => (a,b,c,d,e) }

  def unbias6[A,B,C,D,E,F,S](r: TableFlattener[S,(((((A,B),C),D),E),F)]): TableFlattener[S,(A,B,C,D,E,F)] = r.contramap(bias6Fn)
  def unbias5[A,B,C,D,E,S](r: TableFlattener[S,((((A,B),C),D),E)]): TableFlattener[S,(A,B,C,D,E)] = r.contramap(bias5Fn)
  def unbias4[A,B,C,D,S](r: TableFlattener[S,(((A,B),C),D)]): TableFlattener[S,(A,B,C,D)] = r.contramap(bias4Fn)
  def unbias3[A,B,C,S](r: TableFlattener[S,((A,B),C)]): TableFlattener[S,(A,B,C)] = r.contramap(bias3Fn)

  object Implicits {
  // these will let us use flatteners with unit state as flatteners for any other kind of state
    implicit def trivialTableFlattener[R,A](f : TableFlattener[Unit, A]): TableFlattener[R, A] = f.lens(Lens.trivialLens[R])
    implicit def trivialRowFlattener[R,A](f : RowFlattener[Unit, A]): RowFlattener[R, A] = f.lens(Lens.trivialLens[R])
    implicit def headS[T,A](f: RowFlattener[ConsIndexee[T,Unit],A]): RowFlattener[Indexee[T],A] = f.headS

    //path * map * list *
    //trait ContramapThatShit[F[_],G[_]] { def apply[A](
  }
}

