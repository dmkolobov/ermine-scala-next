package com.clarifi.reporting
package writers

import java.util.Date
import collection.immutable.{IndexedSeq, SortedSet}

import scalaz.{Bifunctor, NonEmptyList}
import scalaz.Scalaz._ // TODO: Remove
import scalaz.{ContravariantCoyoneda => CtCoyo, Monad, Order}
//import scalaz.std.vector._

import relational._

import Tabular.{Label, displayRecords}

import scalaz.IterV.collect

import com.clarifi.machines._

import java.lang.ref.SoftReference

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

  /** Returns the entire result set as an IndexedSeq */
  def takeAll: F[IndexedSeq[A]] = slice(0, None)

  /** As `takeAll`, but don't cache results for future calls */
  def takeAllOnce: F[IndexedSeq[A]] = slice(0, None)

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
                         M[_]]: Functor[[x] =>> Repr[M, x]] =
    new Functor[[x] =>> Repr[M, x]] {
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

  /* A dummy Tabular with no content, useful for debugging purposes.
   * Likely doesn't implement some methods in the expected way.
   */
  def dummy[F[_], A](implicit M: Monad[F]): Tabular[F, A] =
    new Tabular[F, A] {
      def F = M
      def columnIds = Set()
      def columnLabels = IndexedSeq()
      def slice(start:Int, stop:Option[Int]) = M.pure(IndexedSeq())
      def relation = relational.Closed[Ext](ExtRel(RelEmpty(Map()), ""),Map())
      def apply(f: ClosedExt => ClosedExt) = this
      def map[B](f: A => B) = dummy[F,B]
      def size = M.pure(0)
      def ordering = IndexedSeq()
      def orderBy(o: IndexedSeq[(com.clarifi.reporting.writers.Tabular.Label,SortOrder)]) = this
      def clearOrder = this
      def label(l: Legend.U[com.clarifi.reporting.writers.Tabular.Label]) = this
      def displayRules = Legend.empty
      def isTransposed = false
      def postSort(ps: CtCoyo[Order, Record]) = this
      def transpose = this
    }

  def buildTranspose[F[_]](displayRules: Legend.U[String]
                          , relationHeader: Header
                          , seqRows: IndexedSeq[IndexedSeq[PrimExpr]])
                          (implicit S: Scanner[F]): Tabular[F,Record] = {
    // Nested colgroups ==> top level + list for sublevels.
    val lg1: Legend.U[String] = displayRules.oneDeep // The orginal legend, collapsed to 1 deep
    val lg2: Legend.U[String] = lg1.sansGroupingColumn // Legend without grouping column

    // if we have new row groups but not old ones, fake a column name.
    val rgColName: ColumnName = lg1.groupingColumn.fold("__dummy_name_for_row_group_column__")(_._1)
    val rgColHeader: String = lg1.groupingColumnIndex.fold("")(i => lg1.labels.toIndexedSeq(i))

    val colNameForRow : Int => ColumnName = i => "__dummy_name_row_" + i.toString

    // Figure out the new list of column/row groups
    val newColumnGroups: Option[IndexedSeq[String]] =
      lg1.groupingColumnIndex map (i => seqRows map (x => x(i).toString))
    val newRowGroups_ = lg2.inOrder.flattened.tail.map(_._2)
    val newRowGroups: Option[IndexedSeq[String]] =
      if (newRowGroups_.forall(_.isEmpty)) None else Some(newRowGroups_.map(_.getOrElse("")))

    // Remove the row group column, if it exists
    val seqRows2: IndexedSeq[IndexedSeq[PrimExpr]] = lg1.groupingColumnIndex.fold(seqRows) { i => seqRows map (x => x.patch(i, Nil, 1)) }

    // Take the legend, turn the labels into the first column
    val firstColHeader: String = lg2.labels.head
    val newRows: IndexedSeq[PrimExpr] = lg2.labels.tail.map(x => StringExpr(false, x)).toIndexedSeq
    // Take the first value of each row, turn it into the new column names
    val newColumnNames : IndexedSeq[ColumnName] = seqRows2.zipWithIndex.map{ case (_, i) => colNameForRow(i) }
    val newColumns: IndexedSeq[String] = seqRows2 map (x => x(0).toString)
    // Add the new first column, and transpose
    val tblVals: IndexedSeq[IndexedSeq[PrimExpr]] = (newRows +: seqRows2.map((_.tail))).transpose
    // Convert each row back into a record, using the new column names for keys
    val tblRecordVals: IndexedSeq[Record] = tblVals.map(tblRow => (firstColHeader +: newColumnNames).zip(tblRow).toMap)
    // Attach the new rowgrouping column
    val tblRecordVals2: IndexedSeq[Record] = newRowGroups.fold(tblRecordVals) {
      _.zip(tblRecordVals) map {
        case (rgName, rec) => rec + (rgColName -> StringExpr(false, rgName))
      }
    }

    // Make it a literal mem.
    val tblRecordHardMem: HardMem = Literal.toLit(tblRecordVals2).getOrElse(EmptyRel(relationHeader))

    val newLegend: Legend.U[String] = {
      val newGroupingColumn = newRowGroups map { _ => (rgColName, PrimT.StringT(0, false)) }

      // Legend for the row grouping column
      val rgLeg = newGroupingColumn.fold(Legend.empty[String, String])(gc =>
        implicitly[Bifunctor[Legend]].bimap(
          Legend.select[String](Vector(rgColName), _ => gc._2)
        )(identity, _ => rgColHeader).setGroupingColumn(newGroupingColumn)
      )
      // Legend for the new 'row' column
      val rowLeg = Legend.select[String](Vector(firstColHeader), _ => PrimT.StringT(0, true))
      // Legend for everything else
      val valsLeg = implicitly[Bifunctor[Legend]].bimap(
        Legend[String,String](
          LegendColumns flat (
            newColumnNames.map (c => (Presentation.verbatim(NonEmptyList(c -> PrimT.DoubleT(true))),
                                 SortStrategy allForward IndexedSeq(c),
                                 c))),
            IndexedSeq.empty,
            None)
      )(identity, cName => newColumns(newColumnNames.indexOf(cName)))
      val restLeg = valsLeg.applyColumnGroups(newColumnGroups)
      rgLeg.append(rowLeg).append(restLeg)
    }
    relationRec(ExtMem(tblRecordHardMem)).label(newLegend)
  }

}

class StrictTabular[F[_],A](r: ClosedExt, val ordering: IndexedSeq[(Label, SortOrder)],
                            extract: (Set[ColumnName], Record) => A,
                            postSort: Option[CtCoyo[Order, Record]],
                            labels: Option[Legend.U[Label]],
                            val isTransposed: Boolean)(
  implicit B: Scanner[F]) extends Tabular[F,A] {
  implicit val F = B.M

  private var _records: SoftReference[IndexedSeq[Record]] = null

  private def records: Option[IndexedSeq[Record]] =
    if (_records == null) None
    else _records.get match {
      case null => None
      case xs => Some(xs)
    }

  private def records_=(rs: IndexedSeq[Record]) = {
    _records = new SoftReference(rs)
  }

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
        records = sts
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

  override def takeAllOnce: F[IndexedSeq[A]] =
    records match {
      case Some(ts) => ts.map(extract(columnIds,_)).pure[F]
      case _ => B.scanExt(r.out, Process.wrapping[Record], relationalOrder).map(ts => ts.map(extract(columnIds,_)))
    }
}

