/*
TODO: Port this later to the new relations
package com.clarifi.reporting.writers

import java.util.Date

import scalaz.{@@, IterV, Monoid, NonEmptyList, WriterT}
import scalaz.Id._
import scalaz.Tags.Disjunction
import scalaz.WriterT.writer
import scalaz.std.list._
import scalaz.std.option._
import scalaz.syntax.foldable._
import scalaz.syntax.monoid._

import com.clarifi.{reporting => ccr}
import ccr.{BackedColumn, PrimExpr, Provenance, Relation, RTag,
            Scanner, SortOrder, Sourced, Tuple, TypeTag}
import ccr.Provenance.RefUsage
import ccr.Provenance.RefUsage._        // for Disjunction monoid

import ccr.ermine

import CapabilitySink._

/** Collect `C`s by default. */
trait MonoidWriter[F[_], C] extends Writer[F, C] {
  protected def Cmonoid: Monoid[C]
  private implicit def mCmonoid = Cmonoid

  def empty = mzero[C]

  def atom(f: Format, p: NonEmptyList[PrimExpr]) = empty

  override def grid(data: List[List[C]]) = data.flatten.suml

  def horizontalSpan(cs: List[(Option[Int],C)]) = cs foldMap (_._2)

  def verticalSpan(cs: List[(Option[Int],C)]) = cs foldMap (_._2)

  def horizontalFlow(cs: List[C]) = cs.suml

  def verticalFlow(cs: List[C]) = cs.suml

  def border(center: Option[C], north: Option[C], south: Option[C],
             east: Option[C], west: Option[C]) =
    List(center, north, south, east, west) foldMap (_.suml)

  def tabbed(cs: List[(String,C)]) = cs foldMap (_._2)
}

/** Fake-execute a report, gathering up
  * [[com.clarifi.reporting.Provenance]] from the underlying
  * relations. */
class CapabilitySink
      extends MonoidWriter[RefUsageWriter, RefUsage @@ Disjunction] {
  type F[A] = RefUsageWriter[A]
  type C = RefUsage @@ Disjunction

  protected def Cmonoid = implicitly[Monoid[C]]
  def B = implicitly[Scanner[F, Sourced]]

  def run(c: C) = ()

  def table(t: Tabular[F, Tuple]) = F.point(capabilityOf tabular t)

  def drilldownTable(labelColumn: String, parentCol: String,
                     childCol: String, query: Relation[Sourced],
                     t: TreeTabular[F, Tuple]) =
    F.point(capabilityOf treeTabular t)

  def axisChart(args: AxisChart[Tabular[F,Tuple]]) =
    F.point(args foldMap capabilityOf.tabular)

  def pieChart(pcd: PieChartData, labelcol: Presentation, datacol: Presentation, data: Tabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]) =
    F.point(capabilityOf tabular data)

  def drilldownPieChart(pcd: PieChartData, labelColumn: Presentation,
                        dataCol: Presentation, parentCol: String, childCol: String,
                        query: Relation[Sourced],
                        data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]) =
    F.point(capabilityOf treeTabular data)

  def drilldownBarChart(meta: AxisChartData, seriesPres: Presentation,
                        categoryPres: Presentation, dataPres: Presentation,
                        parentCol: String, childCol: String, query: Relation[Sourced],
                        data: TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]): F[C] =
    F.point(capabilityOf treeTabular data)

  override def selector[A](mode: SelectorMode, choice: Choice[A],
                           f: (C, SelectorEvent, ((SelectorEvent, A => F[C]) => F[C])) => F[C]) : F[C] =
    F.point(choice match {
      case RemoteChoice(get, _) => capabilityOf untaggedRelation get
      case LocalChoice(_, _) => empty
      case DynamicChoice(_) => empty
    })

  override def button(name: String, f: (C, SelectorEvent) => F[C]) : F[C] = F.point(empty)
}

/** A scanner that doesn't yield any tuples, instead yielding EOF and
  * leaving `RefUsage @@ Disjunction` in the wrapping writer.
  *
  * @note 1bc3afedbfe3 removed the fast path for RTags with Provenance
  * in them, because we don't get them.  Restore if the writer tags
  * change. */
class ReferencingScanner[H] extends Scanner[RefUsageWriter, H] {
  def scan[A](r: Relation[H], f: IterV[Tuple, A],
              order: List[(String, SortOrder)]) =
    writer((capabilityOf untaggedRelation r, f feed IterV.EOF.apply))
}

object CapabilitySink {
  /** Capability extractors, each yielding `Result`. */
  object capabilityOf {
    type Result = RefUsage @@ Disjunction
    def relation[H](r: Relation[H])(implicit tag: RTag[H],
                                    prov: H => Provenance[BackedColumn]): Result =
      Disjunction(prov(r.extract) references (tag toHeader r.extract))

    def untaggedRelation(r: Relation[_]): Result =
      relation(implicitly[RTag[(Provenance[BackedColumn], TypeTag)]].retag(r))

    /** @note If Tabular and TreeTabular should change, we can scan
      *   the relation and extract from RefUsageWriter, instead. */
    def tabular(t: Tabular[F, _] forSome {type F[A]}): Result =
      untaggedRelation(t.relation)

    def treeTabular(t: TreeTabular[F, _] forSome {type F[A]}): Result =
      tabular(t.children)
  }

  implicit def unliftProv[K, H](x: (Provenance[K], H)): Provenance[K] = x._1

  /** @see [[com.clarifi.reporting.writers.ReferencingScanner]] */
  implicit def scanner[H]: Scanner[RefUsageWriter, H] = new ReferencingScanner

  /** Writer of `RefUsage`s. */
  type RefUsageWriter[A] = WriterT[Id, RefUsage @@ Disjunction, A]
}
*/
