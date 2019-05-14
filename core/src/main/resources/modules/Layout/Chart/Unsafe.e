module Layout.Chart.Unsafe where

import Layout.Chart.Type
import Layout.Color using type Color
import Layout.Format using type Format
import Layout.Presentation using type Presentation
import Layout.PresRow using type PresRow
import Layout.Report.Atomic
import Native.Map as NM
import Native.Bool
import Native.Either
import Native.Function
import Native.Maybe
import Native.NonEmpty
import Native.List
import Native.Ord using type Ord#
import Native.Pair
import Native.Record using type ScalaRecord#
import Prim using type PrimExpr#
import Relation.Op using type Op
import Relation.Sort using type SortOrder#

type AxisConstraints# = Axis p

foreign
  data "com.clarifi.reporting.writers.AxisChart" AxisChart#
  data "com.clarifi.reporting.writers.PieChartData" PieChartData#
  data "com.clarifi.reporting.writers.AxisChartData" AxisChartData#
  data "com.clarifi.reporting.writers.Axis" Axis#
  data "com.clarifi.reporting.writers.ChartLegendLocation" ChartLegendLocation#
  data "com.clarifi.reporting.writers.ChartLegendOptions" ChartLegendOptions#
  data "com.clarifi.reporting.writers.DrilldownBarAxisChart" DrilldownBarAxisChart# (dd: *) (q: *)
  data "com.clarifi.reporting.writers.ChartOrientation" PlotOrientation#

  data "com.clarifi.reporting.writers.DisplayScale" DisplayScale#
  value "com.clarifi.reporting.writers.DisplayScale$Linear$" "MODULE$" linear# : DisplayScale#
  value "com.clarifi.reporting.writers.DisplayScale$Logarithmic$" "MODULE$" logarithmic# : DisplayScale#

  data "com.clarifi.reporting.writers.SeriesStructure" SeriesStructure#

  value "com.clarifi.reporting.writers.SeriesStructure$Simple$" "MODULE$"
    simpleStructure# : SeriesStructure#

  value "com.clarifi.reporting.writers.SeriesStructure$Complex$" "MODULE$"
    complexStructure#
      : List# (Pair# Int Int) -> List# (Pair# Int Int) -> SeriesStructure#

  value "com.clarifi.reporting.writers.Line$" "MODULE$"
      line# : SeriesStructure# -> ChartVariant#
  value "com.clarifi.reporting.writers.Bar$" "MODULE$"
      bar# : SeriesStructure# -> ChartVariant#
  value "com.clarifi.reporting.writers.Step$" "MODULE$"
      step# : ChartVariant#
  value "com.clarifi.reporting.writers.Scatter$" "MODULE$"
      scatter# : ChartVariant# 
  value "com.clarifi.reporting.writers.Bubble$" "MODULE$"
      bubble# : Atomic# String -> ChartVariant#
  value "com.clarifi.reporting.writers.StackedBar$" "MODULE$"
      stackedBar# : ChartVariant#
  value "com.clarifi.reporting.writers.StackedArea$" "MODULE$"
      stackedArea# : ChartVariant#
  value "com.clarifi.reporting.writers.BoxAndWhiskers$" "MODULE$"
      boxAndWhiskers# : ChartVariant#

  value "com.clarifi.reporting.writers.ChartOrientation$Horizontal$" "MODULE$" horizontal# : PlotOrientation#
  value "com.clarifi.reporting.writers.ChartOrientation$Vertical$" "MODULE$" vertical# : PlotOrientation#

  value "com.clarifi.reporting.writers.ChartLegendLocation$Default$" "MODULE$"
      chartLegendDefaultLocation# : ChartLegendLocation#
  value "com.clarifi.reporting.writers.ChartLegendLocation$Above$" "MODULE$"
      chartLegendAbove# : ChartLegendLocation#
  value "com.clarifi.reporting.writers.ChartLegendLocation$Overlay$" "MODULE$"
      chartLegendOverlay# : ChartLegendLocation#
  value "com.clarifi.reporting.writers.ChartLegendLocation$RightOverlay$" "MODULE$"
      chartLegendRightOverlay# : ChartLegendLocation#
  value "com.clarifi.reporting.writers.ChartLegendLocation$RightNotOverlay$" "MODULE$"
        chartLegendRightNotOverlay# : ChartLegendLocation#
  value "com.clarifi.reporting.writers.ChartLegendLocation$Hidden$" "MODULE$"
      chartLegendHidden# : ChartLegendLocation#

  function "com.clarifi.reporting.writers.ChartLegendOptions" "default"
      defaultChartLegendOptions# : ChartLegendOptions#

  function "com.clarifi.reporting.writers.PieChartData" "rescopeColors"
    rescopePieColors# : Presentation r a
                     -> List# (Pair# ScalaRecord# Color) -- Has r r'
                     -> PieColors#
  function "com.clarifi.reporting.writers.AxisChartData" "unifyColors"
    unifyColors## : List# (Pair# (ChartSeries# xa ya) (List# (Pair# ScalaRecord# Color)))
                 -> AxisColors#
  function "com.clarifi.reporting.writers.AxisConstraints" "unifyTicks"
    unifyTicks## : List# (Pair# (ChartSeries# xa ya)
                                (Pair# (List# (Pair# ScalaRecord# ScalaRecord#))
                                       (List# (Pair# ScalaRecord# ScalaRecord#))))
                -> Axis xa -> Axis ya
                -> Pair# (Axis xa) (Axis ya)

  function "com.clarifi.reporting.writers.DrilldownBarAxisChart" "rescopeTicks"
    rescopeTicks## : Presentation xr xa -> Presentation yr ya
                  -> List# (Pair# ScalaRecord# ScalaRecord#) -> List# (Pair# ScalaRecord# ScalaRecord#)
                  -> AxisChartData# -> AxisChartData#

private
  type AxisColors# = Map_NM (NonEmpty# PrimExpr#) Color
  type PieColors# = Map_NM (NonEmpty# PrimExpr#) Color

-- Data constructors
private foreign
  data "com.clarifi.reporting.writers.AxisChart$" AxisChartModule#
  value "com.clarifi.reporting.writers.AxisChart$" "MODULE$"
      axisChartModule : AxisChartModule#
  method "apply" axisChartApply# : AxisChartModule# -> List# (ChartSeries# x y) -> AxisChartData# -> AxisChart#

  value "com.clarifi.reporting.writers.PieChartData$" "MODULE$"
      pieChartDataModule : Function4 (Maybe# String) (Maybe# (Atomic# nm)) ChartLegendOptions# PieColors#
                                     PieChartData#

  value "com.clarifi.reporting.writers.ChartLegendOptions$" "MODULE$"
      chartLegendOptionsModule : Function1 ChartLegendLocation# ChartLegendOptions#

  value "com.clarifi.reporting.writers.AxisChartData$" "MODULE$"
      axisChartDataModule : Function6 Axis# Axis# (Maybe# String) PlotOrientation#
                                      ChartLegendOptions#
                                      AxisColors# AxisChartData#

  value "com.clarifi.reporting.writers.Axis$" "MODULE$"
      axisModule : Function4 (Maybe# (EitherZ# (Atomic# l) (Atomic# l'))) (Format p) (Axis p) Bool# Axis#

  value "com.clarifi.reporting.writers.ScaledConstraints$" "MODULE$"
      scaledConstraintsModule : Function4 SortOrder# (Maybe# PrimExpr#) (Maybe# PrimExpr#) DisplayScale# (Axis a)

  value "com.clarifi.reporting.writers.UnscaledConstraints$" "MODULE$"
      unscaledConstraintsModule : Function2 (EitherZ# SortOrder# (Ord# PrimExpr#)) (MapZ#_NM PrimExpr# PrimExpr#) (Axis a)

  data "com.clarifi.reporting.writers.ChartSeries$" ChartSeriesModule#
  value "com.clarifi.reporting.writers.ChartSeries$" "MODULE$"
      chartSeriesModule : ChartSeriesModule#
  method "apply" chartSeriesApply# : ChartSeriesModule# -> Presentation sr sa -> Op xr xa -> Op yr ya -> Maybe# (Presentation xtr xta) -> Maybe# (Presentation ytr yta) -> ChartVariant# -> PresRow er -> z -> ChartSeries# xa ya

  data "com.clarifi.reporting.writers.DrilldownBarAxisChart$" DrilldownBarAxisChartModule#
  value "com.clarifi.reporting.writers.DrilldownBarAxisChart$" "MODULE$"
      drilldownBarAxisChartModule : DrilldownBarAxisChartModule#
  method "apply" drilldownBarAxisChartApply# : DrilldownBarAxisChartModule# -> Presentation sr sa -> Presentation xr xa -> Presentation yr ya -> Maybe# (Presentation xtr xta) -> Maybe# (Presentation ytr yta) -> q -> dd -> AxisChartData# -> DrilldownBarAxisChart# dd q

axisChart# = axisChartApply# axisChartModule
axisChartData# = funcall6# axisChartDataModule
pieChartData# = funcall4# pieChartDataModule
axis# = funcall4# axisModule
scaledConstraints# = funcall4# scaledConstraintsModule
unscaledConstraints# = funcall2# unscaledConstraintsModule
chartSeries# = chartSeriesApply# chartSeriesModule
chartLegendOptions# = funcall1# chartLegendOptionsModule
drilldownBarAxisChart# = drilldownBarAxisChartApply# drilldownBarAxisChartModule

toChartSeries# (ChartSeries c xti yti so xo yo xto yto cv ex r) =
  chartSeries# so xo yo (toMaybe# xto) (toMaybe# yto) cv ex r
