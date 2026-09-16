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
import Layout.Doc using widget; type Node

data StyleBoxProps r = StyleBoxProps { xTitle : String
                                     , yTitle : String
                                     , aggColumn : String
                                     , aggTitle : String
                                     , aggFormat : CellFormat
                                     , xPositionColumn : String  -- cells in 0..2
                                     , yPositionColumn : String  -- cells in 0..2
                                     , rowLabels : List String
                                     , columnLabels : List String
                                     , showNumber : Bool
                                     , xBins : List (Double, Double)
                                     , yBins : List (Double, Double)
                                     , styleBoxRows : Inline r }

styleBox : StyleBoxProps r -> Node
styleBox p = widget "styleBox" p
