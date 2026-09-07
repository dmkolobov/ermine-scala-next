module Lang.ReaderParams where

{- ONE REPORT, THREE PARAMETER SETS: `Control.Monad.Reader` as the production shape of
   an Ermine report — parameters in, document out.

   Fact: siteReadings (11 fields: siteRef, networkLabel, regionName, countryCode,
         landUse, stationName, gradeCode, heightBand, hoursLogged,
         pm25Reading, reviewYear)

   WHY THIS FILE EXISTS. `tracker/JSON-API-DESIGN.md` fixes the production shape of an
   Ermine deliverable: a function from its parameters to a document. That function IS a
   `Reader`, and `Control/Monad/Reader.e` says so in one line:

       type Reader e a = e -> a

   There is no wrapper, no `newtype`, no `runReader` to speak of (`runReader = id`), and
   that is the point worth making: a parameterised report needs no monad transformer
   stack, it needs a record and a function. What the `Reader` machinery buys is
   COMPOSITION — `<$>`, `<*>`, `lift2` and `local` let three parameter-dependent pieces
   be assembled without any of them mentioning the parameter record.

   `Syntax.Reader` is the fixed-monad syntax module for it, and it has one operator no
   other `Syntax.*` module has:

       (<$$>) : Reader e a -> (a -> b) -> Reader e b     -- flip map

   with the comment "useful for attaining a sort of forward chaining style; which is
   useful in aiding the typechecker". That is a real thing in a language whose
   inference is left-to-right, and it is used below.

   SHAPES EXERCISED
     * `askField`'s `Has e h` — sugar for `exists c. e <- (h, c)`; the interface writes
       the sugar out, and `Lang/Signatures.e` proves the two forms equivalent.
     * Five `askField`s under ONE row variable in a single `lift`ed expression: the
       `Layout.Validation` shape that produced E4's 225-draw resolution cascade, here
       without any presentation library involved.
     * `local` / `localField`: running a sub-report under a modified parameter set.
     * `Syntax.Reader`'s `<$>`, `<*>`, `lift2`, `lift3` and `<$$>`.
     * `ReaderT r Maybe` (`readerTMonad`) for the parameter set that may be absent.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/ReaderParams.e
   >> northSelection
   >> coastSelection
   >> allRegionsSelection
   >> selectionCaption northParams
   >> networkReport northParams
-}

import Prelude
import Syntax.List
import Control.Monad as M
import Control.Monad.Reader as Rd
import Syntax.Reader as SR
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import List as L
import String as S
import Lang.Helpers

field siteRef          : String
field networkLabel     : String
field regionName       : String
field countryCode      : String
field landUse          : String
field stationName      : String
field gradeCode        : String
field heightBand       : String
field hoursLogged      : Double
field pm25Reading      : Double
field reviewYear       : Int

-- the parameter row
field pRegion    : String
field pMinReading : Double
field pGrade     : String
field pYear      : Int
field pTitleText : String

type Params = {pRegion, pMinReading, pGrade, pYear, pTitleText}

-- ---------------------------------------------------------------------------
-- 1. The facts.

siteReadings : Relation (|siteRef, networkLabel, regionName, countryCode, landUse,
                          stationName, gradeCode, heightBand, hoursLogged,
                          pm25Reading, reviewYear|)
siteReadings = relation [
  { siteRef = "ST-01", networkLabel = "Urban background", regionName = "North",
    countryCode = "GB", landUse = "Urban", stationName = "Rheinallt Road",
    gradeCode = "A", heightBand = "2-4m", hoursLogged = 8100.0,
    pm25Reading = 14.6, reviewYear = 2011 },
  { siteRef = "ST-02", networkLabel = "Urban background", regionName = "North",
    countryCode = "FR", landUse = "Suburban", stationName = "Sarthe Parkway",
    gradeCode = "B", heightBand = "4-10m", hoursLogged = 7900.0,
    pm25Reading = 11.2, reviewYear = 2011 },
  { siteRef = "ST-03", networkLabel = "Roadside", regionName = "Coastal",
    countryCode = "JP", landUse = "Urban", stationName = "Kanto Harbour",
    gradeCode = "A", heightBand = "0-2m", hoursLogged = 8400.0,
    pm25Reading = 18.4, reviewYear = 2011 },
  { siteRef = "ST-04", networkLabel = "Roadside", regionName = "Coastal",
    countryCode = "AU", landUse = "Industrial", stationName = "Pilbara Works",
    gradeCode = "C", heightBand = "10m+", hoursLogged = 6800.0,
    pm25Reading = 9.7, reviewYear = 2010 },
  { siteRef = "ST-05", networkLabel = "Rural", regionName = "South",
    countryCode = "US", landUse = "Rural", stationName = "Halcyon Ridge",
    gradeCode = "A", heightBand = "2-4m", hoursLogged = 8200.0,
    pm25Reading = 7.3, reviewYear = 2011 },
  { siteRef = "ST-06", networkLabel = "Rural", regionName = "South",
    countryCode = "CA", landUse = "Rural", stationName = "Athabasca Flats",
    gradeCode = "B", heightBand = "4-10m", hoursLogged = 7600.0,
    pm25Reading = 6.1, reviewYear = 2010 },
  { siteRef = "ST-07", networkLabel = "Rural", regionName = "North",
    countryCode = "GB", landUse = "Urban", stationName = "Thameside Wharf",
    gradeCode = "C", heightBand = "0-2m", hoursLogged = 5900.0,
    pm25Reading = 5.2, reviewYear = 2011 }
  ]_L

-- ---------------------------------------------------------------------------
-- 2. The three parameter sets.

northParams, coastParams, allRegionsParams : Params
northParams = { pRegion = "North", pMinReading = 12.0, pGrade = "B",
                pYear = 2011, pTitleText = "Northern network PM2.5" }
coastParams = { pRegion = "Coastal", pMinReading = 12.0, pGrade = "C",
                pYear = 2011, pTitleText = "Coastal network PM2.5" }
allRegionsParams = { pRegion = "*", pMinReading = 0.0, pGrade = "D",
                     pYear = 2010, pTitleText = "Network-wide PM2.5" }

-- ---------------------------------------------------------------------------
-- 3. The report as a Reader.
--
-- Nothing below mentions the parameter record by name. Each piece asks for the one
-- field it needs, and the pieces compose.

regionOf : Reader_Rd Params String
regionOf = askField pRegion

thresholdOf : Reader_Rd Params Double
thresholdOf = askField pMinReading

yearOf : Reader_Rd Params Int
yearOf = askField pYear

titleOf : Reader_Rd Params String
titleOf = askField pTitleText

gradeOf : Reader_Rd Params String
gradeOf = askField pGrade

-- | The caption: two parameters combined with `Syntax.Reader`'s applicative.
selectionCaption : Reader_Rd Params String
selectionCaption = lift2_SR (r n -> r ++_S " at or above " ++_S toString n)
                            regionOf thresholdOf

-- | The selection: FIVE `askField`s under one row variable, combined with `lift3` and
--   an explicit `bind`. This is the shape that stresses the row solver -- one record
--   projected many times, each projection an existential partition.
selectedRows : Reader_Rd Params (Relation (|siteRef, networkLabel, regionName, countryCode,
                                            landUse, stationName, gradeCode,
                                            heightBand, hoursLogged, pm25Reading,
                                            reviewYear|))
selectedRows = lift3_SR pick regionOf thresholdOf yearOf
  where pick r n y =
          siteReadings
          |> filter_Pred (col_Op pm25Reading >=_Pred prim_Op n)
          |> filter_Pred (col_Op reviewYear ==_Pred prim_Op y)
          |> (rel -> if (r == "*") rel (filter_Pred (col_Op regionName ==_Pred prim_Op r) rel))

-- | `<$$>` is `flip map`: the forward-chaining spelling `Syntax.Reader` provides and
--   no other `Syntax.*` module does. The header of whatever the parameters selected.
selectionHeader : Reader_Rd Params (Row (|siteRef, networkLabel, regionName, countryCode,
                                          landUse, stationName, gradeCode,
                                          heightBand, hoursLogged, pm25Reading,
                                          reviewYear|))
selectionHeader = selectedRows <$$>_SR rheader

-- | The whole report, still a function from parameters.
networkReport : Reader_Rd Params (Report f z)
networkReport = (do t <- liftDo titleOf
                    c <- liftDo selectionCaption
                    s <- liftDo selectedRows
                    g <- liftDo gradeOf
                    unit (vflow [
                      text ("## " ++_S t),
                      text ("### " ++_S c ++_S " (worst grade shown: " ++_S g ++_S ")"),
                      tabular Nothing (s # {siteRef, stationName, regionName,
                                            gradeCode, pm25Reading}),
                      text "### The whole network, for context",
                      tabular Nothing (siteReadings # {siteRef, regionName,
                                                       stationName, pm25Reading})
                      ]_L)) ' readerMonad_Rd

-- ---------------------------------------------------------------------------
-- 4. The three runs.

northSelection, coastSelection, allRegionsSelection :
  Relation (|siteRef, networkLabel, regionName, countryCode, landUse, stationName,
             gradeCode, heightBand, hoursLogged, pm25Reading, reviewYear|)
northSelection      = runWith northParams selectedRows
coastSelection      = runWith coastParams selectedRows
allRegionsSelection = runWith allRegionsParams selectedRows

northReport, coastReport, allRegionsReport : Report f z
northReport      = runWith northParams networkReport
coastReport      = runWith coastParams networkReport
allRegionsReport = runWith allRegionsParams networkReport

-- ---------------------------------------------------------------------------
-- 5. `local`: one parameter overridden for part of the report.
--
-- `Control.Monad.Reader.local : (e -> e) -> Reader e a -> Reader e a` is `flip (.)`.
-- `localField` in `Helpers.e` narrows it to one field, and carries the `Has` that says
-- the field is in the parameter row.

doubledThreshold : Reader_Rd Params String
doubledThreshold = localField pMinReading (n -> n * 2.0) selectionCaption

sideBySide : Reader_Rd Params (List String)
sideBySide = lift2_SR (a b -> [a, b]_L) selectionCaption doubledThreshold

bothCaptions : List String
bothCaptions = runWith northParams sideBySide

-- ---------------------------------------------------------------------------
-- 6. Parameters that may be absent: `ReaderT r Maybe`.
--
-- `readerTMonad : Monad m -> Monad (ReaderT r m)`. The base monad carries the failure,
-- the reader carries the parameters, and `askT` gets the whole record.

requireRegion : ReaderT_Rd Params Maybe String
requireRegion = ReaderT_Rd (p -> if ((p ! pRegion) == "*") Nothing (Just (p ! pRegion)))

strictCaption : ReaderT_Rd Params Maybe String
strictCaption = bind_M (readerTMonad_Rd maybeMonad) requireRegion (r ->
                unit_M (readerTMonad_Rd maybeMonad) ("Region " ++_S r))

strictNorth, strictAll : Maybe String
strictNorth = runReaderT_Rd strictCaption northParams
strictAll   = runReaderT_Rd strictCaption allRegionsParams
