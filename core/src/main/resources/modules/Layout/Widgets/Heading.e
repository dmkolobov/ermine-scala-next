module Layout.Widgets.Heading where

-- The report heading, registry name "heading": a title and a one-line summary
-- of what the report matched -- how many rows, their total, and the column the
-- tables are sorted by.  Rendered by client/src/widgets/heading.ts as plain DOM
-- (no legacy renderer), and validated there by the zod GENERATED from
-- `HeadingProps` below (client/scripts/generate.sh), like every other widget.
--
-- Added by Q25 (tracker/JSON-WIDGET-PLAYGROUND.md section 13, 2026-09-23): the
-- names are the ones core/src/test/resources/doc/Sales.e has always put on the
-- wire (`title`, `sortColumn`, `matched`, `total`), so the typed widget is the
-- same JSON the report-local record produced.
--
-- NOT RE-EXPORTED FROM Layout.Widgets: `title` is also Scorecard's field,
-- `sortColumn` Table's `ColumnSort` field and `total` Headline's, and field
-- selectors are module-global.  Through the umbrella the names would not
-- clash -- they would SILENTLY resolve to HeadingProps (measured by the Q25
-- review), breaking Scorecard/Table code.  Import this module by name.

import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}
import Layout.Widgets.Table using {type Column; columnName}

-- | A record with one constructor carries no "tag" key: the props are the four
-- fields, in this order.
data HeadingProps = HeadingProps { title      : String
                                 , sortColumn : String   -- a column name, shown as text (typed: headingSort)
                                 , matched    : Int
                                 , total      : Double }

-- | The registry name, tied to the props type.
headingName : WidgetName HeadingProps
headingName = WidgetName "heading"

heading : HeadingProps -> Node
heading p = widget headingName p

-- * The typed authoring API (WP-37, D1/D4)
--
-- `HeadingProps` is the WIRE (D3).  A report builds it with `headingOf` from a
-- `HeadingSource`, whose sort column is a `Layout.Widgets.Table.Column r`, not a
-- String, and whose `headingOver` names the relation that column is checked
-- against (it is not sent: the heading carries no rows).
--
-- A `Column r`, not a `Field h a` slot: the column a report sorts by is
-- usually chosen at RUN TIME from a parameter, among fields of DIFFERENT value
-- types (doc/Sales.e: day : Date, amount : Double, units : Int), which one
-- `Field h a` cannot hold and a `Column r` can -- each branch's `Has r h`
-- merges into one constraint on `r`.  Only the column's name reaches the wire.

-- | What `headingOf` lowers.  Server-side only.
data HeadingSource rel r = HeadingSource { headingSourceTitle : String
                                         , headingSort : Column r
                                         , headingMatched : Int
                                         , headingTotal : Double
                                         , headingOver : rel r }

headingOf : HeadingSource rel r -> HeadingProps
headingOf s = HeadingProps (headingSourceTitle s) (columnName (headingSort s))
                           (headingMatched s) (headingTotal s)
