package com.clarifi.reporting.ermine.parsing

import scala.jdk.CollectionConverters._
import com.clarifi.reporting.ermine.syntax.ForeignClass
import scalaparsers.Pos

/** The throwables a LOAD or a CHECK is allowed to turn into a diagnostic
  * (LSP-FFI, review finding P-1).
  *
  * `scala.util.control.NonFatal` is almost this set, but it treats the
  * whole `LinkageError` family as fatal — and that family is precisely
  * what a stale or partial classpath produces: `NoClassDefFoundError`
  * from a missing supertype, from a member signature naming an absent
  * class, or `ExceptionInInitializerError` from a static initialiser.
  * Letting one escape a check means the editor publishes NOTHING for the
  * file, which is worse than any diagnostic.  So: catch everything except
  * the three that must never be swallowed — `VirtualMachineError`
  * (`OutOfMemoryError`, `StackOverflowError`), an interrupt, and scala's
  * non-local control flow.  (`ThreadDeath` is not listed: it has been
  * unthrowable since JDK 20 and referencing it is a deprecation warning.)
  */
object Recoverable {
  def unapply(e: Throwable): Option[Throwable] = e match {
    case _: VirtualMachineError                 => None
    case _: InterruptedException                => None
    case _: scala.util.control.ControlThrowable => None
    case _                                      => Some(e)
  }

  /** Run a reflective lookup, keeping whatever it threw. */
  def attempt[A](a: => A): Either[Throwable, A] =
    try Right(a) catch { case Recoverable(e) => Left(e) }
}

/** Foreign-class reflection lookup with a process-wide cache.  Extracted
  * from the fused StatementParsers when the grammar retired (post-G1 D3)
  * — the renamer and NewPipeline resolve `foreign data "…"` class names
  * through it. */
object ForeignClasses {
  // a concurrent map gives thread-safe caching
  val classMap = new java.util.concurrent.ConcurrentHashMap[String, Class[?]]().asScala

  /** FAILURES are cached too (LSP-FFI, review finding P-5).  A class that
    * is not on the classpath cannot appear on it later — the JVM's
    * application loader is fixed at startup and nothing here installs
    * another — so a `Left` is as permanent as a `Right`.  Without this,
    * every editor re-check of a fork module re-ran `Class.forName` once
    * per missing binding, and each of those walks the whole classpath
    * before throwing; at a 300 ms debounce that is the same work over and
    * over.  (A REPL `:reload` re-reads sources, not the classpath, so it
    * wants the cached answer too.) */
  val failureMap = new java.util.concurrent.ConcurrentHashMap[String, Throwable]().asScala

  /** `Class.forName` fails in TWO ways, and only one of them is an
    * Exception (LSP-FFI L1 kind 2): a class that is absent throws
    * `ClassNotFoundException`, while a class that is PRESENT but whose
    * own supertype is not throws `NoClassDefFoundError` — an `Error`,
    * which the old `case e: Exception` let escape uncaught, crashing
    * the loader in both batch and editor modes instead of reporting
    * "error loading '…'".  `Recoverable` is the catch set. */
  def classLookup(p: Pos, s: String): Either[Throwable, ForeignClass] =
    classMap.get(s) match {
      case Some(c) => Right(ForeignClass(p, c))
      case None    => failureMap.get(s) match {
        case Some(e) => Left(e)
        case None    => Recoverable.attempt(Class.forName(s)) match {
          case Right(c) => classMap += (s -> c); Right(ForeignClass(p, c))
          case Left(e)  => failureMap += (s -> e); Left(e)
        }
      }
    }
}
