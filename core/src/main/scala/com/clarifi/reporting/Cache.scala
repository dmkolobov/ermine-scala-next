package com.clarifi.reporting

import org.apache.log4j.Logger

object Cache {
  private[this] def logger = Logger getLogger this.getClass

  /**
   * Implements a cache that will store canonical instances
   * of a type, for the purpose of using less memory on
   * functionally identical values.
   *
   * shift specifies the size of the cache: 2^shift
   * identifier is used in logging messages
   */
  final class SetAssociativeCache[A:reflect.ClassTag](identifier: String, shift: Int,
                                                      same: (A, A) => Boolean = (a: A, b: A) => a == b) {
    private[this] val mask: Int = (1 << shift) - 1
    private[this] val vals: Array[Array[A]] = new Array(1 << shift)

    // `same` decides which cached instance may stand in for `v`.  It defaults to `==`,
    // but a type whose `==` is coarser than its identity (SQL audit P2: `PrimExpr`
    // ignores the nullable flag and string case) passes a field-wise comparison, or the
    // cache would hand back a DIFFERENT value for an equal one.
    def canonicalize(v: A): A = {
      val bucket = v.hashCode & mask
      Option(vals(bucket)) match {
        case Some(cached) =>
          Option(cached(0)) match {
            case Some(c0) =>
              if(same(c0, v)) c0
              else Option(cached(1)) match {
                case Some(c1) if same(c1, v) =>
                  cached(0) = c1
                  cached(1) = c0
                  c1
                case _ =>
                  logger.trace(identifier + " ejecting: " + cached(1))
                  cached(0) = v
                  cached(1) = c0
                  v
              }
            case None =>
              cached(0) = v
              v
          }
        case None =>
          val cached = new Array[A](2)
          vals(bucket) = cached
          cached(0) = v
          v
      }
    }
  }
}
