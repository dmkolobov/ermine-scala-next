module Layout.Chart.Unsafe where

import Layout.Chart.Type
import Layout.Color using type Color
import Layout.Format using type Format
import Layout.Presentation using type Presentation
import Layout.Report.Atomic
import Native.Map as NM
import Native.Bool
import Native.Either
import Native.Function
import Native.Maybe
import Native.NonEmpty
import Native.List
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
  data "com.clarifi.reporting.writers.ChartVariant" ChartVariant#
  data "com.clarifi.reporting.writers.ChartLegendLocation" ChartLegendLocation#
  data "com.clarifi.reporting.writers.ChartLegendOptions" ChartLegendOptions#
  data "org.jfree.chart.plot.PlotOrientation" PlotOrientation#

  value "com.clarifi.reporting.writers.Line$" "MODULE$"
      line# : ChartVariant#
  value "com.clarifi.reporting.writers.Bar$" "MODULE$"
      bar# : ChartVariant#
  value "com.clarifi.reporting.writers.Step$" "MODULE$"
      step# : ChartVariant#
  value "com.clarifi.reporting.writers.Scatter$" "MODULE$"
      scatter# : ChartVariant#
  value "com.clarifi.reporting.writers.StackedBar$" "MODULE$"
      stackedBar# : ChartVariant#
  value "com.clarifi.reporting.writers.StackedArea$" "MODULE$"
      stackedArea# : ChartVariant#
  value "com.clarifi.reporting.writers.BoxAndWhiskers$" "MODULE$"
      boxAndWhiskers# : ChartVariant#

  value "org.jfree.chart.plot.PlotOrientation" "HORIZONTAL" horizontal# : PlotOrientation#
  value "org.jfree.chart.plot.PlotOrientation" "VERTICAL" vertical# : PlotOrientation#

  value "com.clarifi.reporting.writers.DefaultLocation$" "MODULE$"
      chartLegendDefaultLocation# : ChartLegendLocation#
  value "com.clarifi.reporting.writers.Overlay$" "MODULE$"
      chartLegendOverlay# : ChartLegendLocation#
  value "com.clarifi.reporting.writers.Hidden$" "MODULE$"
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
      pieChartDataModule : Function2 (Maybe# String) PieColors#
                                     PieChartData#

  value "com.clarifi.reporting.writers.ChartLegendOptions$" "MODULE$"
      chartLegendOptionsModule : Function1 ChartLegendLocation# ChartLegendOptions#

  value "com.clarifi.reporting.writers.AxisChartData$" "MODULE$"
      axisChartDataModule : Function6 Axis# Axis# (Maybe# String) PlotOrientation#
                                      ChartLegendOptions#
                                      AxisColors# AxisChartData#

  value "com.clarifi.reporting.writers.Axis$" "MODULE$"
      axisModule : Function4 (Maybe# (Atomic# l)) (Format p) (Axis p) Bool# Axis#

  value "com.clarifi.reporting.writers.ScaledConstraints$" "MODULE$"
      scaledConstraintsModule : Function3 SortOrder# (Maybe# PrimExpr#) (Maybe# PrimExpr#) (Axis a)

  value "com.clarifi.reporting.writers.UnscaledConstraints$" "MODULE$"
      unscaledConstraintsModule : Function1 (Either# SortOrder# (Function2 PrimExpr# PrimExpr# Bool#)) (Axis a)

  data "com.clarifi.reporting.writers.ChartSeries$" ChartSeriesModule#
  value "com.clarifi.reporting.writers.ChartSeries$" "MODULE$"
      chartSeriesModule : ChartSeriesModule#
  method "apply" chartSeriesApply# : ChartSeriesModule# -> Presentation sr sa -> Op xr xa -> Op yr ya -> ChartVariant# -> z -> ChartSeries# xa ya

axisChart# = axisChartApply# axisChartModule
axisChartData# = funcall6# axisChartDataModule
pieChartData# = funcall2# pieChartDataModule
axis# = funcall4# axisModule
scaledConstraints# = funcall3# scaledConstraintsModule
unscaledConstraints# = funcall1# unscaledConstraintsModule
chartSeries# = chartSeriesApply# chartSeriesModule
chartLegendOptions# = funcall1# chartLegendOptionsModule