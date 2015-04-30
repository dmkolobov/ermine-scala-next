package com.clarifi.reporting
package relational

import scalaz.{-\/, \/-, Bifoldable, Coproduct, Equal, Foldable,
               Monoid, NonEmptyList, OneAnd}
import scalaz.syntax.equal._
import scalaz.syntax.monoid._
import scalaz.Coproduct._
import scalaz.NonEmptyList._
import scala.collection.immutable.IndexedSeq

sealed abstract class Mem[+R, +M] {
  def bimap[S, N](f: R => S, g: M => N): Mem[S, N]
  def map[N](g: M => N): Mem[R, N] = bimap(x => x, g)
  def mapRel[S](f: R => S): Mem[S, M] = bimap(f, x => x)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]): Mem[S, N]
  def substPrg[S, N](f: R => SqlPrg, g: M => MemPrg): Mem[Nothing,Nothing] =
    subst(f andThen (sqlPrg => RelEmpty(sqlPrg.h)),
          g andThen (memPrg => EmptyRel(memPrg.h)))
  def flatMap[S >: R, N](f: M => Mem[S, N]): Mem[S, N] = subst(VarR(_), f)
  def flatRel[S, N >: M](f: R => Relation[N, S]): Mem[S, N] = subst(f, VarM(_))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z): Z
  def foreach(f: R => Any, g: M => Any): Unit
  def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N]
  def unquoteR[S >: R, N >: M](p: Object => Option[Relation[N, S]]): Mem[S, N] = unquote(x => None, p)
  def unquoteM[S >: R, N >: M](p: Object => Option[Mem[S, N]]): Mem[S, N] = unquote(p, x => None)
}

case class VarM[+M](v: M) extends Mem[Nothing, M] {
  def bimap[S, N](f: Nothing => S, g: M => N) = VarM(g(v))
  def subst[S, N](f: Nothing => Relation[N, S], g: M => Mem[S, N]) = g(v)
  def bifoldMap[Z: Monoid](f: Nothing => Z, g: M => Z) = g(v)
  def foreach(f: Nothing => Any, g: M => Any) = g(v)
  def unquote[S >: Nothing, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]) = this
}

case class GroupByM[+R, +M](m: Mem[R, M], key: List[Attribute], expr: Mem[R, MLevel[R, M]]) extends Mem[R,M] {
  def bimap[S, N](f: R => S, g: M => N) =
    GroupByM(m bimap (f, g), key, expr bimap (f, (_ bimap (f, g))))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) =
    GroupByM(m subst (f, g), key,
             expr subst (v => f(v).mapMem(x => MPop(VarM(x))),
                         l => VarM(l subst (f, g))))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) =
    m.bifoldMap(f, g) |+| expr.bifoldMap(f, _ bifoldMap (f, g))
  def foreach(f: R => Any, g: M => Any): Unit = {
    m.foreach(f, g)
    expr.foreach(f, _ foreach (f, g))
  }

  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]],
                                       g: Object => Option[Relation[N, S]]): Mem[S, N] =
    GroupByM(m.unquote(f, g), key,
      expr.unquote(x => f(x).map(v => VarM(MPop(v))),
                   x => g(x).map(_.mapMem(v => MPop(VarM(v))))))

  override lazy val hashCode = m.hashCode ^ key.hashCode ^ Mem.fromScope(expr).hashCode
  override def equals(other: Any) = other match {
    case GroupByM(m2, k2, e2) => m == m2 && key == k2 && Mem.fromScope(expr) == Mem.fromScope(e2)
    case _ => false
  }
}
case class AccumulateM[+R, +M](parentIdCol: Attribute, nodeIdCol: Attribute,
                               expr: Mem[R, MLevel[R, M]],
                               leaves: Mem[R, M],
                               tree: Mem[R, M]) extends Mem[R,M] {
  def bimap[S, N](f: R => S, g: M => N) =
    AccumulateM(parentIdCol, nodeIdCol,
                expr bimap (f, (_ bimap (f, g))),
                leaves bimap (f, g), tree bimap (f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) =
    AccumulateM(parentIdCol, nodeIdCol,
                expr subst (v => f(v).mapMem(x => MPop(VarM(x))),
                            l => VarM(l subst (f, g))),
                leaves subst (f, g),
                tree subst (f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) =
    (leaves.bifoldMap(f, g)
       |+| tree.bifoldMap(f, g)
       |+| expr.bifoldMap(f, _ bifoldMap (f, g)))
  def foreach(f: R => Any, g: M => Any): Unit = {
    leaves foreach (f, g)
    tree foreach (f, g)
    expr foreach (f, _ foreach (f, g))
  }

  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]],
                                       g: Object => Option[Relation[N, S]]): Mem[S, N] =
    AccumulateM(
      parentIdCol, nodeIdCol,
      expr.unquote(x => f(x).map(v => VarM(MPop(v))),
                   x => g(x).map(_.mapMem(v => MPop(VarM(v))))),
      leaves.unquote(f,g),
      tree.unquote(f,g))

  override lazy val hashCode = parentIdCol.hashCode ^ nodeIdCol.hashCode ^
                               Mem.fromScope(expr).hashCode ^ leaves.hashCode ^ tree.hashCode
  override def equals(other: Any) = other match {
    case AccumulateM(pid,cid,e2,l2,t2) =>
      pid == parentIdCol && cid == nodeIdCol && Mem.fromScope(expr) == Mem.fromScope(e2) &&
      leaves == l2 && tree == t2
    case _ => false
  }
}
case class ProcessM[+R, +M](transducer: ProcessSymbol, m: Mem[R, M]) extends Mem[R,M] {
  def bimap[S, N](f: R => S, g: M => N) = ProcessM(transducer, m bimap (f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = ProcessM(transducer, m subst (f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = m bifoldMap (f, g)
  def foreach(f: R => Any, g: M => Any) { m foreach (f, g) }
  // default hashcode and equals are fine
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]) =
    ProcessM(transducer, m.unquote(f, g))
}

case class LetM[+R, +M](r: Ext[M, R], expr: Mem[R, MLevel[R, M]]) extends Mem[R,M] {
  def bimap[S, N](f: R => S, g: M => N) = LetM(r bimap (g, f), expr bimap (f, (_ bimap (f, g))))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) =
    LetM(r subst (g, f), expr subst (v => f(v).mapMem(x => MPop(VarM(x))), l => VarM(l subst (f, g))))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) =
    r.bifoldMap(g, f) |+| expr.bifoldMap(f, _ bifoldMap (f, g))
  def foreach(f: R => Any, g: M => Any) { r foreach (g, f) ; expr foreach (f, _ foreach (f, g)) }
  override def equals(other: Any) = other match {
     case LetM(r2, e2) => r == r2 && Mem.fromScope(expr) == Mem.fromScope(e2)
     case _ => false
  }
  override def hashCode: Int = (r, Mem.fromScope(expr)).hashCode
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    LetM(r.unquote(f, g), expr.unquote(x => f(x).map(v => VarM(MPop(v))), x => g(x).map(_.mapMem(v => MPop(VarM(v))))))
}

case class LimitM[+R,+M](
  r: Mem[R,M],
  start: Option[Int],
  end: Option[Int],
  order: List[(String, SortOrder)]
) extends Mem[R,M] {
  def bimap[S, N](f: R => S, g: M => N) = LimitM(r.bimap(f, g), start, end, order)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = r.bifoldMap(f, g)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S,N]) = LimitM(r.subst(f, g), start, end, order)
  def foreach(f: R => Any, g: M => Any) = r.foreach(f, g)
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]],
                                       g: Object => Option[Relation[N, S]]): Mem[S, N] =
    LimitM(r.unquote(f, g), start, end, order)
}
case class FilterM[+R, +M](m: Mem[R, M], p: Predicate) extends Mem[R,M] {
  def bimap[S, N](f: R => S, g: M => N) = FilterM(m.bimap(f, g), p)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = FilterM(m.subst(f, g), p)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = m.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = m.foreach(f, g)
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    FilterM(m.unquote(f, g), p)
}

case class ProjectM[+R, +M](m: Mem[R, M], cols: Map[Attribute, Op]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = ProjectM(m.bimap(f, g), cols)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = ProjectM(m.subst(f, g), cols)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = m.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = m.foreach(f, g)
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    ProjectM(m.unquote(f, g), cols)
}

/** Except gets optimized away in the Optimizer */
case class ExceptM[+R, +M](rel: Mem[R, M], cs: Set[ColumnName]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = ExceptM(rel bimap (f, g), cs)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = ExceptM(rel subst (f, g), cs)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = rel.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    ExceptM(rel.unquote(f, g), cs)
}

/** Rename gets optimized away in the Optimizer */
case class RenameM[+R, +M](rel: Mem[R, M], attr: Attribute, c: ColumnName, promote: Boolean = false) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = RenameM(rel bimap (f, g), attr, c, promote)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = RenameM(rel subst (f, g), attr, c, promote)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = rel bifoldMap (f, g)
  def foreach(f: R => Any, g: M => Any) { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    RenameM(rel.unquote(f, g), attr, c, promote)
}

/** Combine gets optimized away in the Optimizer */
case class CombineM[+R, +M](rel: Mem[R, M], attr: Attribute, op: Op) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = CombineM(rel bimap (f, g), attr, op)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = CombineM(rel subst (f, g), attr, op)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = rel bifoldMap (f, g)
  def foreach(f: R => Any, g: M => Any) { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    CombineM(rel.unquote(f, g), attr, op)
}

case class AggregateM[+R, +M](m: Mem[R, M], c: Attribute, op: AggFunc) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = AggregateM(m.bimap(f, g), c, op)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = AggregateM(m.subst(f, g), c, op)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = m.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = m.foreach(f, g)
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    AggregateM(m.unquote(f, g), c, op)
}

// Set union
case class UnionM[+R, +M](fst: Mem[R, M], snd: Mem[R, M]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = UnionM(fst.bimap(f, g), snd.bimap(f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = UnionM(fst.subst(f, g), snd.subst(f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = fst.bifoldMap(f, g) |+| snd.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = { fst.foreach(f, g); snd.foreach(f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    UnionM(fst.unquote(f, g), snd.unquote(f, g))
}

// Set difference
case class DifferenceM[+R, +M](fst: Mem[R, M], snd: Mem[R, M]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = DifferenceM(fst.bimap(f, g), snd.bimap(f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = DifferenceM(fst.subst(f, g), snd.subst(f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = fst.bifoldMap(f, g) |+| snd.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = { fst.foreach(f, g); snd.foreach(f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    DifferenceM(fst.unquote(f, g), snd.unquote(f, g))
}


case class HashInnerJoin[+R, +M](fst: Mem[R, M], snd: Mem[R, M]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = HashInnerJoin(fst.bimap(f, g), snd.bimap(f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = HashInnerJoin(fst.subst(f, g), snd.subst(f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = fst.bifoldMap(f, g) |+| snd.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = { fst.foreach(f, g); snd.foreach(f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    HashInnerJoin(fst.unquote(f, g), snd.unquote(f, g))
}

case class HashLeftJoin[+R, +M](inner: Mem[R, M], outer: Mem[R, M]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = HashLeftJoin(inner.bimap(f, g), outer.bimap(f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = HashLeftJoin(inner.subst(f, g), outer.subst(f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = inner.bifoldMap(f, g) |+| outer.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = { inner.foreach(f, g); outer.foreach(f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    HashLeftJoin(inner.unquote(f, g), outer.unquote(f, g))
}

case class MergeOuterJoin[+R, +M](fst: Mem[R, M], snd: Mem[R, M]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = MergeOuterJoin(fst.bimap(f, g), snd.bimap(f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = MergeOuterJoin(fst.subst(f, g), snd.subst(f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = fst.bifoldMap(f, g) |+| snd.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = { fst.foreach(f, g); snd.foreach(f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    MergeOuterJoin(fst.unquote(f, g), snd.unquote(f, g))
}

// 'Statically' determined pivot tables. Generates some specified new columns
// using data in an underlying relation.
case class Pivot[+R, +M](
  under: Mem[R, M], // the underlying relation
  pivotKey: Set[ColumnName], // the columns that determine the pivot key
  pivotVals: Set[ColumnName], // the columns that determine the pivot values
  outer: Boolean, // whether NULL is admitted in the output columns of the pivot
  keyMap: Map[Record,(ColumnName, Op, PrimExpr)] // map from pivotKey records to columns and ways to fill them - the PrimExpr is the default 'missing' element, e.g. 0 or "", to avoid NullExprs.
) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) =
    Pivot(under.bimap(f, g), pivotKey, pivotVals, outer, keyMap)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) =
    Pivot(under.subst(f, g), pivotKey, pivotVals, outer, keyMap)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = under.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = { under.foreach(f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    Pivot(under.unquote(f, g), pivotKey, pivotVals, outer, keyMap)
}

// `main` is the query, and `cur` and `hist` are SM tables being joined against `main`
case class AugmentSM[+R, +M](main: Mem[R, M], cur: List[(String, String)], hist: List[(String, String)]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = AugmentSM(main.bimap(f, g), cur, hist)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = AugmentSM(main.subst(f, g), cur, hist)
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = main.bifoldMap(f, g)
  def foreach(f: R => Any, g: M => Any) = main.foreach(f, g)
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    AugmentSM(main.unquote(f, g), cur, hist)
}

// memoize a mem calculation: run it once, and reuse the result
case class MemoMem[+R, +M](rel: Mem[R, M]) extends Mem[R, M] {
  var memo : List[Record] = List()
  def bimap[S, N](f: R => S, g: M => N) = MemoMem(rel bimap (f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = MemoMem(rel subst (f, g))
  def foreach(f: R => Any, g: M => Any) { rel foreach (f, g) }
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = rel.bifoldMap(f, g)
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    MemoMem(rel.unquote(f, g))
}
case class EmbedMem[+R, +M](ext: Ext[M, R]) extends Mem[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = EmbedMem(ext.bimap(g, f))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = EmbedMem(ext.subst(g, f))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = ext.bifoldMap(g, f)
  def foreach(f: R => Any, g: M => Any) = ext.foreach(g, f)
  override def unquote[S >: R, N >: M](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    EmbedMem(ext.unquote(f, g))
}

sealed abstract class HardMem extends Mem[Nothing, Nothing] {
  def bimap[S, N](f: Nothing => S, g: Nothing => N) = this
  def subst[S, N](f: Nothing => Relation[N, S], g: Nothing => Mem[S, N]) = this
  def bifoldMap[Z: Monoid](f: Nothing => Z, g: Nothing => Z) = mzero[Z]
  def foreach(f: Nothing => Any, g: Nothing => Any) = ()
  def header: Header
  override def unquote[S >: Nothing, N >: Nothing](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] = this
}

case class ProcedureCall(args: List[PrimExpr],
                         header: Header,
                         proc: String,
                         namespace: List[String]) extends HardMem

class Literal( r:  OneAnd[ ({type F[X] = Coproduct[IndexedSeq, List, X]})#F, Record]) extends HardMem {
  val header = recordHeader(r.head)
  def nonEmptyListOrIndexedSeq = r
  def seq = r.head +: Literal.listOrIndexedSeqToSeq(r.tail)
  def listOrIndexedSeq = 
    r.tail.run match { case -\/(xs) => leftc( r.head +: xs )
                       case \/-(xs) => rightc( r.head :: xs )
                     }

  def nel: NonEmptyList[Record] = NonEmptyList.nel( r.head
                                                  , r.tail.run match { case -\/(xs) => xs.toList
                                                                       case \/-(xs) => xs
                                                                     }
                                                  )
  def mapCollections[B](f: IndexedSeq[Record] => IndexedSeq[B], g: List[Record] => List[B]) : Literal.ListOrIndexedSeq[B] = {
    val xs = listOrIndexedSeq
    Coproduct( xs.run.bimap(f,g) )
  }

}

object Literal {
  // type Coproduct f g a = Either (f a) (g a)
  // so this is an Either[IndexedSeq[A],List[A]]
  type ListOrIndexedSeq[X] = Coproduct[IndexedSeq, List, ?][X]
  type NonEmptyListOrIndexedSeq = OneAnd[ ListOrIndexedSeq, Record]
  
  implicit def listOrIndexedSeqFoldable( implicit f: Foldable[Coproduct[IndexedSeq, List, ?]]) = f

  def toLit(seq: IndexedSeq[Record] ): Option[Literal] = seq.headOption match {
    case None => None
    case Some(h) => Some(Literal(h, seq.tail))
  }
  def toLit(seq: List[Record] ): Option[Literal] = seq.headOption match {
    case None => None
    case Some(h) => Some( Literal( nel(h, seq.tail)))
  }

  def apply(rs: NonEmptyList[Record]) =
    new Literal( OneAnd(rs.head, (rightc(rs.tail) : ListOrIndexedSeq[Record] ))) 
  
  def apply(r: Record, rs: IndexedSeq[Record]) =
    new Literal( OneAnd(r, (leftc(rs) : ListOrIndexedSeq[Record] )))
  
  def listOrIndexedSeqToSeq[X]( l : ListOrIndexedSeq[X]): Seq[X] = {
    l.run match { case -\/(xs) => xs
                  case \/-(xs) => xs
                }
  }

  def unapply( l: Literal) : Option[(Record, Seq[Record])] = {
    val o = l.nonEmptyListOrIndexedSeq
    Some( ( o.head
          , listOrIndexedSeqToSeq( o.tail )
          )
        )
  } 
}

case class EmptyRel(header: Header) extends HardMem
case class QuoteMem(n: Object) extends HardMem {
  def header = sys.error("Panic: asked for the header of a quote")
  override def unquote[S >: Nothing, N >: Nothing](f: Object => Option[Mem[S, N]], g: Object => Option[Relation[N, S]]): Mem[S, N] =
    f(n) match {
      case None => this
      case Some(x) => x
    }
}

sealed abstract class MLevel[+R, +M] {
  def bimap[S, N](f: R => S, g: M => N): MLevel[S, N]
  def map[N](f: M => N): MLevel[R, N] = bimap(x => x, f)
  def mapRel[S](f: R => S): MLevel[S, M] = bimap(f, x => x)
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]): MLevel[S, N]
  def flatMap[S >: R,N](f: M => Mem[S, N]): MLevel[S, N] = subst(VarR(_), f)
  def flatRel[S, N >: M](f: R => Relation[N, S]): MLevel[S, N] = subst(f, VarM(_))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z): Z
  def foreach(f: R => Any, g: M => Any): Unit
}

case object MTop extends MLevel[Nothing, Nothing] {
  def bimap[S, N](f: Nothing => S, g: Nothing => N) = this
  def subst[S, N](f: Nothing => Relation[N, S], g: Nothing => Mem[S, N]) = this
  def bifoldMap[Z: Monoid](f: Nothing => Z, g: Nothing => Z) = mzero[Z]
  def foreach(f: Nothing => Any, g: Nothing => Any) = ()
}

case class MPop[R, M](e: Mem[R, M]) extends MLevel[R, M] {
  def bimap[S, N](f: R => S, g: M => N) = MPop(e bimap (f, g))
  def subst[S, N](f: R => Relation[N, S], g: M => Mem[S, N]) = MPop(e subst (f, g))
  def bifoldMap[Z: Monoid](f: R => Z, g: M => Z) = e bifoldMap (f, g)
  def foreach(f: R => Any, g: M => Any) = e foreach (f, g)
}

object Mem {
  type MScope[+R, +M] = Mem[R, MLevel[R, M]]

  def abstrakt[R, M](p: M => Boolean, m: Mem[R, M]): MScope[R, M] = m.map(v => if(p(v)) MTop else MPop(VarM(v)))

  def instantiate[R, M](x: => Mem[R, M], s: MScope[R, M]): Mem[R, M] = s flatMap {
    case MTop    => x
    case MPop(v) => v
  }

  implicit val memBifoldable: Bifoldable[Mem] = new Bifoldable.FromBifoldMap[Mem] {
    def bifoldMap[A,B,M:Monoid](fa: Mem[A, B])(f: A => M)(g: B => M): M =
      fa bifoldMap (f, g)
  }

  implicit def memTraversable[R,M](r: Mem[R, M]): Traversable[M] =
    new Traversable[M] { def foreach[U](f: M => U) { r foreach (x => (), f) } }

  def fromScope[M, R](mem: MScope[R, M]): Mem[R, Option[M]] = mem flatMap {
    case MTop => VarM(None)
    case MPop(e) => e map (Some(_))
  }

  def toScope[M, R](mem: Mem[R, Option[M]]): MScope[R, M] = mem map {
    case None => MTop
    case Some(e) => MPop(VarM(e))
  }

  implicit def memEq[R: Equal, M: Equal]: Equal[Mem[R, M]] = Equal.equalA

  import com.clarifi.machines._
  def concat[K,A](m: Machine[K, Machine[K,A]]): Machine[K,A] = {
    m match {
      case Stop => Stop
      case Emit(o, next) => o >> Mem.concat(next())
      case Await(cont, request, failure) => Await( cont andThen Mem.concat
                                                 , request
                                                 , () => Mem.concat(failure())
                                                 )
    }
  }



  import com.clarifi.machines.Plan._
  import com.clarifi.machines.Tee._
  def passL[A]: Tee[A, Any, A] = (awaits(left[A])  flatMap emit).repeatedly
  def passR[A]: Tee[Any, A, A] = (awaits(right[A]) flatMap emit).repeatedly
  def appendT[A]: Tee[A, A, A] = awaits(left[A]) flatMap (x => emit(x) >> appendT[A]) orElse passR[A]

  def append[M[+_],A](p1: Procedure[M, A], p2: => Procedure[M, A]) = {
    p1.tee(p2)(appendT)
  }
  def zeroProcedure[A]: Procedure[scalaz.Id.Id,A] = new EffectfulProcedure[A] {
    type K = Any
    def machine = Stop
    def setup = (Driver.Id((k: Any) => None : Option[Any]), () => ())
  }

  // NB: this will actually execute the outermost Procedure
  def join[A](p: Procedure[scalaz.Id.Id, Procedure[scalaz.Id.Id, A]]): Procedure[scalaz.Id.Id,A] =
    p.execute( Monoid.instance(append[scalaz.Id.Id, A], zeroProcedure[A]) )
}

object MLevel {
  implicit val mLevelBifoldable: Bifoldable[MLevel] = new Bifoldable.FromBifoldMap[MLevel] {
    def bifoldMap[A,B,M:Monoid](fa: MLevel[A, B])(f: A => M)(g: B => M): M =
      fa bifoldMap (f, g)
  }

  implicit def rLevelEq[R: Equal, M: Equal]: Equal[MLevel[R, M]] = new Equal[MLevel[R, M]] {
    def equal(r1: MLevel[R, M], r2: MLevel[R, M]) = (r1, r2) match {
      case (MTop, MTop) => true
      case (MPop(v1), MPop(v2)) => v1 === v2
      case _ => false
    }
  }
}
