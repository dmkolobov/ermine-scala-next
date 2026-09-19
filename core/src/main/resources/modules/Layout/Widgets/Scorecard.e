module Layout.Widgets.Scorecard where

-- The NEW widget, registry name "scorecard": a row of cards, one per relation row,
-- each showing a label, a formatted value and an optional delta whose sign colours
-- it.  There is no legacy renderer behind it -- client/src/widgets/scorecard.ts is
-- plain DOM -- so it is the end-to-end proof that a widget is one `data` here, one
-- TypeScript component, and one registry line.
--
-- `cards` is `Inline r`, not a bare relation: a scorecard with no numbers is
-- nothing, so the rows always travel in the response and the exported schema is the
-- inline arm alone (no `kind: "deferred"` to handle in the component).

import Json using type Inline
import Layout.Widgets.Format using type CellFormat
import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}

data ScorecardProps r = ScorecardProps { title : String
                                       , cardLabel : String   -- relation column
                                       , cardValue : String   -- relation column
                                       , cardDelta : Maybe String
                                       , cardFormat : CellFormat
                                       , cards : Inline r }

-- | The registry name, tied to the props type.
scorecardName : WidgetName (ScorecardProps r)
scorecardName = WidgetName "scorecard"

scorecard : ScorecardProps r -> Node
scorecard p = widget scorecardName p

-- | No delta column.
simpleScorecard : String -> String -> String -> CellFormat -> Inline r -> ScorecardProps r
simpleScorecard t lbl val fmt rs = ScorecardProps t lbl val Nothing fmt rs
