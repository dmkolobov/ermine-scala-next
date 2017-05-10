module Layout.Report.Keyed.OptionTypes where

{- These definitions *aren't* exported by Keyed, but provide support
in the form of types whose values are manipulated by the combinators
in Options, and default options that Keyed functions fall back upon.
Unless you are writing your own option combinators, you shouldn't need
to import this.

Each *Options type has a single data constructor representing all
options.  Each exposes the underlying type parameters, and also
carries one phantom parameter per option, which starts out as
`Unbound` in the related default* option set.  The combinators in
Options change that `Unbound` to `Bound`, thereby forbidding repeated
options.

The various *Defaults terms are meant for use by the functions in
Keyed.  The *Defaults types fill out the phantom parameters to the
so-named *Options types with Unbounds; they make the
signatures in Keyed more straightforward to read. -}

import Either
import Function
import Int
import Maybe
import List
import Layout.Chart using type AxisLabel; NoAxisLabel
import Layout.Chart.Unsafe
import Layout.Color using type Color
import Layout.Format as Fmt
import Layout.Legend using type Legend
import Layout.Presentation using type Presentation; asPresentation
import Layout.Report using
  type Report; type DisplayScale
  Linear; chartLegendDefaultLocation; val
import Layout.Report.Atomic
import Layout.Report.Direction
import Layout.SortPriority using {type SortPriorityAnnotated; unsorted}
import Layout.SortStrategy as SS
import Layout.Magnitude
import Relation.Op using prim
import Ord using type Ord
import Relation.Sort using {type Sort; type SortOrder; Ascending}
import Void
import DrilldownList using type DrilldownList
import Layout.Report.SoftRelation using type SoftRelation

-- | Uninhabited types acting as markers for phantom boundedness.
data Center
data North
data South
data East
data West
data Width
data Height

-- | border
data BorderOptions cnsew f z =
  BorderOptions (Maybe (Report f z)) (Maybe (Report f z))
                (Maybe (Report f z)) (Maybe (Report f z))
                (Maybe (Report f z))
type BorderDefaults u1 f z = BorderOptions u1 f z
borderDefaults : BorderDefaults u1 f z
borderDefaults = BorderOptions Nothing Nothing Nothing Nothing Nothing

-- | prefS
data PrefSOptions wh = PrefSOptions (Either ( MagnitudeList -- Width
                                            , MagnitudeList -- Height
                                            )
                                    (List Area))
type PrefSDefaults u1 = PrefSOptions u1
prefSDefaults : PrefSDefaults u1
prefSDefaults = PrefSOptions (Left ([], []))

-- | softRelation
data SoftRelationOptions kvsp {-ks' pv' pvss' pvsp'-} k v b =
  SoftRelationOptions (Maybe (Either (Sort k) (Ord {..k})))
                      ({..k} -> Maybe (Presentation v b))
                      ({..k} -> Maybe (SortStrategy_SS v))
                      ({..k} -> () -> SortPriorityAnnotated ())
type SoftRelationDefaults u1 k v b = SoftRelationOptions u1 k v b
softRelationDefaults : SoftRelationDefaults u1 k v b
softRelationDefaults =
  SoftRelationOptions Nothing (const Nothing)
                      (const Nothing) (const . const $ unsorted ())

data KeyValueTabularOptions u1 i label pid id cid r root =
  KeyValueTabularOptions (Maybe (Legend i))
                         (Maybe (Either (Field pid id, Field cid id, Field label String)
                                        (DrilldownList r, root, Field label String)))
type KeyValueTabularDefaults u1 i label pid id cid r root = KeyValueTabularOptions u1 i label pid id cid r root
keyValueTabularDefaults : KeyValueTabularDefaults u1 i label pid id cid r root
keyValueTabularDefaults = KeyValueTabularOptions Nothing Nothing

-- | tabular
data TabularOptions (leg: *) r = TabularOptions (Maybe (Legend r))
type TabularDefaults u1 r = TabularOptions u1 r
tabularDefaults : TabularDefaults u1 r
tabularDefaults = TabularOptions Nothing

-- | scaled
data ScaledOptions dirlowup a = ScaledOptions SortOrder (Maybe a) (Maybe a) DisplayScale
type ScaledDefaults u1 a = ScaledOptions u1 a
scaledDefaults : ScaledDefaults u1 a
scaledDefaults = ScaledOptions Ascending Nothing Nothing Linear

-- | unscaled
data UnscaledOptions sort a = UnscaledOptions (Either SortOrder (Ord a))
type UnscaledDefaults u1 a = UnscaledOptions u1 a
unscaledDefaults : UnscaledDefaults u1 a
unscaledDefaults = UnscaledOptions $ Left Ascending

-- | chart
data ChartOptions tdloxlxfylyf xa ya {-title' dir' legOpts' xlbl' xfmt' xax' ylbl' yfmt' yax'-} =
  ChartOptions (Maybe String) Direction ChartLegendOptions#
               AxisLabel (Format_Fmt xa) Bool
               AxisLabel (Format_Fmt ya) Bool
-- defaults here are a little more complicated; see the term
type ChartDefaults u1 xa ya = ChartOptions u1 xa ya
chartDefaults : (Primitive xa, Primitive ya) => ChartDefaults u1 xa ya
chartDefaults = ChartOptions Nothing Vertical defaultChartLegendOptions#
                             NoAxisLabel unit_Fmt True
                             NoAxisLabel unit_Fmt True

-- | pieChart and drilldownPieChart
data PieChartOptions ph lbl r1 r2 id =
  forall mt.
    PieChartOptions
      String -- chart title
      (Maybe (Atomic mt)) -- series designation (for tool tip)
      ChartLegendOptions#
      (List ({..lbl}, Color)) -- color specifications
      (Maybe (Field r1 id, Field r2 id))

type PieChartDefaults ph lbl = PieChartOptions ph lbl (| |) (| |) Void
pieChartDefaults : PieChartDefaults ph lbl
pieChartDefaults = PieChartOptions "" Nothing chartLegendDefaultLocation Nil Nothing

-- | drilldownBarChart
data DrilldownBarChartOptions tdlocv sr sa cr vr {-title' logOpts' dir' cl' vl'-} =
  DrilldownBarChartOptions (Maybe String) Direction ChartLegendOptions#
                           AxisLabel AxisLabel
                           (Presentation sr sa)
                           (List ({..cr}, {..cr})) (List ({..vr}, {..vr}))
type DrilldownBarChartDefaults u1 cr vr = DrilldownBarChartOptions u1 (||) String cr vr
drilldownBarChartDefaults : DrilldownBarChartDefaults u1 cr vr
drilldownBarChartDefaults =
  DrilldownBarChartOptions Nothing Vertical defaultChartLegendOptions# NoAxisLabel NoAxisLabel
                           (asPresentation ' prim "") Nil Nil
