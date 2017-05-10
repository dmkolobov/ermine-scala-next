module Layout.Report.Keyed where

{- This is an alternative to `Layout.Report`; it is not compatible
with `Layout` or `Layout.Report`.  It replaces symbols in
`Layout.Report` with new versions that are more convenient to use.

The only difference is that the signatures differ in some cases,
replacing several parameters that have sensible defaults with an
optional argument.  These have complex signatures, but not to worry:
where you see Options, or "(SomethingOptions Unbound... -> ...)" in a
signature, that argument may be filled in by `defaults` or any
[...]_Opt, as provided by Layout.Report.Keyed.Options. -}

import Control.Functor using fmap
import Function
import Layout.Chart.Type
import Layout.Presentation
import Layout.Report.Keyed.OptionTypes
import Layout.Report as R
import Layout.Report.SoftRelation using type SoftRelation
import Layout.Report.Keyed.Options
import Layout.Report.Fulcrum.Dynamic
import Either
import Maybe
import Ord using lt
import Pair
import Relation.Sort hiding ordering
export Layout.Report.Keyed.Syntax
-- export Layout.Report hiding prefS

-- | Marker in the following signatures for the option type.  `used`
-- is the result of whatever options you apply, and `def` signifies
-- the defaults.
type Options used def = def -> used

border : Options (BorderOptions cnsew f z) (BorderDefaults cnsew' f z)
      -> Report_R f z
border oa = oa borderDefaults |> (BorderOptions c n s e w) -> border_R c n s e w

prefS : Options (PrefSOptions wh) (PrefSDefaults wh')
     -> Report_R f z            -- ^ Underlying report.
     -> Report_R f z
prefS oa = oa prefSDefaults |> (PrefSOptions o) -> prefs o
  where prefs (Left (w, h)) = prefH_R h  . prefW_R w
        prefs (Right a)  =  prefA_R a


softRelation : (AsPresentation prk, AsPresentation prvd)
            => prk k a -> prvd v b
            -> (Options (SoftRelationOptions kpsp k v b)
                        (SoftRelationDefaults kpsp' k v b))
            -> SoftRelation a b k v
softRelation pk pv oa = oa softRelationDefaults |>
  (SoftRelationOptions ksort pvSpecial pvss pvsp) ->
    (softRelation_R pk (maybe (Left . ordering Ascending $ pk) id ksort) $ ktup ->
      ((maybe (asPresentation pv) id $ pvSpecial ktup, pvss ktup),
       snd $ pvsp ktup ()))

keyValueTabular : (Relational rel, Relational rel2)
               => (Options (KeyValueTabularOptions u1 i label pid id cid r (rel2 root))
                           (KeyValueTabularOptions u2 i label pid id cid r (rel2 root)))
               -> Either (SoftRelation a b k v) (DynamicFulcrum k v)
               -> rel r2
               -> Report_R f z
keyValueTabular kvt srdf rel = kvt keyValueTabularDefaults |> ((KeyValueTabularOptions l dd) -> case srdf of
        Right df -> pivotTabular'_R df l rel
        Left sr -> case dd of
            Nothing -> keyValueTabular_R sr l rel
            Just (Left (p, c, label)) -> drilldownKeyValueTable_R sr l label p c rel
            Just (Right (ddl, root, label)) -> drilldownKeyValueTable2_R sr l label ddl rel root
  )

tabular : Relational rel
       => (Options (TabularOptions u1 r) (TabularDefaults u1' r))
       -> rel r -> Report_R f z
tabular oa = oa tabularDefaults |> (TabularOptions leg) ->
  tabular_R leg

scaled : Scaled a
      => (Options (ScaledOptions u1 a) (ScaledDefaults u1' a))
      -> Axis a
scaled oa = oa scaledDefaults |> (ScaledOptions so low up ds) ->
  scaled_R so low up ds

unscaled : Unscaled a
        => (Options (UnscaledOptions u1 a) (UnscaledDefaults u1' a))
        -> Axis a
unscaled oa = oa unscaledDefaults |> (UnscaledOptions so) ->
  unscaled_R (fmap eitherFunctor lt so)

chart : (Primitive xa', Primitive ya')
     => (Options (ChartOptions tdxfyf xa ya)
                 (ChartDefaults tdxfyf' xa' ya'))
     -> Axis xa
     -> Axis ya
     -> List (ChartSeries xa ya)
     -> Report_R f z
chart oa ax ay = oa chartDefaults |> (ChartOptions title dir legOpts xlbl xfmt xax ylbl yfmt yax) ->
  chart_R title dir legOpts xlbl xfmt xax ax ylbl yfmt yax ay

pieChart : (r <- (label, value, r1, r2, o), PrimitiveNum d,
            AsPresentation prl, AsPresentation prv, Relational rel)
        => Options (PieChartOptions ph label r1 r2 id)
                   (PieChartDefaults ph' label)
        -> prl label lv
        -> prv value d
        -> rel (|..r|)
        -> Report_R f z
pieChart oa label value = oa pieChartDefaults |> (PieChartOptions title nm lo color dd) ->
  maybe (pieChart_R title nm lo color label value)
        (uncurry (drilldownPieChart_R title nm lo color label value))
        dd

drilldownBarChart : (exists o. r <- (sr, cr, vr, pi, ci, o),
                               AsPresentation cpr, AsPresentation vpr,
                               Relational rel)
                 => Axis ca
                 -> Axis va
                 -> (Options (DrilldownBarChartOptions tdlocv sr sa cr vr)
                             (DrilldownBarChartDefaults tdlocv' cr vr))
                 -> cpr cr ca
                 -> vpr vr va
                 -> Field pi id
                 -> Field ci id
                 -> rel r
                 -> Report_R f z
drilldownBarChart cax vax oa = oa drilldownBarChartDefaults
  |> (DrilldownBarChartOptions title dir lo clbl vlbl spr cov vov) ->
    drilldownBarChart_R title dir lo clbl cov cax vlbl vov vax spr
