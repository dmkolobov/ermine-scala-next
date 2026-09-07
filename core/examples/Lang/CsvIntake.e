module Lang.CsvIntake where

{- A CSV READ INTO A RELATION, WITH EVERY ERROR REPORTED AT ONCE — `Validation`, not
   `Either`; and a USER-DEFINED BRACKET LITERAL for the reader that does it.

   Fact: goodIntake (6 fields: partyId, partyName, regionCode, creditLimit,
         riskGrade, onboardedOn), read from CSV text through a typed row reader.

   WHY THIS FILE EXISTS. `IO/CSV.e` is seventeen lines and stops one step short of the
   interesting part:

       readCSVFile : FilePath -> IO (List (List String))
       parseCSV    : String   -> List (List String)

   -- untyped cells. Nothing in the stdlib turns `List (List String)` into `[..r]`, and
   that step is where a reporting language earns its keep: it is the only place a column
   NAME meets a column TYPE. `Lang/Helpers.e`'s `RowReader r` is that step, and
   `consRow`'s `t <- (r, s)` is what makes a duplicated column a compile error rather
   than a runtime surprise.

   `parseCSV` is PURE, so this module runs the real intake path over embedded text. The
   `IO` at the front is a different story, and it is a stdlib BUG rather than a missing
   file: `core/examples/Lang/customers.csv` sits beside this module and
   `readCSVFile` really does read it -- and then the value comes back bombed, because
   `File.e`'s

       withSource# f s = let res = f s in let x = close# s in traceShow res

   TRACES ITS OWN RESULT, and `traceShow` writes through `java.lang.System.console()`,
   which is `null` under a pipe or a redirect. So every `File`/`IO.CSV` read DUMPS the
   whole file to stdout and then hands back a bomb. Measured, on this module, under a
   pipe:

       >> diskLines
       101,Aldgate Joinery,EMEA,2500000.00,A1,2009-04-17
       102,Brackenridge Mills,AMER,750000.00,B2,2011-01-08
       103,Cheviot Castings,APAC,1200000.00,A2,2010-11-30
       res0 : List (List String) =
         <error: error invoking static foreign function: writeron object of type null;
                 expected an object of type class java.io.Console>

   The READ succeeded -- those three lines are the file. What failed is `readFile`'s own
   debug trace, and it takes the value with it, by the mechanism of the module header's
   §0b: the exception becomes a `Bottom` value rather than being thrown, so nothing can
   catch it. One line of `File.e` (drop the `traceShow`, or route it to stderr) is the
   whole fix. (Found by E5's reviewer, L-10.)

   TWO KINDS OF FAILURE, and why the difference matters to a reader:

     * `Either` SHORT-CIRCUITS. `eitherAp` returns the first `Left` and discards the
       second. Handing a user the first of eleven bad cells is a bad report.
     * `accumAp` ACCUMULATES. It differs from `eitherAp` in exactly one clause and is
       not a monad — `bind` cannot accumulate, because the second computation does not
       exist until the first has succeeded. That is the whole content of the word
       "applicative validation", and it is three lines in `Helpers.e`.

   A USER-DEFINED BRACKET LITERAL. `[a, b, c]_M` desugars to
   `cons_Bracket_M a (cons_Bracket_M b (cons_Bracket_M c empty_Bracket_M))`, so ANY
   module that binds the names `empty_Bracket` and `cons_Bracket` gets list syntax for
   its own type. `Validation.e` does it (`[...]_Vd`), `Relation.Row.e` does it, and this
   module does it for `RowReader`. Two consequences a reader must know:

     1. `Prelude` already exports `List`'s pair, so a module that defines its own must
        say `import Prelude hiding {empty_Bracket; cons_Bracket}` or the compiler
        refuses with `term definition would shadow global definition (empty_Bracket)`.
     2. Once it does, EVERY unsuffixed `[...]` in that module is the new literal. Plain
        lists here are written `[...]_L`. That is why the hooks are bound in this module
        and not in `Helpers.e`, which every other module in the group imports.

   SHAPES EXERCISED
     * `consRow`'s `t <- (r, s)` chained six deep under `RowReader`.
     * `readRowsAs` : the row variable travels under `Either (List Err)` and comes out
       as `Relation (|..r|)` — `traverse` over rows with an accumulating applicative.
     * `Relation.relationWithHeader`, so an EMPTY parse still has a typed relation.
     * `Validation.Validator`, `lookupInt`, `lookupDouble`, `within` and `>=>` on the
       report's own parameters, next to the row reader, so the two can be compared.
     * `IO.CSV.parseCSV` for real; `readCSVFile`/`readURL` typed but unrun.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/CsvIntake.e
   >> goodIntake      -- Right <relation …>
   >> badIntake       -- Left [(field, message), … ] : FIVE messages
   >> intakeErrors
   >> shortCircuited  -- the same input under `eitherAp`: TWO, from the first bad line
                      --   only, and nothing at all about the two lines after it
   >> intakeReport
   >> diskLines      -- the real file, and the `traceShow` bomb: see the header
-}

import Prelude hiding {empty_Bracket; cons_Bracket}
import Syntax.List
import Control.Monad as M
import Control.Traversable as T
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import List as L
import String as S
import Date as D
import Validation as Vd
import IO.CSV as CSV
import File as Fl
import IO.Unsafe as IOU
import Lang.Helpers

field partyId     : Int
field partyName   : String
field regionCode  : String
field creditLimit : Double
field riskGrade   : String
field onboardedOn : Date

-- ---------------------------------------------------------------------------
-- 1. The bracket literal for `RowReader`.

empty_Bracket = nilRow
cons_Bracket  = consRow

-- ---------------------------------------------------------------------------
-- 2. The reader. Six columns, six partitions, one row.
--
-- Each entry is (field, column index, cell reader). The index is explicit because a
-- CSV's column ORDER is not its header: this reader works on a file whose columns are
-- in the order below and nowhere says so twice.

partyReader : RowReader (|partyId, partyName, regionCode, creditLimit, riskGrade,
                          onboardedOn|)
partyReader =
  [ (partyId,     0, cellInt)
  , (partyName,   1, cellString)
  , (regionCode,  2, cellString)
  , (creditLimit, 3, cellDouble)
  , (riskGrade,   4, cellGrade)
  , (onboardedOn, 5, cellDate)
  ]

partyHeader : Row (|partyId, partyName, regionCode, creditLimit, riskGrade, onboardedOn|)
partyHeader = {partyId, partyName, regionCode, creditLimit, riskGrade, onboardedOn}

-- | A cell reader is `String -> Maybe a`; two of them are worth writing by hand.
cellDate : String -> Maybe Date
-- A bracket literal is NOT a pattern: `[Just y, Just m, Just d]_L` on the left of a
-- `->` is a parse error, because `[...]_M` desugars to `cons_Bracket_M` applications
-- and those are terms. Cons patterns are the way.
cellDate s = case map parseIntTotal (split_S dashChar (trim_S s)) of
  Just y :: Just m :: Just d :: Nil -> Just (yyyymmdd_D y m d)
  _                                 -> Nothing

cellGrade : String -> Maybe String
cellGrade s = if (contains_L (trim_S s) gradeScale) (Just (trim_S s)) Nothing

gradeScale : List String
gradeScale = ["A1", "A2", "B1", "B2", "C1", "C2", "D"]_L

-- ---------------------------------------------------------------------------
-- 3. The data, as it arrives: text.

goodCsv : String
goodCsv = joinLines [
  "101,Aldgate Joinery,EMEA,2500000.00,A1,2009-04-17",
  "102,Brackenridge Mills,AMER,750000.00,B2,2011-01-08",
  "103,Cheviot Castings,APAC,1200000.00,A2,2010-11-30",
  "104,Dunbar Coatings,EMEA,4000000.00,A1,2008-06-02",
  "105,Eastcheap Timber,AMER,325000.00,B1,2012-02-14"
  ]_L

-- | The same file with five things wrong, spread over three lines: a non-numeric id,
--   a credit limit with a currency symbol in it, a grade that is not on the scale, a
--   date with a month that is not a number, and a missing sixth cell.
badCsv : String
badCsv = joinLines [
  "101,Aldgate Joinery,EMEA,2500000.00,A1,2009-04-17",
  "1O2,Brackenridge Mills,AMER,$750000.00,B2,2011-01-08",
  "103,Cheviot Castings,APAC,1200000.00,A+,2010-XI-30",
  "104,Dunbar Coatings,EMEA,4000000.00,A1"
  ]_L

joinLines : List String -> String
joinLines = foldMapL (joinedMonoid "\n") id

-- ---------------------------------------------------------------------------
-- 4. The intake.

goodIntake : Either (List Err) [partyId, partyName, regionCode, creditLimit,
                                    riskGrade, onboardedOn]
goodIntake = readRowsAs partyReader partyHeader (parseCSV_CSV goodCsv)

badIntake : Either (List Err) [partyId, partyName, regionCode, creditLimit,
                                   riskGrade, onboardedOn]
badIntake = readRowsAs partyReader partyHeader (parseCSV_CSV badCsv)

intakeErrors : List Err
intakeErrors = either id (_ -> Nil) badIntake

-- | The SAME reader run under `Either`'s shipped applicative, which stops at the first
--   failing LINE. Two messages instead of five, and the reader is told nothing about
--   lines 3 and 4: this is the comparison the module is for. (Both messages come from
--   line 2 because `consRow` accumulates WITHIN a row whichever applicative is used
--   over the rows; it is the traversal that short-circuits, not the reader.)
shortCircuited : Either (List Err) (List {partyId, partyName, regionCode, creditLimit,
                                          riskGrade, onboardedOn})
shortCircuited = traverse_T listTraversable_L eitherAp (runRowReader partyReader)
                            (parseCSV_CSV badCsv)

-- ---------------------------------------------------------------------------
-- 5. What the report's own PARAMETERS look like, for comparison.
--
-- `Validation.FormValidator r` is `Map String String -> Either (List Err) {..r}` — the
-- same shape as `RowReader r` with a `Map` instead of a `List` — and it comes with its
-- own bracket literal, `[...]_Vd`. The difference is that a form validator is keyed by
-- FIELD NAME and a row reader by POSITION, which is exactly the difference between a
-- submitted form and a CSV.

field minLimit : Double
field regionWanted : String

intakeParams : FormValidator_Vd (|minLimit, regionWanted|)
intakeParams =
  [ (minLimit,     lookupDouble_Vd)
  -- NOTE the parentheses around the list: a bracket literal with a module suffix
  -- cannot be a non-final argument (`const []_L "x"` does not parse either).
  , (regionWanted, within_Vd (["EMEA", "AMER", "APAC"]_L) (==) lookupString_Vd)
  ]_Vd

-- ---------------------------------------------------------------------------
-- 6. The report drawn from the good intake.

acceptedRel : [partyId, partyName, regionCode, creditLimit, riskGrade, onboardedOn]
acceptedRel = either (_ -> relationWithHeader partyHeader Nil) id goodIntake

largeCustomers : [partyId, partyName, regionCode, creditLimit, riskGrade, onboardedOn]
largeCustomers = acceptedRel |> filter_Pred (col_Op creditLimit >=_Pred prim_Op 1000000.0)

byRegion : Mem (|regionCode, creditLimit|)
byRegion = acceptedRel |> groupBy {regionCode} (sumBy creditLimit)

intakeReport : Report f z
intakeReport = vflow [
    text "## Customer intake",
    tabular Nothing acceptedRel,
    text "### Credit limits at or above 1,000,000",
    tabular Nothing (largeCustomers # {partyName, regionCode, creditLimit}),
    text "### Total limit by region",
    tabular Nothing byRegion
  ]_L

-- ---------------------------------------------------------------------------
-- 7. The IO front end: real, and blocked by a stdlib bug.
--
-- The point is first the TYPE -- the whole intake is `map (readRowsAs …) . readCSVFile`,
-- so the row reader composes with `IO` through `Syntax.IO`'s functor and nothing else
-- changes -- and then the bug in the module header: `File.readFile` traces its own
-- result through `System.console()`, so `intakeFromDisk` returns a bomb under a pipe.
-- The file it reads is real and is `core/examples/Lang/customers.csv`, three rows
-- of the same shape as `goodCsv`; paths are relative to the JVM's working directory,
-- which is the repository root under `bin/ermine`.

intakeFrom : FilePath_Fl -> IO (Either (List Err) [partyId, partyName, regionCode,
                                                       creditLimit, riskGrade,
                                                       onboardedOn])
intakeFrom path = map_IO (readRowsAs partyReader partyHeader) (readCSVFile_CSV path)

intakeFromUrl : URL_Fl -> IO (Either (List Err) [partyId, partyName, regionCode,
                                                     creditLimit, riskGrade,
                                                     onboardedOn])
intakeFromUrl url = map_IO (readRowsAs partyReader partyHeader) (readCSVURL_CSV url)

rawLinesOf : FilePath_Fl -> IO (List String)
rawLinesOf = fileLines_Fl

-- | The real read, over the real file. `<error: … java.io.Console …>` under a pipe.
intakeFromDisk : Either (List Err) [partyId, partyName, regionCode, creditLimit,
                                    riskGrade, onboardedOn]
intakeFromDisk = unsafePerformIO_IOU (intakeFrom "core/examples/Lang/customers.csv")

-- | The same file's raw lines, to show the bomb is in the READ and not in the reader.
diskLines : List (List String)
diskLines = unsafePerformIO_IOU (readCSVFile_CSV "core/examples/Lang/customers.csv")
