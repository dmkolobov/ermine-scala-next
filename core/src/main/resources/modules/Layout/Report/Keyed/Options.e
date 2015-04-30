module Layout.Report.Keyed.Options where

{- This module is meant to be used in tandem with Layout.Report.Keyed;
it provides the numerous options that can be used with :=. -}

import Control.Functor using fmap
import Either
import Function
import Layout.Chart.Unsafe
import Layout.Color using type Color
import Layout.Format using type Format
import Layout.Legend using type Legend
import Layout.Presentation using asPresentation
import Layout.Report using type Report
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
            -> ScaledOptions (Unbound dir, low, up) a
            -> ScaledOptions (Bound SortOrder, low, up) a
numericOrder so (ScaledOptions _ low up) = ScaledOptions so low up

-- | What should the axis bound close to origin be?
lowerBound : a
          -> ScaledOptions (so, Unbound low, up) a
          -> ScaledOptions (so, Bound a, up) a
lowerBound low (ScaledOptions so _ up) = ScaledOptions so (Just low) up

-- | What should the axis bound far from origin be?
upperBound : a
          -> ScaledOptions (so, low, Unbound up) a
          -> ScaledOptions (so, low, Bound a) a
upperBound up (ScaledOptions so low _) = ScaledOptions so low (Just up)

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
          -> ChartOptions (Unbound title', dir', legOpts', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya x y
          -> ChartOptions (Bound String, dir', legOpts', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya x y
chartTitle title (ChartOptions _ dir legOpts xlbl xfmt xax ylbl yfmt yax) =
  ChartOptions (Just title) dir legOpts xlbl xfmt xax ylbl yfmt yax

-- | Display direction; Vertical means the value (Y) axis points up,
-- Horizontal that it points right.
yDirection : Direction
          -> ChartOptions (title', Unbound dir', legOpts', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya x y
          -> ChartOptions (title', Bound Direction, legOpts', xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya x y
yDirection dir (ChartOptions title _ legOpts xlbl xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt yax

-- | Label for the category (x) axis.
xLabel : Atomic x
      -> ChartOptions (title', dir', legOpts', Unbound xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya x' y
      -> ChartOptions (title', dir', legOpts', Bound (Atomic x), xfmt', xax', ylbl', yfmt', yax') xa ya x y
xLabel xlbl (ChartOptions title dir legOpts _ xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts (Just xlbl) xfmt xax ylbl yfmt yax

-- | Scalar format for the category (x) axis.
xFormat : Format xa
       -> ChartOptions (title', dir', legOpts', xlbl', Unbound xfmt', xax', ylbl', yfmt', yax') xa' ya x y
       -> ChartOptions (title', dir', legOpts', xlbl', Bound (Format xa), xax', ylbl', yfmt', yax') xa ya x y
xFormat xfmt (ChartOptions title dir legOpts xlbl _ xax ylbl yfmt yax) =
  ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt yax

showXTicks : Bool
          -> ChartOptions (title', dir', legOpts', xlbl', xfmt', Unbound xax', ylbl', yfmt', yax') xa ya x y
          -> ChartOptions (title', dir', legOpts', xlbl', xfmt', Bound Bool, ylbl', yfmt', yax') xa ya x y
showXTicks xax (ChartOptions title dir legOpts xlbl xfmt _ ylbl yfmt yax) =
  ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt yax

-- | Label for the value (y) axis.
yLabel : Atomic y
      -> ChartOptions (title', dir', legOpts', xlbl', xfmt', xax', Unbound ylbl', yfmt', yax') xa ya x y'
      -> ChartOptions (title', dir', legOpts', xlbl', xfmt', xax', Bound (Atomic y), yfmt', yax') xa ya x y
yLabel ylbl (ChartOptions title dir legOpts xlbl xfmt xax _ yfmt yax) =
  ChartOptions title dir legOpts xlbl xfmt xax (Just ylbl) yfmt yax

-- | Scalar format for the value (y) axis.
yFormat : Format ya
       -> ChartOptions (title', dir', legOpts', xlbl', xfmt', xax', ylbl', Unbound yfmt', yax') xa ya' x y
       -> ChartOptions (title', dir', legOpts', xlbl', xfmt', xax', ylbl', Bound (Format ya), yax') xa ya x y
yFormat yfmt (ChartOptions title dir legOpts xlbl xfmt xax ylbl _ yax) =
  ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt yax

showYTicks : Bool
          -> ChartOptions (title', dir', legOpts', xlbl', xfmt', xax', ylbl', yfmt', Unbound yax') xa ya x y
          -> ChartOptions (title', dir', legOpts', xlbl', xfmt', xax', ylbl', yfmt', Bound Bool) xa ya x y
showYTicks yax (ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt _) =
  ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt yax

legendOpts : ChartLegendOptions#
          -> ChartOptions (title', dir', Unbound legOpts',          xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya x y
          -> ChartOptions (title', dir', Bound ChartLegendOptions#, xlbl', xfmt', xax', ylbl', yfmt', yax') xa ya x y
legendOpts legOpts (ChartOptions title dir _ xlbl xfmt xax ylbl yfmt yax) =
  ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt yax

-- pieChart options

-- | Set the pie chart title.
pieTitle : String
        -> PieChartOptions (Unbound t', c', dd') lbl r1 r2 id
        -> PieChartOptions (Bound String, c', dd') lbl r1 r2 id
pieTitle s (PieChartOptions _ cs dd) = PieChartOptions s cs dd

-- | Set colors.
pieColors : List ({..label}, Color)
         -> PieChartOptions (t', Unbound c', dd') lbl r1 r2 id
         -> PieChartOptions (t', Bound {..label}, dd') label r1 r2 id
pieColors cs (PieChartOptions s _ dd) = PieChartOptions s cs dd

-- | Permit drilling down.
pieDrilldown : (r <- (pid, cid))
            => (Field pid id, Field cid id)
            -> PieChartOptions (t', lbl', Unbound dd') lbl r1 r2 id'
            -> PieChartOptions (t', lbl', Bound (Field r id)) lbl pid cid id
pieDrilldown dd (PieChartOptions s cs _) = PieChartOptions s cs (Just dd)

-- drilldownBarChart options

-- | Set the chart title.
titleB : String
      -> DrilldownBarChartOptions (Unbound title', dir', cl', vl') cl vl
      -> DrilldownBarChartOptions (Bound String, dir', cl', vl') cl vl
titleB title (DrilldownBarChartOptions _ dir cl vl) =
  DrilldownBarChartOptions (Just title) dir cl vl

-- | Display direction; Vertical means the value (Y) axis points up,
-- Horizontal that it points right.
yDirectionB : Direction
           -> DrilldownBarChartOptions (title', Unbound dir', cl', vl') cl vl
           -> DrilldownBarChartOptions (title', Bound Direction, cl', vl') cl vl
yDirectionB dir (DrilldownBarChartOptions title _ cl vl) =
  DrilldownBarChartOptions title dir cl vl

-- | Label for the category (x) axis.
xLabelB : Atomic cl
       -> DrilldownBarChartOptions (title', dir', Unbound cl', vl') clo vl
       -> DrilldownBarChartOptions (title', dir', Bound (Atomic cl), vl') cl vl
xLabelB cl (DrilldownBarChartOptions title dir _ vl) =
  DrilldownBarChartOptions title dir (Just cl) vl

-- | Label for the value (y) axis.
yLabelB : Atomic vl
       -> DrilldownBarChartOptions (title', dir', cl', Unbound vl') cl vlo
       -> DrilldownBarChartOptions (title', dir', cl', Bound (Atomic vl)) cl vl
yLabelB vl (DrilldownBarChartOptions title dir cl _) =
  DrilldownBarChartOptions title dir cl (Just vl)
