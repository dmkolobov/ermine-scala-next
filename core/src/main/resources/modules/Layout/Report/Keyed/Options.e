module Layout.Report.Keyed.Options where

{- This module is meant to be used in tandem with Layout.Report.Keyed;
it provides the numerous options that can be used with :=. -}

import Control.Functor using fmap
import Either
import Function
import Layout.Chart using TooltipOnlyLabel; AxisLabel
import Layout.Chart.Unsafe
import Layout.Color using type Color
import Layout.Format using type Format
import Layout.Legend using type Legend
import Layout.Presentation using type Presentation; asPresentation
import Layout.Report using {type Report; type DisplayScale}
import Layout.Report.Atomic
import Layout.Report.Direction
import Layout.SortPriority using type SortPriorityAnnotated
import Layout.SortStrategy as SS
import Layout.Magnitude
import Maybe using maybeFunctor
import Ord using type Ord; lt
import Relation.Sort using {type Sort; type SortOrder}
import Void
import Layout.Report.Keyed.OptionTypes
import DrilldownList using type DrilldownList
import Layout.Report.SoftRelation using type SoftRelation

-- border options

private
  type Bordering c n s e w c' n' s' e' w' =
    forall f z. Report f z -> BorderOptions (c, n, s, e, w) f z
                           -> BorderOptions (c', n', s', e', w') f z

center : Bordering (Unbound c) n s e w (Bound Center) n s e w
north :  Bordering c (Unbound n) s e w c (Bound North) s e w
south :  Bordering c n (Unbound s) e w c n (Bound South) e w
east :   Bordering c n s (Unbound e) w c n s (Bound East) w
west :   Bordering c n s e (Unbound w) c n s e (Bound West)
center c (BorderOptions _ n s e w) = BorderOptions (Just c) n s e w
north  n (BorderOptions c _ s e w) = BorderOptions c (Just n) s e w
south  s (BorderOptions c n _ e w) = BorderOptions c n (Just s) e w
east   e (BorderOptions c n s _ w) = BorderOptions c n s (Just e) w
west   w (BorderOptions c n s e _) = BorderOptions c n s e (Just w)

-- prefS options

-- | A preferred width, in pixels.
width : MagnitudeList  -> PrefSOptions (Unbound w, h) -> PrefSOptions (Bound Width, h)
width w (PrefSOptions (Left (_, h))) = PrefSOptions (Left (w, h))

-- | A preferred height, in pixels.
height : MagnitudeList -> PrefSOptions (w, Unbound h) -> PrefSOptions (w, Bound Height)
height h (PrefSOptions (Left (w, _))) = PrefSOptions (Left (w, h))

-- softRelation options

-- | How to sort keys, naturally.
hardKeySort : Sort k -> SoftRelationOptions (Unbound ks', pv', pvss', pvsp') k v b
                     -> SoftRelationOptions (Bound (Sort k), pv', pvss', pvsp') k v b
hardKeySort ks (SoftRelationOptions _ pv pvss pvsp) =
  SoftRelationOptions (Just . Left $ ks) pv pvss pvsp

-- | How to sort keys, via an Ord on key tuples.
softKeySort : Ord {..k}
           -> SoftRelationOptions (Unbound ks', pv', pvss', pvsp') k v b
           -> SoftRelationOptions (Bound (Sort k), pv', pvss', pvsp') k v b
softKeySort ks (SoftRelationOptions _ pv pvss pvsp) =
  SoftRelationOptions (Just . Right $ ks) pv pvss pvsp

-- | Override the default `prv v b`, as given to softRelation, on a
-- per-tuple basis.
valuePresentation : AsPresentation prv
                 => ({..k} -> Maybe (prv v b))
                 -> SoftRelationOptions (ks', Unbound pv', pvss', pvsp') k v b
                 -> SoftRelationOptions (ks', Bound (prv v b), pvss', pvsp') k v b
valuePresentation mkpv (SoftRelationOptions ks _ pvss pvsp) =
  SoftRelationOptions ks (fmap maybeFunctor asPresentation . mkpv) pvss pvsp

-- | Choose a different relative sort strategy for the presentations
-- produced for certain tuples.
valueSortStrategy : ({..k} -> Maybe (SortStrategy_SS v))
                  -> SoftRelationOptions (ks', pv', Unbound pvss', pvsp') k v b
                  -> SoftRelationOptions (ks', pv', Bound (SortStrategy_SS v), pvsp')
                                         k v b
valueSortStrategy pvss (SoftRelationOptions ks pv _ pvsp) =
  SoftRelationOptions ks pv pvss pvsp

-- | Choose a different position in the initial tabular sort priority
-- for tuples in a softRelation.  For example, to set all to ascending 10,
-- you can write `(tup z -> z ^ 10)`.
valueSortPriority : ({..k} -> () -> SortPriorityAnnotated ())
                 -> SoftRelationOptions (ks', pv', pvss', Unbound pvsp') k v b
                 -> SoftRelationOptions (ks', pv', pvss', Bound (SortPriorityAnnotated ()))
                                        k v b
valueSortPriority pvsp (SoftRelationOptions ks pv pvss _) =
  SoftRelationOptions ks pv pvss pvsp


-- KeyValueTabular options

-- | Set a key value tabular's legend
keyValTabLegend : Legend i
               -> KeyValueTabularOptions (Unbound l, dd) i label pid id cid r root
               -> KeyValueTabularOptions (Bound (Legend i), dd) i label pid id cid r root
keyValTabLegend l (KeyValueTabularOptions _ dd) = KeyValueTabularOptions (Just l) dd

-- | Set a key value tabular's soft relation
keyValTabSimpleDrilldown : Field pid id
                        -> Field cid id
                        -> Field label String
                        -> KeyValueTabularOptions (l, (Unbound dd)) i label pid id cid r root
                        -> KeyValueTabularOptions (l, (Bound (Field pid id, Field cid id, Field label String))) i label pid id cid r root
keyValTabSimpleDrilldown p c label (KeyValueTabularOptions l _) = KeyValueTabularOptions l (Just $ Left (p, c, label))

-- | Set a key value tabular's soft relation
keyValTabMultiDrilldown : Relational rel
                       => DrilldownList r
                       -> rel r2
                       -> Field label String
                       -> KeyValueTabularOptions (l, (Unbound dd)) i label pid id cid r root
                       -> KeyValueTabularOptions (l, (Bound (DrilldownList r, rel r2, Field label String))) i label pid id cid r (rel r2)
keyValTabMultiDrilldown ddl r label (KeyValueTabularOptions l _) = KeyValueTabularOptions l (Just $ Right (ddl, r, label))

-- tabular options

-- | Set a tabular's legend.
tabLegend : Legend r
         -> TabularOptions (Unbound leg) r
         -> TabularOptions (Bound (Legend r)) r
tabLegend = const . TabularOptions . Just

-- scaled options

-- | How should the chart be ordered, numerically?
numericOrder : SortOrder
            -> ScaledOptions (Unbound dir, low, up, ds) a
            -> ScaledOptions (Bound SortOrder, low, up, ds) a
numericOrder so (ScaledOptions _ low up ds) = ScaledOptions so low up ds

-- | What should the axis bound close to origin be?
lowerBound : a
          -> ScaledOptions (so, Unbound low, up, ds) a
          -> ScaledOptions (so, Bound a, up, ds) a
lowerBound low (ScaledOptions so _ up ds) = ScaledOptions so (Just low) up ds

-- | What should the axis bound far from origin be?
upperBound : a
          -> ScaledOptions (so, low, Unbound up, ds) a
          -> ScaledOptions (so, low, Bound a, ds) a
upperBound up (ScaledOptions so low _ ds) = ScaledOptions so low (Just up) ds

-- | Should the axis be scaled for display?

displayScale : DisplayScale
            -> ScaledOptions (so, low, up, Unbound sc) a
            -> ScaledOptions (so, low, up, Bound DisplayScale) a
displayScale ds (ScaledOptions so low up _) = ScaledOptions so low up ds

-- unscaled options

stringOrder : SortOrder
           -> UnscaledOptions (Unbound sort) a
           -> UnscaledOptions (Bound SortOrder) a
stringOrder = const . UnscaledOptions . Left

arbitraryOrder : Ord a
              -> UnscaledOptions (Unbound sort) a
              -> UnscaledOptions (Bound SortOrder) a
arbitraryOrder = const . UnscaledOptions . Right

-- chart options

-- | Set the chart title.
chartTitle : String
          -> ChartOptions (Unbound title', dir', legOpts', rh', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
          -> ChartOptions (Bound String, dir', legOpts', rh', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
chartTitle title (ChartOptions _ dir legOpts rh xlbl xfmt xax ylbl yfmt yax) =
  ChartOptions (Just title) dir legOpts rh xlbl xfmt xax ylbl yfmt yax

-- | Display direction; Vertical means the value (Y) axis points up,
-- Horizontal that it points right.
yDirection : Direction
          -> ChartOptions (title', Unbound dir', legOpts', rh', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
          -> ChartOptions (title', Bound Direction, legOpts', rh', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
yDirection dir (ChartOptions title _ legOpts rh xlbl xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt yax

-- | Label for the category (x) axis.
xLabel : Atomic xr
      -> ChartOptions (title', dir', legOpts', rh', Unbound xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
      -> ChartOptions (title', dir', legOpts', rh', Bound (Atomic x), xfmt', xax', ylbl', yfmt', yax') xa ya
xLabel xlbl (ChartOptions title dir legOpts rh _ xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts rh (AxisLabel xlbl) xfmt xax ylbl yfmt yax

-- | Label for the category (x) axis, but only for tooltips.
xTooltipLabel : Atomic xr
      -> ChartOptions (title', dir', legOpts', rh', Unbound xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
      -> ChartOptions (title', dir', legOpts', rh', Bound (Atomic x), xfmt', xax', ylbl', yfmt', yax') xa ya
xTooltipLabel xlbl (ChartOptions title dir legOpts rh _ xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts rh (TooltipOnlyLabel xlbl) xfmt xax ylbl yfmt yax

-- | Scalar format for the category (x) axis.
xFormat : Format xa
       -> ChartOptions (title', dir', legOpts', rh', xlbl', Unbound xfmt', xax', ylbl', yfmt', yax') xa' ya
       -> ChartOptions (title', dir', legOpts', rh', xlbl', Bound (Format xa), xax', ylbl', yfmt', yax') xa ya
xFormat xfmt (ChartOptions title dir legOpts rh xlbl _ xax ylbl yfmt yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt yax

showXTicks : Bool
          -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', Unbound xax', ylbl', yfmt', yax') xa ya
          -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', Bound Bool, ylbl', yfmt', yax') xa ya
showXTicks xax (ChartOptions title dir legOpts rh xlbl xfmt _ ylbl yfmt yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt yax

-- | Label for the value (y) axis.
yLabel : Atomic yr
      -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', Unbound ylbl', yfmt', yax') xa ya
      -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', Bound (Atomic y), yfmt', yax') xa ya
yLabel ylbl (ChartOptions title dir legOpts rh xlbl xfmt xax _ yfmt yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax (AxisLabel ylbl) yfmt yax

-- | Label for the value (y) axis, but only for tooltips.
yTooltipLabel : Atomic yr
      -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', Unbound ylbl', yfmt', yax') xa ya
      -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', Bound (Atomic y), yfmt', yax') xa ya
yTooltipLabel ylbl (ChartOptions title dir legOpts rh xlbl xfmt xax _ yfmt yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax (TooltipOnlyLabel ylbl) yfmt yax

-- | Scalar format for the value (y) axis.
yFormat : Format ya
       -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', ylbl', Unbound yfmt', yax') xa ya'
       -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', ylbl', Bound (Format ya), yax') xa ya
yFormat yfmt (ChartOptions title dir legOpts rh xlbl xfmt xax ylbl _ yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt yax

showYTicks : Bool
          -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', ylbl', yfmt', Unbound yax') xa ya
          -> ChartOptions (title', dir', legOpts', rh', xlbl', xfmt', xax', ylbl', yfmt', Bound Bool) xa ya
showYTicks yax (ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt _) =
  ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt yax

legendOpts : ChartLegendOptions#
          -> ChartOptions (title', dir', Unbound legOpts',          rh', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
          -> ChartOptions (title', dir', Bound ChartLegendOptions#, rh', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
legendOpts legOpts (ChartOptions title dir _ rh xlbl xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt yax

-- | Set render hints
renderHints : ChartRenderHints#
           -> ChartOptions (title', dir', legOpts', Unbound rh',             xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
           -> ChartOptions (title', dir', legOpts', Bound ChartRenderHints#, xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya
renderHints rh (ChartOptions title dir legOpts _ xlbl xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts rh xlbl xfmt xax ylbl yfmt yax

-- pieChart options

-- | Set the pie chart title.
pieTitle : String
        -> PieChartOptions (Unbound t', nm', l', c', rh', dd') lbl r1 r2 id
        -> PieChartOptions (Bound String, nm', l', c', rh', dd') lbl r1 r2 id
pieTitle s (PieChartOptions _ nm lo cs rh dd) = PieChartOptions s nm lo cs rh dd

pieSeriesName
   : Atomic nm
  -> PieChartOptions (t', Unbound nm', l', c', rh', dd') lbl r1 r2 id
  -> PieChartOptions (t', Bound nm, l', c', rh', dd') lbl r1 r2 id
pieSeriesName nm (PieChartOptions t _ lo cs rh dd) = PieChartOptions t (Just nm) lo cs rh dd

pieLegendOpts : ChartLegendOptions#
             -> PieChartOptions (t', nm', Unbound l', c', rh', dd') lbl r1 r2 id
             -> PieChartOptions (t', nm', Bound ChartLegendOptions#, c', rh', dd') lbl r1 r2 id
pieLegendOpts lo (PieChartOptions s nm _ cs rh dd) = PieChartOptions s nm lo cs rh dd

-- | Set colors.
pieColors : List ({..label}, Color)
         -> PieChartOptions (t', nm', l', Unbound c', rh', dd') lbl r1 r2 id
         -> PieChartOptions (t', nm', l', Bound {..label}, rh', dd') label r1 r2 id
pieColors cs (PieChartOptions s nm lo _ rh dd) = PieChartOptions s nm lo cs rh dd

-- | Set render hints
pieRenderHints : ChartRenderHints#
         -> PieChartOptions (t', nm', l', c', Unbound rh', dd') lbl r1 r2 id
         -> PieChartOptions (t', nm', l', c', Bound ChartRenderHints#, dd') lbl r1 r2 id
pieRenderHints rh (PieChartOptions s nm lo cs _ dd) = PieChartOptions s nm lo cs rh dd

-- | Permit drilling down.
pieDrilldown : (r <- (pid, cid))
            => (Field pid id, Field cid id)
            -> PieChartOptions (t', l', nm', lbl', rh', Unbound dd') lbl r1 r2 id'
            -> PieChartOptions (t', l', nm', lbl', rh', Bound (Field r id)) lbl pid cid id
pieDrilldown dd (PieChartOptions s nm lo cs rh _) = PieChartOptions s nm lo cs rh (Just dd)

-- drilldownBarChart options

-- | Set the chart title.
titleB : String
      -> DrilldownBarChartOptions (Unbound title', dir', legOpts', rh', cl', vl', prs', cov', vov') sr sa cr vr
      -> DrilldownBarChartOptions (Bound String, dir', legOpts', rh', cl', vl', prs', cov', vov') sr sa cr vr
titleB title (DrilldownBarChartOptions _ dir lo rh cl vl prs cov vov) =
  DrilldownBarChartOptions (Just title) dir lo rh cl vl prs cov vov

-- | Display direction; Vertical means the value (Y) axis points up,
-- Horizontal that it points right.
yDirectionB : Direction
           -> DrilldownBarChartOptions (title', Unbound dir', legOpts', rh', cl', vl', prs', cov', vov') sr sa cr vr
           -> DrilldownBarChartOptions (title', Bound Direction, legOpts', rh', cl', vl', prs', cov', vov') sr sa cr vr
yDirectionB dir (DrilldownBarChartOptions title _ lo rh cl vl prs cov vov) =
  DrilldownBarChartOptions title dir lo rh cl vl prs cov vov

-- | Label for the category (x) axis.
xLabelB : Atomic cl
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', Unbound cl', vl', prs', cov', vov') sr sa cr vr
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', Bound (Atomic cl), vl', prs', cov', vov') sr sa cr vr
xLabelB cl (DrilldownBarChartOptions title dir lo rh _ vl prs cov vov) =
  DrilldownBarChartOptions title dir lo rh (AxisLabel cl) vl prs cov vov

-- | Label for the category (x) axis, but only for tooltips.
xTooltipLabelB : Atomic cl
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', Unbound cl', vl', prs', cov', vov') sr sa cr vr
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', Bound (Atomic cl), vl', prs', cov', vov') sr sa cr vr
xTooltipLabelB cl (DrilldownBarChartOptions title dir lo rh _ vl prs cov vov) =
  DrilldownBarChartOptions title dir lo rh (TooltipOnlyLabel cl) vl prs cov vov

-- | Label for the value (y) axis.
yLabelB : Atomic vl
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', Unbound vl', prs', cov', vov') sr sa cr vr
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', Bound (Atomic vl), prs', cov', vov') sr sa cr vr
yLabelB vl (DrilldownBarChartOptions title dir lo rh cl _ prs cov vov) =
  DrilldownBarChartOptions title dir lo rh cl (AxisLabel vl) prs cov vov

-- | Label for the value (y) axis, but only for tooltips.
yTooltipLabelB : Atomic vl
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', Unbound vl', prs', cov', vov') sr sa cr vr
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', Bound (Atomic vl), prs', cov', vov') sr sa cr vr
yTooltipLabelB vl (DrilldownBarChartOptions title dir lo rh cl _ prs cov vov) =
  DrilldownBarChartOptions title dir lo rh cl (TooltipOnlyLabel vl) prs cov vov

-- | The selection and display rules for the series dimension.
seriesB : AsPresentation pr
       => pr sr sa
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', vl', Unbound prs', cov', vov') sro sao cr vr
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', vl', Bound (Presentation sr sa), cov', vov')
                                   sr sa cr vr
seriesB prs (DrilldownBarChartOptions title dir lo rh cl vl _ cov vov) =
  DrilldownBarChartOptions title dir lo rh cl vl (asPresentation prs) cov vov

-- | Overrides to show as tick labels on the category axis.
xTicksB : List ({..cr}, {..cr})
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', vl', prs', Unbound cov', vov')
                                   sr sa cr vr
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', vl', prs', Bound {..cr}, vov')
                                   sr sa cr vr
xTicksB cov (DrilldownBarChartOptions title dir lo rh cl vl prs _ vov) =
  DrilldownBarChartOptions title dir lo rh cl vl prs cov vov

-- | Overrides to show as tick labels on the value axis.
yTicksB : List ({..vr}, {..vr})
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', vl', prs', cov', Unbound vov')
                                   sr sa cr vr
       -> DrilldownBarChartOptions (title', dir', legOpts', rh', cl', vl', prs', cov', Bound {..vr})
                                   sr sa cr vr
yTicksB vov (DrilldownBarChartOptions title dir lo rh cl vl prs cov _) =
  DrilldownBarChartOptions title dir lo rh cl vl prs cov vov

legendOptsB : ChartLegendOptions#
           -> DrilldownBarChartOptions (title', dir', Unbound legOpts', rh', cl', vl', prs', cov', vov') sr sa cr vr
           -> DrilldownBarChartOptions (title', dir', Bound ChartLegendOptions#, rh', cl', vl', prs', cov', vov') sr sa cr vr
legendOptsB lo (DrilldownBarChartOptions title dir _ rh cl vl prs cov vov) =
  DrilldownBarChartOptions title dir lo rh cl vl prs cov vov

-- | Set render hints
renderHintsB : ChartRenderHints#
            -> DrilldownBarChartOptions (title', dir', legOpts', Unbound rh', cl', vl', prs', cov', vov') sr sa cr vr
            -> DrilldownBarChartOptions (title', dir', legOpts', Bound ChartRenderHints#, cl', vl', prs', cov', vov') sr sa cr vr
renderHintsB rh (DrilldownBarChartOptions title dir lo _ cl vl prs cov vov) =
  DrilldownBarChartOptions title dir lo rh cl vl prs cov vov
