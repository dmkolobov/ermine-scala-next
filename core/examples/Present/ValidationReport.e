module Present.ValidationReport where

{- A DATA-QUALITY REPORT: the report's own PARAMETERS validated by
   `Layout.Validation`, and the FACT TABLE validated by three generic relational
   checks, with every failure drawn as a report of its own.

   Fact: journalEntries (17 fields: entryId, journalRef, postingDate,
         accountCode, accountName, entryKind, regionName, countryCode,
         currencyCode, fxRate, supplierId, debitAmt, creditAmt, netAmt,
         entryStatus, preparerName, quarterName)

   WHY THIS FILE EXISTS. `Layout.Validation` is twelve lines long, has no
   example anywhere, and is the join between two things a reporting language
   must connect: a form submitted as STRINGS, and a report that needs a typed
   RECORD. `Validation.FormValidator r` is exactly

       Map String String -> Either (List (String, String)) {..r}

   -- the row `r` is the record the form produces -- and `Layout.Validation`
   adds the one combinator that turns the failure branch into a `Report`:

       withValidation v f = either showErrors f . validate v

   So a parameterised report is a FUNCTION FROM ITS PARAMETERS whose domain is
   checked at the edge, which is precisely the production shape of
   `tracker/JSON-API-DESIGN.md`: params in, document out. `Present/WriterOutputs.e`
   completes the picture by handing that function to a writer.

   TWO KINDS OF VALIDATION, and why they look different:

     * PARAMETER validation is at the VALUE level. It runs once, on strings, and
       either yields a record or a list of (field, message) pairs. The
       applicative accumulation is real -- `combineErrors` collects EVERY field's
       error, not just the first.
     * DATA validation is at the RELATION level. A check is a filter that keeps
       the OFFENDING rows, so its result is itself a relation and therefore
       itself a report -- which is the only way a data-quality report is any use:
       a reader needs the row, not the count.

   SHAPES EXERCISED
     * `validated` -- `Layout.Validation.withValidation` under an explicit
       row-polymorphic signature; instantiated at a four-field parameter row.
     * `Validation`'s `[...]_Vd` bracket syntax, `lookupInt`, `lookupDouble`,
       `lookupString`, `lookupStringDef`, `within` and the `>=>` composition.
     * `outOfRange`, `missingKey`, `unreconciled` from `Helpers.e`: three
       relational checks whose partitions (`r <- (v, o)`, `r <- (h, o)`,
       `r <- (a, b, c, o)`) carry all seventeen columns through, so the failure
       report shows the row and not just the value.
     * `Relation.Predicate.isNull` on a `Nullable String` key.
     * A failure SUMMARY built by counting each check, joined into one grid.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/ValidationReport.e
     >> qualityReport
     >> badRates
     >> orphanEntries
     >> outOfBalance
     >> goodParameters
     >> badParameters

   There is no `render`; evaluate the report and the relations. See
   `tracker/loopmodel/E4-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Validation as V
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Validation as Vd
import Map as M
import Relation.Op as Op
import Relation.Aggregate as Agg
import Relation.Predicate as Pred
import Syntax.Relation
import Present.Helpers

field entryId : Int
field journalRef, accountCode, accountName, entryKind : String
field regionName, countryCode, currencyCode, entryStatus : String
field preparerName, quarterName : String
field postingDate : Date
field fxRate, debitAmt, creditAmt, netAmt : Double
field supplierId : Nullable String

field checkName : String
field failures : Double

-- ------------------------------------------------------------- the fact table

-- Seventeen columns, fifteen journal entries. Three of them have no
-- supplier, three have an impossible FX rate, and one does not balance.
journalEntries : [ entryId, journalRef, postingDate, accountCode, accountName
                 , entryKind, regionName, countryCode, currencyCode, fxRate
                 , supplierId, debitAmt, creditAmt, netAmt, entryStatus
                 , preparerName, quarterName ]
journalEntries = relation [
  { entryId = 1, journalRef = "JE-20110131-001", postingDate = @2011/1/31, accountCode = "GL-4000",
    accountName = "Revenue", entryKind = "Sales invoice", regionName = "AMER", countryCode = "US",
    currencyCode = "USD", fxRate = 1.0, supplierId = Some "SUP-8801", debitAmt = 128400.0,
    creditAmt = 0.0, netAmt = 128400.0, entryStatus = "Posted", preparerName = "j.reyes",
    quarterName = "Q1" },
  { entryId = 2, journalRef = "JE-20110131-002", postingDate = @2011/1/31, accountCode = "GL-5100",
    accountName = "COGS", entryKind = "Cost of sales", regionName = "AMER", countryCode = "US",
    currencyCode = "USD", fxRate = 1.0, supplierId = Some "SUP-8801", debitAmt = 0.0,
    creditAmt = 70620.0, netAmt = -70620.0, entryStatus = "Posted", preparerName = "j.reyes",
    quarterName = "Q1" },
  { entryId = 3, journalRef = "JE-20110215-004", postingDate = @2011/2/15, accountCode = "GL-4000",
    accountName = "Revenue", entryKind = "Sales invoice", regionName = "EMEA", countryCode = "DE",
    currencyCode = "EUR", fxRate = 1.38, supplierId = Some "SUP-9042", debitAmt = 96200.0,
    creditAmt = 0.0, netAmt = 96200.0, entryStatus = "Posted", preparerName = "h.mueller",
    quarterName = "Q1" },
  { entryId = 4, journalRef = "JE-20110215-005", postingDate = @2011/2/15, accountCode = "GL-2100",
    accountName = "Payables", entryKind = "Vendor bill", regionName = "EMEA", countryCode = "DE",
    currencyCode = "EUR", fxRate = 1.38, supplierId = Null String, debitAmt = 0.0,
    creditAmt = 41880.0, netAmt = -41880.0, entryStatus = "Posted", preparerName = "h.mueller",
    quarterName = "Q1" },
  { entryId = 5, journalRef = "JE-20110228-011", postingDate = @2011/2/28, accountCode = "GL-4000",
    accountName = "Revenue", entryKind = "Sales invoice", regionName = "APAC", countryCode = "JP",
    currencyCode = "JPY", fxRate = 0.0, supplierId = Some "SUP-1177", debitAmt = 58900.0,
    creditAmt = 0.0, netAmt = 58900.0, entryStatus = "Draft", preparerName = "a.mori",
    quarterName = "Q1" },
  { entryId = 6, journalRef = "JE-20110331-020", postingDate = @2011/3/31, accountCode = "GL-6200",
    accountName = "Opex", entryKind = "Payroll accrual", regionName = "AMER", countryCode = "US",
    currencyCode = "USD", fxRate = 1.0, supplierId = Null String, debitAmt = 0.0,
    creditAmt = 214000.0, netAmt = -214000.0, entryStatus = "Posted", preparerName = "j.reyes",
    quarterName = "Q1" },
  { entryId = 7, journalRef = "JE-20110430-031", postingDate = @2011/4/30, accountCode = "GL-4000",
    accountName = "Revenue", entryKind = "Sales invoice", regionName = "EMEA", countryCode = "FR",
    currencyCode = "EUR", fxRate = 1.41, supplierId = Some "SUP-9042", debitAmt = 141750.0,
    creditAmt = 0.0, netAmt = 141750.0, entryStatus = "Posted", preparerName = "h.mueller",
    quarterName = "Q2" },
  { entryId = 8, journalRef = "JE-20110430-032", postingDate = @2011/4/30, accountCode = "GL-5100",
    accountName = "COGS", entryKind = "Cost of sales", regionName = "EMEA", countryCode = "FR",
    currencyCode = "EUR", fxRate = 1.41, supplierId = Some "SUP-9042", debitAmt = 0.0,
    creditAmt = 78180.0, netAmt = -78180.0, entryStatus = "Posted", preparerName = "h.mueller",
    quarterName = "Q2" },
  { entryId = 9, journalRef = "JE-20110531-045", postingDate = @2011/5/31, accountCode = "GL-1200",
    accountName = "Receivable", entryKind = "Cash receipt", regionName = "APAC", countryCode = "AU",
    currencyCode = "AUD", fxRate = 1.07, supplierId = Some "SUP-3320", debitAmt = 67400.0,
    creditAmt = 0.0, netAmt = 67400.0, entryStatus = "Posted", preparerName = "a.mori",
    quarterName = "Q2" },
  { entryId = 10, journalRef = "JE-20110531-046", postingDate = @2011/5/31, accountCode = "GL-4000",
    accountName = "Revenue", entryKind = "Sales invoice", regionName = "APAC", countryCode = "AU",
    currencyCode = "AUD", fxRate = 42.0, supplierId = Some "SUP-3320", debitAmt = 67400.0,
    creditAmt = 1200.0, netAmt = 67400.0, entryStatus = "Posted", preparerName = "a.mori",
    quarterName = "Q2" },
  { entryId = 11, journalRef = "JE-20110630-052", postingDate = @2011/6/30, accountCode = "GL-6200",
    accountName = "Opex", entryKind = "Rent", regionName = "AMER", countryCode = "CA",
    currencyCode = "CAD", fxRate = 1.02, supplierId = Null String, debitAmt = 0.0,
    creditAmt = 36500.0, netAmt = -36500.0, entryStatus = "Posted", preparerName = "j.reyes",
    quarterName = "Q2" },
  { entryId = 12, journalRef = "JE-20110630-053", postingDate = @2011/6/30, accountCode = "GL-4000",
    accountName = "Revenue", entryKind = "Credit note", regionName = "AMER", countryCode = "CA",
    currencyCode = "CAD", fxRate = 1.02, supplierId = Some "SUP-8801", debitAmt = 0.0,
    creditAmt = 18250.0, netAmt = -18250.0, entryStatus = "Reversed", preparerName = "j.reyes",
    quarterName = "Q2" },
  { entryId = 13, journalRef = "JE-20110731-061", postingDate = @2011/7/31, accountCode = "GL-4000",
    accountName = "Revenue", entryKind = "Sales invoice", regionName = "EMEA", countryCode = "GB",
    currencyCode = "GBP", fxRate = 1.61, supplierId = Some "SUP-5510", debitAmt = 203900.0,
    creditAmt = 0.0, netAmt = 203900.0, entryStatus = "Posted", preparerName = "h.mueller",
    quarterName = "Q3" },
  { entryId = 14, journalRef = "JE-20110731-062", postingDate = @2011/7/31, accountCode = "GL-5100",
    accountName = "COGS", entryKind = "Cost of sales", regionName = "EMEA", countryCode = "GB",
    currencyCode = "GBP", fxRate = 1.61, supplierId = Some "SUP-5510", debitAmt = 0.0,
    creditAmt = 112145.0, netAmt = -112145.0, entryStatus = "Posted", preparerName = "h.mueller",
    quarterName = "Q3" },
  { entryId = 15, journalRef = "JE-20110831-070", postingDate = @2011/8/31, accountCode = "GL-2100",
    accountName = "Payables", entryKind = "Vendor bill", regionName = "APAC", countryCode = "JP",
    currencyCode = "JPY", fxRate = 0.013, supplierId = Some "SUP-1177", debitAmt = 0.0,
    creditAmt = 94000.0, netAmt = -94000.0, entryStatus = "Draft", preparerName = "a.mori",
    quarterName = "Q3" }]

-- ============================================ 1. the parameters, at the edge

-- The row the parameter form PRODUCES. These are the report's arguments; a
-- caller sends them as strings and this is where they become a record.
field pAsOfYear, pMinAmount : Int
field pRegion, pStatus : String

-- The validator. `[...]_Vd` is `consV`/`nilV`, and its partition constraint
-- `t <- (r, s)` is what stops the same field being validated twice. Each entry
-- pairs a field with a `Validator (Maybe String) a`; `>=>` composes a lookup
-- with a parse, and `within` restricts the result to a list of legal values.
--
-- NOTE the accumulation: `combineErrors` collects EVERY field's message, so a
-- form with three bad fields reports three errors, not the first one.
reportParams : FormValidator_Vd (| pAsOfYear, pMinAmount, pRegion, pStatus |)
reportParams =
  [ (pAsOfYear,  lookupInt_Vd)
  , (pMinAmount, lookupInt_Vd)
  , (pRegion,    within_Vd ["AMER", "EMEA", "APAC"] (==) lookupString_Vd)
  , (pStatus,    lookupStringDef_Vd "Posted") ]_Vd

submitted : List (String, String) -> Map_Map String String
submitted = fromAssocList_M ord_String

goodForm = submitted [ ("pAsOfYear", "2011"), ("pMinAmount", "50000")
                     , ("pRegion", "EMEA") ]

badForm  = submitted [ ("pAsOfYear", "twenty eleven"), ("pMinAmount", "lots")
                     , ("pRegion", "ANTARCTICA") ]

-- The report as a function of its parameters. `validated`'s row variable is
-- instantiated here at the four-field parameter row; the success branch gets a
-- record it can project with `!`.
parameterised params =
  validated reportParams
            (p -> vflow [ h3 ("Journal entries -- " ++_String (p ! pRegion))
                        , textNoMarkdown ("Year "     ++_String toString (p ! pAsOfYear))
                        , textNoMarkdown ("Minimum "  ++_String toString (p ! pMinAmount))
                        , textNoMarkdown ("Status "   ++_String (p ! pStatus))
                        , tabular Nothing (selectedEntries (p ! pRegion)) ])
            params

goodParameters = parameterised goodForm

-- Three bad fields, three messages -- rendered by `Layout.Validation.showErrors`
-- as a `vflow` of `text`, i.e. a `Report`, so the failure branch drops into the
-- page in exactly the same slot as the success branch.
badParameters = parameterised badForm

selectedEntries r = journalEntries |> filterEq regionName r

-- ================================================ 2. the data, at the relation

-- CHECK 1 -- an FX rate that cannot be right. `outOfRange`'s partition
-- `r <- (v, o)` carries the other sixteen columns, so the failure report shows
-- the whole entry.
badRates = outOfRange fxRate 0.5 5.0 journalEntries

-- CHECK 2 -- a nullable key. Three entries have no supplier; a join to the
-- supplier dimension would drop them and nobody would notice.
orphanEntries = missingKey supplierId journalEntries

-- CHECK 3 -- the components do not add up. `debit = credit + net` should hold on
-- every line; one line was keyed wrong.
outOfBalance = unreconciled creditAmt netAmt debitAmt 0.5 journalEntries

-- Rows that pass everything: the complement, by three set differences. `except`
-- is not needed -- the checks all return the same row type as their input, which
-- is exactly what makes them composable.
cleanEntries =
  difference (difference (difference journalEntries badRates) orphanEntries)
             outOfBalance

-- --------------------------------------------------------------- the summary

-- One row per check. `aggregate` over a filtered relation gives the count; the
-- three counts are labelled by a literal one-row relation and unioned.
rateFailures    = aggregate_Agg countAgg_Agg failures badRates      ** relation [{ checkName = "FX rate outside [0.5, 5.0]" }]
orphanFailures  = aggregate_Agg countAgg_Agg failures orphanEntries ** relation [{ checkName = "Supplier missing" }]
balanceFailures = aggregate_Agg countAgg_Agg failures outOfBalance  ** relation [{ checkName = "Debit /= credit + net" }]

failureSummary : [ checkName, failures ]
failureSummary = union rateFailures (union orphanFailures balanceFailures)

summaryLegend : Legend_Lg (| checkName, failures |)
summaryLegend = [ (checkName, "Check")   ^ 0
                , (failures,  "Failures") ^! 1 ]_Sorted_Lg

-- ==================================================================== the page

-- The failure grids get the SAME legend as the clean grid, because a failing row
-- is an ordinary row of the fact table -- that is the whole argument for doing
-- data validation relationally.
entryLegend : Legend_Lg (| journalRef, postingDate, accountName, regionName
                         , currencyCode, fxRate, supplierId, debitAmt
                         , creditAmt, netAmt, entryStatus |)
entryLegend =
  withFormats ([ (journalRef,   "Reference") ^ 0
               , (postingDate,  "Posted")    ^ 1
               , (accountName,  "Account")   ^ 2
               , (regionName,   "Region")    ^ 3
               , (currencyCode, "Currency")  ^ 4
               , (entryStatus,  "Status")    ^ 5 ]_Sorted_Lg)
              (round_Fmt 2)
              { fxRate, supplierId, debitAmt, creditAmt, netAmt }

shown r = tabular_K ([tabLegend_O := entryLegend]_Opt)
                    (r # { journalRef, postingDate, accountName, regionName
                         , currencyCode, fxRate, supplierId, debitAmt
                         , creditAmt, netAmt, entryStatus })

qualityReport = vflow [
  h2 "Journal quality -- fiscal 2011",
  h3 "Parameters as submitted, accepted",
  goodParameters,
  h3 "Parameters as submitted, rejected -- every bad field reported, not the first",
  badParameters,
  vstrut,
  h3 "Summary",
  tabular_K ([tabLegend_O := summaryLegend]_Opt) failureSummary,
  h3 "FX rate outside [0.5, 5.0]",
  shown badRates,
  h3 "Supplier missing",
  shown orphanEntries,
  h3 "Debit does not equal credit plus net",
  shown outOfBalance,
  h3 "Entries that pass every check",
  shown cleanEntries
]
