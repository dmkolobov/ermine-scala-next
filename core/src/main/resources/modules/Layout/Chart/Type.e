module Layout.Chart.Type where

import Layout.Color using type Color
import Layout.Presentation using type Presentation
import Layout.PresRow using type PresRow
import List.NonEmpty using type NonEmpty
import Relation.Op using type Op
import Prim using type PrimExpr#

foreign
  data "com.clarifi.reporting.writers.ChartSeries" ChartSeries# (x: *) (y: *)
  data "com.clarifi.reporting.writers.AxisConstraints" Axis (p: *)
  data "com.clarifi.reporting.writers.ChartVariant" ChartVariant#

-- | Description of a chart series.
data ChartSeries xa ya =
  forall r s t sr sa xr yr xtr xta ytr yta er rel.
    ChartSeries (List ({..r}, Color))
                (List ({..s}, {..s}))
                (List ({..t}, {..t}))
                (Presentation sr sa)
                (NonEmpty (Op xr xa))
                (Op yr ya)
                (Maybe (Presentation xtr xta))
                (Maybe (Presentation ytr yta))
                ChartVariant#
                (PresRow er)
                rel
                -- (ChartSeries# xa ya)
