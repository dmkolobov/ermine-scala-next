package com.clarifi.reporting
package writers

import Magnitude._

import collection.immutable.IndexedSeq
import compat.Platform.currentTime

import scalaz.{NonEmptyList, Applicative}
import scalaz.syntax.functor._
import scalaz.std.tuple._

import com.clarifi.reporting.util.PimpedLogger._

import relational._

/** A decorator for writers that spits timing information.
  */
abstract class ProfiledWriter[F[_], C](inner: Writer[F, C])(implicit val R: Run[F])
         extends Writer[F, C] {
  /** Save timing. */
  def spitTime(lbl: String, time: Long, c: C, subs: IndexedSeq[C]): Unit

  private[this] def timed(desc: String, c: => C, subs: => TraversableOnce[C] = Seq.empty
                        ): C = {
    val start = currentTime
    val c2 = c
    val delta = currentTime - start
    spitTime(desc, delta, c2, subs.toIndexedSeq)
    c2
  }

  private[this] def timedF(desc: String, c: => F[C]): F[C] =
    F.pure(timed(desc, R run c))

  def B = inner.B

  def empty = timed("empty", inner.empty)

  def atom(f: Format, p: NonEmptyList[PrimExpr]) =
    timed("atom", inner atom (f, p))

  override def grid(data: List[List[C]]) =
    timed("grid", inner grid data, data.flatten)

  override def style(h: String, target: C) =
    timed("renderingHint", inner style (h, target),
          Seq(target))

  override def prefArea(a: List[Area], target: C) =
    timed("prefArea", inner prefArea (a, target),
          Seq(target))

  override def prefHeight(h: List[Magnitude], target: C) =
    timed("prefHeight", inner prefHeight (h, target),
          Seq(target))

  override def prefWidth(w: List[Magnitude], target: C) =
    timed("prefWidth", inner prefWidth (w, target),
          Seq(target))

  override def scrolling(target: C) =
    timed("scrolling", inner scrolling target, Seq(target))

  def horizontalSpan(cs: List[(Option[Int],C)]) =
    timed("horizontalSpan", inner horizontalSpan cs,
          cs map (_._2))

  def verticalSpan(cs: List[(Option[Int],C)]) =
    timed("verticalSpan", inner verticalSpan cs,
          cs map (_._2))

  def horizontalFlow(cs: List[C]) =
    timed("horizontalFlow", inner horizontalFlow cs, cs)

  def verticalFlow(cs: List[C]) =
    timed("verticalFlow", inner verticalFlow cs, cs)

  def border(center: Option[C], north: Option[C], south: Option[C],
             east: Option[C], west: Option[C]) =
    timed("border",
          inner border (center, north, south, east, west),
          Seq(center, north, south, east, west) collect {case Some(c) => c})

  def tabbed(cs: List[(String,C)]) =
    timed("tabbed", inner tabbed cs, cs map (_._2))

  def table(t: Tabular[F, Record]) =
    timedF("table", inner table t)

  def drilldownTable(labelColumn: String, parentCol: String, childCol: String, isDefaultLegend: Boolean,
                     t: TreeTabular[F, Record]) =
    timedF("drilldownTable",
           inner drilldownTable (labelColumn, parentCol, childCol, isDefaultLegend, t))

  def axisChart(chart: AxisChart[Tabular[F, Record]]) =
    timedF("axisChart", inner axisChart chart)

  def pieChart(pcd: PieChartData, labelcol: Presentation, datacol: Presentation,
               data: Tabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]) =
    timedF("pieChart", inner pieChart (pcd, labelcol, datacol, data))

  def drilldownPieChart(pcd: PieChartData, labelColumn: Presentation,
                        dataCol : Presentation, parentCol: String,
                        childCol: String,
                        data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]) =
    timedF("drilldownPieChart",
           inner drilldownPieChart (pcd, labelColumn, dataCol, parentCol,
                                    childCol, data))

  def drilldownBarChart(meta: AxisChartData, categoryPres: Presentation,
                        dataPres: Presentation,
                        parentCol: String, childCol: String,
                        data: TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]) =
    timedF("drilldownBarChart",
           inner drilldownBarChart (meta, categoryPres, dataPres,
                                    parentCol, childCol, data))

  override def scanRelation(r: ClosedExt, f: List[Record] => F[C], ord: List[(String, SortOrder)] = List()): F[C] =
    timedF("scanRelation", inner scanRelation (r, f, ord))

  override def button(name: NonEmptyList[PrimExpr], fmt: Format, f: (C, SelectorEvent) => F[C]) =
    timedF("button", inner button (name, fmt, f))


  override def textBox(default: String, f: (C, SelectorEvent, ((SelectorEvent, String => F[C]) => F[C])) => F[C]) : F[C] =
    timedF("selector", inner textBox (default, f))

  override def selector[A](mode: SelectorMode, default: (NonEmptyList[PrimExpr],A), fmt: Format, values: List[(NonEmptyList[PrimExpr],A)],
                  f: (C, SelectorEvent, ((SelectorEvent, A => F[C]) => F[C])) => F[C]
                   ) : F[C] = timedF("selector", inner selector (mode, default, fmt,  values, f))

  def run(c: C) = inner run c
}

object ProfiledWriter {
  private val _log = org.apache.log4j.Logger getLogger getClass

  /** Functionified `ProfiledWriter`. */
  def apply[F[_], C](inner: Writer[F, C],
                     writeTimeF: (String, Long) => Unit
                   )(implicit R: Run[F]): Writer[F, C] =
    new ProfiledWriter[F, C](inner) {
      def spitTime(lbl: String, time: Long, c: C, subs: IndexedSeq[C]) =
        writeTimeF(lbl, time)
    }

  /** ProfiledWriter that just logs. */
  def logging[F[_], C](inner: Writer[F, C])(implicit R: Run[F]): Writer[F, C] =
    apply(inner, (lbl, time) =>
      (if (time <= 0) _log.ltrace(_) else _log.ldebug(_))
      ("Built report node %s in %sms" format (lbl, time)))
}
