module Ai.HeadcountPlan where

{- An organisation chart whose leaves are heterogeneous: a filled seat, a
   contractor, and an open requisition are all "headcount", but each reads
   differently, and only one of them has a person's name.

   Fact:       seats  (seatId, orgId, seatKind, fte, annualCost)
   Dimensions: person (seatId -> personName, startDate)
               org    (orgId  -> orgName, orgUnitId, parentOrgUnitId)

     >> :load core/examples/Ai/HeadcountPlan.e
     >> render headcountReport
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Ai.Common

field seatId, orgId : Int
field orgUnitId, parentOrgUnitId : Int
field seatKind, personName, orgName, reqStatus : String
field displayName, costCentreLabel : String
field fte, annualCost, costPerFte : Double
field value : Nullable Double

seats = relation [
  { seatId = 1, orgId = 110, seatKind = "employee",   fte = 1.0, annualCost = 185000.0 },
  { seatId = 2, orgId = 110, seatKind = "employee",   fte = 1.0, annualCost = 172000.0 },
  { seatId = 3, orgId = 110, seatKind = "contractor", fte = 0.6, annualCost =  96000.0 },
  { seatId = 4, orgId = 120, seatKind = "employee",   fte = 1.0, annualCost = 210000.0 },
  { seatId = 5, orgId = 120, seatKind = "open",       fte = 1.0, annualCost = 195000.0 },
  { seatId = 6, orgId = 210, seatKind = "open",       fte = 0.5, annualCost =  80000.0 }
]

personDim = relation [
  { seatId = 1, personName = "A. Okafor",    reqStatus = "filled" },
  { seatId = 2, personName = "B. Lindqvist", reqStatus = "filled" },
  { seatId = 3, personName = "C. Duarte",    reqStatus = "filled" },
  { seatId = 4, personName = "D. Nakamura",  reqStatus = "filled" },
  { seatId = 5, personName = "",             reqStatus = "approved" },
  { seatId = 6, personName = "",             reqStatus = "pending" }
]

orgDim = relation [
  { orgId = 110, orgName = "Platform Engineering" },
  { orgId = 120, orgName = "Data Engineering" },
  { orgId = 210, orgName = "Design" }
]

roster : [ seatId, orgId, seatKind, fte, annualCost, personName, reqStatus, orgName ]
roster = seats ** personDim ** orgDim

-- Cost per FTE, derived.
withUnitCost = combine_Op (col_Op annualCost /_Op col_Op fte) costPerFte roster

-- Employees read as a name; contractors are marked as such; open requisitions
-- have no name at all and read as the requisition state instead.
labelled =
  combine_Op
    (if_Op (col_Op seatKind ==_Pred prim_Op "employee")
           (col_Op personName)
           (if_Op (col_Op seatKind ==_Pred prim_Op "contractor")
                  (col_Op personName ++_Op prim_Op " (contract)")
                  (prim_Op "OPEN REQ - " ++_Op col_Op reqStatus ++_Op prim_Op " - " ++_Op col_Op orgName)))
    displayName
    roster

renamed = rename orgName costCentreLabel labelled

orgChart = relation [
  { orgUnitId = 1,   parentOrgUnitId = 0,  orgName = "Company",              value = Some 6.0 },
  { orgUnitId = 10,  parentOrgUnitId = 1,  orgName = "Technology",           value = Some 5.0 },
  { orgUnitId = 110, parentOrgUnitId = 10, orgName = "Platform Engineering", value = Some 3.0 },
  { orgUnitId = 120, parentOrgUnitId = 10, orgName = "Data Engineering",     value = Some 2.0 },
  { orgUnitId = 20,  parentOrgUnitId = 1,  orgName = "Product",              value = Some 1.0 },
  { orgUnitId = 210, parentOrgUnitId = 20, orgName = "Design",               value = Some 1.0 }
]

orgTree = treeTable orgName parentOrgUnitId orgUnitId orgChart

fteChart =
  pieChart_K
    ([pieTitle_O := "FTE by Organisation",
      pieDrilldown_O := (parentOrgUnitId, orgUnitId)]_Opt)
    orgName value orgChart

summary = grid [
  [atomShown "Seats",       atomShown "6"],
  [atomShown "Filled",      atomShown "4"],
  [atomShown "Open reqs",   atomShown "2"],
  [atomShown "Contractors", atomShown "1"]
]

headcountReport = vflow [
  atomShown "## Headcount Plan",
  summary,
  fteChart,
  orgTree,
  atomShown "### Seat detail (employee / contractor / open req)",
  tabular Nothing renamed
]
