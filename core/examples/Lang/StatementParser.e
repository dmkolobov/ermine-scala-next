module Lang.StatementParser where

{- A BANK-STATEMENT TEXT FORMAT PARSED INTO A RELATION, with parser combinators
   written in Ermine, and a report drawn from the result.

   Fact: statementRel (7 fields: postedOn, valueRef, movementKind, narrative,
         movementAmt, runningBal, sourceLine) -- built by PARSING a String, not by
         `relation [...]`.

   WHY THIS FILE EXISTS. Real data does not arrive as a record literal. It arrives as
   text, and the first thing a reporting language must do is turn text into rows. Ermine
   ships a module called `Parse`, and a reader who finds it in the import census
   reasonably expects parser combinators. It is not that:

       Parse.e = six `java.lang.*` number parsers (parseInt, parseByte, parseShort,
                 parseLong, parseFloat, parseDouble) plus `parseBool`, each returning
                 `Maybe`, and one private helper that turns a NumberFormatException
                 into `Nothing`.

   So `Lang/Helpers.e` defines the library instead: `Parser a`, its `Monad`, `Ap` and
   `Alt` dictionaries, `pSat`/`pLit`/`pMany`/`pSome`/`pSepBy`/`pToken`, and `pRecord` --
   which builds a RECORD field by field inside the parser monad and therefore carries a
   row partition under `Parser`.

   SHAPES EXERCISED
     * `pRecord`'s `t <- (r, s)` chained SIX deep, so the solver carries a row variable
       under `Parser` six partitions at a time. This is the shape the census has not
       measured before (G3).
     * `Control.Alt` as ordered choice: `movementKindP` is `firstOf parserAlt` over a
       three-element keyword table.
     * `Control.Monad` used as a DICTIONARY: every `bind_M parserMonad` here is what a
       `do` block would desugar to; `narrativeP` shows the `do` spelling side by side.
     * `Data.Free`-free interpretation: the parser is an ordinary recursive value, and
       `pMany` is where non-termination lives -- see the LEFT RECURSION note below.
     * `Relation.relationWithHeader` to build a relation whose header is known even when
       the parse yields no rows.

   LEFT RECURSION IS NOT A TYPE ERROR. `pMany p` where `p` can succeed WITHOUT consuming
   input loops forever, and so does `expr = bind expr (...)`. Ermine's type system says
   nothing about it: `Parser a` is a function type, and a diverging function is
   well-typed. The `shouldfail/` directory therefore has no left-recursion negative --
   there is nothing to reject. What CAN be rejected is a parser whose record disagrees
   with the row it is claimed to build, and that is `lang01_parser_row_mismatch.e`.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/StatementParser.e
   >> statementRel          -- the parsed relation's header
   >> parsedRows            -- the records
   >> badLineResult         -- Nothing: the parse that fails
   >> bombedAmount          -- Just (<error: For input string: "abc">, "rest") -- why
   >> goodAmount            -- Nothing                    -- amountP uses the total one
   >> statementReport
-}

import Prelude
import Syntax.List
import Syntax.Do
import Control.Monad as M
import Control.Alt as Alt
import Layout
import Layout.Legend as Lg
import Relation.Op as Op
import Relation.Predicate as Pred
import List as L
import String as S
import Date as D
import Lang.Helpers

field postedOn     : Date
field valueRef     : String
field movementKind : String
field narrative    : String
field movementAmt  : Double
field runningBal   : Double
field sourceLine   : String

-- ---------------------------------------------------------------------------
-- 1. The text. Seven movements on one account, one per line, pipe-separated.

statementText : String
statementText = mconcatLines [
  "2011-03-01|REF00181|DEPOSIT|Opening balance brought forward|12500.00|12500.00",
  "2011-03-04|REF00182|DEPOSIT|Payroll March|4820.00|17320.00",
  "2011-03-07|REF00183|WITHDRAWAL|Rent 1104 Marlborough|-2150.00|15170.00",
  "2011-03-11|REF00184|WITHDRAWAL|Card settlement 8821|-318.44|14851.56",
  "2011-03-18|REF00185|TRANSFER|To savings 4471|-5000.00|9851.56",
  "2011-03-24|REF00186|DEPOSIT|Refund from vendor|212.90|10064.46",
  "2011-03-29|REF00187|WITHDRAWAL|Standing order utilities|-96.20|9968.26"
  ]_L

mconcatLines : List String -> String
mconcatLines = foldMapL (joinedMonoid "\n") id

-- ---------------------------------------------------------------------------
-- 2. The cell parsers.

-- | Everything up to the next `|`, with the `|` consumed if present.
cellP : Parser String
cellP = bind_M parserMonad (pUpTo pipeChar)
                           (s -> fmap parserFunctor (_ -> s) (pMany (pLit "|")))

-- | `yyyy-mm-dd` as three integers and two dashes. `Date.yyyymmdd` is a `foreign`
--   constructor over `com.clarifi.reporting.util.YMDTriple`.
dateP : Parser Date
dateP = bind_M parserMonad pInt (y ->
        bind_M parserMonad (pLit "-") (_ ->
        bind_M parserMonad pInt (m ->
        bind_M parserMonad (pLit "-") (_ ->
        bind_M parserMonad pInt (d ->
        bind_M parserMonad (pMany (pLit "|")) (_ ->
          unit_M parserMonad (yyyymmdd_D y m d)))))))

-- | The same thing in `do` notation. `Syntax.Do` desugars to `Monad f -> f a`, so the
--   block is APPLIED to the dictionary -- that is the `' parserMonad` at the end.
--   `liftDo` is what lifts an ordinary `Parser a` into the block.
dateDoP : Parser Date
dateDoP = (do y <- liftDo pInt
              _ <- liftDo (pLit "-")
              m <- liftDo pInt
              _ <- liftDo (pLit "-")
              d <- liftDo pInt
              _ <- liftDo (pMany (pLit "|"))
              unit (yyyymmdd_D y m d)) ' parserMonad

-- | A signed decimal in a cell, through `Helpers.parseDoubleTotal`.
--
--   THE TOTAL PARSER IS NOT OPTIONAL HERE. `Parse.parseDouble` returns `Just <bomb>`
--   rather than `Nothing` on a bad string (see the module header and
--   `Lang/ForeignJdk.e`), so an `amountP` written against it would make `parseLine`
--   SUCCEED on a malformed amount and put the exception in the record, where it detonates
--   at the point of use with no field name attached. `bombedAmount` below is that
--   mistake, kept as a demonstration and never used to build a row.
amountP : Parser Double
amountP = bind_M parserMonad cellP (s -> case parseDoubleTotal (trim_S s) of
  Just d  -> unit_M parserMonad d
  Nothing -> empty_Alt parserAlt)

-- | What the same parser does if it calls `Parse.parseDouble` directly: the parse
--   SUCCEEDS and the value is a bomb. Evaluate it and the REPL prints the exception
--   inside the `Just`.
bombedAmountP : Parser Double
bombedAmountP = bind_M parserMonad cellP (s -> case parseDouble (trim_S s) of
  Just d  -> unit_M parserMonad d
  Nothing -> empty_Alt parserAlt)

bombedAmount : Maybe (Double, String)
bombedAmount = runParser bombedAmountP "abc|rest"

goodAmount : Maybe (Double, String)
goodAmount = runParser amountP "abc|rest"

-- | Ordered choice over a keyword table: `Control.Alt` doing what it is for.
movementKindP : Parser String
movementKindP = bind_M parserMonad
  (firstOf parserAlt [pLit "DEPOSIT", pLit "WITHDRAWAL", pLit "TRANSFER"]_L)
  (k -> fmap parserFunctor (_ -> k) (pMany (pLit "|")))

-- ---------------------------------------------------------------------------
-- 3. The record parser: six `pRecord`s, six row partitions, one row.

lineP : Parser {postedOn, valueRef, movementKind, narrative, movementAmt, runningBal}
-- NOTE the parentheses. `'` and `$` are both `infixl 0`, so `f ' g ' x` is
-- `(f ' g) ' x`; a RIGHT-nested chain like this one cannot be written with either.
lineP =
  pRecord postedOn     dateP
    (pRecord valueRef     cellP
      (pRecord movementKind movementKindP
        (pRecord narrative    cellP
          (pRecord movementAmt  amountP
            (pRecord runningBal   amountP pNil)))))

-- | One line to one record, keeping the source line for the audit column.
parseLine : String -> Maybe {postedOn, valueRef, movementKind, narrative, movementAmt,
                             runningBal, sourceLine}
parseLine ln = case parseAll lineP ln of
  Just t  -> Just (cons sourceLine ln t)
  Nothing -> Nothing

parsedRows : List {postedOn, valueRef, movementKind, narrative, movementAmt,
                   runningBal, sourceLine}
parsedRows = catMaybes (map parseLine (lines_S statementText))

statementRel : Relation (|postedOn, valueRef, movementKind, narrative, movementAmt,
                          runningBal, sourceLine|)
statementRel = relation parsedRows

-- | The parse that does NOT succeed: `TRANSFERRED` is not in the keyword table, and
--   `parseAll` insists the whole line is consumed.
badLineResult : Maybe {postedOn, valueRef, movementKind, narrative, movementAmt,
                       runningBal, sourceLine}
badLineResult = parseLine "2011-03-30|REF00188|TRANSFERRED|Nope|1.00|2.00"

-- | The parsers agree: hand-written binds and `do` notation are the same value.
dateAgreement : Bool
dateAgreement = case (runParser dateP "2011-03-04|x", runParser dateDoP "2011-03-04|x") of
  (Just (a, ra), Just (b, rb)) -> before_D a b == before_D b a && ra == rb
  _                            -> False

-- ---------------------------------------------------------------------------
-- 4. A report over the parsed relation.

debits : Relation (|postedOn, valueRef, movementKind, narrative, movementAmt,
                    runningBal, sourceLine|)
debits = statementRel |> filter_Pred (col_Op movementAmt <_Pred prim_Op 0.0)

byKind : Mem (|movementKind, movementAmt|)
byKind = statementRel |> groupBy {movementKind} (sumBy movementAmt)

statementReport : Report f z
statementReport = vflow [
    text "## Account 4471 - March 2011",
    tabular Nothing (statementRel |> except {sourceLine}),
    text "### Debits only",
    tabular Nothing (debits # {postedOn, narrative, movementAmt}),
    text "### By movement kind",
    tabular Nothing byKind
  ]_L
