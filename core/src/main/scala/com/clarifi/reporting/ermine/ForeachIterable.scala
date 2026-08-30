package com.clarifi.reporting
package ermine

/** A collection defined by `foreach` alone, as Scala 2.11's `Traversable` was.
  *
  * 2.13 replaced `Traversable` with `Iterable`, whose abstract member is
  * `iterator` rather than `foreach`. The types here (`Vars`, the constraint
  * solver's priority queue, the relational traversals) are naturally written as
  * a `foreach`: they walk a structure and hand out elements without ever
  * materialising it. This bridges the two — subclasses still implement
  * `foreach`, and `iterator` falls out of it.
  *
  * Subclasses must `override def foreach`, since `Iterable` supplies a concrete
  * one; leaving it off would recurse through the default `iterator`.
  */
trait ForeachIterable[+A] extends Iterable[A] {
  def iterator: Iterator[A] = {
    val b = Vector.newBuilder[A]
    foreach(b += _)
    b.result().iterator
  }
}
