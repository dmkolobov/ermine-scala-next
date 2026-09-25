module Layout.Trace.Phase where

-- One entry of a render trace's `phases` array (tracker/db/OBSERVABILITY.md
-- section 4; lsp/TraceJson.scala builds it).  The field NAMES are the JSON
-- keys, which is how json/Decode.scala reads a record-style constructor; a
-- `Maybe` field is a key the server may leave out.  One module per record
-- type because a selector is module-global and `ms` is a key of three of
-- them (docs/JSON-GUIDE.md "The collisions you will hit").  Read it through
-- Layout.Trace's helpers, which pattern-match positionally.

data TracePhase = TracePhase { name       : String
                             , ms         : Double
                             , attributed : Maybe Bool
                             , cached     : Maybe Bool }
