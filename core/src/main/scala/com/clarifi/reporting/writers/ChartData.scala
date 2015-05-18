// Most of this file is exploited unsafely by Layout.Chart.Unsafe;
// please take care to update the erased types therein when altering
// these types.

package com.clarifi.reporting
package writers

import scalaz.{
  Applicative, Cord, Enum, Lens, Monoid, NonEmptyList, Order,
  Ordering, Show, Tag, Traverse
}
import scalaz.Tags.Disjunction
import scalaz.std.list._
import scalaz.std.option._
import scalaz.std.tuple._
import scalaz.syntax.apply._
import scalaz.syntax.bind.{^ => _, _}
import scalaz.syntax.equal._
import scalaz.syntax.traverse._

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
}

object AxisChart {
  implicit def axisChartInstance: Traverse[AxisChart] = new Traverse[AxisChart] {
    def traverseImpl[F[_]: Applicative, A, B
                   ](x: AxisChart[A])(f: A => F[B]): F[AxisChart[B]] =
      x.series traverse (_ traverse f) map (s => x.copy(series = s))
  }

  /* TODO SMRC after scalaz da692cf9
  def seriesL[A, B]: LensFamily[AxisChart[A], AxisChart[B],
                                List[ChartSeries[A]], List[ChartSeries[B]]] =
    Lens lensFamilyu ((c, s) => c copy (series = s), _.series)
   */
}

object ChartLegendOptions extends ((ChartLegendLocation) => ChartLegendOptions) {
  val default = ChartLegendOptions(DefaultLocation)
}

sealed trait ChartLegendLocation
  case object DefaultLocation extends ChartLegendLocation
  case object Overlay extends ChartLegendLocation
  case object Hidden extends ChartLegendLocation

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
                        colors: PieColors
                          = Map.empty)
    extends ChartData

object PieChartData extends ((Option[String], PieColors) => PieChartData) {
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
  * @param colors How to color values, according to series and
  *               category.  Absent mappings will be automatically
  *               colored.
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
  def rescopeColors(series: ChartSeries[_], scolors: List[(Record, Color)]
                   ): AxisColors =
    scolors.view.map{case (r, v) =>
      (series.selSeries extract r, v)
    }.toMap

  /** Unify colors individually specified for a series into one color
    * specification for the whole chart.
    */
  def unifyColors(series: List[(ChartSeries[_], List[(Record, Color)])]
                 ): AxisColors = {
    implicit val lastColor = Monoid.instance[AxisColors](_ ++ _, Map.empty)
    series foldMap ((rescopeColors _).tupled)
  }
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

/** Direction-independent description of an axis. */
case class Axis(label: Option[Atomic],
                format: Format,
                constraints: AxisConstraints,
                showTicks: Boolean = true)

object Axis extends ((Option[Atomic], Format, AxisConstraints, Boolean) => Axis) {
  /** Format lens. */
  val formatL: Lens[Axis, Format] =
    Lens lensu ((ax, f) => ax copy (format = f), _.format)
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
       | _: DateT | _: DoubleT => true
    case _: StringT | _: BooleanT | _: UuidT => false
  }
}

/** Constraints on an axis of Scaled values.
  *
  * @param sortOrder Order relative to display origin.
  * @param lower Lower bound, inclusive.  Computed by backend if absent.
  * @param upper Upper bound, inclusive.  Computed by backend if absent.
  */
case class ScaledConstraints(sortOrder: SortOrder,
                             lower: Option[PrimExpr],
                             upper: Option[PrimExpr]) extends AxisConstraints {
  def transformOrder[A](asPe: A => PrimExpr)(implicit usualOA: Order[A]): Order[A] =
    sortOrder match {
      case SortOrder.Asc => usualOA
      case SortOrder.Desc => usualOA.reverseOrder
    }
}

/** Constraints on an axis of Unscaled values.
  *
  * @param sort How to order the discrete values.  Either the natural
  *             order, or by a less-than function.
  */
case class UnscaledConstraints(sort: Either[SortOrder, (PrimExpr, PrimExpr) => Boolean])
     extends AxisConstraints {
  import UnscaledConstraints._

  def transformOrder[A](asPe: A => PrimExpr)(implicit usualOA: Order[A]): Order[A] =
    sort match {
      case Left(SortOrder.Asc) => usualOA
      case Left(SortOrder.Desc) => usualOA.reverseOrder
      case Right(lt) => less(lt) contramap asPe
    }
}

object UnscaledConstraints extends (Either[SortOrder, (PrimExpr, PrimExpr) => Boolean]
                                    => UnscaledConstraints) {
  /** Lift a less-than function to an Order. */
  private[UnscaledConstraints] def less[A](lt: (A, A) => Boolean): Order[A] =
    Order.order((l, r) => () match {
      case _ if lt(l, r) => Ordering.LT
      case _ if lt(r, l) => Ordering.GT
      case _ => Ordering.EQ
    })
}

/** A set of series in a chart, described by `Data`.
  *
  * @tparam Data What `dataSource` is.
  * @param selSeries Selection and display of series from `dataSource`.
  * @param selCategory Selection and display of domain from `dataSource`.
  * @param selValue Selection and display of range from `dataSource`.
  * @param variant Chart-style-specific options.
  * @param dataSource From whence triples shall come.
  */
case class ChartSeries[Data](selSeries: Presentation,
                             selCategory: Op,
                             selValue: Op,
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
