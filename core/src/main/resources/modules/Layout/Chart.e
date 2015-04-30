module Layout.Chart where

export Layout.Chart.Type
import Control.Functor using fmap
import Function
import Maybe using maybeFunctor
import Native
import Native.Map as NM
import Native.NonEmpty using type NonEmpty#
import Native.Ord
import Native.Record
import Layout.Chart.Unsafe
import Layout.Color using type Color
import Layout.Format
import Layout.Presentation
import Layout.Report.Atomic
import Layout.Report.Direction
import Layout.Writer
import List
import Pair
import Prim using type PrimExpr#
import Relation.Op using asOp; type Op
import Syntax.List

-- | A specific kind of chart.
type ChartMode = forall s x y r sr xr yr sa xa rel.
                 (exists o. AsPresentation s, AsOp x, AsOp y, r <- (sr, xr, yr, o), Relational rel)
               => s sr sa       -- ^ select the series identifier
               -> x xr xa       -- ^ select category
               -> y yr ya       -- ^ select value
               -> rel (|..r|)   -- ^ underlying relation for above
               -> ChartSeries xa ya

-- | ChartMode, but scaled in ya.
type ScaledChartMode = forall s x y r sr xr yr sa xa ya rel.
                       (exists o. Scaled ya, AsPresentation s, AsOp x, AsOp y,
                                  r <- (sr, xr, yr, o), Relational rel)
               => s sr sa       -- ^ select the series identifier
               -> x xr xa       -- ^ select category
               -> y yr ya       -- ^ select value
               -> rel (|..r|)   -- ^ underlying relation for above
               -> ChartSeries xa ya

-- | A function that produces `z` for axis value types `xa` and `ya`.
type ChartOptions xa ya z = forall x y.
           Maybe String            -- ^ Chart title.
        -> Direction               -- ^ Orientation.
        -> ChartLegendOptions#     -- ^ Options for the charts legend.
        -> Maybe (Atomic x)        -- ^ Category axis label.
        -> Format xa               -- ^ How to display category.
        -> Bool                    -- ^ Whether to display category axis ticks.
        -> Axis xa                 -- ^ Scaled/unscaled category config.
        -> Maybe (Atomic y)        -- ^ Value axis label.
        -> Format ya               -- ^ How to display value.
        -> Bool                    -- ^ Whether to display value axis ticks.
        -> Axis ya                 -- ^ Scaled/unscaled value config.
        -> z

chartW : forall xa ya.
         ChartOptions xa ya (List (ChartSeries xa ya) -- ^ Liftee.
                             -> AxisChart#)
chartW title ori legOpts catL catF catAx catCons valL valF valAx valCons series =
   axisChart# (toList# . map ((ChartSeries _ ncs) -> ncs) $ series) $
     axisChartDataW catL catF catAx valL valF valAx catCons valCons title ori legOpts series

axisChartDataW catL catF catAx valL valF valAx catCons valCons title ori legOpts series =
    let nativeAxis lbl = axis# (toMaybe# $ fmap maybeFunctor atomic# lbl)
     in axisChartData# (nativeAxis catL catF catCons $ toBool# catAx)
                       (nativeAxis valL valF valCons $ toBool# valAx)
                       (toMaybe# title) (orientation# ori) legOpts
                       (unifyColors# series)

seriesW : ChartVariant# -> ChartMode
seriesW vari s x y fact =
  ChartSeries [] (chartSeries# (asPresentation s) (asOp x) (asOp y)
                               vari (relation# fact))

pieChartW w title color cat =
  pieChart# w (pieChartData# (toMaybe# $ Just title) (pieColors# cat color)) cat
drilldownPieChartW w title color cat =
  drilldownPieChart# w (pieChartData# (toMaybe# $ Just title) (pieColors# cat color)) cat
drilldownPieChart2W w title color cat pres2 cols =
  drilldownPieChart2# w (pieChartData# (toMaybe# $ Just title) (pieColors# cat color)) cat pres2 (toList# $ fmap listFunctor toPair# cols)

drilldownBarChart2W w barData cat pres2 cols =
  drilldownBarChart2# w barData cat pres2 (toList# $ fmap listFunctor toPair# cols)

private
  orientation# : Direction -> PlotOrientation#
  orientation# Horizontal = horizontal#
  orientation# Vertical = vertical#

  srecKeys = toList# . map (toPair# . mapFst (scalaRecord# . record#))

  unifyColors# : List (ChartSeries xa ya)
              -> Map_NM (NonEmpty# PrimExpr#) Color
  unifyColors# = unifyColors## . toList#
               . map ((ChartSeries c ncs) -> toPair# (ncs, srecKeys c))

  pieColors# : Presentation r a
            -> List ({..r}, Color)
            -> Map_NM (NonEmpty# PrimExpr#) Color
  pieColors# pr = rescopePieColors# pr . srecKeys

foreign
  method "axisChartDMTL" axisChartW : forall f a. Writer f a -> AxisChart# -> f a
  method "pieChartDMTL" pieChart# : forall f a . Writer f a -> PieChartData# -> Presentation r b -> Presentation s c -> Relation# -> f a
  method "drilldownPieChartDMTL" drilldownPieChart# : forall f a . Writer f a -> PieChartData# -> Presentation r b -> Presentation s c -> String -> String -> Relation# -> f a
  method "drilldownPieChartDMTL2" drilldownPieChart2# : forall f a . Writer f a -> PieChartData# -> Presentation r b -> Presentation s c -> List# (Pair# String String) -> Relation# -> Relation# -> f a
  method "drilldownBarChartDMTL" drilldownBarChartW : forall f a cr ca vr va. Writer f a -> AxisChartData# -> Presentation cr ca -> Presentation vr va -> String -> String -> Relation# -> f a
  method "drilldownBarChartDMTL2" drilldownBarChart2# : forall f a cr ca vr va. Writer f a -> AxisChartData# -> Presentation cr ca -> Presentation vr va ->  List# (Pair# String String) -> Relation# -> Relation# -> f a
