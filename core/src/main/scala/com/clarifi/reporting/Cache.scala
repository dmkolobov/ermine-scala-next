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
  final class SetAssociativeCache[A:ClassManifest](identifier: String, shift: Int) {
    private[this] val mask: Int = (1 << shift) - 1
    private[this] val vals: Array[Array[A]] = new Array(1 << shift)

    def canonicalize(v: A): A = {
      val bucket = v.hashCode & mask
      Option(vals(bucket)) match {
        case Some(cached) =>
          Option(cached(0)) match {
            case Some(c0) =>
              if(c0 == v) c0
              else Option(cached(1)) match {
                case Some(c1) if c1 == v =>
                  cached(0) = c1
                  cached(1) = c0
                  c1
                case _ =>
                  logger.debug(identifier + " ejecting: " + cached(1))
                  cached(0) = v
                  cached(1) = c0
                  v
              }
            case None =>
              cached(0) = v
              v
          }
        case None =>
          val cached = new Array(2)
          vals(bucket) = cached
          cached(0) = v
          v
      }
    }
  }
}
