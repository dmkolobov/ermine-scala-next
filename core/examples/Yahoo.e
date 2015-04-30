module Yahoo where

import Prelude hiding bind
import Function
import Control.Ap
import Control.Functor
import Control.Traversable
import Control.Monad
import IO
import IO.CSV
import List
import Field
import Record
import Maybe
import Native.Record
import Parse
import Date
import File
import String as String
import Layout.Report
import Syntax.Maybe
import Relation
import Syntax.Relation
import Layout.Format as Fmt
import Relation.Op as Op
import Layout.Legend as Lg
import Layout.Presentation as P
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Double
import Layout.SortPriority
import YahooExtras

-- ======= Potential library functions ========= --

mmap  = fmap maybeFunctor
lmap  = fmap listFunctor
ioMaybeMap = iomap . mmap

concatStrings : List (String) -> String
concatStrings = foldl (++_String) ""

infixr 5 <++>
--<++> : c <- (a,b) => Maybe {..a} -> Maybe {..b} -> Maybe {..c}
(<++>) a b = liftA2 maybeAp (++) a b
parseField : (String -> Maybe a) -> Field b a -> String -> Maybe {..b}
parseField parseFunction fld = (mmap $ v -> {fld = v}) . parseFunction

-- convert YYYY-MM-DD to MM/DD/YYYY
pDate fld s = parseField parseDate fld $ reform (split_String '-' s) where
  reform (yyyy :: mm :: dd :: []) = concatStrings [mm, "/", dd, "/", yyyy]
pDouble     = parseField parseDouble
pInt        = parseField (parseInt 10)

readDataFile tupReader = readData tupReader . readCSVFile
readDataURL  tupReader = readData tupReader . readCSVURL

readData tupReader fetchContents = iomap (readDataRecs . reverse . drop 1) fetchContents where
  readDataRecs ls = mmap relation $
    sequence listTraversable maybeMonad (lmap tupReader ls)

-- todo: define infix operator for this
joinIOM2Rs        = combineIoMaybe (r1 -> r2 -> r1 ** r2)
joinIOM3Rs r      = joinIOM2Rs . (joinIOM2Rs r)
joinIOM4Rs r1 r2  = joinIOM2Rs . (joinIOM3Rs r1 r2)
renameIOMR iomr f = iomr |> (ioMaybeMap $ (rename adjClose f) . project {datefld, adjClose})

go = display . (maybe $ text "parse error") where display f i = iobind i (javaFX . f)

-- ========= Yahoo Code ========= --

pad2 s = if (length_String s == 1) ("0" ++_String s) s
yahooBaseURL = "http://ichart.finance.yahoo.com/table.csv?"
yahooDate a b c d = concatStrings [
  "&", a, "=", pad2 $ getMonth d  |> toString,
  "&", b, "=", pad2 $ getDate  d  |> toString,
  "&", c, "=", (getYear d) + 1900 |> toString
]
yahooStartDate = yahooDate "a" "b" "c"
yahooEndDate   = yahooDate "d" "e" "f"
yahooURL sym startDate endDate =
  concatStrings [yahooBaseURL, "s=", sym, (yahooStartDate startDate), (yahooEndDate endDate), "&g=d&ignore=.csv"]
-- TODO: add flag for daily, monthly, yearly, etc
yahooString sym startDate endDate = readURL (traceShow $ yahooURL sym startDate endDate)
yahoo startDate endDate sym = readHistoryFromURL (traceShowS "???" $ yahooURL sym startDate endDate)
yahoo2011 = yahoo @2011/01/01 @2011/12/31

-- ========= Classwork below ========== --

field datefld : Date
field open, high, low, close, adjClose: Double
field volume  : Int

-- parse one row of the CSV file into a history record
readHistoryRec (d :: o :: hi :: l :: c :: v :: a :: []) =
  (pDate   datefld d) <++>
  (pDouble open o)    <++>
  (pDouble high hi)   <++>
  (pDouble low l)     <++>
  (pDouble close c)   <++>
  (pInt    volume v)  <++>
  (pDouble adjClose a)
readHistoryRec _ = Nothing

-- parse an entire CSV of history records
readHistoryFromFile = readDataFile readHistoryRec
readHistoryFromURL  = readDataURL  readHistoryRec

-- show the history table, given the history relation
priceTable r = tabular priceLegend $ r # {datefld, adjClose} where
  priceLegend = Just [(datefld, "Date") ^ 0, (adjClose, "Adj Close") ^ 10]_Sorted_Lg

-- show a line chart from the history relation
historyChart r = chart_K defaults
  defaultScaled defaultScaled
  [
  line (prim_Op "Open")      datefld open     r
  ,line (prim_Op "High")      datefld high     r
  ,line (prim_Op "Low")       datefld low      r
  --,line (prim_Op "Close")     datefld close    r
  ,line (prim_Op "Adj Close") datefld adjClose r
  ]

-- ========= HW ======== -----

{--
find online broker to paper trade
invest $1M in 4 equities
access portfolio for 2011
  * annual return
  * avg daily return
  * stddev of daily return
  * sharp ratio
Compare with benchmark: SPY (S&P)
Submit:
  * .pdf printout of your spreadsheet (pdf writer, anyone?)
  * Screenshot of your portfolio online.

table columns:
Date | AAPL (adjClose) | AAPL Cumulative return | AAPL invest | GLD | GLD cum ret | GLD invest | 2 more stocks |

cum return = todays price / starting price
invest = total value of my stock holdings for that company
         original investment * cumulative value

then another little table with:
Equities Allocations  ?    | Performance       Fund     Benchmark
Start:    1           1M   | Annual Return     19.58%   ?
AAPL      1.0         1M?  | Avg daily ret              ?
GLD       0.35        350k | Stddev daily ret
other1    0                | Sharp Ratio
other2    0                |

the sum of the allocations column needs to add up to 1.
so, if we put everything in AAPL, the rest must be zero.
find a decent allocation distribution

the performance info on the right is total for all stocks
see what happens to the perf totals if we change the allocations.

calculate the same numbers for the benchmark (SPY)
to see how your portfolio did against the benchmark.

get the historical results for all for stocks every day for the whole year.
put all of this in a table. it seems a little much to have every day,
but whatever, its ok.
--}

-- pull the daily historical data from yahoo for 2011 for 4 stocks
aapl = yahoo2011 "AAPL"
hpq  = yahoo2011 "HPQ"
gld  = yahoo2011 "GLD"
spy  = yahoo2011 "SPY"

anyYahooStock =
  prefA [pixelsA 1000 500] (
  input "AAPL"           $ symTextField       syms   ->
  dateInput "01/01/2011" $ startDateTextField sDates ->
  dateInput "12/31/2011" $ endDateTextField   eDates ->
  button "GO"            $ goButton           go     ->
  vflow [
    hflow [
      text "Stock:",      symTextField,
      text "Start Date:", startDateTextField,
      text "End Date:",   endDateTextField,
      goButton
    ],
    on go (syms *** sDates *** eDates) $ ((sym, sDate), eDate) ->
      maybe (text "parse error") historyChart $ sDate >>= (sd -> eDate >>= (ed -> (unsafePerformIO $ yahoo sd ed sym)))
  ])

historicalDataMain = javaFX anyYahooStock

-- join in a calculation to a relation.
-- @param valueField  - the field to hold the initial value
-- @param v           - the initial value to put in the initVField
-- @param outputField - the field to store the calculation value
-- @param calc        - a calculation that runs over the the initial value field.
--                      the result is stored in the outputField.
joinCalc valueField v outputField calc r =
  r ** (relation [{valueField = v}]) |> [| outputField = calc valueField |]

-- add in the cumulative return for a stock, given its initial value
field initValue, cumRet: Double
joinCumRet initV = joinCalc initValue initV cumRet (x -> adjClose /_Op x)

-- add in the total value of current holdings, given an initial holding amount.
field holdings, initialInvestment: Double
joinTotalValue initV = joinCalc initialInvestment initV holdings (x -> cumRet *_Op x)

investmentTableData initialInvestmentValue ts =
  (relation ts) |> (joinCumRet ((head ts) ! open)) |> (joinTotalValue initialInvestmentValue)
investmentTableFields r = r # {datefld, adjClose, cumRet, holdings}
investmentLegend = Just [
 (datefld, "Date") ^ 0, (adjClose, "Adj Close") ^ 10, (cumRet, "Cum Return") ^ 10, (holdings, "Holdings") ^ 10
]_Sorted_Lg
investmentTable r = prefA [pixelsA 500 1000] . tabular investmentLegend $ investmentTableFields r

-- see what it would have been like to invest in a particular stock
investmentTableWithSelectors =
  prefA [pixelsA 1000 500] (
  input "AAPL"           $ symTextField           syms   ->
  dateInput "01/01/2011" $ startDateTextField     sDates ->
  dateInput "12/31/2011" $ endDateTextField       eDates ->
  doubleInput "0"        $ initialInvestmentField invest ->
  button "GO"  $ goButton           go     ->
  vflow [
    hflow [
      text "Stock:",      symTextField,
      text "Start Date:", startDateTextField,
      text "End Date:",   endDateTextField,
      text "Initial Investment", initialInvestmentField,
      goButton
    ],
    on go (syms *** sDates *** eDates *** invest) $ (((sym, sDate), eDate), initialInvestmentMaybe) ->
      maybe (text "Bad investment value") (i ->
        (maybe (text "unable to get data") (r -> scanRelation r (investmentTable . investmentTableData i)) $
          sDate >>= (sd -> eDate >>= (ed -> (unsafePerformIO $ yahoo sd ed sym)))))
      initialInvestmentMaybe
  ])

investmentTableMain = javaFX investmentTableWithSelectors


-- ========== put together a table with the closing prices for all the stocks ========= --
field aaplClose, hpqClose, gldClose, spyClose : Double
bigR = joinIOM4Rs (rn aapl aaplClose) (rn hpq hpqClose) (rn gld gldClose) (rn spy spyClose)
 where rn = renameIOMR
bigPriceTable r = tabular bigPriceLegend $ r # {datefld, aaplClose, hpqClose, gldClose, spyClose}
  where bigPriceLegend  = Just [ (datefld, "Date") ^ 0,
    (aaplClose, "AAPL") ^ 10, (hpqClose, "HPQ") ^ 10, (gldClose, "GLD") ^ 10, (spyClose, "SPY") ^ 10
  ]_Sorted_Lg
-- run the table in javafx
goBigPriceTable = go bigPriceTable bigR
