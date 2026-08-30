package com.clarifi.reporting
package ermine.session

import scalaparsers.{Document, Death, Supply}
import scalaparsers.Document.{ text, vsep }
import java.util.concurrent.{ Callable, ExecutorService, Executors, Future }
import java.util.Date
import scalaz.Scalaz._

/** A forked session evaluation.
  *
  * This used to sit on `scalaz.concurrent.Promise`, which scalaz dropped after
  * 7.0 and which has no Scala 3 build; the pool below reproduces the same
  * semantics (evaluate on another thread, block on `get`).
  */
case class SessionTask[A](env: SessionEnv, future: Future[Either[Death,A]])

object SessionTask {
  private val pool: ExecutorService =
    Executors.newCachedThreadPool { (r: Runnable) =>
      val t = new Thread(r, "ermine-session-task")
      t.setDaemon(true)
      t
    }

  def fork[A](p: (SessionEnv, Supply) => A)(implicit s: SessionEnv, vs: Supply): SessionTask[A] = {
    val sp = s.copy
    val vsp = vs.split
    SessionTask(
      sp,
      pool.submit(new Callable[Either[Death,A]] {
        def call: Either[Death,A] =
          try { Right(p(sp,vsp)) }
          catch { case r : Death => Left(r) }
      })
    )
  }

  // @throws Death
  def join[A](task: SessionTask[A])(implicit s: SessionEnv): A =
    task.future.get match {
      case Left(e)  => throw Death(e.error, e)
      case Right(a) =>
        s += task.env
        a
    }

  def joins[A](tasks: List[SessionTask[A]])(implicit s: SessionEnv): List[A] = {
    val (failures, successes) = tasks.map(t => (t.future.get, t.env)).partition { _._1.isLeft }
    if (failures.isEmpty)
      successes.foldRight(List[A]()) {
        case ((Right(x), sp), xs) =>
          s += sp
          x :: xs
        case _ => sys.error("joins: the impossible happened")
      }
    else {
      val failDocs = failures.collect {
        case (Left(Death(e,_)), _) => e
      }
      throw Death(vsep(failDocs))
    }
  }
}
