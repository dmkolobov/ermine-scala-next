package com.clarifi.reporting

import java.util.Calendar
import java.util.Date
import java.sql.Timestamp

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
    case Concat(l) => StringExpr(false, l map (_.eval(t) extractNullableString "") concatenate)
    case If(test,c,a) => if (test eval t) c eval t else a eval t
    case Coalesce(l,r) => l.eval(t) match { case NullExpr(_) => r.eval(t) ; case e => e }
    case DateAdd(d,n,u) => d.eval(t) match {
      case n : NullExpr => n
      case dt => n.eval(t) match {
        case v : NullExpr => v
        case m => dt.mapDate(u.incrementTimestamp(_, m.extractInt))
      }
    }
    case DateDiff(u,s,e) =>
      if(u == TimeUnit.Millisecond)
        IntExpr(false, (e.eval(t).extractTimestamp.getTime - s.eval(t).extractTimestamp.getTime).toInt)
      else
        sys error "datediff is meant to be used from SQL; built-in Java date subtraction is limited to milliseconds"
    case Funcall(n,_,_,_,_) => sys error ("Can't invoke %s outside of a database" format n)
    case Windowed(_, _) => sys error ("Can't evaluate window functions outside of a database")
    case BuiltinCall(b, args) => builtinEval(b, args.map(_ eval t))
    case Cast(o, ty, nullIfFail) => if (nullIfFail) o.eval(t).tryCast(ty) else o.eval(t).cast(ty)
  }

  def builtinEval(b: Builtin, args: List[PrimExpr]): PrimExpr = builtinEvalMaybe(b, args) match {
    case Some(pe) => pe
    case None => sys.error("Bad builtin application: " + b.toString + "," + args.toString)
  }

  def builtinEvalMaybe(b: Builtin, args: List[PrimExpr]): Option[PrimExpr] = (b, args) match {
    case (Pow, List(l,r)) => Some(l pow r)
    case (Abs, List(e)) => Some(e abs)
    case (Upper, List(e)) => Some(e upper)
    case (Lower, List(e)) => Some(e lower)
    case (Log, List(e)) => Some(e log)
    case (Log10, List(e)) => Some(e log10)
    case (LogBase, List(e,b)) => Some(e logBase b)
    case (Exp, List(e)) => Some(e exp)
    case (Replace, List(e, a, b)) => Some(e replace (a, b))
    case _ => None
  }

  private def pnum(id: Byte)(p: PrimExpr) = p match {
    case ByteExpr(_, d) => d === id
    case ShortExpr(_, d) => d === id
    case IntExpr(_, i) => i === id
    case LongExpr(_, d) => d === id
    case DoubleExpr(_, d) => d === id
    case _: StringExpr | _: DateExpr | _: BooleanExpr | _: UuidExpr
       | _: NullExpr | _:TimestampExpr => false
  }

  private def asNum(v: Byte)(p: PrimExpr) = p match {
    case _ : ByteExpr => ByteExpr(p.nullable, v)
    case _ : ShortExpr => ShortExpr(p.nullable, v)
    case _ : IntExpr => IntExpr(p.nullable, v)
    case _ : LongExpr => LongExpr(p.nullable, v)
    case _ : DoubleExpr => DoubleExpr(p.nullable, v)
    case _ => sys.error("Op.asNum: called with non-numeric prim expr")
  }

  def builtinSimplify(b: Builtin, args: List[Op]): Op = (b, args) match {
    case (LogBase, List(l,r)) => r match {
      case OpLiteral(pe) if pnum(1)(pe) => OpLiteral(asNum(0)(pe))
    }
    case _ =>
      args.traverse {
        case OpLiteral(pe) => Some(pe) ; case _ => None
      } flatMap {
        builtinEvalMaybe(b, _)
      } map {
        OpLiteral(_)
      } getOrElse (BuiltinCall(b,args))
  }

  def simplify(t: Map[ColumnName, Op]): Op = {
    def opbin(unsimpl: (Op, Op) => Op, simpl: (PrimExpr, PrimExpr) => PrimExpr,
              lident: PrimExpr => Boolean, rident: PrimExpr => Boolean
            )(l: Op, r: Op) = (simp(l), simp(r)) match {
      case (OpLiteral(l), OpLiteral(r)) => OpLiteral(simpl(l, r))
      case (OpLiteral(l), r) if lident(l) => r
      case (l, OpLiteral(r)) if rident(r) => l
      case (l, r) => unsimpl(l, r)
    }

    // When simplifying a Concat, remove nested Concats
    def simpConcat(op: Op): List[Op] = simp(op) match {
      case Concat(xs) => xs
      case o => List(o)
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
      case Concat(xs) =>
        splitWith(xs.flatMap(simpConcat)){case lit : OpLiteral => lit}.toList flatMap {
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
          case Predicate.Atom(b) => if (b) simp(c) else simp(a)
          case pr => If(pr, simp(c), simp(a))
        }
      case Coalesce(l, r) => Coalesce(simp(l), simp(r))
      case DateAdd(d,n,u) => DateAdd(simp(d),simp(n),u)
      case DateDiff(u,s,e) => DateDiff(u,simp(s),simp(e))
      case Funcall(nm,db,ns,args,typ) => Funcall(nm,db,ns,args.map(simp(_)),typ)
      case Windowed(func, w) => Windowed(func.simplify(t), w.simplify(t))
      case BuiltinCall(b, args) => builtinSimplify(b, args.map(simp))
      case Cast(e,ty,nullIfFail) => simp(e) match {
        case OpLiteral(pe) => OpLiteral(if (nullIfFail) (pe tryCast ty) else pe cast ty)
        case no => Cast(no, ty, nullIfFail)
      }
    }
    simp(this)
  }

  def guessTypeUnsafe: PrimT =
    guessType.fold(s => sys.error(s.head), t => t)

  def guessBuiltinType(b: Builtin)(args: List[PrimT]) = {
    import PrimT._
    b match {
      case Upper | Lower | Replace => StringT(0, args.head.nullable)
      case Abs => args.head
      case Log | Log10 | LogBase | Exp | Pow => DoubleT(args.exists(_ nullable))
    }
  }

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
      case Windowed(func, _) => func guessType
      case BuiltinCall(b, args) => args.traverse[M,PrimT](_ guessType).map(guessBuiltinType(b))
      case Cast(e, ty, _) => e.guessType.map(_ => ty)
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
      case Concat(xs) => xs.traverse(_ postReplace f) flatMap (f compose Concat)
      case If(b,y,n) => (b.postReplaceOp(f) |@| y.postReplace(f) |@| n.postReplace(f))(If) flatMap f
      case Coalesce(l,r) => binop(Coalesce)(l postReplace f, r postReplace f)
      case DateAdd(d, n, u) => binop(DateAdd(_,_,u))(d postReplace f, n postReplace f)
      case DateDiff(u, st, en) => binop(DateDiff(u,_,_))(st postReplace f, en postReplace f)
      case Funcall(nm, db, ns, args, ty) =>
        args.traverse(_ postReplace f) flatMap {
          nargs => f(Funcall(nm, db, ns, nargs, ty))
        }
      case Windowed(func, w) => (func.postReplaceOp(f) |@| w.postReplaceOp(f))(Windowed)
      case BuiltinCall(b,args) => args.traverse(_ postReplace f).map(BuiltinCall(b,_))
      case Cast(o, ty, nullIfFail) => o.postReplace(f).map(Cast(_,ty,nullIfFail))
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
      case Concat(xs) => xs.traverse(_ traverseColumns f).map(Concat)
      case If(b,y,n) => (b.traverseColumns(f) |@| y.traverseColumns(f) |@| n.traverseColumns(f))(If)
      case Coalesce(l,r) => (l.traverseColumns(f) |@| r.traverseColumns(f))(Coalesce)
      case DateAdd(d,n,u) => binop(DateAdd(_,_,u))(d.traverseColumns(f), n.traverseColumns(f))
      case DateDiff(u,s,e) => binop(DateDiff(u,_,_))(s.traverseColumns(f), e.traverseColumns(f))
      case Funcall(nm,db,ns,args,ty) => args.traverse(_ traverseColumns f) map (Funcall(nm,db,ns,_,ty))
      case Windowed(func, w) => (func.traverseColumns(f) |@| w.traverseColumns(f))(Windowed)
      case BuiltinCall(b,args) => args.traverse(_ traverseColumns f).map(BuiltinCall(b,_))
      case Cast(o, ty, nullIfFail) => o.traverseColumns(f).map(Cast(_,ty,nullIfFail))
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
    case Concat(xs) => xs.exists(_ isWindowed)
    case If(_, t,f) => t.isWindowed || f.isWindowed
    case Coalesce(l,r) => l.isWindowed || r.isWindowed
    case DateAdd(d,n,_) => d.isWindowed || n.isWindowed
    case DateDiff(_,s,e) => s.isWindowed || e.isWindowed
    case Funcall(_,_,_,args,_) => args.exists(_ isWindowed)
    case BuiltinCall(_, args) => args.exists(_ isWindowed)
    case Cast(o, _, _) => o isWindowed
    case _ => false
  }
}

trait TimeUnit {
  import TimeUnit._ // constructors

  def incrementTimestamp(t: Timestamp, n: Int): Timestamp = {
    def go(t: Timestamp, untypedJavaCalendarUnits: Int, n: Int): Timestamp = {
      val cal = Calendar.getInstance
      cal.setTime(t)
      cal.add(untypedJavaCalendarUnits, n)
      new Timestamp(cal.getTimeInMillis)
    }
    val (units, n2) = this match {
      case Millisecond => (Calendar.MILLISECOND, n)
      case Second => (Calendar.SECOND, n)
      case Day => (Calendar.DATE, n)
      case Week => (Calendar.DATE, n*7)
      case Month => (Calendar.MONTH, n)
      case Year => (Calendar.YEAR, n)
    }
    go(t, units, n2)
  }

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
      case Millisecond | Second => sys.error("Cannot increment Date by milliseconds; Dates represent year/month/day triples")
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
  case object Second extends TimeUnit
  case object Day extends TimeUnit
  case object Week extends TimeUnit
  case object Month extends TimeUnit
  // case object Quarter extends TimeUnit
  case object Year extends TimeUnit
}

object TimeUnits {
  val Millisecond = TimeUnit.Millisecond
  val Second = TimeUnit.Second
  val Day = TimeUnit.Day
  val Week = TimeUnit.Week
  val Month = TimeUnit.Month
  // val Quarter = TimeUnit.Quarter
  val Year = TimeUnit.Year
}

// for easier foreign importing by Ermine
object Ops {
  def dateAdd(n: Op, units: TimeUnit, date: Op): Op =
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
  sealed trait Builtin
    case object Upper extends Builtin
    case object Lower extends Builtin
    case object Log extends Builtin
    case object Log10 extends Builtin
    case object LogBase extends Builtin
    case object Exp extends Builtin
    case object Abs extends Builtin
    case object Pow extends Builtin
    case object Replace extends Builtin

  case class OpLiteral(lit: PrimExpr) extends Op
  case class ColumnValue(col: ColumnName, typ: PrimT) extends Op
  case class Add(l: Op, r: Op) extends Op
  case class Sub(l: Op, r: Op) extends Op
  case class Mul(l: Op, r: Op) extends Op
  case class FloorDiv(l: Op, r: Op) extends Op
  case class DoubleDiv(l: Op, r: Op) extends Op
  case class Concat(cs: List[Op]) extends Op
  case class If(test: Predicate, consequent: Op, alternate: Op) extends Op
  case class Coalesce(l: Op, r: Op) extends Op
  case class DateAdd(date: Op, n: Op, units: TimeUnit) extends Op
  case class DateDiff(units: TimeUnit, start: Op, end: Op) extends Op
  case class Funcall(name: String, database: String, namespace: List[String],
                     args: List[Op], typ: PrimT) extends Op
  case class Windowed(func: WindowFunc, window: Window) extends Op
  case class BuiltinCall(fun: Builtin, args: List[Op]) extends Op
  case class Cast(l: Op, ty: PrimT, nullIfFail: Boolean) extends Op

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

