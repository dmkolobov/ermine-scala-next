package com.clarifi.reporting

/** A G-algebra for "running" a value in G
  * where G is usually some monad.
  *
  * @note identity law: run(fa) == run(run(fa).point[G]) | Applicative[G]
  * @note distributive law: run(f)(run(fa)) == run(fa <*> f) | Apply[G]
  */
trait Run[G[_]] {
  def run[A](a: G[A]): A
}

object Run {
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
