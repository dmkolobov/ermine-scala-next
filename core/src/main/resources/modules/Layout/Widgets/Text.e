module Layout.Widgets.Text where

-- A paragraph of PLAIN text, registry name "text".  Rendered by
-- client/src/widgets/text.ts with textContent only (nothing is parsed as HTML
-- or markdown -- `Layout.Report.text`, the legacy Report builder, means
-- markdown; this does not), and validated by the zod GENERATED from
-- `TextProps` below (client/scripts/generate.sh).
--
-- Added by Q25 (tracker/JSON-WIDGET-PLAYGROUND.md section 13, 2026-09-23).  The
-- props are a record, `{"body": ".."}`, never a bare string: the client's
-- widget vocabulary is the typed one, and a bare runtime value is not in it.
-- The constructor is `plainText`, not `text`, for the same reason.
--
-- Re-exported from Layout.Widgets: `body`, `plainText`, `textName` and
-- `TextProps` collide with nothing there (measured by the Q25 review).

import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}

data TextProps = TextProps { body : String }

-- | The registry name, tied to the props type.
textName : WidgetName TextProps
textName = WidgetName "text"

plainText : TextProps -> Node
plainText p = widget textName p
