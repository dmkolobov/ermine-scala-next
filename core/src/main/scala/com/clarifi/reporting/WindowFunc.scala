package com.clarifi.reporting

import scalaz.syntax.applicative._
import scalaz.syntax.monoid._
import scalaz.syntax.validation._
import scalaz.{Applicative, Monad, Monoid, ValidationNel}

abstract class WindowFunc extends TraversableColumns[WindowFunc] {
  def traverseColumns[F[_] : Applicative](f: ColumnName => F[ColumnName]): F[WindowFunc] =
    this match {
      case Rank => (Rank: WindowFunc).pure[F]
      case DenseRank => (DenseRank: WindowFunc).pure[F]
      case RowNumber => (RowNumber: WindowFunc).pure[F]
      case NTile(op) => op.traverseColumns(f).map(NTile)
    }

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
    this match {
      case Rank => mzero[Z]
      case DenseRank => mzero[Z]
      case RowNumber => mzero[Z]
      case NTile(op) => op.typedColumnFoldMap(f)
    }

  def guessType: ValidationNel[String, PrimT] = this match {
    case Rank => PrimT.IntT(false).success
    case DenseRank => PrimT.IntT(false).success
    case RowNumber => PrimT.IntT(false).success
    case NTile(op) => PrimT.IntT(false).success
  }

  def simplify(t: Map[ColumnName, Op]): WindowFunc = this match {
    case Rank => Rank
    case DenseRank => DenseRank
    case RowNumber => RowNumber
    case NTile(op) => NTile(op simplify t)
  }

  def postReplaceOp[F[_] : Monad](f: Op => F[Op]): F[WindowFunc] = this match {
    case Rank => (Rank: WindowFunc).pure[F]
    case DenseRank => (DenseRank: WindowFunc).pure[F]
    case RowNumber => (RowNumber: WindowFunc).pure[F]
    case NTile(op) => op.postReplace(f).map(NTile)
  }

}


case class AggWindowFunc(agg: AggFunc) extends WindowFunc {
  override def traverseColumns[F[_] : Applicative](f: ColumnName => F[ColumnName]): F[WindowFunc] =
    agg.traverseColumns(f).map(AggWindowFunc)

  override def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
    agg.typedColumnFoldMap(f)

  override def guessType: ValidationNel[String, PrimT] =
    agg.guessType

  override def simplify(t: Map[ColumnName, Op]): WindowFunc =
    AggWindowFunc(agg simplify t)

  override def postReplaceOp[F[_] : Monad](f: Op => F[Op]): F[WindowFunc] =
    agg.postReplaceOp(f).map(AggWindowFunc)
}

case object Rank extends WindowFunc

case object DenseRank extends WindowFunc

case object RowNumber extends WindowFunc

case class NTile(op: Op) extends WindowFunc
