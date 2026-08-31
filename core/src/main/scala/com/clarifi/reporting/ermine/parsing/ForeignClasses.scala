package com.clarifi.reporting.ermine.parsing

import scala.jdk.CollectionConverters._
import com.clarifi.reporting.ermine.syntax.ForeignClass
import scalaparsers.Pos

/** Foreign-class reflection lookup with a process-wide cache.  Extracted
  * from the fused StatementParsers when the grammar retired (post-G1 D3)
  * — the renamer and NewPipeline resolve `foreign data "…"` class names
  * through it. */
object ForeignClasses {
  // a concurrent map gives thread-safe caching
  val classMap = new java.util.concurrent.ConcurrentHashMap[String, Class[?]]().asScala

  def classLookup(p: Pos, s: String): Either[Exception, ForeignClass] =
    classMap.get(s) match {
      case Some(c) => Right(ForeignClass(p, c))
      case None    =>
        val c = try { Right(Class.forName(s)) }
                catch { case e: Exception => Left(e) }
        c.right.map { c =>
          classMap += (s -> c)
          ForeignClass(p, c)
        }
    }
}
