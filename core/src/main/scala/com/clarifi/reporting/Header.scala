package com.clarifi.reporting

import scalaz.std.list._
import scalaz.std.option._
import scalaz.syntax.traverse._

/** Functions for working with `Header`s. */
object Header {
  /** Alias for type `Header`. */
  type T = Header

  /** Special uses only; most should sort Headers. */
  type Ordered = List[(ColumnName, PrimT)]

  def proj(h: Header): Projection =
    h map { case (n, t) => Attribute(n, t) -> Op.ColumnValue(n, t) }

  def sup(h1: Header, h2: Header): Option[Header] =
    if (h1.keySet != h2.keySet) None
    else h1.keySet.toList.traverse(k => (h1(k) sup h2(k)).map((k,_))).map(_.toMap)

  val empty: Header = Map()

  /**
   * Converts a TypeTag to a Header.
   */
  def fromTypeTag(t: TypeTag): Header = t.fold(e => sys.error(e.list.mkString("\n")), s => s)
}
