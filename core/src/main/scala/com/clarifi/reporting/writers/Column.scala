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
import scalaz.syntax.traverse.{ToFunctorOps => _, _}

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
                            initialSort: Option[(SortOrder, Int)],
                            isHidden : Boolean)
       extends TraversableColumns[Single[Lbl, A]] {
    def traverseColumns[F[_]: Applicative
                      ](f: ColumnName => F[ColumnName]): F[Single[Lbl, A]] =
      ^(display traverseColumns f, relativeSort traverseColumns f){
        (d, rs) => Single(data, heading, d, rs, initialSort,isHidden)
      }

    def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
      (display typedColumnFoldMap f) |+| (relativeSort typedColumnFoldMap f)

    /** Build a singleton legend for this column. */
    def singletonLegend[G]: Legend[G, Lbl] =
      if(isHidden) {
        val nameTypes = display typedColumnFoldMap ((x,y) => List((x,y)))
        Legend(LegendColumns.empty, (nameTypes map (x => (x._1, x._2, SortOrder.Asc))).toSeq)
      }
      else
        Legend(LegendColumns flat (Vector((display, relativeSort, heading))), Seq())
  }

  object Single {
    implicit val singleCovariant: Bitraverse[Single] = new Bitraverse[Single] {
      def bitraverseImpl[F[_]: Applicative, Lbl, A, L2, B
                       ](fa: Single[Lbl, A])(f: Lbl => F[L2], g: A => F[B]
                                           ): F[Single[L2, B]] =
        ^(g(fa.data), f(fa.heading)){
            Single(_, _, fa.display, fa.relativeSort, fa.initialSort,fa.isHidden)
        }
    }
  }

  /** An associative combination of `A`s and other `Join`s.
    *
    * @tparam L The type of headings.
    * @tparam A The type of nodes.
    * @note Invariant: A join tree does not contain empty Outer or
    *       Inner joins, unless the root is such an empty join.
    */
  sealed abstract class Join[L, A] {
    import Join._
    /** Produce all the singles. */
    final def singles: Vector[A] = rightCovariant.foldMap(this)(Vector(_))

    /** A bifold that threads each heading through `f` instead of
      * appending children of a heading to the heading.
      */
    final def foldGroups[Z: Monoid](g: A => Z)(f: (L, Z) => Z): Z = this match {
      case Joinee(a) => g(a)
      case InnerJoin(columns) => columns foldMap (_.foldGroups(g)(f))
      case OuterJoin(columns) => columns foldMap (_.foldGroups(g)(f))
      case JoinHeading(heading, over) => f(heading, over.foldGroups(g)(f))
    }
  }

  object Join {
    implicit val joinCovariant: Bitraverse[Join] = new Bitraverse[Join] {
      override def bifoldMap[A, B, Z: Monoid](fa: Join[A, B])(f: A => Z)(g: B => Z): Z =
        fa.foldGroups(g)((a, z) => f(a) |+| z)

      def bitraverseImpl[F[_]: Applicative, A, B, C, D](fa: Join[A, B])
                        (f: A => F[C], g: B => F[D]): F[Join[C, D]] =
        fa match {
          case Joinee(a) => g(a) map Joinee.apply
          case InnerJoin(columns) =>
            columns traverse (bitraverseImpl(_)(f, g)) map InnerJoin.apply
          case OuterJoin(columns) =>
            columns traverse (bitraverseImpl(_)(f, g)) map OuterJoin.apply
          case JoinHeading(heading, over) =>
            ^(f(heading), bitraverseImpl(over)(f, g))(JoinHeading.apply)
        }
    }

    implicit def rightCovariant[L]: Traverse[Join[L, ?]] =
      joinCovariant.rightTraverse
  }

  final case class Joinee[L, A](a: A) extends Join[L, A]

  /** A join that drops rows for which any subtree has no data.
    *
    * @note Invariant: No element of `columns` is an InnerJoin.
    */
  final case class InnerJoin[L, A](columns: Vector[Join[L, A]]) extends Join[L, A] {
    private[Column] def append(right: InnerJoin[L, A]): InnerJoin[L, A] =
      InnerJoin(columns ++ right.columns)
  }

  /** A join that preserves any rows for which any subtree has data.
    *
    * @note Invariant: No element of `columns` is an OuterJoin.
    */
  final case class OuterJoin[L, A](columns: Vector[Join[L, A]]) extends Join[L, A] {
    private[Column] def append(right: OuterJoin[L, A]): OuterJoin[L, A] =
      OuterJoin(columns ++ right.columns)
  }

  /** A heading for the underlying join. */
  final case class JoinHeading[L, A](heading: L, over: Join[L, A]) extends Join[L, A]

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
    * @note Invariant: At most one of `groupingColumn` and `drilldown` is defined.
    *
    * @param drilldown Parent ID column and child ID column, in order,
    *        if and only if this should be a drilldown table.
    */
  case class Table[Lbl, A](columns: Join[Lbl, Single[Lbl, A]],
                           legend: Legend.U[Lbl],
                           initialIdSort: Vector[(Lbl, (SortOrder, Int))],
                           groupingColumn: Option[(ColumnName, PrimT)],
                           drilldown: Option[List[((ColumnName, ColumnName), PrimT)]],
                           rootNodes: Option[ClosedExt])
       extends TraversableColumns[Table[Lbl, A]] {
    def traverseColumns[F[_]: Applicative
                      ](f: ColumnName => F[ColumnName]): F[Table[Lbl, A]] =
      ^^^(columns bitraverse (_.point[F], _ traverseColumns f),
          legend traverseColumns f,
          groupingColumn traverse (_ bitraverse (f, _.point[F])) : F[Option[(ColumnName, PrimT)]],
           // scala can't infer the innermost bitraverse's type parameters without a bit of help
          drilldown traverse (_ traverse (_ bitraverse (_ bitraverse (f, f), _.point[F]))) : F[Option[List[((ColumnName, ColumnName), PrimT)]]]
        )(Table(_, _, initialIdSort, _, _, rootNodes))

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
        ^^(fab.legend bitraverse (f, f),
           fab.columns bitraverse (f, _ bitraverse (f, g)),
           fab.initialIdSort traverse {case (lbl, soi) => f(lbl) map ((_, soi))}){
            (l, c, is) => Table(c, l, is, fab.groupingColumn, fab.drilldown, fab.rootNodes)
        }
    }
  }
}
