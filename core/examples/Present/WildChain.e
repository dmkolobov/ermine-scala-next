module Present.WildChain where

{- THE PROJECTION CLIFF IN CODE NOBODY WROTE TO DEMONSTRATE IT.

   `ProjectionCost.e` measures the ladder with six `p ! field`s in ONE expression,
   which is a fair question to ask of a synthetic probe and an unfair one to ask
   of a reader: nobody writes that. This module asks the reader's question
   instead. It has a 25-column fact relation -- a realistic width, wider than any
   other input in this directory -- and it reads six of those columns THREE
   DIFFERENT WAYS:

     1. `wildChain`     -- six un-annotated LET-BOUND steps, each naming one
                           field, combined at the end. The reads are not in one
                           expression; they are six separate bindings.
     2. `wildHelpers`   -- six un-annotated TOP-LEVEL one-line helpers, each
                           generalised with its own `Has`, all applied to the
                           same record at one call site. The reads are not even
                           in one FUNCTION.
     3. `wildPinned`    -- the same six reads with ONE partition written at the
                           top of the lambda.

   MEASURED on this compiler, this module alone, one JVM
   (`-Dermine.rowTrace.draws=true`); analysis in `tracker/loopmodel/S4-CHANGE.md`:

       binding                       site          draws
       wildChain    (six lets)       (144:8)       6,783
       wildHelpers  (six helpers)    (168:8)       6,783
       wildPinned   (one partition)  --                0

   2,247 solves in the module, 13,566 draws, ALL of them in those two bindings;
   module import 1.65 s.

   BOTH WILD SPELLINGS COST EXACTLY `D(6) = (5^6 - 3*3^6 + 2*2^6)/2 = 6,783`,
   which is the same number `proj6` costs in `ProjectionCost.e`. The fan is a
   property of the CONSTRAINT SET, not of the syntax: six lone-abstract
   partitions at one row variable close the same way whether they arrive from one
   expression, six `let`s or six imported helpers. A seventh of either does not
   compile at the adopted `-Dermine.solveBudget=20000`; see
   `shouldfail/proj01_seven_reads.e`.

   THE FIX IS ONE TOKEN, and it is the same one `Helpers.e` preaches: write the
   row down. `wildPinned` draws nothing at all.

   THIS IS ALSO THE MODULE STAGE S4 USES AS ITS WILD-CODE GATE. With
   `-Dermine.topNormalise=true` (DEFAULT OFF) the solver performs for itself the
   normalisation `wildPinned` writes by hand: the module's 13,566 draws become
   **0** and its import 1.65 s becomes **0.32 s**, with two `tnorm` records
   naming the same six-field partition at both sites. See
   `tracker/loopmodel/S4-CHANGE.md`.

     >> :load core/examples/Present/WildChain.e
     >> wildChain
     >> wildPinned
     >> :type wildStep1
-}

import Prelude
import Syntax.List
import Control.Monoid as Mo
import List as L
import String as S

-- ------------------------------------------------------------- 25 columns

field wskuCode, wskuTitle, wbrandName, wcategoryPath, wsupplierRef : String
field wcountryCode, wcurrencyCode, wchannelName, wwarehouseCode : String
field wbuyerName, wplannerName, wstatusName, wseasonName, wcolourName : String
field wsizeName, wfabricName, woriginPort, wtariffCode, wpackSize : String
field wlistPriceUsd, wcostUsd, wmarginPct, wweightKg, wvolumeM3 : Double
field wstockUnits : Int

-- | THE INPUT: twenty-five columns. Wider than any other fact row in this
--   directory, and the point of the module is that the WIDTH is irrelevant --
--   what costs is how many of the columns one un-annotated lambda reads.
catalogueRows : List (Record (| wskuCode, wskuTitle, wbrandName, wcategoryPath, wsupplierRef
                              , wcountryCode, wcurrencyCode, wchannelName, wwarehouseCode
                              , wbuyerName, wplannerName, wstatusName, wseasonName, wcolourName
                              , wsizeName, wfabricName, woriginPort, wtariffCode, wpackSize
                              , wlistPriceUsd, wcostUsd, wmarginPct, wweightKg, wvolumeM3
                              , wstockUnits |))
catalogueRows =
  [
  { wskuCode = "SKU-1001", wskuTitle = "Merino Crew", wbrandName = "Northvale",
    wcategoryPath = "Apparel/Knitwear", wsupplierRef = "SUP-4410",
    wcountryCode = "PT", wcurrencyCode = "EUR", wchannelName = "Wholesale",
    wwarehouseCode = "WH-LIS", wbuyerName = "a.ferreira", wplannerName = "m.dias",
    wstatusName = "Active", wseasonName = "AW25", wcolourName = "Charcoal",
    wsizeName = "M", wfabricName = "Merino 100%", woriginPort = "Leixoes",
    wtariffCode = "6110.11", wpackSize = "6",
    wlistPriceUsd = 148.0, wcostUsd = 61.4, wmarginPct = 0.585,
    wweightKg = 0.42, wvolumeM3 = 0.0031, wstockUnits = 1840 },
  { wskuCode = "SKU-1002", wskuTitle = "Linen Shirt", wbrandName = "Northvale",
    wcategoryPath = "Apparel/Shirts", wsupplierRef = "SUP-4410",
    wcountryCode = "PT", wcurrencyCode = "EUR", wchannelName = "Retail",
    wwarehouseCode = "WH-LIS", wbuyerName = "a.ferreira", wplannerName = "m.dias",
    wstatusName = "Active", wseasonName = "SS26", wcolourName = "Ecru",
    wsizeName = "L", wfabricName = "Linen 100%", woriginPort = "Leixoes",
    wtariffCode = "6205.20", wpackSize = "6",
    wlistPriceUsd = 112.0, wcostUsd = 44.8, wmarginPct = 0.600,
    wweightKg = 0.28, wvolumeM3 = 0.0024, wstockUnits = 2310 },
  { wskuCode = "SKU-2007", wskuTitle = "Trail Shell", wbrandName = "Fellhaus",
    wcategoryPath = "Outerwear/Shells", wsupplierRef = "SUP-7712",
    wcountryCode = "VN", wcurrencyCode = "USD", wchannelName = "Wholesale",
    wwarehouseCode = "WH-HCM", wbuyerName = "t.nguyen", wplannerName = "k.tran",
    wstatusName = "Active", wseasonName = "AW25", wcolourName = "Slate",
    wsizeName = "M", wfabricName = "3L Nylon", woriginPort = "Cat Lai",
    wtariffCode = "6201.40", wpackSize = "4",
    wlistPriceUsd = 385.0, wcostUsd = 132.9, wmarginPct = 0.655,
    wweightKg = 0.61, wvolumeM3 = 0.0058, wstockUnits = 640 },
  { wskuCode = "SKU-2008", wskuTitle = "Alpine Fleece", wbrandName = "Fellhaus",
    wcategoryPath = "Outerwear/Fleece", wsupplierRef = "SUP-7712",
    wcountryCode = "VN", wcurrencyCode = "USD", wchannelName = "Direct",
    wwarehouseCode = "WH-HCM", wbuyerName = "t.nguyen", wplannerName = "k.tran",
    wstatusName = "Discontinued", wseasonName = "AW24", wcolourName = "Moss",
    wsizeName = "S", wfabricName = "Recycled PET", woriginPort = "Cat Lai",
    wtariffCode = "6110.30", wpackSize = "4",
    wlistPriceUsd = 168.0, wcostUsd = 57.1, wmarginPct = 0.660,
    wweightKg = 0.47, wvolumeM3 = 0.0044, wstockUnits = 95 },
  { wskuCode = "SKU-3155", wskuTitle = "Harbour Tote", wbrandName = "Quayside",
    wcategoryPath = "Accessories/Bags", wsupplierRef = "SUP-2290",
    wcountryCode = "IN", wcurrencyCode = "USD", wchannelName = "Retail",
    wwarehouseCode = "WH-NSA", wbuyerName = "r.iyer", wplannerName = "s.rao",
    wstatusName = "Active", wseasonName = "SS26", wcolourName = "Navy",
    wsizeName = "OS", wfabricName = "Canvas 16oz", woriginPort = "Nhava Sheva",
    wtariffCode = "4202.22", wpackSize = "12",
    wlistPriceUsd = 96.0, wcostUsd = 31.2, wmarginPct = 0.675,
    wweightKg = 0.83, wvolumeM3 = 0.0091, wstockUnits = 4120 } ]_L

-- --------------------------------------------------------- a plain renderer

-- | One rendered line per row, six cells joined by ` | `.  No markdown, no
--   monoid: what this module measures is the CELLS function's inferred type, and
--   everything else is deliberately out of the way.
sep : String -> String -> String
sep a b = a ++_S " | " ++_S b

-- ------------------------------------------- 1. six un-annotated LET steps

-- | THE CHAIN.  Six `let`-bound steps, each naming a different field of the same
--   un-annotated parameter, combined at the end.  Six lone-abstract partitions at
--   one row variable: 6,783 draws.
wildChain : List String
wildChain =
  map (t -> let s1 = t ! wskuCode
                s2 = t ! wskuTitle
                s3 = t ! wbrandName
                s4 = t ! wsupplierRef
                s5 = t ! wwarehouseCode
                s6 = t ! wseasonName
             in sep s1 (sep s2 (sep s3 (sep s4 (sep s5 s6)))))
      catalogueRows

-- --------------------------------- 2. six un-annotated top-level helpers

-- | THE SAME COST FROM SIX SEPARATE FUNCTIONS.  Each of these is a one-line
--   generalised helper with its own inferred `Has`; the fan appears at the CALL
--   SITE, where all six instantiate at the same row variable.  The reads do not
--   have to be in one expression, or even in one function.
wildStep1 r = r ! wskuCode
wildStep2 r = r ! wskuTitle
wildStep3 r = r ! wbrandName
wildStep4 r = r ! wsupplierRef
wildStep5 r = r ! wwarehouseCode
wildStep6 r = r ! wseasonName

wildHelpers : List String
wildHelpers =
  map (t -> sep (wildStep1 t) (sep (wildStep2 t) (sep (wildStep3 t)
              (sep (wildStep4 t) (sep (wildStep5 t) (wildStep6 t))))))
      catalogueRows

-- ------------------------------------- 3. the same six, one partition written

-- | THE FIX, one line.  `r <- ((| ... |), o)` says what the six reads were going
--   to make the solver discover one partition at a time.  Zero draws.
wildCells : forall r o.
            r <- ((| wskuCode, wskuTitle, wbrandName
                   , wsupplierRef, wwarehouseCode, wseasonName |), o)
         => {..r} -> String
wildCells t = sep (t ! wskuCode) (sep (t ! wskuTitle) (sep (t ! wbrandName)
                (sep (t ! wsupplierRef) (sep (t ! wwarehouseCode) (t ! wseasonName)))))

wildPinned : List String
wildPinned = map wildCells catalogueRows
