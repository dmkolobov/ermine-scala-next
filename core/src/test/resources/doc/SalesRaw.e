module SalesRaw where

-- The RAW runner fixture: what core/src/test/resources/doc/Sales.e was until
-- Q25 (tracker/JSON-WIDGET-PLAYGROUND.md section 13, 2026-09-23) rewrote that
-- report's body with the typed widgets.  This copy keeps the untyped shape ON
-- PURPOSE, because the runner's own tests read it (TestRunner `(ex)`, and
-- TestLspRobustness's group-D registration property, which needs a
-- report-local `data Heading`):
--
--     bin/ermine-serve --root core/src/test/resources/doc --preload SalesRaw --port 8080
--     curl -s localhost:8080/report/SalesRaw -H 'Content-Type: application/json' \
--          -d '{"params": {"fromDay": "2026-01-05", "toDay": "2026-02-20",
--                          "onlyRegion": "north", "orderBy": "ByAmount"},
--              "data": {"default": "inline", "threshold": 50}}'
--
-- It is NOT a client fixture.  Its widget props are bare runtime values --
-- `rawWidget` over a report-local record, a bare string and bare relations --
-- which the client refuses: its widget vocabulary is the typed one, validated
-- by zod generated from Layout.Widgets.* (client/README.md "Adding a widget").
-- Every table here is an error box in the preview panel, by design.
--
-- What it shows (the runner, not the client):
--   * a params `data` with NAMED fields -- a date range, a `Maybe` filter
--     and an enum -- which is what the request's "params" object is decoded
--     into (json/Decode.scala).  The params type is Sales.e's, byte for byte;
--   * a relation filtered by those parameters, delivered the way the request
--     asked (inline unless "data.default" says otherwise, and deferred
--     anyway once it is over "data.threshold" rows);
--   * one BARE relation (the regions) and one `Deferred` relation (the line
--     items), which goes out as columns plus a token whatever the request
--     asks for, to be fetched from GET /data/<token>;
--   * a report-local record (`Heading`) encoded by the generic walker;
--   * a date range that matches NO sale still renders: `byDay` is built with
--     `relationWithHeader`, so an empty table keeps its four columns
--     (tracker/JSON-WIDGET-PLAYGROUND.md, WP-29).

import Bool
import Date
import Eq
import Json
import Layout.Doc
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

-- What the "heading" widget is given.  A data type with ONE constructor
-- carries no "tag" key, so its props are just the four fields.
data Heading = Heading
  { title      : String
  , sortColumn : String
  , matched    : Int
  , total      : Double
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
      -- bare: the request's "data.default" decides how it is delivered
      regions = relation (map_List (r -> { region = r }) (nub (map_List sRegion sales)))
      -- always deferred, whatever the request asks for
      items = Deferred (relation (map_List (s -> { item = sItem s, amount = sAmount s,
                                              units = sUnits s }) sales))
  in vflow
       [ rawWidget "heading" (Heading "Sales" (columnOf (orderBy q)) (length picked) total)
       , grid [ [ rawWidget "table" byDay, rawWidget "table" regions ]
              , [ rawWidget "table" items, rawWidget "text" "line items on demand" ] ]
       ]
