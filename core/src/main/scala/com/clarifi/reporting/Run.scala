package com.clarifi.reporting

/** The ability to suspend the computation of any `A` if it comes from
  * `G`.
  *
  * @note law: suspend(ga) map (_.value) == ga | Functor[G]
  */
trait Suspendable[G[_]] {
  import Suspendable._
  def suspend[A](a: G[A]): G[O[A]]
  def background[A](a: G[A]): G[O[A]] = suspend(a)
}

abstract class InstrumentedName[+A] {
  val creationTime = System.nanoTime
  val instanceNumber = InstrumentedName.numInstances
/*  
  if (
       instanceNumber == 14 ||
       instanceNumber == 295 ||
       instanceNumber == 30 ||
       instanceNumber == 359 ||
       instanceNumber == 71 ||
       instanceNumber == 366 ||
       instanceNumber == 87 ||
       instanceNumber == 390 ||
       instanceNumber == 103 ||
       instanceNumber == 199 ||
       instanceNumber == 217 ||
       instanceNumber == 846 ||
      false) {
      println("InstrumentedName.init with DB access: " + instanceNumber)
      java.lang.Thread.dumpStack
  }

  if (instanceNumber == 2 || instanceNumber == 20 || instanceNumber == 200) {
      println("InstrumentedName.init NO DB access: " + instanceNumber)
      java.lang.Thread.dumpStack
  }     
*/  
  var accessTime: Long = 0

  def value: A
  def >>=[B](f: A => B) : B = f(value)
  def flatMap[B](f: A => B) : B = f(value)
  def map[B](f: A => B): InstrumentedName[B] = InstrumentedName(f(value))

  def delayTimeNano: Long = {
    val t = if (accessTime == 0) 0
            else (accessTime - creationTime)
//    println(">> delayTimeNano[" + instanceNumber + "] = " + t + " ns")
    t
  }
}

object InstrumentedName {
  var accumulatedAccessDelay: Long = 0
  var numInstances: Long = 0
  var currentObjectDelay: Long = 0
  var currentObjectNumber: Long = 0
  
  def apply[A](a: => A) = {
    numInstances = numInstances + 1
    new InstrumentedName[A] {
      def value = {
        if (accessTime == 0) {
          accessTime = System.nanoTime
          accumulatedAccessDelay = accumulatedAccessDelay + delayTimeNano
        }
        currentObjectDelay = delayTimeNano
        currentObjectNumber = instanceNumber
        
        a
      }
    }
  }
  
  def unapply[A](v: InstrumentedName[A]): Option[A] = Some(v.value)

  implicit val nameMonad: scalaz.Monad[InstrumentedName] = new scalaz.Monad[InstrumentedName] {
    def bind[A,B](v: InstrumentedName[A])(f: A => InstrumentedName[B]): InstrumentedName[B] = 
      f(v.value)
    def point[A](a: => A) = InstrumentedName(a)
  }

}

object Suspendable {
  /** Retrieve the implicit `Suspendable[G]`. */
  @inline def apply[G[_]](implicit G: Suspendable[G]): Suspendable[G] = G

  /** The suspension representable functor currently in use.  Other
    * candidates are Function0, Need, Callback, (()) => ?.  Here mainly
    * to make refactoring easier if we decide `Name` isn't good
    * enough.
    */
  type O[+A] = InstrumentedName[A]

  var i: Int = 0
  
  def O[A](a: => A): O[A] = {
//    if (i % 10 == 0) java.lang.Thread.dumpStack
    i = i + 1
    InstrumentedName(a)
  }
    
    
  /** Invoke the `suspend` method on the `Suspendable` instance in
    * scope.
    */
  @inline def suspendG[G[_], A](ga: G[A])(implicit G: Suspendable[G])
      : G[O[A]] =
    G suspend ga

  object Syntax {
    implicit final class `Suspend syntax`[G[_], A](val _self: G[A]) extends AnyVal {
      @inline def suspendG(implicit G: Suspendable[G]): G[O[A]] = G suspend _self
    }
  }
}

/** A G-algebra for "running" a value in G where G is usually some
  * monad.
  *
  * Scala doesn't have DefaultSignatures, but you can usually start
  * with:
  *
  * {{{
  *   def suspend[A](ga: G[A]): G[Suspendable.O[A]] =
  *     Run.runSuspendGM(this, ga)
  * }}}
  *
  * @note identity law: run(fa) == run(run(fa).point[G]) | Applicative[G]
  * @note distributive law: run(f)(run(fa)) == run(fa <*> f) | Apply[G]
  */
trait Run[G[_]] extends Suspendable[G] {
  def run[A](a: G[A]): A
}

trait BGSuspendableGen[A] {
  def create(=> A): Suspendable.O[A]
}

object Run {
  /** Retrieve the implicit `Run[G]`. */
  @inline def apply[G[_]](implicit G: Run[G]): Run[G] = G

  import scalaz.{Applicative, Distributive, Functor}

  type BGO[A] = (=> A) => Suspendable.O[A]
  
  var bgSuspendableO: Option[BGO[A]]
  
  /** A default definition for `Run#suspend` built on `#run` and
    * `G.point`.
    */
  def runSuspendGM[G[_], A](R: Run[G], ga: G[A])(implicit G: Applicative[G])
      : G[Suspendable.O[A]] =
    G.point(Suspendable.O(R.run(ga)))

    
  
  /** For all Runs of applicative G, there is a half-legal distributive
    * instance, that lifts 'run' into the functor and wraps the result
    * with G.point.  Better that than the Function1 distributive. –SMRC
    */
  def impliedDistributive[G[_]](R: Run[G])(implicit G: Applicative[G])
      : Distributive[G] =
    new Distributive[G] {
      override def map[A, B](fa: G[A])(f: A => B) = G.map(fa)(f)
      override def distributeImpl[H[_], A, B](fa: H[A])(f: A => G[B])
                                 (implicit H: Functor[H]): G[H[B]] =
        G.point(H.map(fa)(f andThen R.run))
    }

  /** Runs over limited resources are still required to satisfy the
    * identity law.  This can help in such cases; it also avoids a
    * great deal of resource allocations, provided that you understand
    * that the same resource may be used in interleaving ways within a
    * thread.
    *
    * A good choice for `Resource` for `DB` might be
    * `java.sql.Connection`, for example.
    *
    * @author AAG
    * @author SMRC
    */
  abstract class ThreadLocal[G[_]] extends ThreadLocalDC[G] {
    protected def acquire(): Resource
    protected def release(r: Resource): Unit

    protected final def freshResource[A](f: Resource => A): A = {
      val conn = acquire()
      try {f(conn)} finally { release(conn) }
    }
  }

  /** A variant of `ThreadLocal` that permits the implementer to supply
    * a full dynamic context instead of `acquire` and `release`
    * methods.
    */
  abstract class ThreadLocalDC[G[_]] extends Run[G] {
    private[this] val tl = new java.lang.ThreadLocal[Option[Resource]] {
      override def initialValue = None
    }

    type Resource

    /** Given an acquired resource, use it to run `a`. */
    protected def runR[A](a: G[A], r: Resource): A

    /** Acquire a resource, invoke `f`, release it, and return `f`'s result. */
    protected def freshResource[A](f: Resource => A): A

    final def run[A](a: G[A]): A = tl.get map (runR(a, _)) getOrElse {
      freshResource{conn =>
        try {
          tl set Some(conn)
          runR(a, conn)
        }
        finally {tl set None}
      }
    }
  }
}
