package com.clarifi.reporting

import com.clarifi.machines.Source._
import com.clarifi.machines._
import scalaz.std.anyVal._
import scalaz.std.tuple._
import scalaz.syntax.applicative._
import scalaz.syntax.monoid._
import scalaz.syntax.validation._
import scalaz.{Applicative, Equal, Foldable, Monad, Monoid, Reducer, Show, ValidationNel}

sealed abstract class AggFunc extends TraversableColumns[AggFunc] {
  import AggFunc._

  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[AggFunc] =
    this match {
      case Count => (Count: AggFunc).pure[F]
      case Sum(op) => op.traverseColumns(f).map(Sum(_))
      case Avg(op) => op.traverseColumns(f).map(Avg(_))
      case Min(op) => op.traverseColumns(f).map(Min(_))
      case Max(op) => op.traverseColumns(f).map(Max(_))
      case Stddev(op) => op.traverseColumns(f).map(Stddev(_))
      case Variance(op) => op.traverseColumns(f).map(Variance(_))
      case WMean(op,wt) =>
        implicitly[Applicative[F]].apply2(
          op.traverseColumns(f),
          wt.traverseColumns(f)
        )(WMean(_,_))
      case WHMean(op,wt) =>
        implicitly[Applicative[F]].apply2(
          op.traverseColumns(f),
          wt.traverseColumns(f)
        )(WHMean(_,_))
    }

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
    this match {
      case Count => mzero[Z]
      case Sum(op) => op typedColumnFoldMap f
      case Avg(op) => op typedColumnFoldMap f
      case Min(op) => op typedColumnFoldMap f
      case Max(op) => op typedColumnFoldMap f
      case Stddev(op) => op typedColumnFoldMap f
      case Variance(op) => op typedColumnFoldMap f
      case WMean(op,wt) =>
        op.typedColumnFoldMap(f) |+|
        wt.typedColumnFoldMap(f)
      case WHMean(op,wt) =>
        op.typedColumnFoldMap(f) |+|
        wt.typedColumnFoldMap(f)
    }

  def guessType: ValidationNel[String, PrimT] = this match {
    case Count => PrimT.IntT(false).success
    case Sum(op) => op guessType
    case Avg(op) => op guessType
    case Min(op) => op guessType
    case Max(op) => op guessType
    case Stddev(op) => op guessType
    case Variance(op) => op guessType
    case WMean(op,wt) => Op.numbin(op guessType, wt guessType)
    case WHMean(op,wt) => Op.numbin(op guessType, wt guessType)
  }

  def simplify(t: Map[ColumnName,Op]) : AggFunc = this match {
    case Count => Count
    case Sum(op) => Sum(op simplify t)
    case Avg(op) => Avg(op simplify t)
    case Min(op) => Min(op simplify t)
    case Max(op) => Max(op simplify t)
    case Stddev(op) => Stddev(op simplify t)
    case Variance(op) => Variance(op simplify t)
    case WMean(op,wt) => WMean(op simplify t, wt simplify t)
    case WHMean(op,wt) => WHMean(op simplify t, wt simplify t)
  }

  def postReplaceOp[F[_]:Monad](f: Op => F[Op]) : F[AggFunc] = this match {
    case Count => (Count: AggFunc).pure[F]
    case Sum(op) => op.postReplace(f).map(Sum)
    case Avg(op) => op.postReplace(f).map(Avg)
    case Min(op) => op.postReplace(f).map(Min)
    case Max(op) => op.postReplace(f).map(Max)
    case Stddev(op) => op.postReplace(f).map(Stddev)
    case Variance(op) => op.postReplace(f).map(Variance)
    case WMean(op,wt) => (op.postReplace(f) |@| wt.postReplace(f))(WMean)
    case WHMean(op,wt) => (op.postReplace(f) |@| wt.postReplace(f))(WHMean)
  }
}

object AggFunc {
  case object Count extends AggFunc
  case class Sum(op: Op) extends AggFunc
  case class Avg(op: Op) extends AggFunc
  case class Min(op: Op) extends AggFunc
  case class Max(op: Op) extends AggFunc
  case class Stddev(op: Op) extends AggFunc
  case class Variance(op: Op) extends AggFunc
  case class WMean(op: Op, wt: Op) extends AggFunc // weighted mean
  case class WHMean(op: Op, wt: Op) extends AggFunc // weighted harmonic mean

  implicit val AggFuncEqual: Equal[AggFunc] = Equal.equalA
  implicit val AggFuncShow: Show[AggFunc] = Show.showFromToString

  import PrimExpr._
  import Reducer._

  def reduce[F[_]](a: AggFunc, t: PrimT)(implicit F: Foldable[F]): F[Record] => PrimExpr =
    xs => (reduceProcess(a, t) cap source(xs)).foldRight(NullExpr(t):PrimExpr)((a, _) => a)

  def count(t: PrimT): Process[Record, PrimExpr] =
    reducer(unitReducer((_: Record) => 1)).outmap(mkExpr(_, t))

  def sum(f: Op, m: Monoid[PrimExpr]): Process[Record, PrimExpr] =
    reducer(unitReducer(f.eval(_:Record))(m))

  def avg(f: Op, t: PrimT): Process[Record, PrimExpr] = {
    implicit val m = sumMonoid(t)
    reducer(unitReducer((tup: Record) => (f.eval(tup), 1))).outmap(x => x._1 / mkExpr(x._2, t))
  }

  def variance(f: Op, t: PrimT): Process[Record, PrimExpr] = {
    implicit val m = sumMonoid(t)
    reducer(unitReducer((e: Record) => {
      val x = f.eval(e)
      (x, x * x) : (PrimExpr, PrimExpr)
    })).outmap {
      case (ms, m) => ms - m * m
    }
  }

  def wmean(f: Op, wt: Op, t: PrimT): Process[Record, PrimExpr] = {
    implicit val m = sumMonoid(t)
    reducer(unitReducer((tup: Record) => {
      val w = wt.eval(tup)
      (f.eval(tup) * w, w) : (PrimExpr, PrimExpr)
    })).outmap(p => p._1 / p._2)
  }

  def whmean(f: Op, wt: Op, t: PrimT): Process[Record, PrimExpr] = {
    implicit val m = sumMonoid(t)
    reducer(unitReducer((tup: Record) => {
      val w = wt.eval(tup)
      (w / f.eval(tup), w) : (PrimExpr, PrimExpr)
    })).outmap(p => p._2 / p._1)
  }

  def stddev(f: Op, t: PrimT): Process[Record, PrimExpr] =
    variance(f, t).outmap(x => mkExpr(math.sqrt(x.extractDouble), t))

   /** A `Process` that reduces with a monoid. */
  def reducer[A, B](r: Reducer[A, B]): Process[A, B] = {
    def go(acc: B): Process[A, B] =
      Plan.await[A].orElse(Plan.emit(acc) >> Stop).flatMap(a => go(r.snoc(acc, a)))
    go(r.zero)
  }

  def reduceProcess(a: AggFunc, t: PrimT): Process[Record, PrimExpr] =
    a match {
      case Count => count(t)
      case Sum(f) => sum(f, sumMonoid(t))
      case Avg(f) => avg(f, t)
      case Min(f) => sum(f, minMonoid(t))
      case Max(f) => sum(f, maxMonoid(t))
      case Stddev(f) => stddev(f, t)
      case Variance(f) => variance(f, t)
      case WMean(f,wt) => wmean(f, wt, t)
      case WHMean(f,wt) => whmean(f, wt, t)
    }
}

