module Algebra.BillOfMaterials where

{- A BILL OF MATERIALS EXPLODED: transitive closure, leaves, and a cost
   roll-up over the same parent/child columns.

   A BOM is a tree of POSITIONS, not of parts: the same part appears at several
   places in the product and each place is its own node with its own quantity.
   So the hierarchy columns are `bomNodeId` / `parentBomNodeId` and the part is
   an ordinary attribute -- which is what makes the generic tree helpers apply
   to it at all.

   Fact:      bom       (bomNodeId, parentBomNodeId, partId, qtyPer,
                         positionRef, scrapPct, isOptional)
   Dimension: partDim   (12 columns: partId, partName, partKind, uom,
                         revision, unitCostEur, leadTimeDays, supplierId,
                         hazardClass, isPhantom, weightKg, obsolete)
   Derived:   nodeCost  (bomNodeId, extCost)

   Helpers used: closure, composeEdges, leaves, carry, alias, groupSum,
                 semiJoin.
   Stdlib exercised: `Relation.leafRows`, `Relation.RTree` (`rtreeAt`,
                 `level1`, `root`, `leaves` -- no example used this module
                 before), `Native.Relation.accumulate`, `Relation.copyColumn`.

   SOLVER SHAPES. `closure` is a RECURSIVE definition carrying a partition
   constraint, so `e <- (from, to)` is discharged at the recursive call as well
   as at the top; `composeEdges` renames a column to a GUID-named scratch
   column minted by `withFieldCopy`, joins on it and projects it away, which
   makes the solver reason about a label it has never seen in any header. The
   `RTree` constructor carries a `Predicate` alongside two `Field`s, so its
   three row variables are related only through the predicate's row.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/BillOfMaterials.e
     >> :import Algebra.BillOfMaterials
     >> reachable
     >> bomReport
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Relation.RTree as RT
import Syntax.Relation
import Algebra.Helpers

field bomNodeId, parentBomNodeId, partId, supplierId, leadTimeDays : Int
field ancestorNodeId : Int
field positionRef, partName, partKind, uom, revision, hazardClass : String
field isOptional, isPhantom, obsolete : String
field qtyPer, scrapPct, unitCostEur, weightKg, extCost, rolledCostEur : Double

-- ---------------------------------------------------------------- the tree
--
-- Node 1 is the finished product. 0 is the conventional "no parent" sentinel.

bom : [bomNodeId, parentBomNodeId, partId, qtyPer, positionRef, scrapPct, isOptional]
bom = relation [
  { bomNodeId = 1,  parentBomNodeId = 0,  partId = 5100, qtyPer = 1.0,  positionRef = "top",     scrapPct = 0.00, isOptional = "no" },
  { bomNodeId = 2,  parentBomNodeId = 1,  partId = 5200, qtyPer = 1.0,  positionRef = "A-frame", scrapPct = 0.01, isOptional = "no" },
  { bomNodeId = 3,  parentBomNodeId = 1,  partId = 5300, qtyPer = 1.0,  positionRef = "B-top",   scrapPct = 0.02, isOptional = "no" },
  { bomNodeId = 4,  parentBomNodeId = 1,  partId = 5400, qtyPer = 1.0,  positionRef = "C-elec",  scrapPct = 0.00, isOptional = "yes" },
  { bomNodeId = 5,  parentBomNodeId = 2,  partId = 5210, qtyPer = 4.0,  positionRef = "leg",     scrapPct = 0.00, isOptional = "no" },
  { bomNodeId = 6,  parentBomNodeId = 2,  partId = 5220, qtyPer = 2.0,  positionRef = "rail",    scrapPct = 0.03, isOptional = "no" },
  { bomNodeId = 7,  parentBomNodeId = 2,  partId = 5230, qtyPer = 16.0, positionRef = "bolt",    scrapPct = 0.05, isOptional = "no" },
  { bomNodeId = 8,  parentBomNodeId = 5,  partId = 5211, qtyPer = 1.0,  positionRef = "foot",    scrapPct = 0.00, isOptional = "no" },
  { bomNodeId = 9,  parentBomNodeId = 5,  partId = 5212, qtyPer = 1.0,  positionRef = "glide",   scrapPct = 0.00, isOptional = "yes" },
  { bomNodeId = 10, parentBomNodeId = 3,  partId = 5310, qtyPer = 1.0,  positionRef = "laminate",scrapPct = 0.08, isOptional = "no" },
  { bomNodeId = 11, parentBomNodeId = 3,  partId = 5320, qtyPer = 2.0,  positionRef = "edge",    scrapPct = 0.04, isOptional = "no" },
  { bomNodeId = 12, parentBomNodeId = 4,  partId = 5410, qtyPer = 1.0,  positionRef = "psu",     scrapPct = 0.00, isOptional = "no" },
  { bomNodeId = 13, parentBomNodeId = 4,  partId = 5420, qtyPer = 3.0,  positionRef = "cable",   scrapPct = 0.02, isOptional = "no" },
  { bomNodeId = 14, parentBomNodeId = 12, partId = 5411, qtyPer = 1.0,  positionRef = "fuse",    scrapPct = 0.00, isOptional = "no" }
]

-- ------------------------------------------------------------ the dimension

partDim : [ partId, partName, partKind, uom, revision, unitCostEur
          , leadTimeDays, supplierId, hazardClass, isPhantom, weightKg
          , obsolete ]
partDim = relation [
  { partId = 5100, partName = "Standing desk, 180cm", partKind = "assembly", uom = "ea", revision = "C", unitCostEur =   0.00, leadTimeDays =  0, supplierId = 0,    hazardClass = "none", isPhantom = "no",  weightKg = 0.0,  obsolete = "no" },
  { partId = 5200, partName = "Frame assembly",       partKind = "assembly", uom = "ea", revision = "B", unitCostEur =   0.00, leadTimeDays =  0, supplierId = 0,    hazardClass = "none", isPhantom = "no",  weightKg = 0.0,  obsolete = "no" },
  { partId = 5300, partName = "Top assembly",         partKind = "assembly", uom = "ea", revision = "A", unitCostEur =   0.00, leadTimeDays =  0, supplierId = 0,    hazardClass = "none", isPhantom = "yes", weightKg = 0.0,  obsolete = "no" },
  { partId = 5400, partName = "Electrics kit",        partKind = "assembly", uom = "ea", revision = "D", unitCostEur =   0.00, leadTimeDays =  0, supplierId = 0,    hazardClass = "none", isPhantom = "no",  weightKg = 0.0,  obsolete = "no" },
  { partId = 5210, partName = "Leg, telescopic",      partKind = "made",     uom = "ea", revision = "F", unitCostEur =  61.20, leadTimeDays = 21, supplierId = 8801, hazardClass = "none", isPhantom = "no",  weightKg = 3.4,  obsolete = "no" },
  { partId = 5220, partName = "Cross rail, 1.6m",     partKind = "bought",   uom = "ea", revision = "A", unitCostEur =  18.75, leadTimeDays = 14, supplierId = 8801, hazardClass = "none", isPhantom = "no",  weightKg = 2.1,  obsolete = "no" },
  { partId = 5230, partName = "Bolt M8x40",           partKind = "bought",   uom = "ea", revision = "-", unitCostEur =   0.14, leadTimeDays =  7, supplierId = 8802, hazardClass = "none", isPhantom = "no",  weightKg = 0.02, obsolete = "no" },
  { partId = 5211, partName = "Foot, cast",           partKind = "bought",   uom = "ea", revision = "B", unitCostEur =   4.05, leadTimeDays = 30, supplierId = 8803, hazardClass = "none", isPhantom = "no",  weightKg = 0.6,  obsolete = "no" },
  { partId = 5212, partName = "Glide pad",            partKind = "bought",   uom = "ea", revision = "A", unitCostEur =   0.31, leadTimeDays =  5, supplierId = 8802, hazardClass = "none", isPhantom = "no",  weightKg = 0.01, obsolete = "yes" },
  { partId = 5310, partName = "Laminate sheet",       partKind = "bought",   uom = "m2", revision = "C", unitCostEur =  37.40, leadTimeDays = 18, supplierId = 8804, hazardClass = "none", isPhantom = "no",  weightKg = 9.8,  obsolete = "no" },
  { partId = 5320, partName = "Edge banding, 2m",     partKind = "bought",   uom = "ea", revision = "A", unitCostEur =   2.60, leadTimeDays = 10, supplierId = 8804, hazardClass = "none", isPhantom = "no",  weightKg = 0.3,  obsolete = "no" },
  { partId = 5410, partName = "PSU, 24V 90W",         partKind = "bought",   uom = "ea", revision = "E", unitCostEur =  44.90, leadTimeDays = 45, supplierId = 8805, hazardClass = "elec", isPhantom = "no",  weightKg = 0.9,  obsolete = "no" },
  { partId = 5420, partName = "Cable, 1.5m",          partKind = "bought",   uom = "ea", revision = "B", unitCostEur =   1.95, leadTimeDays = 12, supplierId = 8805, hazardClass = "none", isPhantom = "no",  weightKg = 0.12, obsolete = "no" },
  { partId = 5411, partName = "Fuse, 5A",             partKind = "bought",   uom = "ea", revision = "A", unitCostEur =   0.22, leadTimeDays =  9, supplierId = 8805, hazardClass = "elec", isPhantom = "no",  weightKg = 0.01, obsolete = "no" }
]

-- ------------------------------------------------- the explosion (closure)
--
-- `closure` wants an edge relation and NOTHING ELSE -- `e <- (from, to)` says
-- the row is exactly the two id columns -- so project first. Four rounds of
-- path doubling cover any path of length 16; this tree is four deep.

bomEdges : [parentBomNodeId, bomNodeId]
bomEdges = bom # {parentBomNodeId, bomNodeId}

reachable = closure parentBomNodeId bomNodeId 4 bomEdges

-- one composition step on its own, for comparison: the grandchild edges
grandchildren = composeEdges parentBomNodeId bomNodeId bomEdges bomEdges

-- Everything under the frame assembly (node 2), named as ancestor/descendant
-- rather than parent/child now that the edges are transitive.
underFrame = alias parentBomNodeId ancestorNodeId (filterEq parentBomNodeId 2 reachable)

-- ------------------------------------------------------------- the leaves
--
-- Two spellings of the same idea. `leaves` is `Relation.leafRows`: remove
-- every row whose node id is somebody's parent id.

purchasedPositions = leaves parentBomNodeId bomNodeId bom

-- and the `Relation.RTree` spelling, which bundles the two fields with a root
-- predicate into one value that the tree operations then take
frameTree = rtreeAt_RT bomNodeId parentBomNodeId 2
frameRoot     = root_RT   frameTree bom
frameChildren = level1_RT frameTree bom
frameLeaves   = leaves_RT frameTree bom

-- ---------------------------------------------------------- the cost roll-up
--
-- Extended cost of each position, then `accumulate` sums it up the tree, so
-- every assembly node carries the cost of everything beneath it.

positionCost =
  combine_Op (col_Op qtyPer *_Op col_Op unitCostEur *_Op
              (prim_Op 1.0 +_Op col_Op scrapPct))
             extCost
             (bom ** partDim)

nodeCost : Mem (|bomNodeId, extCost|)
nodeCost = asMem (positionCost # {bomNodeId, extCost})

rolledUp =
  accumulate parentBomNodeId bomNodeId
             (aggregate_Agg (sum_Agg extCost) extCost)
             nodeCost
             (asMem (bom # {parentBomNodeId, bomNodeId, partId}))

-- `carry` copies a column rather than moving it, so the roll-up can be shown
-- next to the position's own cost.
rolledUpNamed = carry extCost rolledCostEur (join rolledUp (asMem (bom ** partDim)))

-- -------------------------------------------------------- supplier exposure
--
-- Which suppliers a subtree depends on: semi-join the part dimension against
-- the descendants of one node.
frameParts = semiJoin {bomNodeId} (filterEq parentBomNodeId 2 reachable) bom
frameSuppliers = groupSum {supplierId} extCost (semiJoin {bomNodeId} frameParts positionCost)

-- ---------------------------------------------------------------- the report

bomReport = vflow [
  atomShown "## Bill of materials",
  atomShown "### Positions (the tree)",
  drilldownTable Nothing positionRef parentBomNodeId bomNodeId (bom ** partDim),
  atomShown "### Transitive closure: every ancestor/descendant pair",
  tabular Nothing reachable,
  atomShown "### One composition step only: the grandchild edges",
  tabular Nothing grandchildren,
  atomShown "### Everything under the frame assembly",
  tabular Nothing underFrame,
  atomShown "### Leaves: the positions that are bought, not made",
  tabular Nothing purchasedPositions,
  atomShown "### The same, via Relation.RTree",
  tabular Nothing frameLeaves,
  atomShown "### Rolled-up cost per node",
  tabular Nothing rolledUp,
  atomShown "### Supplier exposure of the frame subtree",
  tabular Nothing frameSuppliers
]
