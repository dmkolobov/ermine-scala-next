{-
A chart is built from an x-axis (of type `Axis x`), a y-axis (of type `Axis y`), and a data series (a `Series x y`). The type of the axes must match the series type. `y` will often be `Double`, `x` could be `Date`, `String`, `Double`, etc.
-}

-- `typ` tracks the chart type, Bar, Line, etc
-- `x` and `y` track type of x and y axes
-- `axis` tracks whether the x-axis on the chart has been set, so
-- we can disallow setting this multiple times (to different things)
-- Note: don't track whether y-axis has been set, since it is always
-- well-defined to have multiple y-axes
data Chart axis typ x y

-- Create a single-series chart; `typ` will be `Line`, `Bar`, etc
-- Chart starts out with no title and no axis information
-- ex: chart Bar $ series [("GOOG", 1.0), ("MSFT", .5)]
-- ex: chart Line $ series [(@2012/1/1, .03), (@2012/2/1, .06)]
chart : (BasicChartType typ, PrimitiveNum y)
     => typ -> Series x y -> Chart axis typ x y

-- Possible values for `typ`:
data Line = Line
data Bar = Bar
data Scatter = Scatter
data Area = Area

-- enforced by this typeclass
class BasicChartType typ
instance BasicChartType Line
instance BasicChartType Bar
instance BasicChartType Scatter
instance BasicChartType Area

{-
Setting options on the chart, including axes:

  chart Line (series [(@2012/1/1, .03), (@2012/2/1, .06)])
  |> title "Important title"
  |> xAxis xa
  |> yAxis ya

Order of setting options doesn't matter; this works too:

  chart Line (series [(@2012/1/1, .03), (@2012/2/1, .06)])
  |> yAxis ya
  |> title "Important title"
  |> xAxis xa
-}

-- The `chart` combinator above leaves `axis` free, so it can be
-- unified with `Bound` or `Unbound`. Type parameter for these data
-- types is just to give a nicer error message when unification fails
data Bound a
data Unbound a

-- we can set the `x` and `y` axes of a chart; requires both axes
-- are `Unbound`; returns a `Chart` whose `axis` type param is bound
axis : Axis x -> Axis y
    -> Chart (Unbound (Axis x)) t x y
    -> Chart (Bound (Axis x)) t x y
axis x y = xAxis x . yAxis y

xAxis : Axis x
     -> Chart (Unbound (Axis x)) t x y
     -> Chart (Bound (Axis x)) t x y

yAxis : Axis y -> Chart axis t x y -> Chart axis t x y
title : String -> Chart axis typ x y -> Chart axis typ x y

-- convert a chart to a report - this throws out type information, so no further chart composition is possible afterwards
displayChart : Chart axis typ x y -> Report f z

{-
A chart may have multiple _series_. For instance, a time-series bar chart may have multiple bars for each date. In this API, multi-series charts are built up by combining single-series charts. There are three methods of creating multi-series charts:

* overlaying: combines charts of _different_ types by overlaying them, for instance, overlaying a line chart on top of a bar chart
* merging: combines charts of the same type by merging their axes
* stacking: combines charts of the same type by stacking (suitable only for bar and area charts)
-}

-- first, we introduce a few new values for `typ`:

data Overlay -- deliberately no public constructors
data Stacked typ = Stacked typ

-- Notice that the chart types do not need to match for overlaying
-- and the second chart must have no x-axis bound (ok if the second
-- chart has a bound y-axis)
overlay : Chart axis typ1 x y
       -> Chart (Unbound (Axis x)) typ2 x y
       -> Chart axis Overlay x y

-- Merge the axes of the list of charts, e.g. combine a list of
-- single-series bar charts into a multi-series bar chart,
-- or combine a list of line charts into a multi-series line chart.
-- The types must match for all the charts being merged.
--
-- Note: all the charts being merged must have an unbound x-axis,
-- which should be bound after the call to `mergeAxes`
--
-- Note: title of each chart becomes its series name in the merged
-- chart, otherwise series name is blank
--
-- Note: BasicChartType constraint prevents this operation for
-- Overlay charts; everything but `Overlay` is an instance of
-- `BasicChartType`.
--
-- If charts disagree on the y-axis, _show both y-axes_
mergeAxes : BasicChartType typ
         => List (Chart (Unbound (Axis x)) typ x y)
         -> Chart (Unbound (Axis x)) typ x y


-- Combine a list of charts by stacking, e.g.
--   stack [b1, b2, b3]
--   stack [b1, b2, b3]
-- Not all chart types are stackable, we enforce this with a
-- constraint:
-- stack [chart Line s2, c2, c3] -- type error! no Stackable Line instance
stack : Stackable typ
     => List (Chart (Unbound (Axis x)) typ x y)
     -> Chart (Unbound (Axis x)) (Stacked typ) x y

data Stacked typ = Stacked

class Stackable typ
instance Stackable Bar
instance Stackable Area

-- These are the only combinators for creating multi-series charts. If we have a relation with three columns, ticker, date, and value, and want to create a multi-series line chart from this data, that would be expressed with a `scanRelation`, followed by a `mergeAxes`. (note, a `placeholder` combinator might be nice in the writer API, to supply a report to use while another more expensive report is loading)

{-
A `Series x y` defines the data that can be used to build a single-series `Chart x y`. We can create a series from a list of pairs, a two column relation, or a box-and-whiskers list of pairs
-}

data Series x y

  -- Create a series from a list of pairs
  seriesList : List (x,y) -> Series x y

  -- Create a series from a relation with two logical columns
  -- AsOp typeclass can be satisfied by Fields or Ops
  seriesRel : (AsOp f1, AsOp f2, r <- (r1,r2,t)) =>
              f1 r1 x -> f2 r2 y -> [..r] -> Series x y

  -- seriesBoxAndWhiskersRel : a relation with 6 columns
  -- boxAndWhiskers : Series x (y,y,y,y,y) -> Series x y

  -- Create a box-and-whiskers series from a list
  -- y-values are min,25%,50%,75%,max, say, prob should roll into a stats object
  seriesListBoxAndWhiskers : List (x,(y,y,y,y,y)) -> Series x y

{-
An axis can specify several pieces of information:

* _ordering_: what order values appear on the axis
* _value formatting_: how values are formatted (as a number, a rounded number, as a percent, in dollars, etc)
* _scaling_: axes may be _scaled_ or _unscaled_--in a scaled axis, the visual distance between points on the axis reflects some distance metric. This makes sense only for numeric or date x-axes, not for a string x-axis. A scaled axis may be log-scaled as well as linearly scaled.
* _tick granularity_: the axis can decide at which points tick marks should appear
-}

data Axis a = Axis
  (Format a)   -- how values are formatted
  (Ticks a)    -- where ticks appear on this axis
  (Scaling a)  -- relative visual distance between values on axis
  (Ordering a) -- order of points on this axis
  Title        -- the name of this axis, possibly empty

-- Ticks a controls at which points ticks will appear on an axis
-- Receives the overall range, and returns two values:
--   an `a -> Bool`, controls whether to display a tick for that value
--   a `List a`, determines minimum set of ticks, 'major' ticks
-- The `List a` is useful if the data is sparse, may still want
-- ticks to appear at the start of each month, say.
type Ticks a = (a,a) -> (Maybe (a -> Bool), List a)
-- as a GADT
data Ticks a -- (a,a) -> (a -> Bool, List a)
  monthly : Ticks Date
  weekly : Ticks Date
  daily : Ticks Date
  every : Double -> Ticks Double
  autoTicks : Ticks a
  nullableTicks : Ticks a -> Ticks (Nullable a)
  splitEvenly : Int -> Ticks a
  literalTicks : List a -> Ticks a

type Ticks a = (a,a) -> List a -- (Maybe (a -> Bool), List a)
type Ticks a = List a -- (a,a) -> List a -- (Maybe (a -> Bool), List a)
type Title = String

data Scaling a
  unscaled : Scaling a
  linearScaled : Scaled a => Scaling a
  logScaled : Scaled a => Scaling a
-- Scaled constraint includes all primitive nums, nullable versions of them, and dates
-- log-scaling dates doesn't make much sense, though I guess we could allow it
-- instance LogScalable Date

-- Ordering controls order of values on the axis
data Ordering a = Asc | Desc | LiteralOrdering (List a)

-- note - certain combinations of Ordering and Scaling don't make
-- sense, for instance, LiteralOrdering combined with linear or log scaling
-- can enforce this with an extra type parameter on `Ordering` and `Scaling`:
data Unscaled
data Scaled

data Ordering t a
  asc : Ordering t a
  desc : Ordering t a
  literalOrdering : List a -> Ordering Unscaled a

data Scaling t a
  unscaled : Scaling Unscaled a
  linearScaled : LinearScalable a => Scaling Scaled a
  logScaled : LinearScalable a => Scaling Scaled a

-- Then change `Axis` definition to:
data Axis a = forall t . Axis ... (Scaling t a) (Ordering t a)

{-
A chart may have several options not associated with any one series--the overall chart title, where the legend should be shown if multi-series, whether the bars should grow horizontally or vertically if the chart is a simple bar chart, etc. A series may have options as well--whether to render the data points using diamonds, circles, or squares, the series color, etc.

API conventions - if an object (like a chart, or a series) has optional parameters, we create that object with default parameters, then supply additional parameters after the fact. Clients should not have to write things like `barChart (Just "A title") Nothing Nothing Nothing blah`, which is annoying, not to mention ugly. Instead, this would be expressed as something like `withTitle "A title" (foo blah)`, or `foo blah |> title := "A title"` (assuming `title` were a Lens of some sort, say).
-}

data SeriesOpts -- color, dashes vs solid lines if a line chart, color, etc
setSeriesOpts : SeriesOpts -> Series x y -> Series x y

data ChartOpts -- title, stuff about legends, etc...
setChartOpts : ChartOpts -> Chart x y -> Chart x y

-- just meant to be suggestive
withOpts : ChartOpts -> Chart typ x y -> Chart typ x y
withTitle : String -> Chart typ x y -> Chart typ x y

-- Instead or in addition, might want pretty Lens-based API for setting options
data Orientation = Horizontal | Vertical
orientation : Lens (Chart Bar x y) Orientation

-- mychart |> orientation := Horizontal
--          . title       := "Important chart title"

(:=) : Lens ctx a -> a -> (ctx -> ctx)

{-
Chart typ x y representation is something complicated, like:
(title, List (type, axis, axis, List series))
Would be stored, erased, Scala side
-}
