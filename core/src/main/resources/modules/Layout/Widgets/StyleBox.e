module Layout.Widgets.StyleBox where

-- The style box: registry name "styleBox", rendered by the legacy
-- htmlwriter.runStylebox (ermine-htmlwriter.js:3582 -> js/ermine/stylebox.js).
-- HTMLWriter.styleBox (~1188-1271) is the emission site.
--
-- The widget is a FIXED 3x3 grid (`gridSize = 3`, stylebox.js:28) of aggregated
-- cells.  Server-side the aggregation is a relational AggregateByGroupE that sums
-- `aggColumn` grouped by the two position columns, and the formatted cell text is
-- `aPres.basicEval` of the sum; the result is handed to the browser as
-- `cellCounts`, which is JSON INSIDE a JSON string (:1263, parsed back at
-- stylebox.js:87).  client/src/charts.ts does that aggregation on the rows of
-- `styleBoxRows` and re-encodes the string, so the grid needs no callback.
--
-- What does still need one: clicking a cell opens a popup whose rows come from a
-- `styleBoxData` POST (`withStyleBoxData`, ermine-htmlwriter.js:297-319), and that
-- function has NO local branch.  The adapter sends `relation: null` and
-- `legend: null`; the grid renders, the popup does not.  See report-J3e.md.
--
-- `xBins`/`yBins` are pairs of NUMBERS here.  The server sends them pre-formatted
-- as strings, but their only consumer is `formatBounds` (stylebox.js:183), which
-- calls `.toFixed(3)` on them -- so the legacy string form throws there today.
--
-- `aggFormat` reaches the renderer as the LOSSY TUPLE form: runStylebox applies
-- `formatDisplay` to `args.aFormat` ITSELF (ermine-htmlwriter.js:3583), so the
-- adapter must hand it a tuple, not a formatted value.

import Json using type Inline
import Layout.Widgets.Format using type CellFormat
import List using empty_Bracket; cons_Bracket
import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}
import Field using fieldName

data StyleBoxProps r = StyleBoxProps { xTitle : String
                                     , yTitle : String
                                     , aggColumn : String
                                     , aggTitle : String
                                     , aggFormat : CellFormat
                                     , xPositionColumn : String  -- cells in 0..2 (typed: sbXPosition)
                                     , yPositionColumn : String  -- cells in 0..2 (typed: sbYPosition)
                                     , rowLabels : List String
                                     , columnLabels : List String
                                     , showNumber : Bool
                                     , xBins : List (Double, Double)
                                     , yBins : List (Double, Double)
                                     , styleBoxRows : Inline r }

-- | The registry name, tied to the props type.
styleBoxName : WidgetName (StyleBoxProps r)
styleBoxName = WidgetName "styleBox"

styleBox : StyleBoxProps r -> Node
styleBox p = widget styleBoxName p

-- * The typed authoring API (WP-37, D4)
--
-- `StyleBoxProps` is the WIRE (column names, D3).  A report builds it with
-- `styleBoxOf` from a `StyleBoxSource`, whose three column slots are FIELDS:
-- the partition in `styleBoxOf` proves the aggregated column and the two
-- position columns are three DISTINCT columns of the relation (as the
-- legacy `Layout.Report.styleBox` does).  Positions are `Int`, as there.

-- | What `styleBoxOf` lowers.  Server-side only.
data StyleBoxSource h1 h2 h3 a r =
  StyleBoxSource { sbXTitle : String
                 , sbYTitle : String
                 , sbAgg : Field h1 a
                 , sbAggTitle : String
                 , sbAggFormat : CellFormat
                 , sbXPosition : Field h2 Int  -- cells in 0..2
                 , sbYPosition : Field h3 Int  -- cells in 0..2
                 , sbRowLabels : List String
                 , sbColumnLabels : List String
                 , sbShowNumber : Bool
                 , sbXBins : List (Double, Double)
                 , sbYBins : List (Double, Double)
                 , sbRows : Inline r }

styleBoxOf : (r <- (h1, h2, h3, t)) => StyleBoxSource h1 h2 h3 a r -> StyleBoxProps r
styleBoxOf s =
  StyleBoxProps (sbXTitle s) (sbYTitle s) (fieldName (sbAgg s)) (sbAggTitle s) (sbAggFormat s)
                (fieldName (sbXPosition s)) (fieldName (sbYPosition s))
                (sbRowLabels s) (sbColumnLabels s) (sbShowNumber s)
                (sbXBins s) (sbYBins s) (sbRows s)
