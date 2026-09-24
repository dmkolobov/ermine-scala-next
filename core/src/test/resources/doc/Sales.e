module Sales where

-- The example report of the JSON document runner (json/Runner.scala,
-- tracker/json-stage3/report-J3c.md) AND of the editor preview.  It is
-- deliberately small and has no database behind it: every relation is built
-- from literal rows, so
--
--     bin/ermine-serve --root core/src/test/resources/doc --preload Sales --port 8080
--     curl -s localhost:8080/report/Sales -H 'Content-Type: application/json' \
--          -d '{"params": {"fromDay": "2026-01-05", "toDay": "2026-02-20",
--                          "onlyRegion": "north", "orderBy": "ByAmount"},
--              "data": {"default": "inline", "threshold": 50}}'
--
-- answers with one JSON document and touches nothing but the in-memory
-- SQLite connection the runner opens for the request.
--
-- TYPED SINCE Q25 (tracker/JSON-WIDGET-PLAYGROUND.md section 13, 2026-09-23):
-- every widget is a Layout.Widgets.* constructor, so every props object is one
-- the client validates with the zod GENERATED from that module.  The untyped
-- shape this report had before (`rawWidget` over a report-local record, a bare
-- string and bare relations) lives on in SalesRaw.e, which the runner's tests
-- read; the params type below is the same there, byte for byte.
--
-- What it shows:
--   * a params `data` with NAMED fields -- a date range, a `Maybe` filter
--     and an enum -- which is what the request's "params" object is decoded
--     into (json/Decode.scala).  A record-style constructor is a JSON object
--     keyed by the field names, an all-nullary `data` is a string, and a
--     `Maybe` field may be left out of the object entirely;
--   * the typed "heading" and "text" widgets (Layout.Widgets.Heading and
--     Layout.Widgets.Text), the parameters echoed back into the heading;
--   * three typed "table" widgets (Layout.Widgets.Table's `tabular`).  A
--     table's `rows` is a BARE relation, so the request decides how they are
--     delivered: inline unless "data.default" says otherwise, and deferred
--     anyway once a relation is over "data.threshold" rows.  A typed table
--     cannot FORCE deferral (`rows : [..r]`, not `Deferred r`), so under the
--     editor preview's request -- inline, no threshold -- all three arrive
--     inline; SalesRaw.e keeps the forced `Deferred` the runner tests;
--   * VFlow / Grid layout, and the sort order a parameter picks carried into
--     the tables' `sorts`;
--   * a date range that matches NO sale still renders: `byDay` is built with
--     `relationWithHeader`, so an empty table keeps its four columns.  A
--     plain `relation []` has no columns to send (the header is read off the
--     first row) and the runner would answer a 500 (tracker/JSON-WIDGET-
--     PLAYGROUND.md, WP-29).

import Bool
import Date
import Eq
import Json
import Layout.Doc
import Layout.Widgets.Format using type CellFormat; Default; Currency
import Layout.Widgets.Heading using {heading; HeadingProps}
import Layout.Widgets.Text using {plainText; TextProps}
-- a `using` list: Table's `sortColumn` selector would collide with Heading's
import Layout.Widgets.Table using {tabular; TableProps; type TableColumn; TableColumn;
                                   type ColumnSort; ColumnSort; AlignLeft; DateColumn;
                                   textColumn; numberColumn}
-- the `using` list keeps `map`/`length` from colliding with String's and
-- Control.Functor's; `empty_Bracket`/`cons_Bracket` are what a `[..]`
-- literal desugars to
import List using {filter; length; nub; sum'; map_List; empty_Bracket; cons_Bracket}
import Maybe
import Primitive
import Relation
-- `{region, day, ..}` (a Row, the header `relationWithHeader` takes)
-- desugars to these two
import Relation.Row using {single_Brace; snoc_Brace}

-- the columns of the relations below
field region : String
field day    : Date
field amount : Double
field units  : Int
field item   : String

-- How the client should sort the table.  An all-nullary `data` is its
-- constructor name on the wire, so the request sends "orderBy": "ByAmount".
data Sort = ByDay | ByAmount | ByUnits

-- The report's parameters:
--   {"fromDay": "2026-01-05", "toDay": "2026-02-20",
--    "onlyRegion": "north", "orderBy": "ByAmount"}
data Query = Query
  { fromDay    : Date
  , toDay      : Date
  , onlyRegion : Maybe String
  , orderBy    : Sort
  }

-- One fact.  The named fields give selector functions (sRegion, sDay, ..),
-- which is how the rows below are read.
data Sale = Sale
  { sRegion : String
  , sDay    : Date
  , sAmount : Double
  , sUnits  : Int
  , sItem   : String
  }

sales : List Sale
sales =
  [ Sale "north" @2026/1/5  1200.5  3  "widget"
  , Sale "north" @2026/1/19 840.0   2  "gizmo"
  , Sale "north" @2026/2/14 2310.25 7  "widget"
  , Sale "south" @2026/1/9  615.75  1  "doohickey"
  , Sale "south" @2026/2/2  1990.0  5  "widget"
  , Sale "east"  @2026/2/20 75.5    1  "gizmo"
  , Sale "east"  @2026/3/3  4100.0  11 "doohickey"
  , Sale "west"  @2026/3/17 1550.0  4  "widget"
  ]

columnOf : Sort -> String
columnOf ByDay    = "day"
columnOf ByAmount = "amount"
columnOf ByUnits  = "units"

-- The by-day table's sort: an INDEX into its columns below (region, day,
-- amount, units), oldest day first, the biggest amount or unit count first.
sortOf : Sort -> ColumnSort
sortOf ByDay    = ColumnSort 1 False
sortOf ByAmount = ColumnSort 2 True
sortOf ByUnits  = ColumnSort 3 True

money : CellFormat
money = Currency False False "$" 2

-- A typed table over a bare relation: every knob at its legacy default but
-- the sort.
salesTable : List TableColumn -> List ColumnSort -> [..r] -> Node
salesTable cs ss rs = tabular (TableProps cs Nothing ss True True rs)

-- `Date` is a Primitive, so <= and >= compare two of them.
keep : Query -> Sale -> Bool
keep q s =
  sDay s >= fromDay q && sDay s <= toDay q &&
  maybe True (w -> w == sRegion s) (onlyRegion q)

report : Query -> Node
report q =
  let picked = filter (keep q) sales
      total  = sum' (map_List sAmount picked)
      -- `picked` is empty when the range matches nothing, so the header is
      -- given explicitly rather than read off a first row
      byDay  = relationWithHeader {region, day, amount, units}
                 (map_List (s -> { region = sRegion s, day = sDay s,
                                   amount = sAmount s, units = sUnits s }) picked)
      -- `regions` and `items` are built from the whole `sales` list, never
      -- empty, so plain `relation` is enough there.
      regions = relation (map_List (r -> { region = r }) (nub (map_List sRegion sales)))
      items = relation (map_List (s -> { item = sItem s, amount = sAmount s,
                                         units = sUnits s }) sales)
  in vflow
       [ heading (HeadingProps "Sales" (columnOf (orderBy q)) (length picked) total)
       , grid [ [ salesTable [ textColumn "region" "Region"
                             , TableColumn "day" "Day" Default AlignLeft DateColumn
                             , numberColumn "amount" "Amount" money
                             , numberColumn "units" "Units" Default ]
                             [sortOf (orderBy q)] byDay
                , salesTable [textColumn "region" "Region"] [] regions ]
              , [ salesTable [ textColumn "item" "Item"
                             , numberColumn "amount" "Amount" money
                             , numberColumn "units" "Units" Default ]
                             [] items
                , plainText (TextProps "every line item, whatever the date range") ] ]
       ]
