module Algebra.SoftSchema where

{- A KEY/VALUE ("soft") TABLE TURNED BACK INTO A WIDE ONE, three ways, and
   joined against a hard table.

   Asset telemetry arrives as (asset, attribute name, attribute value): one row
   per reading, all values as text, the set of attributes not known in advance.
   That is the right shape for the database and the wrong shape for a report,
   so something has to widen it. Ermine offers three answers and this file uses
   all three on the same data:

     1. RELATIONAL ALGEBRA, by hand: one `filterEq` + `except` + `rename` per
        attribute, joined back together. Explicit, checkable, and the attribute
        list is in the source.
     2. `Relation.Pivot.pivot` with a `Fulcrum`: the same thing as one
        combinator, with the attribute-to-column mapping as a value.
     3. `Layout.Report.SoftRelation`: do not widen the relation at all -- widen
        the PRESENTATION, so the columns are discovered at run time from the
        data and only the layout knows about them.

   The point of putting them side by side is that they have different types
   and therefore different failure modes. (1) and (2) produce relations whose
   header the type checker knows; (3) produces a `Report` whose columns the
   type checker does NOT know, which is exactly why it can cope with an
   attribute set that changes.

   Soft table: sensorReadings (assetId, readingKey, readingValue)
   Hard table: assetDim (12 columns: assetId, assetName, assetType, siteCode,
               siteName, installDate, manufacturer, modelCode, serialNo,
               criticality, ownerTeam, warrantyEnd)

   Helpers used: alias, lookupOr, semiJoin, antiJoin, groupTop.
   Stdlib exercised: `Layout.Report.SoftRelation` / `softRelation` /
               `keyValueTabular` (two example uses before this one),
               `Relation.Pivot.pivot`, `Relation.filterEq`,
               `Relation.Row.except`.

   SOLVER SHAPES. The hand pivot instantiates `except`'s `r <- (r1, r2)` five
   times against five different concrete two-column headers and then joins the
   five results into one, which is the `concrete` branch used as a fold.
   `keyValueTabular`'s `r <- (k, v, i)` is a THREE-part partition solved
   against a concrete three-column header, with `i` -- the identifier columns --
   determined only by subtraction.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/SoftSchema.e
     >> :import Algebra.SoftSchema
     >> widened
     >> softReport
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Presentation as Pres
import Layout.Legend as Lg
import Layout.Report.SoftRelation
import Layout.SortPriority
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Pivot hiding single_Brace; snoc_Brace
import Relation.Sort using ordering
import Ord using fromLess
import Syntax.Relation
import Algebra.Helpers

field assetId, criticality : Int
field readingKey, readingValue : String
field assetName, assetType, siteCode, siteName, installDate : String
field manufacturer, modelCode, serialNo, ownerTeam, warrantyEnd : String
field voltageV, tempC, hoursRun, firmware, lastFault : String

-- ------------------------------------------------------------- the two tables

sensorReadings : [assetId, readingKey, readingValue]
sensorReadings = relation [
  { assetId = 8101, readingKey = "voltageV",  readingValue = "231.4" },
  { assetId = 8101, readingKey = "tempC",     readingValue = "41.2" },
  { assetId = 8101, readingKey = "hoursRun",  readingValue = "18244" },
  { assetId = 8101, readingKey = "firmware",  readingValue = "4.2.1" },
  { assetId = 8101, readingKey = "lastFault", readingValue = "2025-11-03 E14" },
  { assetId = 8102, readingKey = "voltageV",  readingValue = "229.8" },
  { assetId = 8102, readingKey = "tempC",     readingValue = "38.9" },
  { assetId = 8102, readingKey = "hoursRun",  readingValue = "2210" },
  { assetId = 8102, readingKey = "firmware",  readingValue = "4.2.1" },
  { assetId = 8103, readingKey = "voltageV",  readingValue = "233.0" },
  { assetId = 8103, readingKey = "tempC",     readingValue = "55.7" },
  { assetId = 8103, readingKey = "hoursRun",  readingValue = "40118" },
  { assetId = 8103, readingKey = "firmware",  readingValue = "3.9.7" },
  { assetId = 8103, readingKey = "lastFault", readingValue = "2026-01-09 E02" },
  { assetId = 8104, readingKey = "voltageV",  readingValue = "230.1" },
  { assetId = 8104, readingKey = "tempC",     readingValue = "36.4" },
  { assetId = 8104, readingKey = "hoursRun",  readingValue = "907" },
  { assetId = 8104, readingKey = "firmware",  readingValue = "4.3.0" }
]

assetDim : [ assetId, assetName, assetType, siteCode, siteName, installDate
           , manufacturer, modelCode, serialNo, criticality, ownerTeam
           , warrantyEnd ]
assetDim = relation [
  { assetId = 8101, assetName = "Compressor A", assetType = "compressor", siteCode = "TAC", siteName = "Tacoma",    installDate = "2019-04-12", manufacturer = "Ostvold", modelCode = "OC-500",  serialNo = "OC500-11244", criticality = 1, ownerTeam = "utilities", warrantyEnd = "2026-04-12" },
  { assetId = 8102, assetName = "Compressor B", assetType = "compressor", siteCode = "TAC", siteName = "Tacoma",    installDate = "2024-09-30", manufacturer = "Ostvold", modelCode = "OC-500",  serialNo = "OC500-40012", criticality = 1, ownerTeam = "utilities", warrantyEnd = "2029-09-30" },
  { assetId = 8103, assetName = "Chiller 1",    assetType = "chiller",    siteCode = "ROT", siteName = "Rotterdam", installDate = "2014-02-01", manufacturer = "Kelvex",  modelCode = "KX-220",  serialNo = "KX220-00871", criticality = 2, ownerTeam = "facilities", warrantyEnd = "2019-02-01" },
  { assetId = 8104, assetName = "Chiller 2",    assetType = "chiller",    siteCode = "ROT", siteName = "Rotterdam", installDate = "2025-06-18", manufacturer = "Kelvex",  modelCode = "KX-240",  serialNo = "KX240-00190", criticality = 3, ownerTeam = "facilities", warrantyEnd = "2030-06-18" },
  { assetId = 8105, assetName = "Pump 7",       assetType = "pump",       siteCode = "ROT", siteName = "Rotterdam", installDate = "2021-01-05", manufacturer = "Hydris",  modelCode = "HP-90",   serialNo = "HP90-55510",  criticality = 3, ownerTeam = "utilities", warrantyEnd = "2026-01-05" }
]

-- ------------------------------------------------ 1. the hand-written pivot
--
-- One attribute at a time: select the rows for that key, drop the key column,
-- rename the value column to the attribute's own name. Three primitives, no
-- magic, and the resulting header is known to the type checker.

-- WRITTEN OUT PER ATTRIBUTE RATHER THAN AS A GENERIC HELPER, and the reason is
-- a language trap worth knowing about. The obvious helper is
--
--     column1 : Field c String -> [assetId, c]
--     column1 f k = alias readingValue f (except {readingKey}
--                                          (filterEq readingKey k sensorReadings))
--
-- and it CHECKS. It is also wrong: in the bracket relation-type syntax every
-- name is a LABEL, so the `c` in `[assetId, c]` is a fixed column called "c",
-- not the row variable bound by `Field c String`. The compiler agrees --
-- `:type column1` reports
--
--     forall (c: rho). Field c String -> Relation (|assetId, c|)
--
-- and `column1 voltageV "voltageV"` has type `Relation (|assetId, c|)`, not
-- `Relation (|assetId, voltageV|)`. Nothing complains until a LATER call site:
-- here the five columns all had the same type, so `widened`'s `lookupOr` two
-- definitions below failed with
--
--     Row partitions are unsatisfiable at field 'lastFault':
--     the whole contains it but no part does
--
-- A row variable in a result position has to be written `[..r]` with a
-- partition constraint. Since there is nothing useful to constrain here --
-- each column's header is fully known -- five lines of algebra with five
-- concrete annotations is the honest spelling.
oneKey k = except {readingKey} (filterEq readingKey k sensorReadings)

voltageCol  : [assetId, voltageV]
voltageCol  = alias readingValue voltageV  (oneKey "voltageV")
tempCol     : [assetId, tempC]
tempCol     = alias readingValue tempC     (oneKey "tempC")
hoursCol    : [assetId, hoursRun]
hoursCol    = alias readingValue hoursRun  (oneKey "hoursRun")
firmwareCol : [assetId, firmware]
firmwareCol = alias readingValue firmware  (oneKey "firmware")
faultCol    : [assetId, lastFault]
faultCol    = alias readingValue lastFault (oneKey "lastFault")

-- Assets 8102 and 8104 have never faulted, so `faultCol` has no row for them:
-- an inner join would drop them. `lookupOr` fills the gap with a constant, and
-- is the only one of the five that needs to.
widened = lookupOr lastFault "(none recorded)"
                   (voltageCol ** tempCol ** hoursCol ** firmwareCol)
                   faultCol

-- and the hard table alongside; asset 8105 has no readings at all
assetWithReadings = assetDim ** widened
assetsWithNoReadings = antiJoin {assetId} sensorReadings assetDim
assetsWithReadingsOnly = semiJoin {assetId} sensorReadings assetDim

-- ---------------------------------------------- 2. the built-in pivot
--
-- `Relation.Pivot` says the same thing as a value: a `Fulcrum` is the list of
-- (new column, op, key-record) triples, built up with `consFulcrum`.

fulcrum0 = nilFulcrum {readingKey} {readingValue}
fulcrum1 = consFulcrum voltageV  (col_Op readingValue) { readingKey = "voltageV" }  fulcrum0
fulcrum2 = consFulcrum tempC     (col_Op readingValue) { readingKey = "tempC" }     fulcrum1
fulcrum3 = consFulcrum hoursRun  (col_Op readingValue) { readingKey = "hoursRun" }  fulcrum2
fulcrum4 = consFulcrum firmware  (col_Op readingValue) { readingKey = "firmware" }  fulcrum3
fulcrum5 = consFulcrum lastFault (col_Op readingValue) { readingKey = "lastFault" } fulcrum4

pivoted = pivot fulcrum5 (asMem sensorReadings)

-- AND WHAT IT COSTS TO LEAVE THAT UNANNOTATED. `pivot`'s result row is not
-- determined by its arguments' types -- the Fulcrum's column list is a VALUE --
-- so the module publishes a residual instead of a type. The interface for
-- `pivoted` above is (measured 2026-09-06, `-Dermine.useInterface=true`):
--
--   pivoted : forall (s: rho). (exists RUnion2 v3 i v31 RUnion21 v32 v33
--                RUnion22 v34 RUnion23 RUnion24.
--       RUnion23 v31 v32 (|readingValue|),
--       (|assetId, readingKey, readingValue|) <- ((|readingKey|), v31, i),
--       RUnion22 v33 v34 (|readingValue|),
--       RUnion21 v32 v33 (|readingValue|),
--       RUnion2  v3  (|readingValue|) (|readingValue|),
--       RUnion24 v34 v3 (|readingValue|),
--       s <- ((|voltageV, lastFault, firmware, hoursRun, tempC|), i))
--     => Mem s
--
-- Eleven existentials and five `RUnion2`s -- ONE PER `consFulcrum` -- for a
-- five-column pivot. Every downstream use has to solve that set again. An
-- annotation discharges the whole thing and publishes a concrete row:
pivotedTyped : Mem (|assetId, voltageV, tempC, hoursRun, firmware, lastFault|)
pivotedTyped = pivot fulcrum5 (asMem sensorReadings)

-- ----------------------------------------- 3. do not widen: present it soft
--
-- A `SoftRelation` says how to turn a key column into headings and a value
-- column into cells. The relation stays three columns wide; the REPORT is what
-- gains a column per key. Nothing here mentions `voltageV` or `tempC` -- an
-- attribute added to the data tomorrow shows up without a recompile, which is
-- the whole trade.

private
  tf = flip (!)
  on' bin un x y = bin (un x) (un y)

type ReadingRel = SoftRelation String String (|readingKey|) (|readingValue|)

-- The default: keys in alphabetical order, values shown as they are, with
-- `voltageV` pinned to the left.
byKeyName : ReadingRel
byKeyName = softRelation readingKey (Left $ ordering {readingKey}) (pres . tf readingKey)
  where pres "voltageV" = (readingValue, Nothing) ^ 0
        pres _ = unsorted (readingValue, Nothing)

-- The same data with the operational order a technician wants, and the fault
-- string bracketed so an empty one is visible.
byUrgency : ReadingRel
byUrgency = softRelation readingKey (Right . fromLess $ on' urgent (tf readingKey))
                         (showingValues . pres . tf readingKey)
  where urgent "lastFault" _ = True
        urgent "tempC" "voltageV" = True
        urgent _ _ = False
        pres "lastFault" = [prim_Op "<", readingValue, prim_Op ">"]_Op
        pres _ = asOp_Op readingValue

aboutAsset : Legend_Lg (|assetId|)
aboutAsset = legend_Lg assetId "Asset"

-- ------------------------------------------------------------ the questions
--
-- The widened columns are all STRINGS -- that is what a key/value table costs
-- you, and it is why this cannot be "the hottest asset per site": `tempC`
-- would sort lexically. Rank on a column that really is ordered instead.
newestPerSite = groupTop {siteCode} {criticality} 1 (asMem assetWithReadings)

-- ---------------------------------------------------------------- the report

softReport = vflow [
  atomShown "## Asset telemetry: one soft table, three widenings",
  atomShown "### 1. Widened by hand, joined to the asset dimension",
  tabular Nothing assetWithReadings,
  atomShown "### 2. Widened by Relation.Pivot",
  tabular Nothing pivotedTyped,
  atomShown "### 3. Not widened at all -- the presentation does it",
  keyValueTabular byKeyName (Just aboutAsset) sensorReadings,
  atomShown "### The same, ordered the way a technician reads it",
  keyValueTabular byUrgency (Just aboutAsset) sensorReadings,
  atomShown "### Assets with no readings at all",
  tabular Nothing assetsWithNoReadings,
  atomShown "### Assets that do report",
  tabular Nothing assetsWithReadingsOnly,
  atomShown "### Least critical asset per site (ranking a column that is really ordered)",
  tabular Nothing newestPerSite
]
