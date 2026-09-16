module Layout.Widgets.Format where

-- CellFormat: how one cell of a widget is rendered, as a PURE ERMINE mirror of the
-- object form of HTMLWriter.jsFormat (ermine-writers,
-- writers/html/src/main/scala/com/clarifi/reporting/writers/HTMLWriter.scala
-- ~269-347), which is the per-cell `format` the legacy tabular renderer already
-- receives.  This is the replacement, on the JSON path, of the foreign
-- Layout.Format (tracker/JSON-API-DESIGN.md section 3.1a): Layout.Format is a Scala
-- ADT with no Ermine eliminator, so the walker cannot encode it.  A CONVERTER from
-- Layout.Format to CellFormat is out of scope for Stage 3 (it needs a Scala-side
-- fold, not Ermine code).
--
-- The generic walker spells the discriminator "tag" and uses the CONSTRUCTOR NAME,
-- so the mapping to the legacy `"type"` key is exactly lower-casing the first
-- letter -- Default -> "default", IntegralRound -> "integralRound".  Three
-- departures from the legacy object, all forced:
--
--   * Conditional's "then"/"else" are Ermine keywords: `whenTrue`/`whenFalse`.
--   * `aliases` is a list of pairs, not an object: the walker has no map encoding.
--   * Currency carries `places`; the legacy server reads it from
--     CurrencyObj.settings(symbol, Locale.US), a table the client does not have.
--
-- client/src/format.ts is a total port of formatDisplay over this type, and
-- client/src/legacy.ts holds the one function that maps a CellFormat back to the
-- legacy object and tuple forms.

-- | A colour as the legacy `bg`/`fg` triples; components in [0,255].
data RGB = RGB { red : Int, green : Int, blue : Int }

-- | What a Conditional format compares the cell's first value against.
-- Positional on purpose: {"tag":"TNum","args":[1.0]} is mutation-detectable,
-- where the stdlib Json type exports as `{}` -- any document at all.
data Threshold = TNum Double | TStr String | TBool Bool

-- | Layout.Format's Condition, as the legacy jsCondition object plus a tag:
-- {"tag":"Gt","gt":{"tag":"TNum","args":[3.0]}}.
data CellCondition = Gt { gt : Threshold }
                   | Lt { lt : Threshold }
                   | Eq { eq : Threshold }
                   | Gte { gte : Threshold }
                   | Lte { lte : Threshold }
                   | And { and : (CellCondition, CellCondition) }

-- | All fifteen cases of the legacy Format.
data CellFormat =
    Default
  | Verbatim
  | Markdown { base : CellFormat }
  | Constant { value : String }
  | Percentage { color : Bool, negParens : Bool, places : Int, pad : Bool }
  | Currency { color : Bool, negParens : Bool, symbol : String, places : Int }
  | Pr1 { base : CellFormat }
  | Pr2 { base : CellFormat }
  | DateRange
  | Round { color : Bool, negParens : Bool, places : Int }
  | IntegralRound { color : Bool, negParens : Bool, places : Int }
  | Truncate { places : Int }
  | Conditional { condition : CellCondition, whenTrue : CellFormat, whenFalse : CellFormat }
  | Color { bg : RGB, fg : RGB, base : CellFormat }
  | Alias { aliases : List (String, String) }

-- the spellings a report reaches for; the constructors stay available

plain : CellFormat
plain = Default

percent : Int -> CellFormat
percent n = Percentage False False n False

dollars : Int -> CellFormat
dollars n = Currency False False "$" n

roundTo : Int -> CellFormat
roundTo n = Round False False n

truncateTo : Int -> CellFormat
truncateTo n = Truncate n

constantly : String -> CellFormat
constantly s = Constant s
