module Layout.Chart.Type where

import Layout.Color using type Color

foreign
  data "com.clarifi.reporting.writers.ChartSeries" ChartSeries# (x: *) (y: *)
  data "com.clarifi.reporting.writers.AxisConstraints" Axis (p: *)

-- | Description of a chart series.
data ChartSeries xa ya =
  forall r. ChartSeries (List ({..r}, Color)) (ChartSeries# xa ya)
