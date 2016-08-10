package com.clarifi.reporting

import java.util.Calendar
import java.util.Date

import scalaz._
import scalaz.Scalaz._
import Equal._
import Show._

import com.clarifi.reporting.ReportingUtils.splitWith

/** An expression to be evaluated in the environment of a record. */
sealed abstract class Op extends TraversableColumns[Op] {
  import Op._
  /** Evaluate this op in the environment `t`.  Throws if a column is
    * missing or there is a type mismatch.
    */
  def eval(t: Record): PrimExpr = this match {
    case OpLiteral(l) => l
    case ColumnValue(n, _) => t.getOrElse(n, sys.error("missing column: " + n + " in " + t.keySet))
    case Add(l, r) => l.eval(t) + r.eval(t)
    case Sub(l, r) => l.eval(t) - r.eval(t)
    case Mul(l, r) => l.eval(t) * r.eval(t)
    case FloorDiv(l,r) => l.eval(t) floordiv r.eval(t)
    case DoubleDiv(l,r) => l.eval(t) / r.eval(t)
    case Pow(l,r) => l.eval(t) pow r.eval(t)
    case Abs(o) => o.eval(t) abs
    case Concat(l) => StringExpr(false, l map (_.eval(t) extractNullableString "") concatenate)
    case If(test,c,a) => if (test eval t) c eval t else a eval t
    case Coalesce(l,r) => l.eval(t) match { case NullExpr(_) => r.eval(t) ; case e => e }
    case DateAdd(d,n,u) => d.eval(t) match {
      case n : NullExpr => n
      case dt => DateExpr(false, u.increment(dt.extractDate, n))
    }
    case DateDiff(u,s,e) =>
      if(u == TimeUnit.Millisecond)
        IntExpr(false, (e.eval(t).extractDate.getTime - s.eval(t).extractDate.getTime).toInt)
      else
        sys error "datediff is meant to be used from SQL; built-in Java date subtraction is limited to milliseconds"
    case Funcall(n,_,_,_,_) => sys error ("Can't invoke %s outside of a databse" format n)
    case Windowed(_, _) => sys error ("Can't evaluate window functions outside of a database")
    case Upper(o) => o.eval(t).upper
    case Lower(o) => o.eval(t).lower
    case Log(o) => o.eval(t).log
    case LogBase(o,b) => o.eval(t).logBase(b.eval(t))
    case Log10(o) => o.eval(t).log10
    case Exp(o) => o.eval(t).exp
  }

  def simplify(t: Map[ColumnName, Op]): Op = {
    def pnum(id: Byte)(p: PrimExpr) = p match {
      case ByteExpr(_, d) => d === id
      case ShortExpr(_, d) => d === id
      case IntExpr(_, i) => i === id
      case LongExpr(_, d) => d === id
      case DoubleExpr(_, d) => d === id
      case _: StringExpr | _: DateExpr | _: BooleanExpr | _: UuidExpr
         | _: NullExpr => false
    }
    def opbin(unsimpl: (Op, Op) => Op, simpl: (PrimExpr, PrimExpr) => PrimExpr,
              lident: PrimExpr => Boolean, rident: PrimExpr => Boolean
            )(l: Op, r: Op) = (simp(l), simp(r)) match {
      case (OpLiteral(l), OpLiteral(r)) => OpLiteral(simpl(l, r))
      case (OpLiteral(l), r) if lident(l) => r
      case (l, OpLiteral(r)) if rident(r) => l
      case (l, r) => unsimpl(l, r)
    }
    def simp(op: Op): Op = op match {
      case o : OpLiteral => o
      case ColumnValue(n, ty) =>
        t get n map simp getOrElse ColumnValue(n, ty)
      case Add(l,r) => opbin(Add, (_ + _), pnum(0), pnum(0))(l,r)
      case Sub(l,r) => opbin(Sub, (_ - _), Function const false, pnum(0))(l,r)
      case Mul(l,r) => opbin(Mul, (_ * _), pnum(1), pnum(1))(l,r)
      case FloorDiv(l,r) =>
        opbin(FloorDiv, (_ floordiv _), Function const false, Function const false)(l,r)
      case DoubleDiv(l,r) => opbin(DoubleDiv, (_ / _), Function const false, pnum(1))(l,r)
      case Pow(l,r) => opbin(Pow, (_ pow _), Function const false, pnum(1))(l,r)
      case Abs(x) => simp(x) match {
          case OpLiteral(y) => OpLiteral(y.abs)
          case _ => Abs(x)
        }
      case Concat(xs) =>
        splitWith(xs.map(simp)){case lit : OpLiteral => lit}.toList flatMap {
          case Left(lits) =>
            val newS = lits.toList.map(_.lit extractNullableString "").suml
            if (newS == "") List()
            else List(OpLiteral(StringExpr(false, newS)))
          case Right(l) => l
        } match {
          case List() => OpLiteral(StringExpr(false, ""))
          // Note: even though Concat on a non-string isn't the identity,
          // we've turned everything into a StringExpr by this point.
          case List(l : OpLiteral) => l
          case l => Concat(l)
        }
      case If(test, c, a) =>
        Predicates simplify (test liftOp (simp(_) : Id[Op])) match {
          case Predicate.Atom(b) => if (b) c else a
          case pr => If(pr, c, a)
        }
      case Coalesce(l, r) => Coalesce(simp(l), simp(r))
      case DateAdd(d,n,u) => DateAdd(simp(d),n,u)
      case DateDiff(u,s,e) => DateDiff(u,simp(s),simp(e))
      case Funcall(nm,db,ns,args,typ) => Funcall(nm,db,ns,args.map(simp(_)),typ)
      case Windowed(agg, w) => Windowed(agg.simplify(t), w.simplify(t))
      case Upper(o) => simp(o) match {
        case OpLiteral(pe) => OpLiteral(pe upper)
        case no => Upper(no)
      }
      case Lower(o) => simp(o) match {
        case OpLiteral(pe) => OpLiteral(pe lower)
        case no => Lower(no)
      }
      case Log(l) => simp(l) match {
        case OpLiteral(pe) => OpLiteral(pe log)
        case no => Log(no)
      }
      case Log10(l) => simp(l) match {
        case OpLiteral(pe) => OpLiteral(pe log10)
        case no => Log10(no)
      }
      case LogBase(l,b) => opbin(LogBase, (_ logBase _), Function const false, Function const false)(l,b)
      case Exp(e) => simp(e) match {
        case OpLiteral(pe) => OpLiteral(pe exp)
        case no => Exp(no)
      }
    }
    simp(this)
  }

  def guessTypeUnsafe: PrimT =
    guessType.fold(s => sys.error(s.head), t => t)

  /** Try to type me.  Failure doesn't necessarily mean I won't run
    * in a `Project`. */
  def guessType: ValidationNel[String, PrimT] = {
    import PrimT._
    type M[A] = ValidationNel[String, A]
    import Op.numbin

    this match {
      case OpLiteral(x) => x.typ.success
      case ColumnValue(_, typ) => typ.success
      case Add(l,r) => numbin(l guessType, r guessType)
      case Sub(l,r) => numbin(l guessType, r guessType)
      case Mul(l,r) => numbin(l guessType, r guessType)
      case FloorDiv(l,r) => numbin(l guessType, r guessType)
      case DoubleDiv(l,r) => numbin(l guessType, r guessType)
      case Pow(l,r) => numbin(l guessType, r guessType)
      case Abs(o) => o guessType
      case Concat(xs) => xs.traverse_[M](x => x.guessType >| (())) map (_ => StringT(0, false))
      case If(_, t, f) =>
        (t.guessType |@| f.guessType)(_ -> _) flatMap {
          case (c, a) =>
            c sup a map (_.success) getOrElse
              ("Unmatched if branches %s and %s" format (c, a) failureNel)
        }
      case Coalesce(e, t) =>
        (e.guessType |@| t.guessType)(_ -> _) flatMap {
          case (e, t) =>
            e.withoutNull sup t map (_.success) getOrElse
            ("Unmatched coalesce branches %s and %s" format (e, t) failureNel)
        }
      case DateAdd(d, _, _) => d guessType
      case DateDiff(_, _, _) => IntT().success
      case Funcall(nm,db,ns,args,ty) => args.traverse_[M](x => x.guessType >| (())) >| ty
      case Windowed(agg, _) => agg guessType
      case Upper(o) => o.guessType map (t => StringT(0, t.nullable))
      case Lower(o) => o.guessType map (t => StringT(0, t.nullable))
      case Log(l) => l.guessType map (t => DoubleT(t.nullable))
      case Log10(l) => l.guessType map (t => DoubleT(t.nullable))
      case Exp(l) => l.guessType map (t => DoubleT(t.nullable))
      case LogBase(l,b) => (l.guessType |@| b.guessType) ((t,u) => DoubleT(t.nullable || u.nullable))
    }
  }

  /** Post-order replace the expression tree, with traversal. */
  def postReplace[F[_]: Monad](f: Op => F[Op]): F[Op] = {
    def binop(b: (Op, Op) => Op) =
      (fl: F[Op], fr: F[Op]) => b.lift[F].apply(fl, fr) >>= f

    this match {
      case l : OpLiteral => f(l)
      case c : ColumnValue => f(c)
      case Add(l,r) => binop(Add)(l postReplace f, r postReplace f)
      case Sub(l,r) => binop(Sub)(l postReplace f, r postReplace f)
      case Mul(l,r) => binop(Mul)(l postReplace f, r postReplace f)
      case FloorDiv(l,r) => binop(FloorDiv)(l postReplace f, r postReplace f)
      case DoubleDiv(l,r) => binop(DoubleDiv)(l postReplace f, r postReplace f)
      case Pow(l,r) => binop(Pow)(l postReplace f, r postReplace f)
      case Abs(o) => o.postReplace(f) flatMap (x => f(Abs(x)))
      case Concat(xs) => xs.traverse(_ postReplace f) flatMap (f compose Concat)
      case If(b,y,n) => (b.postReplaceOp(f) |@| y.postReplace(f) |@| n.postReplace(f))(If) flatMap f
      case Coalesce(l,r) => binop(Coalesce)(l postReplace f, r postReplace f)
      case DateAdd(d, n, u) => d.postReplace(f) flatMap { nd => f(DateAdd(nd,n,u)) }
      case DateDiff(u, st, en) => binop(DateDiff(u,_,_))(st postReplace f, en postReplace f)
      case Funcall(nm, db, ns, args, ty) =>
        args.traverse(_ postReplace f) flatMap {
          nargs => f(Funcall(nm, db, ns, nargs, ty))
        }
      case Windowed(agg, w) => (agg.postReplaceOp(f) |@| w.postReplaceOp(f))(Windowed)
      case Upper(o) => o.postReplace(f) flatMap { x => f(Upper(x)) }
      case Lower(o) => o.postReplace(f) flatMap { x => f(Lower(x)) }
      case Log(o) => o.postReplace(f) flatMap { x => f(Log(x)) }
      case Log10(o) => o.postReplace(f) flatMap { x => f(Log10(x)) }
      case Exp(o) => o.postReplace(f) flatMap { x => f(Exp(x)) }
      case LogBase(o,b) => binop(LogBase)(o postReplace f, b postReplace f)
    }
  }

  /** Traverse the column references in an `Op`. */
  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[Op] = {
    def binop(liftee: (Op, Op) => Op) = liftee.lift[F]
    this match {
      case l : OpLiteral => (l : Op).pure[F]
      case ColumnValue(c, ty) => f(c) map (ColumnValue(_, ty))
      case Add(l,r) => binop(Add(_,_))(l traverseColumns f, r traverseColumns f)
      case Sub(l,r) => binop(Sub(_,_))(l traverseColumns f, r traverseColumns f)
      case Mul(l,r) => binop(Mul(_,_))(l traverseColumns f, r traverseColumns f)
      case FloorDiv(l,r) => binop(FloorDiv(_,_))(l traverseColumns f, r traverseColumns f)
      case DoubleDiv(l,r) => binop(DoubleDiv(_,_))(l traverseColumns f, r traverseColumns f)
      case Pow(l,r) => binop(Pow(_,_))(l traverseColumns f, r traverseColumns f)
      case Abs(o) => o.traverseColumns(f).map(Abs)
      case Concat(xs) => xs.traverse(_ traverseColumns f).map(Concat)
      case If(b,y,n) => (b.traverseColumns(f) |@| y.traverseColumns(f) |@| n.traverseColumns(f))(If)
      case Coalesce(l,r) => (l.traverseColumns(f) |@| r.traverseColumns(f))(Coalesce)
      case DateAdd(d,n,u) => d.traverseColumns(f) map(DateAdd(_,n,u))
      case DateDiff(u,s,e) => binop(DateDiff(u,_,_))(s.traverseColumns(f), e.traverseColumns(f))
      case Funcall(nm,db,ns,args,ty) => args.traverse(_ traverseColumns f) map (Funcall(nm,db,ns,_,ty))
      case Windowed(agg, w) => (agg.traverseColumns(f) |@| w.traverseColumns(f))(Windowed)
      case Upper(o) => o traverseColumns f map Upper
      case Lower(o) => o traverseColumns f map Lower
      case Log(o) => o traverseColumns f map Log
      case Log10(o) => o traverseColumns f map Log10
      case Exp(o) => o traverseColumns f map Exp
      case LogBase(o,b) => binop(LogBase)(o traverseColumns f, b traverseColumns f)
    }
  }

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z = {
    type WM[A] = Writer[Z, A]
    postReplace[WM]{
      case it@Op.ColumnValue(n, t) => (it:Op) set f(n, t)
      case it => it.point[WM]
    }.written
  }

  final def isWindowed: Boolean = this match {
    case Windowed(_, _) => true
    case Add(l,r) => l.isWindowed || r.isWindowed
    case Sub(l,r) => l.isWindowed || r.isWindowed
    case Mul(l,r) => l.isWindowed || r.isWindowed
    case FloorDiv(l,r) => l.isWindowed || r.isWindowed
    case DoubleDiv(l,r) => l.isWindowed || r.isWindowed
    case Pow(l,r) => l.isWindowed || r.isWindowed
    case Abs(e) => e isWindowed
    case Concat(xs) => xs.exists(_ isWindowed)
    case If(_, t,f) => t.isWindowed || f.isWindowed
    case Coalesce(l,r) => l.isWindowed || r.isWindowed
    case DateAdd(d,_,_) => d.isWindowed
    case DateDiff(_,s,e) => s.isWindowed || e.isWindowed
    case Funcall(_,_,_,args,_) => args.exists(_ isWindowed)
    case Upper(s) => s isWindowed
    case Lower(s) => s isWindowed
    case Log(o) => o isWindowed
    case Log10(o) => o isWindowed
    case Exp(o) => o isWindowed
    case LogBase(o,b) => o.isWindowed || b.isWindowed
    case _ => false
  }
}

trait TimeUnit {
  import TimeUnit._ // constructors

  /**
   * Increment `d` by `n` units. Example: `Day.increment(1/1/2013, 10)`
   * yields `1/11/2013`.
   */
  def increment(d: Date, n: Int): Date = {
    def go(d: Date, untypedJavaCalendarUnits: Int, n: Int): Date = {
      val cal = Calendar.getInstance
      cal.setTime(d)
      cal.add(untypedJavaCalendarUnits, n)
      cal.getTime
    }
    val (units, n2) = this match {
      case Millisecond => (Calendar.MILLISECOND, n)
      case Day => (Calendar.DATE, n)
      case Week => (Calendar.DATE, n*7)
      case Month => (Calendar.MONTH, n)
      case Year => (Calendar.YEAR, n)
    }
    go(d, units, n2)
  }
}

object TimeUnit {
  case object Millisecond extends TimeUnit
  // case object Second extends TimeUnit
  case object Day extends TimeUnit
  case object Week extends TimeUnit
  case object Month extends TimeUnit
  // case object Quarter extends TimeUnit
  case object Year extends TimeUnit
}

object TimeUnits {
  val Millisecond = TimeUnit.Millisecond
  val Day = TimeUnit.Day
  val Week = TimeUnit.Week
  val Month = TimeUnit.Month
  // val Quarter = TimeUnit.Quarter
  val Year = TimeUnit.Year
}

// for easier foreign importing by Ermine
object Ops {
  def dateAdd(n: Int, units: TimeUnit, date: Op): Op =
    Op.DateAdd(date, n, units)
  def dateDiff(units: TimeUnit, start: Op, end: Op): Op =
    Op.DateDiff(units, start, end)
  def coalesce(l: Op, r: Op): Op = Op.Coalesce(l, r)
}

case class Frame(preceding: Option[Int], following: Option[Int])
case class Window(
  partition: List[Op],
  order: List[(Op, SortOrder)],
  frame: Frame
) extends TraversableColumns[Window] {
  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[Window] = {
    val fPart = partition.traverse(_.traverseColumns(f))
    val fOrd = order.traverse { case (o, so) => o.traverseColumns(f).map(_ -> so) }
    ^(fPart, fOrd)(Window(_,_,frame))
  }

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
    partition.foldMap(_.typedColumnFoldMap(f)) |+|
    order.foldMap(_._1.typedColumnFoldMap(f))

  def postReplaceOp[F[_]:Monad](f: Op => F[Op]) =
    (partition.traverse(_ postReplace f) |@|
     order.traverse{ case (o, s) => o.postReplace(f) map ((_,s)) })(Window(_,_,frame))

  def simplify(f: Map[ColumnName, Op]) =
    Window(partition.map(_ simplify f), order.map{ case (x, y) => (x simplify f, y) }, frame)
}

object Window extends Function3[List[Op], List[(Op, SortOrder)], Frame, Window] {
  import Op.ColumnValue
  def simple(part: List[(ColumnName, PrimT)], ord: List[((ColumnName, PrimT), SortOrder)], frame: Frame) =
    Window(part.map(ColumnValue.tupled), ord.map{ case ((c,t),s) => (ColumnValue(c,t), s) }, frame)
}

object Op {
  case class OpLiteral(lit: PrimExpr) extends Op
  case class ColumnValue(col: ColumnName, typ: PrimT) extends Op
  case class Add(l: Op, r: Op) extends Op
  case class Sub(l: Op, r: Op) extends Op
  case class Mul(l: Op, r: Op) extends Op
  case class FloorDiv(l: Op, r: Op) extends Op
  case class DoubleDiv(l: Op, r: Op) extends Op
  case class Pow(l: Op, r: Op) extends Op
  case class Abs(l: Op) extends Op
  case class Concat(cs: List[Op]) extends Op
  case class If(test: Predicate, consequent: Op, alternate: Op) extends Op
  case class Coalesce(l: Op, r: Op) extends Op
  case class DateAdd(date: Op, n: Int, units: TimeUnit) extends Op
  case class DateDiff(units: TimeUnit, start: Op, end: Op) extends Op
  case class Funcall(name: String, database: String, namespace: List[String],
                     args: List[Op], typ: PrimT) extends Op
  case class Windowed(agg: AggFunc, window: Window) extends Op
  case class Upper(op: Op) extends Op
  case class Lower(op: Op) extends Op
  case class Log(l: Op) extends Op
  case class LogBase(l: Op, b: Op) extends Op
  case class Log10(l: Op) extends Op
  case class Exp(l: Op) extends Op

  implicit val OpEqual: Equal[Op] = equalA
  implicit val OpShow: Show[Op] = showFromToString

  import PrimT._
  private def numRank(t: PrimT): Option[Int] = t match {
    case ByteT(_) => Some(10)
    case ShortT(_) => Some(20)
    case IntT(_) => Some(30)
    case LongT(_) => Some(40)
    case DoubleT(_) => Some(50)
    case _ => None
  }
  // Autopromoting numeric type unification.
  def numbin(mleft: ValidationNel[String,PrimT], mright: ValidationNel[String,PrimT]): ValidationNel[String,PrimT] =
    (mleft |@| mright)(_ -> _) flatMap {case (left, right) =>
      (numRank(left), numRank(right), left sup right) match {
        case (None, _, _) => ("Nonnumeric type " + left).failureNel
        case (_, None, _) => ("Nonnumeric type " + right).failureNel
        case (_, _, Some(t)) => t.success
        case (Some(rkl), Some(rkr), _) =>
          (if (rkl < rkr) right else left).success
    }}
}

