package com.clarifi.reporting.ermine

/** Perform strongly connected component analysis using Tarjan's algorithm.
  *
  * More or less a transliteration of:
  *
  * http://en.wikipedia.org/wiki/Tarjan%27s_strongly_connected_components_algorithm
  *
  * @author EAK
  */

class Component(val id: Int) {
  var index: Option[Int] = None
  var lowlink: Int = 0
}

object SCC {
  // scala> tarjan(List(0,1,2), { case 0 => List(0,1) case 1 => List(1,0) case 2 => List(0) })
  // res1: List[Set[Int]] = List(Set(2), Set(0, 1))
  def tarjan(vertices: List[Int])(successors: Int => List[Int]): List[Set[Int]] = {
    val comps = vertices.map(id => id -> new Component(id)).toMap
    var output : List[Set[Int]] = List()
    var stack: List[Component] = List()
    var ix:    Int = 0
    def connect(v: Component): Unit = {
      v.index = Some(ix)
      v.lowlink = ix
      ix = ix + 1
      stack = v :: stack
      successors(v.id).foreach { i =>
        val w = comps(i)
        w.index match {
          case None =>
            connect(w)
            v.lowlink = v.lowlink min w.lowlink
          case Some(j) =>
            if (stack.exists(_.id == w.id))
              v.lowlink = v.lowlink min j
        }
      }
      if (v.lowlink == v.index.get) {
        val (comp, h::rhs) = stack.span(_.id != v.id)
        output = (h :: comp).map(_.id).toSet :: output
        stack = rhs
      }
    }
    /* E11c (`Constraints.GenRules.solveDet`, DEFAULT OFF).  `comps` is an immutable
     * `Map[Int, Component]` keyed by a variable id, and `Int.hashCode` is the id, so
     * `comps.foreach` walks a CHAMP trie whose shape is `improve(id)`: the order in
     * which Tarjan picks its DFS ROOTS, and therefore the order of the components it
     * returns, is a function of the ABSOLUTE id base.  Under ON the driver walks the
     * vertex list it was handed instead -- the callers pass it in SOURCE order.
     * Tarjan is correct for ANY root order (the roots only decide which of several
     * valid topological orders of the condensation comes out), so nothing here
     * changes a dependency; `vertices` may repeat an id, which the `index` test
     * already absorbs. */
    if (Constraints.GenRules.solveDet)
      vertices.foreach { i => val v = comps(i); if (!v.index.isDefined) connect(v) }
    else
      comps.foreach { case (k,v) => if (!v.index.isDefined) connect(v) }
    output
  }


}

// vim: set ts=4 sw=4 et:
