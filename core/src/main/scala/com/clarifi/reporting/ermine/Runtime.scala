package com.clarifi.reporting.ermine

import scala.collection.immutable.{ IntMap, List }
import scala.util.control.NonFatal
import scalaz.Scalaz._
import com.clarifi.reporting.relational._
import com.clarifi.reporting._

import Type.{True, False}

class FFI[A](e: => A) {
  def eval = e
}

/** A COOPERATIVE CANCEL in flight (WP-6, tracker/JSON-WIDGET-PLAYGROUND.md
  * sections 2.5 and 14).  Thrown by `Runtime.swhnf` on the ONE thread that
  * `Runtime.cancelTarget` names, so that an evaluation nothing can interrupt
  * from outside ends at its next force.
  *
  * A `ControlThrowable`, and each of the three reasons is load-bearing:
  *
  *  - it is STACKLESS (`Throwable(message, null, false, false)`), so the
  *    throw costs nothing on a path a long unwind takes many times;
  *  - `scala.util.control.NonFatal` EXCLUDES it, so `swhnf`'s own capture --
  *    `catch { case NonFatal(e) => r = Bottom(throw e) }` below -- does NOT
  *    memoise it into the thunk.  A cancelled force therefore leaves no
  *    poisoned `Bottom` for a later render to re-throw.  What it DOES leave
  *    is WHITEHOLED thunks with this thread still in their `pending` queue,
  *    which a later force on the same thread would memoise as "infinite loop
  *    detected" -- and that is why the canceller must throw the whole
  *    session away (`lsp/Preview.scala`'s cancel path, which discards the
  *    render session unconditionally);
  *  - it is NOT a `java.lang.Error`.  `parsing/ForeignClasses.Recoverable`
  *    swallows an arbitrary `Error` into a failed reflective lookup, and the
  *    arm that lets this class through is `case _: ControlThrowable => None`
  *    (`ForeignClasses.scala:26`).  An `Error` here would be turned into
  *    "error loading '...'" instead of ending the evaluation.
  *
  * `userAsked` tells a cancel the CLIENT asked for from the watchdog's own.
  * NOTHING SETS IT TRUE IN STAGE 1: a user `$/cancelRequest` deliberately
  * does not interrupt (section 14's WP-6 row), and the field is here for the client
  * that one day sends one. */
final class Cancelled(val why: String, val userAsked: Boolean)
  extends scala.util.control.ControlThrowable(why)

sealed abstract class Runtime {
  def extract[A]: A
  def nf: Runtime = this
  final def whnf: Runtime = Runtime.swhnf(this)
  def apply1(arg: Runtime): Runtime = die("Cannot apply runtime value " + this + " to " + arg)
  def apply(args: Runtime*): Runtime = args.foldLeft(this)(_.apply1(_))
  def err(caller: String): Runtime = die("Panic: unexpected runtime value in " + caller + " - " + whnf)
  def nfMatch(caller: String)(p: PartialFunction[Runtime, Runtime]): Runtime = {
    val myNf = nf
    p.lift(myNf).getOrElse(myNf.err(caller))
  }
  def whnfMatch(caller: String)(p: PartialFunction[Runtime, Runtime]): Runtime = {
    val myWhnf = whnf
    p.lift(myWhnf).getOrElse(myWhnf.err(caller))
  }
  override def toString = Pretty.ppRuntime(this)(Pretty.Unqualified).runAp.toString
}

class Prim(p: Any) extends Runtime {
  def extract[A] = p.asInstanceOf[A]
  override def apply1(arg: Runtime): Runtime = p match {
    case f : Function1[Any,_] => Prim(f(arg.extract[Any]))
    case _ => die("Cannot apply " + this + " to " + arg)
  }
  override def equals(v: Any) = v match {
    case (rv : Runtime) => rv.whnf match {
      case Prim(q) => p == q
      case Box(q) => p == q
      case e : Bottom => e.inspect
      case _       => false
    }
    case _ => false
  }
  override def toString = p.toString
}

object Prim {
  def apply(p: => Any) = try {
    val pForced = p
    pForced match {
      case r: Runtime => r
      case p => new Prim(p)
    }
  // WP-6: a `Cancelled` is NOT a failure of this primitive and must not be
  // turned into a value.  Without this arm the catch below would wrap the
  // cancel in a `Bottom` whose forcing re-throws it, which `writeback`
  // then memoises -- and the cancel would silently not work at all.
  } catch { case c: Cancelled => throw c
            case e: Throwable => Bottom(throw e) }
  def unapply(p: Prim) = Some(p.extract[Any])
}

class Box(p: Any) extends Runtime {
  def extract[A] = p.asInstanceOf[A]
  override def apply1(arg: Runtime): Runtime = p match {
    case f : Function1[Any,_] => Box(f(arg.extract[Any]))
    case _ => die("Cannot apply " + this + " to " + arg)
  }
  override def equals(v: Any) = v match {
    case (rv : Runtime) => rv.whnf match {
      case Box(q) => p == q
      case Prim(q) => p == q
      case e : Bottom => e.inspect
      case _       => false
    }
    case _ => false
  }
  override def toString = p.toString
}

object Box {
  def apply(b: => Any) = try {
    val bForced = b
    bForced match {
      case r: Runtime => r
      case b => new Box(b)
    }
  // WP-6, exactly as in `Prim.apply` above.
  } catch { case c: Cancelled => throw c
            case e: Throwable => Bottom(throw e) }
  def unapply(b: Box) = Some(b.extract[Any])
}

/** Relational value */
class Rel(r: Ext[Nothing, Nothing]) extends Runtime {
  def extract[A] = r.asInstanceOf[A]
  override def equals(v: Any) = v match {
    case (rv : Runtime) => rv.whnf match {
      case Rel(s) => r == s
      case e : Bottom => e.inspect
      case _      => false
    }
    case _ => false
  }
}

object Rel {
  def apply(h: => Ext[Nothing, Nothing]) =
    try new Rel(h) catch { case NonFatal(e) => Bottom(throw e) }
  def unapply(r: Rel) = Some(r.extract[Ext[Nothing, Nothing]])
}

case object EmptyRel extends Runtime {
  def extract[A] = this.asInstanceOf[A]
}

case class Arr(arr: Array[Runtime] = Array()) extends Runtime {
  def extract[A] = this.asInstanceOf[A]
  override def nf = Arr(arr.map(_.nf))

  override def equals(v: Any) = v match {
    case (rv : Runtime) => rv.whnf match {
      case Arr(bss)   => Runtime.arrEq(arr, bss)
      case e : Bottom => e.inspect
      case _          => false
    }
    case _ => false
  }
}

case class Data(name: Global, arr: Array[Runtime] = Array()) extends Runtime {
  def extract[A] = this.asInstanceOf[A]
  override def nf       = Data(name, arr.map(_.nf))

  override def equals(v: Any) = v match {
    case (rv : Runtime) => rv.whnf match {
      case Data(nm, bss) => name == nm && Runtime.arrEq(arr, bss)
      case e : Bottom    => e.inspect
      case _             => false
    }
    case _ => false
  }
}

class Bottom(msg: => Nothing) extends Runtime {
  def inspect = msg
  def extract[A] = msg
  def exn: Exception = try msg catch { case e: Exception => e }
  /** @todo SMRC Use NonFatal for this? */
  // WP-6, DM-3 of the stage 1 review.  A `Bottom`'s body is USUALLY a bare
  // `throw`, but not always: `session/Lib.scala`'s stdlib `error` is
  // `Bottom(error(s.extract[String]))` and its `pipe#` failure is
  // `Bottom(... + rel.whnf)`, and both FORCE.  Without this arm a cancel
  // raised by that forcing would be CAUGHT HERE AND RETURNED AS A VALUE --
  // and `thrown` is what `json/Encode.scala`, `json/Doc.scala`,
  // `Pretty.ppRuntime` and `toString` below all call, so the cancel would
  // come back as a bogus error node inside a 200, or as a job that
  // "succeeded" with the cancel's own text embedded in it.
  private[ermine] def thrown: Throwable = try msg catch {
    case c: Cancelled => throw c
    case e: Throwable => e }
  override def apply1(r: Runtime) = this
  override def err(caller: String) = this
  override def toString = "Bottom(" + thrown.toString + ")"
  override def equals(v: Any) = inspect
}

object Bottom {
  def apply(f: => Nothing): Bottom = {
    new Bottom(f)
  }
  def unapply(f: Bottom): Option[() => Nothing] = Some(() => f.inspect)
}

class Rec(val t: Map[String, Runtime]) extends Runtime {
  def extract[A] = this.asInstanceOf[A]
  override def nf = Rec( t.mapValues( _.nf ).toMap )

  override def equals(v: Any) = v match {
    case (rv : Runtime) => rv.whnf match {
      case Rec(u)     => t == u
      case e : Bottom => e.inspect
      case _          => false
    }
    case _ => false
  }
}

object Rec {
  def apply(t: => Map[String, Runtime]): Runtime =
    try new Rec(t) catch { case NonFatal(e) => Bottom (throw e) }
  def unapply(t: Rec) = Some(t.t)
}

class Fun(val f: Runtime => Runtime) extends Runtime  {
  def extract[A] = this.asInstanceOf[A]
  override def nf = Fun(e => f(e).nf)
  override def apply1(arg: Runtime) = f(arg)
}
object Fun {
  def apply(f: Runtime => Runtime): Fun = new Fun(f)
  def apply(name: String, pf: PartialFunction[Runtime, Runtime]): Fun = Fun(a => a.whnfMatch(name)(pf))
  def unapply(f: Fun) = Some(f.f)
}

object Runtime {
  val arrUnit = Arr()

  /** WP-6's COOPERATIVE CANCEL: the ONE thread a cancel may stop, and the
    * `Cancelled` it is to be stopped with.  `null` -- the case every
    * ordinary run is in -- means no cancel is armed anywhere in this JVM.
    *
    * ONE GLOBAL REFERENCE, not a `ThreadLocal` and not `Thread.interrupt`.
    * The interrupt was rejected outright: `lsp/Preview.takeJob` reads an
    * `InterruptedException` as "stop", `backends`' chunk offering and
    * `parsing/ForeignClasses.Recoverable` both react to interrupts, third
    * party code may clear the flag before this evaluator ever sees it, and
    * a JDBC driver may abort its connection on one.  A `ThreadLocal` would
    * cost a map lookup on every force instead of one volatile read.
    *
    * THE WRITE ORDER IS PART OF THE CONTRACT: a canceller writes
    * `cancelWhy` FIRST and `cancelTarget` SECOND, and clears them in the
    * opposite order, so that a thread which has seen the target has almost
    * always already seen the reason.  `swhnf` tolerates the remaining
    * window by throwing a generic `Cancelled` rather than an NPE.
    *
    * THE FIELDS ARE `private[Runtime]` AND THE WRITES GO THROUGH
    * `armCancel` / `disarmCancel` (S1 and S2 of the stage 1 review).  The
    * write ORDER and the identity guard are the whole contract, and five
    * call sites each re-implementing them is five chances to get one
    * wrong; `cancelArmedFor` is the read accessor the guards and the
    * properties use.  The HOT PATH -- `swhnf` below -- still reads the
    * field DIRECTLY: it is in this object, and a method call with a
    * monitor in it is exactly what must not be on every force. */
  @volatile private[Runtime] var cancelTarget: Thread = null
  @volatile private[Runtime] var cancelWhy: Cancelled = null

  /** The monitor `armCancel` and `disarmCancel` share.  OFF THE HOT PATH by
    * construction: nothing in `swhnf` touches it, and the two operations
    * run once per watchdog fire and once per job. */
  private val cancelLock = new Object

  /** ARM a cooperative cancel for `target`, or answer `false` because
    * ANOTHER thread's arming is already live.
    *
    * The refusal is the point: the flag is ONE global reference, so a
    * second arming would silently replace the first and the thread that
    * was to be stopped would run on. A caller that is refused has not
    * armed anything and must say so and fall back (`lsp/Preview`'s
    * `fireCancel` degrades to phase 2b).  Re-arming the SAME target is
    * allowed and simply refreshes the reason.
    *
    * THE WRITE ORDER IS ENFORCED HERE, not asked of the caller: the reason
    * first, the target second, so a thread that has seen the target has
    * already seen the reason. */
  private[reporting] def armCancel(target: Thread, why: Cancelled): Boolean =
    cancelLock.synchronized {
      val live = cancelTarget
      if ((live ne null) && (live ne target)) false
      else { cancelWhy = why; cancelTarget = target; true }
    }

  /** DISARM `target`'s own arming, and nothing else.  Idempotent, safe on a
    * `null` target, and safe to call from any thread: the identity guard is
    * what keeps two `Preview`s (or a test and a `Preview`) in one unforked
    * JVM from clearing each other.  The order is the reverse of `armCancel`'s. */
  private[reporting] def disarmCancel(target: Thread): Unit =
    cancelLock.synchronized {
      if ((target ne null) && (cancelTarget eq target)) {
        cancelTarget = null
        cancelWhy    = null
      }
    }

  /** Which thread a cancel is armed for, or `null`.  READ ONLY. */
  private[reporting] def cancelArmedFor: Thread = cancelTarget

  private sealed abstract class ThunkState { def result: Runtime }
  private case object Whitehole extends ThunkState { def result = Bottom(sys.error("infinite loop detected")) }
  private class Unevaluated(e: => Runtime) extends ThunkState { def result = e }
  private case class Evaluated(result: Runtime) extends ThunkState

  class Thunk(e: => Runtime, val update: Boolean) extends Runtime {
    private[Runtime] val latch = new java.util.concurrent.CountDownLatch(1)
    private[Runtime] var state : ThunkState = new Unevaluated(e)
    private[Runtime] val pending = new java.util.concurrent.ConcurrentLinkedQueue[Thread]
    def extract[A] = whnf.extract[A]
    override def nf: Runtime = whnf.nf
    override def apply1(arg: Runtime): Runtime = whnf.apply1(arg)
    override def equals(v: Any) = whnf.equals(v)
  }
  object Thunk {
    def apply(t: => Runtime, update: Boolean = true) = new Thunk(t, update)
    def unapply(t: Thunk) = Some(swhnf(t))
  }

  @annotation.tailrec
  def swhnf(r: Runtime, chain: List[Thunk] = Nil): Runtime = {
    import scala.jdk.CollectionConverters._
    // WP-6'S CANCEL CHECK, AT THE HEAD AND ON EVERY CALL.  In the ordinary
    // case it is ONE VOLATILE LOAD and one perfectly predicted null branch;
    // `Thread.currentThread` is reached only while a cancel is armed
    // somewhere in this JVM.
    //
    // IT IS AT THE HEAD AND NOT INSIDE THE `case old =>` BRANCH BELOW, and
    // that is a measured decision rather than a careless one.  The cheaper
    // placement -- inside the branch that actually FORCES something -- was
    // proposed first and then falsified: `json/Encode.scala`'s `spine` walks
    // a list with `while (true) { Runtime.swhnf(cur) ... }`, and on a CYCLIC
    // list (the stdlib's `repeat a = t where t = a :: t`) every thunk it
    // re-reads is ALREADY `Evaluated`, so that loop never enters `case old`
    // at all and a check placed there would never fire.
    val ct = cancelTarget
    if ((ct ne null) && (ct eq Thread.currentThread)) {
      // READ ONLY AFTER THE TARGET TEST PASSED, and tolerant of `null`: the
      // canceller writes `cancelWhy` before `cancelTarget`, but a reader
      // that lands between the two must end the evaluation, not raise an
      // NPE inside the evaluator.
      val c = cancelWhy
      throw (if (c ne null) c else new Cancelled("the evaluation was cancelled", false))
    }
    r match {
      case t : Thunk => t.state match {
        case Evaluated(e) => writeback(e, chain)
        case Whitehole => {
          if (t.pending.isEmpty || !t.pending.asScala.exists(_.getId == Thread.currentThread.getId)) {
            t.latch.await
            swhnf(t, chain)
          } else writeback(Whitehole.result, t :: chain)
        }
        case old => {
          def res = {
            var r : Runtime = null
            try {
              r = old.result
            } catch { case NonFatal(e) => r = Bottom(throw e) }
            r
          }

          if(t.update) {
            t.state = Whitehole
            t.pending add Thread.currentThread
            swhnf(res, t :: chain)
          } else { swhnf(res, chain) }
        }
      }
      case _         => writeback(r, chain)
    }
  }

  @annotation.tailrec
  private def writeback(answer: Runtime, chain: List[Thunk]): Runtime = chain match {
    case t :: ts =>
      t.state = Evaluated(answer)
      t.pending.clear
      t.latch.countDown
      writeback(answer, ts)
    case Nil => answer
  }

  @annotation.tailrec
  def appl(v: Runtime, stk: List[Runtime]): Runtime = stk match {
    case Nil => v
    case a :: stkp => swhnf(v) match {
      case t : Thunk                   => die("PANIC: whnf returned thunk")
      case b : Bottom                  => b
      case Fun(f)                      => appl(f(a), stkp)
      case Prim(f : Function1[Any, _]) => appl(Prim(f(a.extract)), stkp) // our current behavior
      case Box(f : Function1[Any, _])  => appl(Box(f(a.extract)), stkp)
      case f                           => die("PANIC: Cannot apply runtime value " + f + " to " + a)
    }
  }

  def arrEq[A](l: Array[A], r: Array[A]): Boolean =
    l.length == r.length && ((0 until r.length) forall (i => l(i) == r(i)))
  def fun2(f: (Runtime, Runtime) => Runtime) = Fun(a => Fun(b => f(a,b)))
  def fun2(name: String, pf: PartialFunction[Runtime, PartialFunction[Runtime, Runtime]]) = Fun(name,pf.andThen(Fun(name,_)))

  def fun3(f: (Runtime, Runtime, Runtime) => Runtime) = Fun(a => Fun(b => Fun(c => f(a,b,c))))
  def fun3(name: String, pf: PartialFunction[Runtime, PartialFunction[Runtime, PartialFunction[Runtime, Runtime]]]) =
    Fun(name,pf.andThen(fun2(name,_)))

  def fun4(f: (Runtime, Runtime, Runtime, Runtime) => Runtime) = Fun(a => Fun(b => Fun(c => Fun(d => f(a,b,c,d)))))
  def fun4(name: String, pf: PartialFunction[Runtime, PartialFunction[Runtime, PartialFunction[Runtime, PartialFunction[Runtime, Runtime]]]]) =
    Fun(name,pf.andThen(fun3(name,_)))

  def fun5(f: (Runtime, Runtime, Runtime, Runtime, Runtime) => Runtime) = Fun(a => Fun(b => Fun(c => Fun(d => Fun(e => f(a,b,c,d,e))))))
  def fun5(name: String, pf: PartialFunction[Runtime, PartialFunction[Runtime, PartialFunction[Runtime, PartialFunction[Runtime, PartialFunction[Runtime, Runtime]]]]]) =
    Fun(name,pf.andThen(fun4(name,_)))

  def accumProduct(n: Int, vals: List[Runtime] = List()): Runtime =
    if (n == 0) Arr(vals.reverse.toArray)
    else Fun(v => accumProduct(n - 1, v :: vals))

  def accumArgs(k: Int, xs: List[Runtime] = List())(f: List[Runtime] => Runtime): Runtime =
    if (k == 0) f(xs.reverse)
    else Fun (x => accumArgs(k - 1, x :: xs)(f))

  def withRec[B](f : Map[String, Runtime] => B) : Runtime => B =
    v => v.whnf match {
      case Rec(m) => f(m)
      case x => die("expected record instead of " + x)
    }

  def fieldFun(f: String => Runtime): Runtime = Fun (v =>
    v.nfMatch("field") {
      case Data(Global(_,n,_), _) => f(n)
    })

  def fieldTup(f: (String, PrimT) => Runtime) = Fun (v =>
    v.nfMatch("field") {
      case Data(Global(_,n,_), ts) => f(n, ts(0).extract[PrimT])
    })

  def toPrimExpr(rt: Runtime, nullable: Boolean = false): PrimExpr = rt.nf match {
    case Prim(s: String) => StringExpr(nullable, s)
    case Prim(i: Int) => IntExpr(nullable, i)
    // java.sql.Timestamp <: java.util.Date, so check Timestamp first
    case Prim(t: java.sql.Timestamp) => TimestampExpr(nullable, t)
    case Prim(d: java.util.Date) => DateExpr(nullable, d)
    case Prim(b: Boolean) => BooleanExpr(nullable, b)
    case `True` => BooleanExpr(nullable, true)
    case `False` => BooleanExpr(nullable, false)
    case Prim(d: Double) => DoubleExpr(nullable, d)
    case Prim(b: Byte) => ByteExpr(nullable, b)
    case Prim(s: Short) => ShortExpr(nullable, s)
    case Prim(l: Long) => LongExpr(nullable, l)
    case Prim(u: java.util.UUID) => UuidExpr(nullable, u)
    case NullableValue(Right(rt2)) => toPrimExpr(rt2, true).withNull
    case NullableValue(Left(pt)) => NullExpr(pt)
    // may need to add some smarts here to create a NullExpr
    case o => die("Panic: toPrimExpr: Unsupported primitive: " + o)
  }

  def fromPrimExpr(e: PrimExpr): Runtime = {
    val withoutNull = e match {
      case NullExpr(_) => Bottom(throw new RuntimeException("Null encountered for non-nullable column."))
      case BooleanExpr(_, b) => if (b) True else False
      case _           => Prim(e.value)
    }
    if (e.typ.nullable)
      e match {
        case NullExpr(p) => Data(Global("Builtin","Null",Idfix), Array(Prim(p)))
        case _ => Data(Global("Builtin","Some",Idfix), Array(withoutNull))
      }
    else withoutNull
  }

  def accumData(name: Global, vals: List[Runtime], n: Int): Runtime =
    if (n == 0) Data(name, vals.reverse.toArray)
    else Fun(v => accumData(name, v :: vals, n - 1))

  /** The runtime of a generated record-field selector (named constructor
    * fields, tracker/JSON-API-DESIGN.md 3.1 item 2).  The representation
    * stays POSITIONAL, so reading a field is projecting one argument;
    * `sites` maps each constructor that carries the field to its index.
    *
    * A constructor of the same type that does NOT carry the field is
    * well-typed and can reach here (`data Shape = Circle { radius :
    * Double } | Dot`, `radius Dot`), so the miss is a named Bottom rather
    * than `whnfMatch`'s generic "Panic: unexpected runtime value" -- the
    * message has to say which constructor and which field. */
  def selectData(field: String, sites: Map[Global, Int]): Runtime =
    Fun(v => swhnf(v) match {
      case Data(g, args) => sites.get(g) match {
        case Some(i) => args(i)
        case None    => Bottom(sys.error(g.string + " has no field " + field))
      }
      case b: Bottom => b
      case other     => Bottom(sys.error("field " + field + ": not a data value: " + other))
    })

  def recAsRecord(r: Rec): Record = r match {
    case Rec(tup) => tup.mapValues( toPrimExpr(_, false) ).toMap
  }

  object RecAsRecord {
    def unapply(r: Rec): Some[Record] = Some(recAsRecord(r))
  }

  def buildRelation(ts: List[Runtime]): Runtime = ts match {
    case Nil => EmptyRel
    case (_ :: _) => {
      try {
        val rs = ts.map(x => {
          x.nf match {
            case RecAsRecord(r) => r
            case o => die("Panic: buildRelation: Expected a record. Found: " + o)
          }
        })
        Rel(ExtRel(SmallLit(rs.toNel.get), ""))
      } catch { case NonFatal(e) => Bottom(throw e) }
    }
  }

  def buildMem(ts: List[Runtime]): Runtime = ts match {
    case Nil => EmptyRel
    case (_ :: _) => {
      try {
        Rel(ExtMem( Literal.toLit(ts.map(x => x.nf match {
          case RecAsRecord(r) => r
          case o => die("Panic: buildRelation: Expected a record. Found: " + o)
        })).get))
      } catch { case NonFatal(e) => Bottom(throw e) }
    }
  }
}

object NullableValue {
  def unapply(rt: Runtime): Option[Either[PrimT,Runtime]] = rt match {
    case Data(Global("Builtin","Null",Idfix), p) => p(0).whnf match {
      case Prim(pt: PrimT) => Some(Left(pt))
      case o => die("Null data constructor contained a non PrimT value: " + o)
    }
    case Data(Global("Builtin","Some",Idfix), p) => Some(Right(p(0))) // TODO: this is actually not in lib, we need to change this to Prelude when it exists
    case _ => None
  }
}
