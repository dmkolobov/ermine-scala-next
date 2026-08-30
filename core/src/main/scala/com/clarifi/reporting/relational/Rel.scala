package com.clarifi.reporting
package relational

import scalaz.{\/, Bifoldable, Bifunctor, Equal, Foldable, Functor, Monoid, NonEmptyList}
import scalaz.std.list._
import scalaz.std.tuple._
import scalaz.syntax.equal._
import scalaz.syntax.foldable._
import scalaz.syntax.monoid._
import util.{Clique, PartitionedSet}
import com.clarifi.reporting.Header

sealed abstract class Relation[+M,+R] {
  def bimap[N,S](f: M => N, g: R => S): Relation[N, S]
  def map[S](f: R => S): Relation[M, S] = bimap(x => x, f)
  def mapMem[N](f: M => N): Relation[N, R] = bimap(f, x => x)

  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]): Relation[N, S]
  def flatMap[N >: M, S](f: R => Relation[N, S]): Relation[N, S] = subst(VarM(_), f)
  def flatMem[N, S >: R](f: M => Mem[S, N]): Relation[N, S] = subst(f, VarR(_))

  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z): Z

  def foreach(f: M => Any, g: R => Any): Unit

  def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                              g: Object => Option[Mem[S, N]]): Relation[N, S]
  def unquoteR[S >: R, N >: M](f: Object => Option[Relation[N, S]]): Relation[N, S] = unquote(f, x => None)
  def unquoteM[S >: R, N >: M](f: Object => Option[Mem[S, N]]): Relation[N, S] = unquote(x => None, f)
}

case class VarR[+R](v: R) extends Relation[Nothing, R] {
  def bimap[N, S](f: Nothing => N, g: R => S) = VarR(g(v))
  def subst[N, S](f: Nothing => Mem[S,N], g: R => Relation[N,S]) = g(v)
  def bifoldMap[Z: Monoid](f: Nothing => Z, g: R => Z) = g(v)
  def foreach(f: Nothing => Any, g: R => Any) = g(v)
  override def unquote[S >: R, N >: Nothing](f: Object => Option[Relation[N, S]],
                                             g: Object => Option[Mem[S, N]]): Relation[N, S] = this
}

case class Limit[+M,+R](
  r: Relation[M,R],
  start: Option[Int],
  end: Option[Int],
  order: List[(String, SortOrder)]
) extends Relation[M,R] {
  def bimap[N, S](f: M => N, g: R => S) = Limit(r.bimap(f, g), start, end, order)
  def subst[N, S](f: M => Mem[S,N], g: R => Relation[N, S]) = Limit(r.subst(f, g), start, end, order)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = r.bifoldMap(f, g)
  def foreach(f: M => Any, g: R => Any) = r.foreach(f, g)
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Limit(r.unquote(f, g), start, end, order)
}

case class MemoR[+M,+R](r: Relation[M,R], pk: List[String]) extends Relation[M,R] {
  def bimap[N, S](f: M => N, g : R => S) = MemoR(r.bimap(f,g), pk)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = MemoR(r.subst(f,g), pk)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = r.bifoldMap(f,g)
  def foreach(f: M => Any, g: R => Any) = r.foreach(f,g)
  override def equals(other: Any) = other match {
    case MemoR(r2, pk2) => r == r2 && pk == pk2
    case _ => false
  }
  override def hashCode: Int = (r, pk, 1).hashCode
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    MemoR(r.unquote(f, g), pk)
}

case class LetR[+M,+R](r: Ext[M,R], pk: List[String], expr: Relation[M,RLevel[M, R]]) extends Relation[M,R] {
  def bimap[N, S](f: M => N, g: R => S) = LetR(r.bimap(f, g), pk, expr.bimap(f, (_.bimap(f, g))))
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) =
    LetR(r subst (f, g), pk, expr subst (v => f(v).mapRel(x => RPop(VarR(x))), l => VarR(l subst (f, g))))
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = r.bifoldMap(f, g) |+| expr.bifoldMap(f, (_.bifoldMap(f, g)))
  def foreach(f: M => Any, g: R => Any) = { r.foreach(f, g) ; expr.foreach(f, (_.foreach(f, g))) }
  override def equals(other: Any) = other match {
     case LetR(r2, pk2, e2) => r == r2 && pk == pk2 && Relation.fromScope(expr) == Relation.fromScope(e2)
     case _ => false
  }
  override def hashCode: Int = (r, pk, Relation.fromScope(expr)).hashCode
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    LetR(r.unquote(g, f), pk,
         expr.unquote(x => f(x).map(v => VarR(RPop(v))), x => g(x).map(_.mapRel(v => RPop(VarR(v))))))
}

object Join {
  def apply[M, R](fst: Relation[M, R], snd: Relation[M, R]): Relation[M, R] =
    // Ermine only lets us make aggregates with a single aggregate function natively
    // therefore, we coalesce them when natural-joined.  but make sure none of the
    // aggregated columns have the same name, because coalescing would then be incorrect
    // wrt natural join semantics.
    (fst, snd) match {
      case (a: AggregateByGroup[M,R], b: AggregateByGroup[M,R])
        if a.rel == b.rel &&
           a.cs == b.cs &&
           a.group == b.group &&
           (a.aggs.map(_._1.name).toSet intersect b.aggs.map(_._1.name).toSet isEmpty) =>
          a.copy(aggs = a.aggs ++ b.aggs)
      case _ =>
        Relation.combineFilters(fst, snd) {
          (l,r) => Predicates.simplify(Predicate.And(l,r))
        }.getOrElse(JoinOn(fst, snd, Set()))
    }
  def unapply[M, R](j: JoinOn[M, R]): Option[(Relation[M, R], Relation[M, R])] =
    j match {
      case JoinOn(fst, snd, cs, JoinMode.Inner) if cs.isEmpty => Some((fst, snd))
      case _ => None
    }
}

case class JoinOn[+M, +R](fst: Relation[M, R], snd: Relation[M, R], cs: Set[(String, String)], mode: JoinMode = JoinMode.Inner) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = JoinOn(fst bimap (f, g), snd bimap (f, g), cs)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = JoinOn(fst subst (f, g), snd subst (f, g), cs)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = fst.bifoldMap(f, g) |+| snd.bifoldMap(f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { fst foreach (f, g) ; snd foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    JoinOn(fst.unquote(f, g), snd.unquote(f, g), cs)
}

case class Union[+M, +R](fst: Relation[M, R], snd: Relation[M, R]) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = Union(fst bimap (f, g), snd bimap (f, g))
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = Union(fst subst (f, g), snd subst (f, g))
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = fst.bifoldMap(f, g) |+| snd.bifoldMap(f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { fst foreach (f, g) ; snd foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Union(fst.unquote(f, g), snd.unquote(f, g))
}

case class MinusI[+M, +R](fst: Relation[M, R], snd: Relation[M, R]) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = MinusI(fst bimap (f, g), snd bimap (f, g))
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = MinusI(fst subst (f, g), snd subst (f, g))
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = fst.bifoldMap(f, g) |+| snd.bifoldMap(f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { fst foreach (f, g) ; snd foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    MinusI(fst.unquote(f, g), snd.unquote(f, g))
}

// type Minus[+M,+R] = MinusI[M,R]
// ^- actually exists but lives in package.scala where it must

object Minus {
  def apply[M,R](fst: Relation[M, R], snd: Relation[M, R]): Relation[M, R] =
    Relation.combineFilters(fst, snd) {
      (l, r) => Predicates.simplify(Predicate.And(l, Predicate.Not(r)))
    }.getOrElse(MinusI[M,R](fst,snd))
  def unapply[M,R](x: Minus[M,R]): Some[(Relation[M,R],Relation[M,R])] = Some((x.fst, x.snd)) 
}

case class Filter[+M, +R](rel: Relation[M, R], p: Predicate) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = Filter(rel bimap (f, g), p)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = Filter(rel subst (f, g), p)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = rel bifoldMap (f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Filter(rel.unquote(f, g), p)
}

case class Project[+M, +R](rel: Relation[M, R], cs: Map[Attribute, Op]) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = Project(rel bimap (f, g), cs)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = Project(rel subst (f, g), cs)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = rel bifoldMap (f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Project(rel.unquote(f, g), cs)
}

/** Except gets optimized away in the Optimizer */
case class Except[+M, +R](rel: Relation[M, R], cs: Set[ColumnName]) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = Except(rel bimap (f, g), cs)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = Except(rel subst (f, g), cs)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = rel bifoldMap (f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Except(rel.unquote(f, g), cs)
}

/** Combine gets optimized away in the Optimizer */
case class Combine[+M, +R](rel: Relation[M, R], attr: Attribute, op: Op) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = Combine(rel bimap (f, g), attr, op)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = Combine(rel subst (f, g), attr, op)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = rel bifoldMap (f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Combine(rel.unquote(f, g), attr, op)
}

/** RenameR gets optimized away in the Optimizer */
case class RenameR[+M, +R](rel: Relation[M, R], attr: Attribute, c: ColumnName) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = RenameR(rel bimap (f, g), attr, c)
  def bifoldMap[Z:Monoid](f: M => Z, g: R => Z) = rel bifoldMap (f, g)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = RenameR(rel subst (f, g), attr, c)
  def foreach(f: M => Any, g: R => Any): Unit = { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    RenameR(rel.unquote(f, g), attr, c)
}

/* Group by combined with an aggregation */
case class AggregateByGroup[+M, +R](
  rel: Relation[M, R],
  cs: Map[Attribute, Op],
  aggs: List[(Attribute, AggFunc)],
  group: List[Op.ColumnValue] = List()
) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = AggregateByGroup(rel bimap (f, g), cs, aggs, group)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = rel bifoldMap (f, g)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = AggregateByGroup(rel subst (f, g), cs, aggs, group)
  def foreach(f: M => Any, g: R => Any): Unit = { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    AggregateByGroup(rel.unquote(f, g), cs, aggs, group)
}

case class Aggregate[+M, +R](rel: Relation[M, R], attr: Attribute, agg: AggFunc) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = Aggregate(rel bimap (f, g), attr, agg)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = Aggregate(rel subst (f, g), attr, agg)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = rel bifoldMap (f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { rel foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Aggregate(rel.unquote(f, g), attr, agg)
}

case class Note[+M,+R](tags: List[String], under: Relation[M,R]) extends Relation[M,R] {
  def bimap[N, S](f: M => N, g: R => S) = Note(tags, under.bimap(f,g))
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = Note(tags, under.subst(f,g))
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = under bifoldMap(f, g)
  def foreach(f: M => Any, g: R => Any): Unit = { under foreach (f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                       g: Object => Option[Mem[S, N]]): Relation[N, S] =
    Note(tags, under.unquote(f, g))
}

object Annotated {
  def apply[M,R](ts: List[String], un: Relation[M, R]): Relation[M,R] =
    if (ts.isEmpty) un else Note(ts, un)
}

// 'Statically' determined pivot tables. Generates some specified new columns
// using data in an underlying relation.
case class PivotR[+M, +R](
  under: Relation[M, R], // the underlying relation
  pivotKey: Set[ColumnName], // the columns that determine the pivot key
  pivotVals: Set[ColumnName], // the columns that determine the pivot values
  outer: Boolean, // whether NULL is admitted in the output columns of the pivot
  colMap: Map[ColumnName,(Record, Op, PrimExpr)] // association from column names to ways to fill them - the PrimExpr is the default 'missing' element, e.g. 0 or "", to avoid NullExprs.
) extends Relation[M, R] {
  def bimap[N, S](f: M => N, g: R => S) =
    PivotR(under.bimap(f, g), pivotKey, pivotVals, outer, colMap)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) =
    PivotR(under.subst(f, g), pivotKey, pivotVals, outer, colMap)
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = under.bifoldMap(f, g)
  def foreach(f: M => Any, g: R => Any) = { under.foreach(f, g) }
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]], g: Object => Option[Mem[S, N]]): Relation[N, S] =
    PivotR(under.unquote(f, g), pivotKey, pivotVals, outer, colMap)
}

sealed abstract class HardRel extends Relation[Nothing, Nothing] {
  def bimap[N, S](f: Nothing => N, g: Nothing => S) = this
  def subst[N, S](f: Nothing => Mem[S, N], g: Nothing => Relation[N, S]) = this
  def bifoldMap[Z: Monoid](f: Nothing => Z, g: Nothing => Z) = mzero[Z]
  def foreach(f: Nothing => Any, g: Nothing => Any) = ()
  def header: Header
  override def unquote[S >: Nothing, N >: Nothing](f: Object => Option[Relation[N, S]],
                                                   g: Object => Option[Mem[S, N]]): Relation[N, S] = this
}

/** A table-valued stored procedure.
  *
  * @param headerOrder SQL uses order, rather than column name, in
  *   exciting bug-causing ways.  Normally, we resolve potential
  *   conflicts between orders by applying a universal sorting
  *   strategy—i.e., the Ord[String] sort.  The nature of the sort is
  *   irrelevant; all that matters is consistency.  We can't control
  *   the ordering of procedure calls in the same way, though, so we
  *   have to save it, and use it when we're ready to pull the call
  *   result into our world.
  */
case class TableProc[+M, +R](args: List[(String, Relation[M, R]) \/ PrimExpr],
                             headerOrder: List[(ColumnName, PrimT)],
                             fun: String, namespace: List[String])
     extends Relation[M, R] {
  import TableProc.relFunctor
  def bimap[N, S](f: M => N, g: R => S) =
    copy(args = relFunctor.map(args)(_ bimap (f, g)))
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) =
    copy(args = relFunctor.map(args)(_ subst (f, g)))
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) =
    args foldMap (_.swap foldMap (_._2 bifoldMap (f, g)))
  def foreach(f: M => Any, g: R => Any) =
    args foreach (_.swap foreach (_._2 foreach (f, g)))
  override def unquote[S >: R, N >: M](f: Object => Option[Relation[N, S]],
                                     g: Object => Option[Mem[S, N]]): Relation[N, S] =
    copy(args = relFunctor.map(args)(_ unquote (f, g)))

  def header: Header = headerOrder.toMap
}
object TableProc {
  private type RArg[+A] = A \/ PrimExpr
  private type LTup[+A] = (String, A)
  val argFunctor = Functor[List].compose[RArg](Bifunctor[\/].leftFunctor)
  val argFoldable = Foldable[List].compose[RArg](Bifoldable[\/].leftFoldable)
  val relFunctor = argFunctor compose Functor[LTup]
  val relFoldable = argFoldable compose Foldable[LTup]
}

case class Table(header: Header, n: TableName) extends HardRel
case class RelEmpty(header: Header) extends HardRel
// Tiny literals turn into filters in the optimizer
case class SmallLit(tups: NonEmptyList[Record]) extends HardRel {
  val header = recordHeader(tups.head)
}
case class QuoteR(n: Object) extends HardRel {
  def header = sys.error("Panic: Asked for the header of a quote.")
  override def unquote[R, M](f: Object => Option[Relation[M, R]],
                             g: Object => Option[Mem[R, M]]): Relation[M, R] =
    f(n) getOrElse this
}

sealed abstract class RLevel[+M, +R] {
  def bimap[N, S](f: M => N, g: R => S): RLevel[N, S]
  def map[S](f: R => S): RLevel[M, S] = bimap(x => x, f)
  def mapMem[N](f: M => N): RLevel[N, R] = bimap(f, x => x)
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]): RLevel[N, S]
  def flatMap[S,N >: M](f: R => Relation[N, S]): RLevel[N, S] = subst(VarM(_), f)
  def flatMapMem[S >: R, N](f: M => Mem[S, N]): RLevel[N, S] = subst(f, VarR(_))
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z): Z
  def foreach(f: M => Any, g: R => Any): Unit
}

case object RTop extends RLevel[Nothing, Nothing] {
  def bimap[N, S](f: Nothing => N, g: Nothing => S) = this
  def subst[N, S](f: Nothing => Mem[S, N], g: Nothing => Relation[N, S]) = this
  def bifoldMap[Z: Monoid](f: Nothing => Z, g: Nothing => Z) = mzero[Z]
  def foreach(f: Nothing => Any, g: Nothing => Any) = ()
}

case class RPop[+M, +R](e: Relation[M,R]) extends RLevel[M, R] {
  def bimap[N, S](f: M => N, g: R => S) = RPop(e bimap (f, g))
  def subst[N, S](f: M => Mem[S, N], g: R => Relation[N, S]) = RPop(e subst (f, g))
  def bifoldMap[Z: Monoid](f: M => Z, g: R => Z) = e bifoldMap (f, g)
  def foreach(f: M => Any, g: R => Any) = e foreach (f, g)
}

object Relation {
  type RScope[+M, +R] = Relation[M, RLevel[M, R]]

  def abstrakt[M, R](p: R => Boolean, r: Relation[M, R]): RScope[M, R] = r.map(v => if(p(v)) RTop else RPop(VarR(v)))

  def instantiate[M, R](x: => Relation[M, R], s: RScope[M, R]): Relation[M, R] = s flatMap {
    case RTop    => x
    case RPop(v) => v
  }

  /** If `left` and `right` are the same except in filter, answer a
    * combination that joins the filters with `bin`, otherwise
    * None.
    */
  def combineFilters[M, R](left: Relation[M, R], right: Relation[M, R])(
                                         bin: (Predicate, Predicate) => Predicate) =
    (left, right) match {
      case (Filter(r1, p1), Filter(r2, p2)) if r1 == r2 =>
        Some(Filter(r1, bin(p1, p2)))
      case _ => None
    }

  implicit val relBifoldable: Bifoldable[Relation] = new Bifoldable.FromBifoldMap[Relation] {
    def bifoldMap[A,B,M:Monoid](fa: Relation[A, B])(f: A => M)(g: B => M): M =
      fa bifoldMap (f, g)
  }

  implicit def relTraversable[M, R](r: Relation[M,R]): Traversable[R] =
    new Traversable[R] { def foreach[U](f: R => U): Unit = { r foreach (x => (), f) } }

  def toScope[M, R](mem: Relation[M, Option[R]]): RScope[M, R] = mem map {
    case None => RTop
    case Some(e) => RPop(VarR(e))
  }

  def fromScope[R, M](rel: RScope[M, R]): Relation[M, Option[R]] = rel flatMap {
    case RTop => VarR(None)
    case RPop(e) => e map (Some(_))
  }

  implicit def relEq[M: Equal, R: Equal]: Equal[Relation[M, R]] = Equal.equalA
}

object RLevel {
  implicit val rLevelBifoldable: Bifoldable[RLevel] = new Bifoldable.FromBifoldMap[RLevel] {
    def bifoldMap[A,B,M:Monoid](fa: RLevel[A, B])(f: A => M)(g: B => M): M =
      fa bifoldMap (f, g)
  }

  implicit def rLevelEq[M: Equal, R: Equal]: Equal[RLevel[M, R]] = new Equal[RLevel[M, R]] {
    def equal(r1: RLevel[M, R], r2: RLevel[M, R]) = (r1, r2) match {
      case (RTop, RTop) => true
      case (RPop(v1), RPop(v2)) => v1 === v2
      case _ => false
    }
  }
}

