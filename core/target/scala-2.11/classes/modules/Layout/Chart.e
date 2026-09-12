module Layout.Chart where

export Layout.Chart.Type
import Control.Functor using fmap
import Either
import Function
import Maybe using maybeFunctor; maybe
import Native
import Native.Map as NM
import Native.Maybe using Just# ; Nothing#
import Native.NonEmpty using type NonEmpty#
import Native.Ord
import Native.Record
import Layout.Chart.Unsafe
import Layout.Color using type Color
import Layout.Format
import Layout.Presentation
import Layout.PresRow as PR
import Layout.Report.Atomic
import Layout.Report.Direction
import Layout.Writer
import List hiding singleton
import List.NonEmpty using singleton
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

type ExtraMode = forall s x y r sr xr yr sa xa er rel.
                 (exists o. AsPresentation s, AsOp x, AsOp y, r <- (sr, xr, yr, o), Has r er, Relational rel)
                 => s sr sa       -- ^ select the series identifier
                 -> x xr xa       -- ^ select category
                 -> y yr ya       -- ^ select value
                 -> PresRow_PR er
                 -> rel (|..r|)   -- ^ underlying relation for above
                 -> ChartSeries xa ya

-- | An axis label; a tooltip-only label, or a label suitable for use
-- in both tooltips and on the axis, or neither.
data AxisLabel = NoAxisLabel
               | forall t. TooltipOnlyLabel (Atomic t)
               | forall t. AxisLabel (Atomic t)

-- | A function that produces `z` for axis value types `xa` and `ya`.
type ChartOptions xa ya z = forall x x' y y'.
           Maybe String            -- ^ Chart title.
        -> Direction               -- ^ Orientation.
        -> ChartLegendOptions#     -- ^ Options for the charts legend.
        -> ChartRenderHints#       -- ^ Misc. options for the chart that may or may not be adhered to, depending on the writer (e.g. data labels)
        -> AxisLabel               -- ^ Category axis label.
        -> Format xa               -- ^ How to display category.
        -> Bool                    -- ^ Whether to display category axis ticks.
        -> Axis xa                 -- ^ Scaled/unscaled category config.
        -> AxisLabel               -- ^ Value axis label.
        -> Format ya               -- ^ How to display value.
        -> Bool                    -- ^ Whether to display value axis ticks.
        -> Axis ya                 -- ^ Scaled/unscaled value config.
        -> z

chartW : forall xa ya.
         ChartOptions xa ya (List (ChartSeries xa ya) -- ^ Liftee.
                             -> AxisChart#)
chartW title ori legOpts hints catL catF catAx catCons valL valF valAx valCons series =
   axisChart# (toList# . map toChartSeries# $ series) $
     axisChartDataW catL catF catAx valL valF valAx catCons valCons title ori legOpts hints series

axisChartDataW catL catF catAx valL valF valAx catCons valCons title ori legOpts hints series =
    let nativeAxis = axisLabel# axis#
     in unifyTicks# catCons valCons series |> (catCons', valCons') ->
        axisChartData# (nativeAxis catL catF catCons' $ toBool# catAx)
                       (nativeAxis valL valF valCons' $ toBool# valAx)
                       (toMaybe# title) (orientation# ori) legOpts
                       (unifyColors# series)
                       hints

seriesW : ChartVariant# -> ChartMode
seriesW vari s x y fact =
  ChartSeries
    [] [] []
    (asPresentation s) (singleton $ asOp x) (asOp y)
    Nothing Nothing vari empty#_PR (relation# fact)

seriesWE : ChartVariant# -> ExtraMode 
seriesWE vari s x y extra fact = 
  ChartSeries
    [] [] []
    (asPresentation s) (singleton $ asOp x) (asOp y)
    Nothing Nothing vari extra (relation# fact)

private
  atomize : Maybe (Atomic nm) -> Maybe# (Atomic# nm)
  atomize = maybe Nothing# (Just# . atomic#)

pieChartW w title nm legendOptions color hints cat =
  pieChart# w (pieChartData# (Just# title) (atomize nm) legendOptions (pieColors# cat color) hints) cat
drilldownPieChartW w title nm legendOptions color hints cat =
  drilldownPieChart# w (pieChartData# (Just# title) (atomize nm) legendOptions (pieColors# cat color) hints) cat
drilldownPieChart2W w title nm legendOptions color hints cat pres2 cols =
  drilldownPieChart2# w (pieChartData# (Just# title) (atomize nm) legendOptions (pieColors# cat color) hints) cat pres2 (toList# $ fmap listFunctor toPair# cols)

drilldownBarChartW : Writer f a -> AxisChartData# -> List ({..cr}, {..cr}) -> List ({..vr}, {..vr}) -> Presentation sr sa -> Presentation cr ca -> Presentation vr va -> String -> String -> Relation# -> f a
drilldownBarChartW w barData cov vov s c v pid cid dat =
  drilldownBarChartW' w barData cov vov s c v Nothing Nothing pid cid dat

drilldownBarChartW'
  :  Writer f a
  -> AxisChartData#
  -> List ({..cr}, {..cr})
  -> List ({..vr}, {..vr})
  -> Presentation sr sa
  -> Presentation cr ca
  -> Presentation vr va
  -> Maybe (Presentation xtr xta)
  -> Maybe (Presentation ytr yta)
  -> String
  -> String
  -> Relation#
  -> f a
drilldownBarChartW' w barData cov vov s c v xt yt pid cid dat =
  drilldownBarChart# w
    (drilldownBarAxisChart#
       s c v
       (toMaybe# xt) (toMaybe# yt)
       dat
       (toPair# (pid, cid))
       (rescopeTicks# c v cov vov barData))

drilldownBarChart2W : Writer f a -> AxisChartData# -> List ({..cr}, {..cr}) -> List ({..vr}, {..vr}) -> Presentation sr sa -> Presentation cr ca -> Presentation vr va -> List (String, String) -> Relation# -> Relation# -> f a
drilldownBarChart2W w barData cov vov series cat pres2 cols dat root =
  drilldownBarChart2W' w barData cov vov series cat pres2 Nothing Nothing cols dat root

drilldownBarChart2W'
  :  Writer f a
  -> AxisChartData#
  -> List ({..cr}, {..cr})
  -> List ({..vr}, {..vr})
  -> Presentation sr sa
  -> Presentation cr ca
  -> Presentation vr va
  -> Maybe (Presentation xtr xta)
  -> Maybe (Presentation ytr yta)
  -> List (String, String)
  -> Relation#
  -> Relation#
  -> f a
drilldownBarChart2W' w barData cov vov series cat val xt yt cols dat root =
  drilldownBarChart2# w
    (drilldownBarAxisChart#
       series
       cat
       val
       (toMaybe# xt)
       (toMaybe# yt)
       dat
       (toPair# ((toList# $ fmap listFunctor toPair# cols), root))
       (rescopeTicks# cat val cov vov barData))

private
  orientation# : Direction -> PlotOrientation#
  orientation# Horizontal = horizontal#
  orientation# Vertical = vertical#

  axisLabel# (c : some z. forall t t'. (Maybe# (EitherZ# (Atomic# t) (Atomic# t'))) -> z)  = me
    where me NoAxisLabel = cont Nothing
          me (TooltipOnlyLabel a) = cont . Just . Left . atomic# $ a
          me (AxisLabel a) = cont . Just . Right . atomic# $ a
          cont = c . toMaybe# . fmap maybeFunctor toEitherZ#

  srecKeys part = toList# . map (toPair# . part (scalaRecord# . record#))

  unifyColors# : List (ChartSeries xa ya)
              -> Map_NM (NonEmpty# PrimExpr#) Color
  unifyColors# = unifyColors## . toList#
               . map (cs@(ChartSeries c _ _ _ _ _ _ _ _ _ _) -> toPair# (toChartSeries# cs, srecKeys mapFst c))

  pieColors# : Presentation r a
            -> List ({..r}, Color)
            -> Map_NM (NonEmpty# PrimExpr#) Color
  pieColors# pr = rescopePieColors# pr . srecKeys mapFst

  umap f (a, b) = (f a, f b)

  rescopeTicks# : Presentation xr xa -> Presentation yr ya
               -> List ({..xr}, {..xr}) -> List ({..yr}, {..yr})
               -> AxisChartData# -> AxisChartData#
  rescopeTicks# px py ovx ovy =
    rescopeTicks## px py (srecKeys umap ovx) (srecKeys umap ovy)

  unifyTicks# : Axis xa -> Axis ya -> List (ChartSeries xa ya) -> (Axis xa, Axis ya)
  unifyTicks# cc vc series =
    fromPair# $ unifyTicks## (toList# . map explode $ series) cc vc
    where explode cs@(ChartSeries _ cts vts _ _ _ _ _ _ _ _) =
            toPair# (toChartSeries# cs, toPair# (srecKeys umap cts, srecKeys umap vts))

foreign
  method "axisChartDMTL" axisChartW : forall f a. Writer f a -> AxisChart# -> f a
  method "pieChartDMTL" pieChart# : forall f a . Writer f a -> PieChartData# -> Presentation r b -> Presentation s c -> Relation# -> f a

  method "treeMapDMTL" treeMap# : forall f a. Writer f a -> String -> String -> Presentation r b -> Presentation s c -> Presentation t d -> Relation# -> f a

  method "drilldownPieChartDMTL" drilldownPieChart# : forall f a . Writer f a -> PieChartData# -> Presentation r b -> Presentation s c -> String -> String -> Relation# -> f a
  method "drilldownPieChartDMTL2" drilldownPieChart2# : forall f a . Writer f a -> PieChartData# -> Presentation r b -> Presentation s c -> List# (Pair# String String) -> Relation# -> Relation# -> f a
  method "drilldownBarChartDMTL" drilldownBarChart# : Writer f a -> DrilldownBarAxisChart# (Pair# String String) Relation# -> f a
  method "drilldownBarChartDMTL2" drilldownBarChart2# : Writer f a -> DrilldownBarAxisChart# (Pair# (List# (Pair# String String)) Relation#) Relation# -> f a
