module Algebra.InventorySnapshots where

{- TWO SNAPSHOTS OF THE SAME TABLE, RECONCILED: what was added, what was
   removed, what is unchanged, and what changed without changing key.

   Set operations are the part of relational algebra Ermine expresses most
   directly and the part the examples covered least. There are only two
   primitives -- `union` and `difference`, both demanding IDENTICAL headers on
   both sides -- and everything else is built from them plus `join`:

     intersection  =  join            (identical headers -> the common rows)
     A \ B         =  difference A B
     symmetric     =  union (A \ B) (B \ A)
     changed keys  =  (A \ B) semi-joined against (B \ A) on the key

   That last one is the interesting case and the reason a diff is not just two
   differences: a row whose quantity moved appears in BOTH one-sided
   differences, and only the key tells you it is one row changed rather than
   two rows swapped.

   Tables: stockMonday, stockFriday -- the same 14 columns
             sku, warehouseId, binCode, lotNumber, onHandQty, allocatedQty,
             availableQty, unitCostEur, lastCountDate, ownerCode,
             conditionCode, uom, expiryDate, cycleCountDue

   Helpers used: unionRows, exceptRows, intersectRows, semiJoin, antiJoin, groupSum,
                 groupTop.
   Stdlib exercised: `Relation.union`, `Relation.difference`,
                 `Relation.unionAll`, `Relation.unionAllWithHeader` (the
                 empty-safe form, which no example used before),
                 `Relation.relationWithHeader`.

   SOLVER SHAPES. Every set operation here forces the solver to prove two
   14-column CONCRETE headers equal -- there is no row variable to hide behind,
   so this is the `concrete` branch at its widest and its most repetitive
   (fourteen set operations over the same header). `unionAllWithHeader` adds a
   `Row` witness that must be proved equal to that header as well.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/InventorySnapshots.e
     >> :import Algebra.InventorySnapshots
     >> reconciliationReport
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Algebra.Helpers

field warehouseId, lotNumber, cycleCountDue : Int
field sku, binCode, lastCountDate, ownerCode, conditionCode, uom : String
field expiryDate, changeKind : String
field onHandQty, allocatedQty, availableQty, unitCostEur : Double
field deltaQty, valueEur : Double

type StockRow = [ sku, warehouseId, binCode, lotNumber, onHandQty, allocatedQty
                , availableQty, unitCostEur, lastCountDate, ownerCode
                , conditionCode, uom, expiryDate, cycleCountDue ]

-- The row identity is (sku, warehouseId, binCode, lotNumber): a bin can hold
-- more than one lot of the same sku.
stockKey : Row (|sku, warehouseId, binCode, lotNumber|)
stockKey = {sku, warehouseId, binCode, lotNumber}

stockMonday : StockRow
stockMonday = relation [
  { sku = "LMP-0041", warehouseId = 7001, binCode = "A-01-1", lotNumber = 5511, onHandQty = 480.0, allocatedQty =  40.0, availableQty = 440.0, unitCostEur =  22.10, lastCountDate = "2026-01-12", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "",           cycleCountDue = 90 },
  { sku = "CHR-2210", warehouseId = 7001, binCode = "A-02-3", lotNumber = 5512, onHandQty =  36.0, allocatedQty =   6.0, availableQty =  30.0, unitCostEur = 148.00, lastCountDate = "2026-01-12", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "",           cycleCountDue = 90 },
  { sku = "BAT-9001", warehouseId = 7001, binCode = "B-11-2", lotNumber = 5513, onHandQty = 900.0, allocatedQty = 120.0, availableQty = 780.0, unitCostEur =   1.85, lastCountDate = "2026-01-05", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "2027-03-01", cycleCountDue = 30 },
  { sku = "BAT-9001", warehouseId = 7001, binCode = "B-11-2", lotNumber = 5514, onHandQty = 150.0, allocatedQty =   0.0, availableQty = 150.0, unitCostEur =   1.90, lastCountDate = "2026-01-05", ownerCode = "OWN", conditionCode = "quarantine", uom = "ea", expiryDate = "2026-09-01", cycleCountDue = 30 },
  { sku = "STL-0500", warehouseId = 7002, binCode = "Y-03-1", lotNumber = 5515, onHandQty =  12.0, allocatedQty =   2.0, availableQty =  10.0, unitCostEur = 310.00, lastCountDate = "2025-12-30", ownerCode = "CON", conditionCode = "good", uom = "ea", expiryDate = "",           cycleCountDue = 180 },
  { sku = "INK-3300", warehouseId = 7002, binCode = "Y-04-2", lotNumber = 5516, onHandQty = 220.0, allocatedQty =  20.0, availableQty = 200.0, unitCostEur =  14.40, lastCountDate = "2025-12-30", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "2026-11-15", cycleCountDue = 60 }
]

-- Friday: BAT-9001/5514 was scrapped, a new pallet of TAP-1000 arrived, the
-- LMP-0041 count moved, and INK-3300 changed condition after a spill.
stockFriday : StockRow
stockFriday = relation [
  { sku = "LMP-0041", warehouseId = 7001, binCode = "A-01-1", lotNumber = 5511, onHandQty = 455.0, allocatedQty =  40.0, availableQty = 415.0, unitCostEur =  22.10, lastCountDate = "2026-01-16", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "",           cycleCountDue = 90 },
  { sku = "CHR-2210", warehouseId = 7001, binCode = "A-02-3", lotNumber = 5512, onHandQty =  36.0, allocatedQty =   6.0, availableQty =  30.0, unitCostEur = 148.00, lastCountDate = "2026-01-12", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "",           cycleCountDue = 90 },
  { sku = "BAT-9001", warehouseId = 7001, binCode = "B-11-2", lotNumber = 5513, onHandQty = 900.0, allocatedQty = 120.0, availableQty = 780.0, unitCostEur =   1.85, lastCountDate = "2026-01-05", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "2027-03-01", cycleCountDue = 30 },
  { sku = "STL-0500", warehouseId = 7002, binCode = "Y-03-1", lotNumber = 5515, onHandQty =  12.0, allocatedQty =   2.0, availableQty =  10.0, unitCostEur = 310.00, lastCountDate = "2025-12-30", ownerCode = "CON", conditionCode = "good", uom = "ea", expiryDate = "",           cycleCountDue = 180 },
  { sku = "INK-3300", warehouseId = 7002, binCode = "Y-04-2", lotNumber = 5516, onHandQty = 220.0, allocatedQty =  20.0, availableQty = 200.0, unitCostEur =  14.40, lastCountDate = "2025-12-30", ownerCode = "OWN", conditionCode = "damaged", uom = "ea", expiryDate = "2026-11-15", cycleCountDue = 60 },
  { sku = "TAP-1000", warehouseId = 7002, binCode = "Y-06-1", lotNumber = 5517, onHandQty = 500.0, allocatedQty =   0.0, availableQty = 500.0, unitCostEur =   0.95, lastCountDate = "2026-01-15", ownerCode = "OWN", conditionCode = "good", uom = "ea", expiryDate = "",           cycleCountDue = 60 }
]

-- ------------------------------------------------------- the three set facts

-- Rows present on Monday and gone by Friday (whole row, all 14 columns).
goneByFriday = exceptRows stockMonday stockFriday

-- Rows that appeared.
newOnFriday = exceptRows stockFriday stockMonday

-- Rows that did not move at all. `intersectRows` IS `join`: identical headers
-- means the natural join has every column as its key.
unchanged = intersectRows stockMonday stockFriday

-- The symmetric difference: everything that is not in `unchanged`.
allChanges = unionRows goneByFriday newOnFriday

-- ------------------------------------------------- added / removed / changed
--
-- A one-sided difference cannot tell "removed" from "changed": both put the
-- Monday row in `goneByFriday`. The key decides.

changedKeys = semiJoin stockKey newOnFriday goneByFriday   -- Monday side
changedKeysNew = semiJoin stockKey goneByFriday newOnFriday -- Friday side
trulyRemoved = antiJoin stockKey newOnFriday goneByFriday
trulyAdded   = antiJoin stockKey goneByFriday newOnFriday

-- The three-way split is exact: `changedKeys`, `trulyRemoved` and the
-- unchanged rows partition Monday's snapshot.
mondayAccountedFor = unionRows (unionRows changedKeys trulyRemoved) unchanged
mondayLeftOver     = exceptRows stockMonday mondayAccountedFor  -- empty

-- ----------------------------------------------------------- what changed by

-- Both sides of one changed row, side by side, needs the columns to stop
-- colliding first: keep the key and the quantity, rename the quantity per side.
mondayQty = alias onHandQty deltaQty (changedKeys # {sku, warehouseId, binCode, lotNumber, onHandQty})
fridayQty = changedKeysNew # {sku, warehouseId, binCode, lotNumber, onHandQty}
qtyMoves  = combine_Op (col_Op onHandQty -_Op col_Op deltaQty) availableQty
                       (joinOnExactly stockKey mondayQty fridayQty)

-- ------------------------------------------------- unions over a list, safely

-- `unionAll` folds a list; on the EMPTY list it produces a relation with no
-- header at all, which then fails to join with anything. `unionAllWithHeader`
-- takes a `Row` witness so the empty case still has the right shape -- worth
-- the extra argument whenever the list is computed rather than written out.
everything    = unionAll [stockMonday, stockFriday]
nothingSafely = unionAllWithHeader (rheader stockMonday) []
nothingRisky  = unionAll []

-- ------------------------------------------------------------- the valuation

-- Named for the snapshot it values: `valued` is also a top-level binding in
-- `Algebra/KeyDiscipline.e`, and the two clash in the whole-group session
-- `Algebra/README.md` tells you to open.
fridayValued = combine_Op (col_Op onHandQty *_Op col_Op unitCostEur) valueEur stockFriday
valueByWarehouse = groupSum {warehouseId} valueEur fridayValued
biggestLots = groupTop {warehouseId} {valueEur} 2 fridayValued

-- ---------------------------------------------------------------- the report

reconciliationReport = vflow [
  atomShown "## Inventory reconciliation, Monday against Friday",
  atomShown "### Unchanged rows (the intersection)",
  tabular Nothing unchanged,
  atomShown "### Removed (gone, and no row with that key came back)",
  tabular Nothing trulyRemoved,
  atomShown "### Added (new key)",
  tabular Nothing trulyAdded,
  atomShown "### Changed (same key, different row) -- Monday side",
  tabular Nothing changedKeys,
  atomShown "### Changed -- Friday side",
  tabular Nothing changedKeysNew,
  atomShown "### Quantity movement on the changed rows",
  tabular Nothing qtyMoves,
  atomShown "### Nothing left over: Monday minus (changed + removed + unchanged)",
  tabular Nothing mondayLeftOver,
  atomShown "### Friday valuation by warehouse",
  tabular Nothing valueByWarehouse,
  atomShown "### Two biggest lots per warehouse",
  tabular Nothing biggestLots
]
