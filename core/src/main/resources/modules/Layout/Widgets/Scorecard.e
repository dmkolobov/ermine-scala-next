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
import Field using fieldName

data ScorecardProps r = ScorecardProps { title : String
                                       , cardLabel : String   -- a column name (typed: scoreLabel)
                                       , cardValue : String   -- a column name (typed: scoreValue)
                                       , cardDelta : Maybe String
                                       , cardFormat : CellFormat
                                       , cards : Inline r }

-- | The registry name, tied to the props type.
scorecardName : WidgetName (ScorecardProps r)
scorecardName = WidgetName "scorecard"

scorecard : ScorecardProps r -> Node
scorecard p = widget scorecardName p

-- * The typed authoring API (WP-37, D4)
--
-- `ScorecardProps` is the WIRE (column names, D3).  A report builds it with
-- `scorecardOf` from a `ScorecardSource`, whose column slots are FIELDS.

-- | What `scorecardOf` lowers.  Server-side only.  `scoreDelta = Nothing`
-- leaves its row variable free, which the partition allows.
data ScorecardSource h1 h2 h3 a b c r =
  ScorecardSource { scorecardSourceTitle : String
                  , scoreLabel : Field h1 a
                  , scoreValue : Field h2 b
                  , scoreDelta : Maybe (Field h3 c)
                  , scoreFormat : CellFormat
                  , scoreCards : Inline r }

-- | The wire props: each field becomes its name.  Label, value and delta are
-- DISTINCT columns of the relation, or a type error.
scorecardOf : (r <- (h1, h2, h3, t)) => ScorecardSource h1 h2 h3 a b c r -> ScorecardProps r
scorecardOf s =
  ScorecardProps (scorecardSourceTitle s) (fieldName (scoreLabel s)) (fieldName (scoreValue s))
                 (deltaName (scoreDelta s)) (scoreFormat s) (scoreCards s)

-- | No delta column.
simpleScorecard : (r <- (h1, h2, t)) => String -> Field h1 a -> Field h2 b -> CellFormat -> Inline r
               -> ScorecardProps r
simpleScorecard t lbl val fmt rs = scorecardOf (ScorecardSource t lbl val Nothing fmt rs)

private
  deltaName : Maybe (Field h a) -> Maybe String
  deltaName Nothing  = Nothing
  deltaName (Just f) = Just (fieldName f)
