package com.clarifi.reporting
package writers

import java.util.Date
import collection.immutable.{IndexedSeq, SortedSet}

import scalaz.Scalaz._ // TODO: Remove
import scalaz.{ContravariantCoyoneda => CtCoyo, Monad, Order}
//import scalaz.std.vector._

import relational._

import Tabular.{Label, displayRecords}

import scalaz.IterV.collect

import com.clarifi.machines._

/** Interface for access to tabular data - conceptually, a sequence of values of type A.
  * TODO: add support for filtering
  */
abstract class Tabular[F[_],A] extends GenTabular[Tabular, F, A] {
  /** Transform the underlying relation - this should not modify the type of this table. */
  def apply(f: ClosedExt => ClosedExt): Tabular[F,A]

  /** Set a software sort to be applied instead of the relational
    * sort.
    */
  def postSort(postSort: CtCoyo[Order, Record]): Tabular[F, A]

  /** @todo if generic, move to GenTabular */
  def isTransposed: Boolean

  /** @todo if generic, move to GenTabular */
  def transpose: Tabular[F, A]
}

/** Operations supported by Tabular and TreeTabular. */
abstract class GenTabular[Repr[G[_], B] <: GenTabular[Repr, G, B], F[_], A] {
  implicit def F: Monad[F]

  /** The set of unique column IDs in the relational (`Record`) view
    * of the tabular.  In no particular order. */
  def columnIds: Set[ColumnName]

  /** The list of column labels, possibly containing duplicates, in
    * the two-dimensional (`IndexedSeq`) view of the tabular. In the
    * same order as said `IndexedSeq`s.
    *
    * In the relational view, this merely implies a display order for
    * `columnIds`.
    */
  def columnLabels: IndexedSeq[Label]

  /** Retrieve rows [start,stop), or to the end of this tabular data if no stop index is provided. */
  def slice(start: Int, stop: Option[Int]): F[IndexedSeq[A]]

  def takeAll: F[IndexedSeq[A]] = slice(0, None)

  /** Return the relational representation of this table. */
  def relation: ClosedExt

  /** Transform the values of this Tabular data. */
  def map[B](f: A => B): Repr[F,B]

  /** Return the number of rows in this tabular data. */
  def size: F[Int]

  /** Return the current ordering priority, highest-first. */
  def ordering: IndexedSeq[(Label, SortOrder)]

  /** Sort the rows in this Tabular by the given column. */
  def orderBy(o: IndexedSeq[(Label, SortOrder)]): Repr[F,A]

  /** Clear any ordering applied to this Tabular. */
  def clearOrder: Repr[F,A]

  /** Answer self with columns relabeled. */
  def label(labels: Legend.U[Label]): Repr[F,A]

  /** Rules for displaying relations. */
  def displayRules: Legend.U[Label]

  /** The two-dimensional view, incorporating presentation.  The
    * resulting sequence is in `columnLabels` order.  Using this
    * subsumes `displayRules` for value presentation. */
  def display(implicit ev: A <:< Record): Repr[F, IndexedSeq[PrimExpr]] =
    map(ev andThen displayRules.basicEval)
}

object GenTabular {
  import scalaz.Functor

  implicit def covariant[Repr[G[_], B] <: GenTabular[Repr, G, B],
                         M[_]]: Functor[Repr[M, ?]] =
    new Functor[Repr[M, ?]] {
      def map[A, B](fa: Repr[M, A])(f: A => B): Repr[M, B] = fa map f
    }
}

object Tabular {
  type Label = String

  private val _log = org.apache.log4j.Logger.getLogger(classOf[Tabular[Nothing,Nothing]])

  def relationRec[F[_]](r: ClosedExt)(implicit S: Scanner[F]): Tabular[F,Record] =
    new StrictTabular[F,Record](r, IndexedSeq(), (_,t) => t, None, None, false)
  def timeSeries[F[_]](r: ClosedExt)(implicit S: Scanner[F]): Tabular[F,(String,Date,Double)] =
    relationRec(r).map(t => (t("Label").extractString, t("Timestamp").extractDate, t("Value").extractDouble))

  /** Find a reasonable deterministic default #displayRules for the
    * schema `h`. */
  def displayRecords(h: Header): Legend.U[ColumnName] =
    Legend select (SortedSet(h.keys.toSeq:_*).toIndexedSeq, h)
}

class StrictTabular[F[_],A](r: ClosedExt, val ordering: IndexedSeq[(Label, SortOrder)],
                            extract: (Set[ColumnName], Record) => A,
                            postSort: Option[CtCoyo[Order, Record]],
                            labels: Option[Legend.U[Label]],
                            val isTransposed: Boolean)(
  implicit B: Scanner[F]) extends Tabular[F,A] {
  implicit val F = B.M

  private var records: Option[IndexedSeq[Record]] = None

  // Relies on the monadic chaining of `scan`.
  // You have to have `run` it once in order for the caching to kick in.
  private def scan: F[IndexedSeq[Record]] =
    records match {
      case Some(ts) => ts.pure[F]
      case _ => B.scanExt(r.out, Process.wrapping[Record], relationalOrder).map{ts =>
        val sts = postSort cata (coy => ts.map(coy.k &&& identity)
                                   .sortBy(_._1)(coy.fi.toScalaOrdering)
                                   .map(_._2),
                                 ts)
        records = Some(sts)
        sts
      }
    }

  lazy val columnIds = labels.map(_.columnReferences) | r.header.keySet

  lazy val columnLabels =
    labels.map(_.labels.toIndexedSeq) | columnIds.toIndexedSeq.sorted

  def size: F[Int] = r.out match {
    case ExtRel(rout, db) => B.scanExt(
      ExtRel(Aggregate(rout, Attribute("rowcount", PrimT.IntT()), AggFunc.Count), db),
           Process.wrapping[Record].outmap(_.head("rowcount").extractDouble.toInt)
    )
    case _ => scan.map(_.size) // this will use the `records` cache after the first use
  }

  def relation = r

  private[this] def relationalOrder =
    labels map (_ deriveSort ordering toList) getOrElse ordering.toList

  def slice(start: Int, stop: Option[Int]): F[IndexedSeq[A]] = {
    val stopVal = stop.flatMap(x => if(x<0) None else Some(x))
    scan.map(ts => ts.slice(start, stopVal.getOrElse(ts.length)).map(extract(columnIds, _)))
  }

  def map[B](f: A => B): Tabular[F,B] = copy(extract = (cs,t) => f(extract(cs,t)))

  def displayRules = labels | displayRecords(r.header)

  def clearOrder = copy(ordering = IndexedSeq())
  def orderBy(order: IndexedSeq[(Tabular.Label, SortOrder)]) =
    copy(ordering = displayRules filterSort order)

  def postSort(postSort: CtCoyo[Order, Record]): Tabular[F, A] =
    copy(postSort = Some(postSort))

  def label(labels: Legend.U[Label]) = copy(labels = Some(labels))

  def transpose = copy(isTransposed = true)

  def apply(f: ClosedExt => ClosedExt): Tabular[F,A] = copy(r = f(r))

  private[this]
  def copy[B](r: ClosedExt = r,
              ordering: IndexedSeq[(Label, SortOrder)] = ordering,
              extract: (Set[ColumnName], Record) => B = extract,
              postSort: Option[CtCoyo[Order, Record]] = postSort,
              labels: Option[Legend.U[Label]] = labels,
              isTransposed: Boolean = isTransposed) =
    new StrictTabular[F, B](r, ordering, extract, postSort, labels, isTransposed)
}

