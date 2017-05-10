// Most of this file is exploited unsafely by Layout.Chart.Unsafe;
// please take care to update the erased types therein when altering
// these types.

package com.clarifi.reporting
package writers

import scalaz.{
  @>, ==>>, \/, -\/, \/-, Applicative, Bitraverse, Cord, Enum, Lens,
  LensFamily, Monoid, NonEmptyList, Order, Ordering, Show, Tag,
  Traverse
}
import scalaz.Tags.Disjunction
import scalaz.std.list._
import scalaz.std.option._
import scalaz.syntax.apply._
import scalaz.syntax.bind.{^ => _, ToFunctorOps => _, _}
import scalaz.syntax.equal._
import scalaz.syntax.id._
import scalaz.syntax.traverse.{ToFunctorOps => _, _}

import java.awt.Color

import ChartDesiderata._

/** Description of a layered chart of three-dimensional data
  * (category, value, discrete series) displayed over shared axes.
  *
  * @tparam Data The data store attached to each `series`.
  * @param series Layered individual charts.
  * @param meta Details of chart display shared across all `series`.
  */
case class AxisChart[Data](series: List[ChartSeries[Data]],
                           meta: AxisChartData) {
  def categoryType: Option[PrimT] =
    Tag.unsubst(series.foldMap(s => some(Disjunction(some(s.categoryType))))).join

  def valueType: Option[PrimT] =
    Tag.unsubst(series.foldMap(s => some(Disjunction(some(s.valueType))))).join

  def invariantFailures: Seq[String] = if (series.isEmpty) Seq.empty else
    ^(categoryType, valueType){(catT, valT) =>
      (Seq((AxisConstraints primitiveScaled catT, meta.domain.constraints),
           (AxisConstraints primitiveScaled valT, meta.range.constraints)) flatMap {
             case (true, _: ScaledConstraints) => Seq.empty
             case (false, _: UnscaledConstraints) => Seq.empty
             case _ => Seq("Scalability of category/value type must match axis constraint")
           }) ++ (series flatMap (s =>
                   if (s.variant permitsConstraint meta.range.constraints) Seq.empty
                   else Seq("%s doesn't support %s"
                            format (s.variant, meta.range.constraints))))
      } getOrElse Seq("All series must have same category/value types")

  def augmentSeries: AxisChart[Data] = meta match {
    case AxisChartData(domain, range, _, _, _, _) =>
      def augment(fmt: Format, op: Op, opres: Option[Presentation]) : Option[Presentation] =
        opres match {
          case None => Some(Presentation(fmt, NonEmptyList(op)))
          case e => e
        }
      val newSeries = series map {
        case ChartSeries(ss, sx, sy, xtt, ytt, v, data) =>
          ChartSeries(ss, sx, sy, augment(domain.format, sx, xtt), augment(range.format, sy, ytt), v, data)
      }
      AxisChart(newSeries, meta)
  }
}

object AxisChart {
  implicit def axisChartInstance: Traverse[AxisChart] = new Traverse[AxisChart] {
    def traverseImpl[F[_]: Applicative, A, B
                   ](x: AxisChart[A])(f: A => F[B]): F[AxisChart[B]] =
      x.series traverse (_ traverse f) map (s => x.copy(series = s))
  }

  def seriesL[A, B]: LensFamily[AxisChart[A], AxisChart[B],
                                List[ChartSeries[A]], List[ChartSeries[B]]] =
    Lens lensFamilyu ((c, s) => c copy (series = s), _.series)
}

object ChartLegendOptions extends ((ChartLegendLocation) => ChartLegendOptions) {
  val default = ChartLegendOptions(ChartLegendLocation.Default)
}

sealed abstract class ChartLegendLocation extends Product with Serializable

object ChartLegendLocation {
  case object Default extends ChartLegendLocation
  case object Above extends ChartLegendLocation
  case object Overlay extends ChartLegendLocation
  case object RightOverlay extends ChartLegendLocation
  case object RightNotOverlay extends ChartLegendLocation
  case object Hidden extends ChartLegendLocation
}


case class ChartLegendOptions(location: ChartLegendLocation)


/**
 * Encapsulates non-datapoint information relevant to rendering charts.
 */
sealed trait ChartData {
  def title: Option[String]
//  def legend = true
//  def tooltips = true
//  def URLs = false
}

/** Information for rendering a pie chart.
  *
  * @param colors How to color values, according to series and
  *               category.  Absent mappings will be automatically
  *               colored.
  */
case class PieChartData(title: Option[String] = None,
                        seriesName: Option[Atomic] = None,
                        legendOptions: ChartLegendOptions = ChartLegendOptions.default,
                        colors: PieColors
                          = Map.empty)
    extends ChartData

object PieChartData extends ((Option[String], Option[Atomic], ChartLegendOptions, PieColors) => PieChartData) {
  def rescopeColors(cat: Presentation, colors: List[(Record, Color)]
                   ): Map[NonEmptyList[PrimExpr], Color] =
    colors.view.map{case (rec, color) => (cat extract rec, color)}.toMap
}

/** Axes, orientation, other non-data details of an `AxisChart`.
  *
  * @param domain The category axis.
  * @param range The value axis.
  * @param title Chart title to display, if present.
  * @param orientation `Vertical` if range should run vertically,
  *                    `Horizontal` otherwise.
  * @param colors How to color values, according to series.  Absent
  *               mappings will be automatically colored.
  */
case class AxisChartData(domain: Axis,
                         range: Axis,
                         title: Option[String] = None,
                         orientation: ChartOrientation = ChartOrientation.Vertical,
                         legendOptions: ChartLegendOptions = ChartLegendOptions.default,
                         colors: AxisColors = Map.empty)
     extends ChartData

object AxisChartData extends ((Axis, Axis, Option[String], ChartOrientation, ChartLegendOptions,
                               AxisColors)
                              => AxisChartData) {
  /** Domain lens. */
  val domainL: Lens[AxisChartData, Axis] =
    Lens lensu ((ad, x) => ad copy (domain = x), _.domain)
  /** Range lens. */
  val rangeL: Lens[AxisChartData, Axis] =
    Lens lensu ((ad, x) => ad copy (range = x), _.range)

  /** Describe the colors associated with a series in the language of
    * [[com.clarifi.reporting.writers.AxisChartData]].
    */
  private[this]
  def rescopeColors(series: ChartSeries[_], scolors: List[(Record, Color)]
                   ): AxisColors =
    scolors.view.map{case (r, v) =>
      (series.selSeries extract r, v)
    }.toMap

  /** Unify colors individually specified for a series into one color
    * specification for the whole chart.
    */
  def unifyColors[A](series: List[(ChartSeries[A], List[(Record, Color)])])
      : AxisColors = {
    implicit val lastColor = Monoid.instance[AxisColors](_ ++ _, Map.empty)
    series foldMap ((rescopeColors _).tupled)
  }

  /** Lift record-based tick label overrides to the chart level. */
  private[writers]
  def rescopeTicks[A, B: Order](on: List[(A, A)])(f: A => B): B ==>> B =
    ==>>.fromList(on.map{case (r, v) => (f(r), f(v))}
                    .filter{case (r, v) => r /== v})
}

sealed abstract class ChartOrientation extends Product with Serializable {
  def flip: ChartOrientation
  def ?|?(o: ChartOrientation): Ordering
}

object ChartOrientation {
  case object Vertical extends ChartOrientation {
    def flip = Horizontal
    override def toString = "VERTICAL"

    def ?|?(o: ChartOrientation) = o match {
      case Vertical => Ordering.EQ
      case Horizontal => Ordering.LT
    }
  }
  case object Horizontal extends ChartOrientation {
    def flip = Vertical
    override def toString = "HORIZONTAL"

    def ?|?(o: ChartOrientation) = o match {
      case Horizontal => Ordering.EQ
      case Vertical => Ordering.GT
    }
  }

  implicit val instance: Enum[ChartOrientation] with Show[ChartOrientation] =
    new Enum[ChartOrientation] with Show[ChartOrientation] {
      def succ(co: ChartOrientation) = co.flip
      def pred(co: ChartOrientation) = co.flip
      override def min = some(Vertical)
      override def max = some(Horizontal)
      override def equalIsNatural = true

      def order(a: ChartOrientation, b: ChartOrientation) = a ?|? b

      override def show(co: ChartOrientation) = co.toString: Cord
    }
}

sealed abstract class ChartAxisScale extends Product with Serializable

object ChartAxisScale {
  case object Linear extends ChartAxisScale
  case object Logarithmic extends ChartAxisScale
}


/** Direction-independent description of an axis.
  *
  * @param label If defined, either a tooltip-only label, or a label
  *              to also show on the axis.
  * @param format How to format results of associated `Op`, whether
  *               category or value.
  * @param constraints Further rules dependent on whether this is a
  *                    scaled or unscaled axis.
  * @param showTicks Whether to show ticks.
  */
case class Axis(label: Option[Atomic \/ Atomic],
                format: Format,
                constraints: AxisConstraints,
                showTicks: Boolean = true)

object Axis extends ((Option[Atomic \/ Atomic], Format, AxisConstraints, Boolean) => Axis) {
  /** Format lens. */
  val formatL: Lens[Axis, Format] =
    Lens lensu ((ax, f) => ax copy (format = f), _.format)

  /** Constraints lens. */
  val constraintsL: Axis @> AxisConstraints =
    Lens lensu ((ax, c) => ax copy (constraints = c), _.constraints)
}

/** Scaled/unscaled-specific axis options. */
sealed abstract class AxisConstraints {
  /** Catamorphism, sanity-checking against `e`.
    *
    * @param scaled Called with myself if `e` can be constrained suchly.
    * @param unscaled Likewise.
    * @param error Fallback. */
  def constraining[Z](e: PrimExpr)(scaled: ScaledConstraints => Z,
                                   unscaled: UnscaledConstraints => Z,
                                   error: => Z = sys error ("%s cannot constrain %s" format (this, e))): Z =
    (AxisConstraints primitiveScaled e.typ, this) match {
      case (true, c: ScaledConstraints) => scaled(c)
      case (false, c: UnscaledConstraints) => unscaled(c)
      case _ => error
    }

  /** Build an alternative ordering of `A`s using my relative
    * reordering rules.
    *
    * @param asPe Isomorphism.
    * @param usualOA Natural ordering of `A`s to be transformed.
    * @returns `usualOA`, but suited to `A`s constrained by myself. */
  def transformOrder[A](asPe: A => PrimExpr)(implicit usualOA: Order[A]): Order[A]
}

object AxisConstraints {
  import PrimT._
  /** Answer whether `t` requires a ScaledConstraints; it requires
    * UnscaledConstraints otherwise. */
  def primitiveScaled(t: PrimT): Boolean = t match {
    case _: ByteT | _: ShortT | _: IntT | _: LongT
       | _: DateT | _: DoubleT | _: TimestampT => true
    case _: StringT | _: BooleanT | _: UuidT => false
  }


  /** Lift record-based tick label overrides into one tick label
    * specification for the whole chart.  Has a weird signature that's
    * convenient to call from Ermine.
    */
  def unifyTicks[A](series: List[(ChartSeries[A], (List[(Record, Record)],
                                                   List[(Record, Record)]))],
                    catc: AxisConstraints, valc: AxisConstraints)
      : (AxisConstraints, AxisConstraints) = {
    implicit val lastTick = Monoid.instance[PrimExpr ==>> PrimExpr](_ union _, ==>>.empty)
    def xf(op: ChartSeries[A] => Op,
           f: ((List[(Record, Record)], List[(Record, Record)]))
             => List[(Record, Record)], on: AxisConstraints) = on match {
      case us: UnscaledConstraints => us.copy(
        tickOverrides = series foldMap {case (s, lsts) =>
          AxisChartData.rescopeTicks(f(lsts))(op(s).eval)})
      case _: ScaledConstraints => on
    }
    (xf(_.selCategory, _._1, catc), xf(_.selValue, _._2, valc))
  }
}

sealed abstract class DisplayScale extends Product with Serializable

object DisplayScale {
  case object Linear extends DisplayScale
  case object Logarithmic extends DisplayScale
}

/** Constraints on an axis of Scaled values.
  *
  * @param sortOrder Order relative to display origin.
  * @param lower Lower bound, inclusive.  Computed by backend if absent.
  * @param upper Upper bound, inclusive.  Computed by backend if absent.
  * @param displayScale how data is displayed, linear, log or whichever.
  */
case class ScaledConstraints(sortOrder: SortOrder,
                             lower: Option[PrimExpr],
                             upper: Option[PrimExpr],
                             displayScale: DisplayScale
                           ) extends AxisConstraints {
  def transformOrder[A](asPe: A => PrimExpr)(implicit usualOA: Order[A]): Order[A] =
    sortOrder match {
      case SortOrder.Asc => usualOA
      case SortOrder.Desc => usualOA.reverseOrder
    }
}

/** Constraints on an axis of Unscaled values.
  *
  * @param sort How to order the discrete values.  Either the natural
  *             order, or by an ordering.
  * @param tickOverrides Different values to show at ticks along the
  *                      axis, formatted with the same format.
  */
case class UnscaledConstraints(sort: SortOrder \/ Order[PrimExpr],
                               tickOverrides: PrimExpr ==>> PrimExpr = ==>>.empty)
     extends AxisConstraints {
  def transformOrder[A](asPe: A => PrimExpr)(implicit usualOA: Order[A]): Order[A] =
    sort match {
      case -\/(SortOrder.Asc) => usualOA
      case -\/(SortOrder.Desc) => usualOA.reverseOrder
      case \/-(o) => o contramap asPe
    }
}

/** A set of series in a chart, described by `Data`.
  *
  * @tparam Data What `dataSource` is.
  * @param selSeries Selection and display of series from `dataSource`.
  * @param selCategory Selection and display of domain from `dataSource`.
  * @param selValue Selection and display of range from `dataSource`.
  * @param selCatTooltips Selection and display of category axis tooltips from `dataSource`.
  * @param selValTooltips Selection and display of value axis tooltips from `dataSource`.
  * @param variant Chart-style-specific options.
  * @param dataSource From whence triples shall come.
  */
case class ChartSeries[Data](selSeries: Presentation,
                             selCategory: Op,
                             selValue: Op,
                             selCatTooltips: Option[Presentation],
                             selValTooltips: Option[Presentation],
                             variant: ChartVariant,
                             dataSource: Data) {
  def categoryType: PrimT =
    selCategory.guessType fold (sys error _.head, identity)

  def valueType: PrimT =
    selValue.guessType fold (sys error _.head, identity)

  def basicEval: (Record => (PrimExpr, C, V), PrimType[C], PrimType[V])
                 forSome {type C; type V} =
    (categoryType.primType, valueType.primType) match {
      case (c, v) =>
        ((tu:Record) => (selSeries.basicEval(tu),
                       c.unExpr(selCategory.eval(tu)),
                       v.unExpr(selValue.eval(tu))),
         c, v)
    }
}

object ChartSeries {
  implicit def chartSeriesInstance: Traverse[ChartSeries] = new Traverse[ChartSeries] {
    def traverseImpl[F[_]: Applicative, A, B
                   ](x: ChartSeries[A])(f: A => F[B]): F[ChartSeries[B]] =
      f(x.dataSource) map (d => x copy (dataSource=d))
  }
}

sealed abstract class ChartVariant {
  def permitsConstraint(c: AxisConstraints): Boolean = true
}

sealed abstract class ScaledChartVariant extends ChartVariant {
  override def permitsConstraint(c: AxisConstraints): Boolean = c match {
    case _: ScaledConstraints => true
    case _: UnscaledConstraints => false
  }
}

case object Line extends ChartVariant
case object Bar extends ChartVariant
case object Step extends ChartVariant
case object Scatter extends ChartVariant
case object StackedBar extends ScaledChartVariant
case object StackedArea extends ScaledChartVariant
case object BoxAndWhiskers extends ScaledChartVariant

object ChartDesiderata {
  type AxisColors = Map[NonEmptyList[PrimExpr], Color]
  type PieColors = Map[NonEmptyList[PrimExpr], Color]
}

/** Drilldown bar charts are currently something like half-encoded in
  * the `AxisChart` form.  They aren't expected to support all the
  * features of `AxisChart` as of this writing, so a separate
  * structure is used, despite the duplication this causes.
  * Nevertheless, drilldown bars do degrade to `AxisChart` by losing
  * their drilldown-ness.
  *
  * @todo Merge into axis chart API.
  * @todo Lose `DD` tparam by merging the two cases we actually use.
  */
final case class DrilldownBarAxisChart[DD, Data](
  selSeries: Presentation,
  selCategory: Presentation,
  selValue: Presentation,
  selCatTooltips: Option[Presentation],
  selValTooltips: Option[Presentation],
  dataSource: Data,
  drilldownCols: DD,
  meta: AxisChartData) {
  /** Remove information unsupported by AxisChart and fill in what's
    * sensible in the AxisChart API.
    */
  def asAxisChart: AxisChart[Data] =
    AxisChart(List(ChartSeries(selSeries,
                               selCategory.displayData.head,
                               selValue.displayData.head,
                               selCatTooltips, selValTooltips,
                               Bar, dataSource)),
              meta)

  /** Make the `meta` formats the semigroup sum of the category/value
    * presentation formats.  Usually what you want.
    *
    * This is kind of nonsense, because really AxisChartData shouldn't
    * have a Format at all, and it should be derived from the
    * semigroup sum of formats of presentations of each ChartSeries in
    * question.  That's just not how it is right now.
    *
    * @note x.flattenFormat.flattenFormat = x.flattenFormat
    */
  def flattenFormat: DrilldownBarAxisChart[DD, Data] =
    copy(meta = meta
           |> (AxisChartData.domainL >=> Axis.formatL set (_, selCategory.format))
           |> (AxisChartData.rangeL >=> Axis.formatL set (_, selValue.format)))
}

object DrilldownBarAxisChart {
  implicit val dbacInstance: Bitraverse[DrilldownBarAxisChart] = new Bitraverse[DrilldownBarAxisChart] {
    def bitraverseImpl[F[_]: Applicative, A, B, C, D
                     ](x: DrilldownBarAxisChart[A, B])(f: A => F[C], g: B => F[D]): F[DrilldownBarAxisChart[C, D]] =
      ^(g(x.dataSource), f(x.drilldownCols))((d2, dd2) =>
        x copy (dataSource = d2, drilldownCols = dd2))
  }

  def dataSourceL[A, D, D2]: LensFamily[DrilldownBarAxisChart[A, D], DrilldownBarAxisChart[A, D2],
                                        D, D2] =
    LensFamily lensFamilyu ((d, a) => d copy (dataSource = a), _.dataSource)

  /** Lift record-based tick label overrides into one tick label
    * specification for the whole chart.  Has a weird signature that's
    * convenient to call from Ermine.
    *
    * It's not currently possible to represent all valid drilldown
    * category/value overrides in this way, because `AxisChartData`
    * operates over single Ops, but we have Nels of Ops (so Nels of
    * PEs) at hand.  The fix here is to "support date range
    * category/values in axis charts", which entails full
    * presentations (and elimination of the AxisChartData format).
    */
  def rescopeTicks(catpr: Presentation, valpr: Presentation,
                   oncat: List[(Record, Record)], onval: List[(Record, Record)],
                   into: AxisChartData): AxisChartData = {
    def xf(on: List[(Record, Record)], pr: Presentation, into: Axis) = into.constraints match {
      case uc: UnscaledConstraints =>
        val ticks = AxisChartData.rescopeTicks(on)(c => pr.extract(c).head)
        into.copy(constraints = uc.copy(tickOverrides = ticks))
      case _: ScaledConstraints => into
    }
    into.copy(domain = xf(oncat, catpr, into.domain),
              range = xf(onval, valpr, into.range))
  }
}
