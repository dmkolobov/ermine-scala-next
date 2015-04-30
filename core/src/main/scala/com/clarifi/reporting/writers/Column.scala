// Column.scala: A more dynamic subsumption of KeyValueTabular.dynamicSchema.
package com.clarifi.reporting
package writers

import scalaz.{Applicative, Bitraverse, Functor, Monoid, Semigroup,
               Traverse}
import scalaz.std.option._
import scalaz.std.tuple._
import scalaz.std.vector._
import scalaz.std.list._
import scalaz.syntax.applicative._
import scalaz.syntax.bitraverse._
import scalaz.syntax.semigroup._
import scalaz.syntax.traverse._

import relational.{ClosedExt}

/** A table of data gathered from multiple sources, joined together by
  * some common data.
  *
  * We use a heterogenous, simple type representation at the Scala
  * level, whereas the type that subsumes all of these in Ermine is
  * homogenous and complex, because it's easier to consume.  The
  * production of the extra data not explicitly represented in Ermine
  * is essentially "defaulting".
  */
object Column {
  /** A single column; data represents both the data in the column and
    * the data by which it may be associated with other Singles by way
    * of Joins. */
  case class Single[Lbl, A](data: A, heading: Lbl, display: Presentation,
                            relativeSort: SortStrategy,
                            initialSort: Option[(SortOrder, Int)])
       extends TraversableColumns[Single[Lbl, A]] {
    def traverseColumns[F[_]: Applicative
                      ](f: ColumnName => F[ColumnName]): F[Single[Lbl, A]] =
      ^(display traverseColumns f, relativeSort traverseColumns f){
        (d, rs) => Single(data, heading, d, rs, initialSort)
      }

    def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
      (display typedColumnFoldMap f) |+| (relativeSort typedColumnFoldMap f)

    /** Build a singleton legend for this column. */
    def singletonLegend: Legend[Lbl] =
      Legend(Vector((display, relativeSort, heading)), Seq())
  }

  object Single {
    implicit val singleCovariant: Bitraverse[Single] = new Bitraverse[Single] {
      def bitraverseImpl[F[_]: Applicative, Lbl, A, L2, B
                       ](fa: Single[Lbl, A])(f: Lbl => F[L2], g: A => F[B]
                                           ): F[Single[L2, B]] =
        ^(g(fa.data), f(fa.heading)){
            Single(_, _, fa.display, fa.relativeSort, fa.initialSort)
        }
    }
  }

  /** An associative combination of `A`s and other `Join`s.
    *
    * @note Invariant: A join tree does not contain empty Outer or
    *       Inner joins, unless the root is such an empty join.
    */
  sealed abstract class Join[A] {
    /** Traversable for any applicative. */
    def traverse[F[_]: Applicative, B](f: A => F[B]): F[Join[B]]

    /** Produce all the singles. */
    final def singles: Vector[A] = this foldMap (Vector(_))
  }

  object Join {
    implicit val joinCovariant: Traverse[Join] = new Traverse[Join] {
      def traverseImpl[F[_]: Applicative, A, B](fa: Join[A])(f: A => F[B]): F[Join[B]] =
        fa traverse f
    }
  }

  case class Joinee[A](a: A) extends Join[A] {
    def traverse[F[_]: Applicative, B](f: A => F[B]): F[Join[B]] =
      f(a) map Joinee.apply
  }

  /** A join that drops rows for which any subtree has no data.
    *
    * @note Invariant: No element of `columns` is an InnerJoin.
    */
  case class InnerJoin[A](columns: Vector[Join[A]]) extends Join[A] {
    def traverse[F[_]: Applicative, B](f: A => F[B]): F[Join[B]] =
      columns traverse (_ traverse f) map InnerJoin.apply

    private[Column] def append(right: InnerJoin[A]): InnerJoin[A] =
      InnerJoin(columns ++ right.columns)
  }

  /** A join that preserves any rows for which any subtree has data.
    *
    * @note Invariant: No element of `columns` is an OuterJoin.
    */
  case class OuterJoin[A](columns: Vector[Join[A]]) extends Join[A] {
    def traverse[F[_]: Applicative, B](f: A => F[B]): F[Join[B]] =
      columns traverse (_ traverse f) map OuterJoin.apply

    private[Column] def append(right: OuterJoin[A]): OuterJoin[A] =
      OuterJoin(columns ++ right.columns)
  }

  /** An Ermine `Column` with sufficient detail to build a report.
    *
    * @note Invariant: If `drilldown` is defined, its columns are
    *       disjoint from `legend.columnReferences`.
    *
    * @note Invariant: `drilldown` and `legend.columnReferences`'s
    *       columns are disjoint from each `display.columnReferences`
    *       in `columns`.
    * @note Invariant: if drilldown.get.length >= 2, then rootNodes must be defined
    *
    * @param drilldown Parent ID column and child ID column, in order,
    *        if and only if this should be a drilldown table.
    */
  case class Table[Lbl, A](columns: Join[Single[Lbl, A]],
                           legend: Legend[Lbl],
                           initialIdSort: Vector[(Lbl, (SortOrder, Int))],
                           drilldown: Option[List[((ColumnName, ColumnName), PrimT)]],
                           rootNodes: Option[ClosedExt])
       extends TraversableColumns[Table[Lbl, A]] {
    def traverseColumns[F[_]: Applicative
                      ](f: ColumnName => F[ColumnName]): F[Table[Lbl, A]] =
      ^^(columns traverse (_ traverseColumns f),
          legend traverseColumns f,
          drilldown traverse (_ traverse (_ bitraverse (_ bitraverse (f, f), _.point[F])))
        )(Table(_, _, initialIdSort, _, rootNodes))

    def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
      ((columns foldMap (_ typedColumnFoldMap f))
         |+| (legend typedColumnFoldMap f)
         |+| (drilldown.foldMap(_.foldMap({case ((p, c), ty) => f(p, ty) |+| f(c, ty)}))))

    /** Initial sort priority for displaying this table. */
    def initialSort: Vector[(Lbl, SortOrder)] =
      initialIdSort ++ (columns foldMap (sing => sing.initialSort map {
        s => Vector((sing.heading, s))
      } getOrElse Vector.empty)) sortBy (_._2._2) map {case (l, (s, _)) => (l, s)}
  }

  object Table {
    implicit val tableCovariant: Bitraverse[Table] = new Bitraverse[Table] {
      def bitraverseImpl[G[_] : Applicative, A, B, C, D
                       ](fab: Table[A, B])(f: A => G[C], g: B => G[D]): G[Table[C, D]] =
        ^^(fab.legend traverse f, fab.columns traverse (_ bitraverse (f, g)),
           fab.initialIdSort traverse {case (lbl, soi) => f(lbl) map ((_, soi))}){
            (l, c, is) => Table(c, l, is, fab.drilldown, fab.rootNodes)
        }
    }
  }
}
