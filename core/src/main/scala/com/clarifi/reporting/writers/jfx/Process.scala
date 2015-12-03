package com.clarifi.reporting.writers.jfx

import java.util.concurrent.{ ScheduledThreadPoolExecutor, ThreadFactory }
import scalaz.{Applicative, Monad, Need}
import scalaz.concurrent.{Promise, Strategy}

import com.clarifi.reporting.Run

/** Control of threaded operations specific to JavaFX.  For example,
  * `lazyFill` has a special relationship with the JavaFX application
  * thread.
  */
object Process {

  def promiseMonad(S: Strategy): Monad[Promise] = new Monad[Promise] {
    def point[A](a: => A) = scalaz.concurrent.Promise(a)(S)
    override def map[A,B](fa: Promise[A])(f: A => B): Promise[B] = fa map f
    def bind[A,B](fa: Promise[A])(f: A => Promise[B]): Promise[B] = fa flatMap f
  }

  private[jfx] def newDaemonThreadFactory(threadLabel: String) = new ThreadFactory {
    def newThread(r: Runnable) = {
      val t = new Thread(r, threadLabel)
      t.setDaemon(true)
      t
    }
  }

  private val taskPoolThreadFactory  = newDaemonThreadFactory("Java FX Task Pool daemon thread")
  private val fetchPoolThreadFactory = newDaemonThreadFactory("Java FX Fetch Pool daemon thread")
  private val setPoolThreadFactory   = newDaemonThreadFactory("Java FX Set Pool daemon thread")

  val taskPool = new ScheduledThreadPoolExecutor(1, taskPoolThreadFactory)
  private[reporting]
  implicit val Promise = promiseMonad(Strategy.Executor(taskPool))

  /** A pool for running relational and other queries, building
    * `Record`s for their results.
    *
    * @see `observableList`
    */
  private[reporting] val fetchPool =
    new ScheduledThreadPoolExecutor(1, fetchPoolThreadFactory)
  /** A pool for filling lists.
    *
    * @see `observableList`
    */
  private[reporting] val setPool =
    new ScheduledThreadPoolExecutor(2, setPoolThreadFactory)

  /** Shortcut for producing runnables. */
  @inline def runnable(f: => Unit) = new Runnable{ def run = f }
}
