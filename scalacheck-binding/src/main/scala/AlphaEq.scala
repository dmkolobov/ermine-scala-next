package com.clarifi.reporting

import com.clarifi.reporting.ermine.{ AppT, Arrow, ConcreteRho, Exists, Forall,
                                      Memory, Part, ProductT, Type, VarT }
import com.clarifi.reporting.ermine.tools.G1Compare

/** ALPHA-EQUIVALENCE for the test sweeps, in one place (LSP Stage 4,
  * item 7.2 -- it was inside `TestTolerantCheck`'s 6.6 sweep, and 7.2's
  * corpus sweep needs the same comparator).
  *
  * `G1Compare.alphaEq` is the G1 gate's comparator, and it is
  * INCOMPLETE: `matchMultiset` keeps only the FIRST bijection each
  * constraint admits, so a permuted row-constraint set whose first
  * pairing paints the bijection into a corner is reported unequal even
  * when a consistent pairing exists (`Relation.e`'s `&`).  `loose`
  * returns EVERY bijection lazily, so the search backtracks properly and
  * stops at the first success; it is strictly more permissive than
  * `G1Compare.alphaEq` and agrees with it everywhere that one succeeds.
  *
  * The repair lives HERE and not in `G1Compare`: that comparator is a
  * gate tool and its verdicts are not a test's to move.
  */
object AlphaEq {

  type Bij = G1Compare.Bij
  val empty: Bij = G1Compare.Bij.empty

  /** The gate comparator, verbatim. */
  def strict(a: Type, b: Type): Boolean = G1Compare.alphaEq(a, b, empty).isDefined

  /** The complete one. */
  def loose(a: Type, b: Type): Boolean = aeq(a, b, empty).nonEmpty

  /** Either: the answer a sweep wants. */
  def same(a: Type, b: Type): Boolean = strict(a, b) || loose(a, b)

  def aeq(a: Type, b: Type, e: Bij): LazyList[Bij] = (a, b) match {
    case (VarT(x), VarT(y)) =>
      e.tv get x.id match {
        case Some(m) => if (m == y.id) LazyList(e) else LazyList.empty
        case None =>
          if (e.tv.valuesIterator contains y.id) LazyList.empty
          else if (e.open1(x.id) && e.open2(y.id)) LazyList(e.bindT(x.id, y.id))
          else if (x.id == y.id) LazyList(e)
          else if (x.name.isDefined && x.name == y.name) LazyList(e)
          else LazyList.empty
      }
    case (AppT(f1, a1), AppT(f2, a2))             => aeq(f1, f2, e).flatMap(aeq(a1, a2, _))
    case (Arrow(_), Arrow(_))                     => LazyList(e)
    case (ProductT(_, n1), ProductT(_, n2))       => if (n1 == n2) LazyList(e) else LazyList.empty
    case (ConcreteRho(_, f1), ConcreteRho(_, f2)) => if (f1 == f2) LazyList(e) else LazyList.empty
    case (c1: Type.Con, c2: Type.Con)             => if (c1.name == c2.name) LazyList(e) else LazyList.empty
    case (f1: Forall, f2: Forall) =>
      if (f1.ks.length != f2.ks.length || f1.ts.length != f2.ts.length) LazyList.empty
      else {
        val e2 = e.copy(tv = e.tv ++ f1.ts.map(_.id).zip(f2.ts.map(_.id)),
                        kv = e.kv ++ f1.ks.map(_.id).zip(f2.ks.map(_.id)))
        aeq(f1.constraints, f2.constraints, e2).flatMap(aeq(f1.body, f2.body, _))
      }
    case (x1: Exists, x2: Exists) =>
      if (x1.xs.length != x2.xs.length || x1.constraints.length != x2.constraints.length)
        LazyList.empty
      else {
        val e2 = e.copy(open1 = e.open1 ++ x1.xs.map(_.id), open2 = e.open2 ++ x2.xs.map(_.id))
        multi(x1.constraints, x2.constraints, e2).map(_.copy(open1 = e.open1, open2 = e.open2))
      }
    case (p1: Part, p2: Part) => aeq(p1.lhs, p2.lhs, e).flatMap(multi(p1.rhs, p2.rhs, _))
    case (Memory(_, b1), Memory(_, b2)) => aeq(b1, b2, e)
    case _ => LazyList.empty
  }
  def multi(cs1: List[Type], cs2: List[Type], e: Bij): LazyList[Bij] = cs1 match {
    case Nil => if (cs2.isEmpty) LazyList(e) else LazyList.empty
    case c1 :: rest =>
      cs2.indices.to(LazyList).flatMap(j =>
        aeq(c1, cs2(j), e).flatMap(e2 => multi(rest, cs2.patch(j, Nil, 1), e2)))
  }
}
