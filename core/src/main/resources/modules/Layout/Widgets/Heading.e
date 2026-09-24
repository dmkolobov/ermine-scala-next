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

-- | A record with one constructor carries no "tag" key: the props are the four
-- fields, in this order.
data HeadingProps = HeadingProps { title      : String
                                 , sortColumn : String   -- a relation column name, shown as text
                                 , matched    : Int
                                 , total      : Double }

-- | The registry name, tied to the props type.
headingName : WidgetName HeadingProps
headingName = WidgetName "heading"

heading : HeadingProps -> Node
heading p = widget headingName p
