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

  // SQL audit P4/P5 (S-13, S-12; decisions D1, D2).  Every aggregate below behaves as
  // its SQL twin: NULL inputs are skipped; over an EMPTY input the process emits
  // NOTHING (the SQL side gets `having count(*) > 0`, so an ungrouped `meanBy`/`minBy`
  // over no rows is no row, not one NULL row into a non-nullable column); over rows
  // that are all NULL it emits one NULL.  `sum` and `count` are the exceptions SQL
  // makes too: 0 over an empty input.  Before: `avg` divided a NULL-poisoned sum by
  // the row count, `variance` was `Σx - (Σx²)²` (the tuple read in the wrong order,
  // never divided by n), and every one answered a row over an empty input.

  /** Fold the input with `step` from `zero`, counting rows; at the end emit what `out`
    * answers for the accumulator and the row count, if anything. */
  private def folding[B](zero: B)(step: (B, Record) => B)(out: (B, Int) => Option[PrimExpr]): Process[Record, PrimExpr] = {
    def finish(acc: B, rows: Int): Plan[Record => Any, PrimExpr, Nothing] =
      (out(acc, rows) match {
        case Some(v) => Plan.emit(v)
        case None => Return(())
      }) >> Stop
    def go(acc: B, rows: Int): Process[Record, PrimExpr] =
      Plan.await[Record].orElse(finish(acc, rows)).flatMap(r => go(step(acc, r), rows + 1))
    go(zero, 0)
  }

  /** `out` is asked only when there were rows; `None` from it means one NULL. */
  private def nonEmpty[B](zero: B)(step: (B, Record) => B)(out: B => Option[PrimExpr], t: PrimT): Process[Record, PrimExpr] =
    folding(zero)(step)((acc, rows) => if (rows == 0) None else Some(out(acc).getOrElse(NullExpr(t))))

  /** `(sum, count of non-NULL values)`. */
  private def sumAndCount(f: Op, m: Monoid[PrimExpr]): ((PrimExpr, Int), Record) => (PrimExpr, Int) = {
    case ((s, n), r) => f.eval(r) match {
      case _: NullExpr => (s, n)
      case x => (m.append(s, x), n + 1)
    }
  }

  def avg(f: Op, t: PrimT): Process[Record, PrimExpr] = {
    val m = sumMonoid(t)
    nonEmpty((m.zero, 0))(sumAndCount(f, m))({
      case (s, n) => if (n == 0) None else Some(s / mkExpr(n, t))
    }, t)
  }

  /** Population variance, `(Σx² / n) - (Σx / n)²` in doubles (`VAR_POP`/`VARP`), typed
    * back to `t` as `stddev` always was. */
  private def varianceD(f: Op): Process[Record, Option[Double]] = {
    // (Σx, Σx², n) over the non-NULL values
    val p: Process[Record, PrimExpr] = nonEmpty((0.0, 0.0, 0))({
      case ((s, s2, n), r) => f.eval(r) match {
        case _: NullExpr => (s, s2, n)
        case x => val d = x.extractDouble; (s + d, s2 + d * d, n + 1)
      }
    })({
      case (s, s2, n) =>
        if (n == 0) None
        else { val mean = s / n; Some(DoubleExpr(true, s2 / n - mean * mean)) }
    }, PrimT.DoubleT(true))
    p.outmap(x => if (x.isNull) None else Some(x.extractDouble))
  }

  def variance(f: Op, t: PrimT): Process[Record, PrimExpr] =
    varianceD(f).outmap(_.map(mkExpr(_, t)).getOrElse(NullExpr(t)))

  def stddev(f: Op, t: PrimT): Process[Record, PrimExpr] =
    varianceD(f).outmap(_.map(v => mkExpr(math.sqrt(v), t)).getOrElse(NullExpr(t)))

  /** `SUM(x*w) / SUM(w)`: a row with a NULL value or weight contributes nothing. */
  def wmean(f: Op, wt: Op, t: PrimT): Process[Record, PrimExpr] = {
    val m = sumMonoid(t)
    nonEmpty((m.zero, m.zero, 0))({
      case ((sxw, sw, n), r) => (f.eval(r), wt.eval(r)) match {
        case (_: NullExpr, _) | (_, _: NullExpr) => (sxw, sw, n)
        case (x, w) => (m.append(sxw, x * w), m.append(sw, w), n + 1)
      }
    })({
      case (sxw, sw, n) => if (n == 0) None else Some(sxw / sw)
    }, t)
  }

  /** `SUM(w) / SUM(w/x)`, the weighted harmonic mean. */
  def whmean(f: Op, wt: Op, t: PrimT): Process[Record, PrimExpr] = {
    val m = sumMonoid(t)
    nonEmpty((m.zero, m.zero, 0))({
      case ((swx, sw, n), r) => (f.eval(r), wt.eval(r)) match {
        case (_: NullExpr, _) | (_, _: NullExpr) => (swx, sw, n)
        case (x, w) => (m.append(swx, w / x), m.append(sw, w), n + 1)
      }
    })({
      case (swx, sw, n) => if (n == 0) None else Some(sw / swx)
    }, t)
  }

  /** MIN/MAX: the monoid skips NULLs and starts from NULL, so the fold is the answer;
    * only the empty input is turned into no row. */
  private def extremum(f: Op, m: Monoid[PrimExpr], t: PrimT): Process[Record, PrimExpr] =
    nonEmpty(m.zero)((acc, r) => m.append(acc, f.eval(r)))(acc => Some(acc), t)

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
      case Min(f) => extremum(f, minMonoid(t), t)
      case Max(f) => extremum(f, maxMonoid(t), t)
      case Stddev(f) => stddev(f, t)
      case Variance(f) => variance(f, t)
      case WMean(f,wt) => wmean(f, wt, t)
      case WHMean(f,wt) => whmean(f, wt, t)
    }
}

