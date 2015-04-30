module Layout.Chart.Type where

import Layout.Color using type Color
import Prim using type PrimExpr#

foreign
  data "com.clarifi.reporting.writers.ChartSeries" ChartSeries# (x: *) (y: *)
  data "com.clarifi.reporting.writers.AxisConstraints" Axis (p: *)

-- | Description of a chart series.
data ChartSeries xa ya =
  forall r s t. ChartSeries (List ({..r}, Color))
                            (List ({..s}, {..s}))
                            (List ({..t}, {..t}))
                            (ChartSeries# xa ya)
