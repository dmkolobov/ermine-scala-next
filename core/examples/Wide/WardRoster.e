module Wide.WardRoster where

{- FOUR GENERIC HELPERS COMPOSED, so that each one's OUTPUT row is the next
   one's INPUT row.

   Every other module in this directory calls its helpers on the same base
   relation.  This one chains them: `rowNumberWithin` mints a row, `runningTotal`
   is applied to THAT row and mints another, `windowTotal` is applied to the
   second and mints a third, and `withDerived2` is applied to the third.  Each
   link instantiates the previous link's existential remainder, so the solver
   sees a chain of partition constraints four deep rather than four independent
   ones.  Section 4 of `tracker/loopmodel/E1-EXAMPLES.md` measures what that does
   to the solver's own derivation depth, against the existing corpus.

   It is also how a real roster report is written.  Nobody computes a shift
   index, a cumulative overtime figure and a ward share in three separate
   passes; they write one pipeline.

   Fact:       shift (24 columns)
                 keys      shiftId, wardId, staffId, gradeId
                 clock     shiftStart, shiftEnd, plannedHours, workedHours,
                           overtimeHours, breakMinutes
                 cost      baseCost, overtimeCost, agencyCost, oncallCost,
                           allowanceCost
                 load      patientCount, admissions, discharges, acuityScore,
                           incidentCount
                 quality   handoverMinutes, lateStartMinutes, sicknessFlag,
                           bankHolidayFlag
   Dimensions: ward  (wardId  -> wardName, specialty, bedCount)
               staff (staffId -> staffName, gradeName, contractType)

   Helpers used: rowNumberWithin, runningTotal, windowTotal, withDerived2,
                 withDerived3, asc (Wide.Helpers).

   Solver shapes exercised:
     * a FOUR-LINK chain of helper applications, each solving against the row the
       previous link minted;
     * `withDerived2` and `withDerived3`, the two helpers that deliberately
       bundle more than one row union in a single signature -- the shape
       `Ai/Common.e` warns about, measured here at the adopted defaults;
     * the whole chain applied to a 30-column joined row.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/WardRoster.e
     >> :type rosterPipeline
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field shiftId, wardId, staffId, gradeId : Int
field patientCount, admissions, discharges, incidentCount : Int
field breakMinutes, handoverMinutes, lateStartMinutes, bedCount : Int
field shiftStart, shiftEnd : Date
field plannedHours, workedHours, overtimeHours, acuityScore : Double
field baseCost, overtimeCost, agencyCost, oncallCost, allowanceCost : Double
field sicknessFlag, bankHolidayFlag : String
field wardName, specialty, staffName, gradeName, contractType : String
field shiftIndex : Int
field cumulativeOvertime, wardAgencyTotal, agencySharePct : Double
field totalCost, agencyPerAcuity, utilisationPct : Double

-- Twenty-four columns, nine shifts across two wards, in date order.
shift = relation [
  { shiftId = 1, wardId = 1, staffId = 100, gradeId = 5,
    shiftStart = yyyymmdd 2025 6 2, shiftEnd = yyyymmdd 2025 6 2,
    plannedHours = 12.0, workedHours = 12.5, overtimeHours = 0.5, breakMinutes = 45,
    baseCost = 384.0, overtimeCost = 24.0, agencyCost = 0.0, oncallCost = 0.0,
    allowanceCost = 18.0,
    patientCount = 24, admissions = 5, discharges = 4, acuityScore = 3.1,
    incidentCount = 0, handoverMinutes = 22, lateStartMinutes = 0,
    sicknessFlag = "no", bankHolidayFlag = "no" },
  { shiftId = 2, wardId = 1, staffId = 101, gradeId = 4,
    shiftStart = yyyymmdd 2025 6 3, shiftEnd = yyyymmdd 2025 6 3,
    plannedHours = 12.0, workedHours = 14.0, overtimeHours = 2.0, breakMinutes = 30,
    baseCost = 312.0, overtimeCost = 104.0, agencyCost = 0.0, oncallCost = 60.0,
    allowanceCost = 18.0,
    patientCount = 26, admissions = 7, discharges = 3, acuityScore = 3.6,
    incidentCount = 1, handoverMinutes = 35, lateStartMinutes = 12,
    sicknessFlag = "no", bankHolidayFlag = "no" },
  { shiftId = 3, wardId = 1, staffId = 102, gradeId = 3,
    shiftStart = yyyymmdd 2025 6 4, shiftEnd = yyyymmdd 2025 6 4,
    plannedHours = 12.0, workedHours = 12.0, overtimeHours = 0.0, breakMinutes = 45,
    baseCost = 0.0, overtimeCost = 0.0, agencyCost = 588.0, oncallCost = 0.0,
    allowanceCost = 0.0,
    patientCount = 25, admissions = 4, discharges = 6, acuityScore = 3.0,
    incidentCount = 0, handoverMinutes = 18, lateStartMinutes = 0,
    sicknessFlag = "yes", bankHolidayFlag = "no" },
  { shiftId = 4, wardId = 1, staffId = 100, gradeId = 5,
    shiftStart = yyyymmdd 2025 6 5, shiftEnd = yyyymmdd 2025 6 5,
    plannedHours = 12.0, workedHours = 13.0, overtimeHours = 1.0, breakMinutes = 45,
    baseCost = 384.0, overtimeCost = 48.0, agencyCost = 0.0, oncallCost = 0.0,
    allowanceCost = 18.0,
    patientCount = 23, admissions = 3, discharges = 5, acuityScore = 2.8,
    incidentCount = 0, handoverMinutes = 20, lateStartMinutes = 0,
    sicknessFlag = "no", bankHolidayFlag = "no" },
  { shiftId = 5, wardId = 1, staffId = 103, gradeId = 3,
    shiftStart = yyyymmdd 2025 6 6, shiftEnd = yyyymmdd 2025 6 6,
    plannedHours = 12.0, workedHours = 12.0, overtimeHours = 0.0, breakMinutes = 45,
    baseCost = 0.0, overtimeCost = 0.0, agencyCost = 612.0, oncallCost = 0.0,
    allowanceCost = 0.0,
    patientCount = 27, admissions = 8, discharges = 2, acuityScore = 3.9,
    incidentCount = 2, handoverMinutes = 41, lateStartMinutes = 25,
    sicknessFlag = "no", bankHolidayFlag = "no" },
  { shiftId = 6, wardId = 2, staffId = 200, gradeId = 6,
    shiftStart = yyyymmdd 2025 6 2, shiftEnd = yyyymmdd 2025 6 2,
    plannedHours = 10.0, workedHours = 10.0, overtimeHours = 0.0, breakMinutes = 40,
    baseCost = 420.0, overtimeCost = 0.0, agencyCost = 0.0, oncallCost = 90.0,
    allowanceCost = 24.0,
    patientCount = 14, admissions = 2, discharges = 2, acuityScore = 4.4,
    incidentCount = 0, handoverMinutes = 26, lateStartMinutes = 0,
    sicknessFlag = "no", bankHolidayFlag = "no" },
  { shiftId = 7, wardId = 2, staffId = 201, gradeId = 5,
    shiftStart = yyyymmdd 2025 6 3, shiftEnd = yyyymmdd 2025 6 3,
    plannedHours = 10.0, workedHours = 11.5, overtimeHours = 1.5, breakMinutes = 40,
    baseCost = 350.0, overtimeCost = 78.0, agencyCost = 0.0, oncallCost = 0.0,
    allowanceCost = 24.0,
    patientCount = 15, admissions = 3, discharges = 1, acuityScore = 4.7,
    incidentCount = 1, handoverMinutes = 31, lateStartMinutes = 8,
    sicknessFlag = "no", bankHolidayFlag = "no" },
  { shiftId = 8, wardId = 2, staffId = 202, gradeId = 4,
    shiftStart = yyyymmdd 2025 6 4, shiftEnd = yyyymmdd 2025 6 4,
    plannedHours = 10.0, workedHours = 10.0, overtimeHours = 0.0, breakMinutes = 40,
    baseCost = 0.0, overtimeCost = 0.0, agencyCost = 495.0, oncallCost = 0.0,
    allowanceCost = 0.0,
    patientCount = 16, admissions = 4, discharges = 3, acuityScore = 4.2,
    incidentCount = 0, handoverMinutes = 24, lateStartMinutes = 0,
    sicknessFlag = "yes", bankHolidayFlag = "no" },
  { shiftId = 9, wardId = 2, staffId = 200, gradeId = 6,
    shiftStart = yyyymmdd 2025 6 5, shiftEnd = yyyymmdd 2025 6 5,
    plannedHours = 10.0, workedHours = 12.0, overtimeHours = 2.0, breakMinutes = 40,
    baseCost = 420.0, overtimeCost = 116.0, agencyCost = 0.0, oncallCost = 90.0,
    allowanceCost = 24.0,
    patientCount = 15, admissions = 1, discharges = 4, acuityScore = 4.0,
    incidentCount = 0, handoverMinutes = 19, lateStartMinutes = 0,
    sicknessFlag = "no", bankHolidayFlag = "no" }
]

wardDim = relation [
  { wardId = 1, wardName = "Ash",   specialty = "General medicine", bedCount = 28 },
  { wardId = 2, wardName = "Birch", specialty = "High dependency",  bedCount = 16 }
]

staffDim = relation [
  { staffId = 100, staffName = "A. Whitlock", gradeName = "Band 6", contractType = "Permanent" },
  { staffId = 101, staffName = "D. Serrano",  gradeName = "Band 5", contractType = "Permanent" },
  { staffId = 102, staffName = "F. Nkemelu",  gradeName = "Band 5", contractType = "Agency" },
  { staffId = 103, staffName = "G. Petrides", gradeName = "Band 5", contractType = "Agency" },
  { staffId = 200, staffName = "H. Mbeki",    gradeName = "Band 7", contractType = "Permanent" },
  { staffId = 201, staffName = "J. Karlsen",  gradeName = "Band 6", contractType = "Permanent" },
  { staffId = 202, staffName = "K. Ozturk",   gradeName = "Band 6", contractType = "Agency" }
]

-- Thirty columns after the joins.
roster = shift ** wardDim ** staffDim

-- ------------------------------------------------------------- the pipeline
--
-- Four links.  Read it downwards: each definition is the previous one plus one
-- column, and each helper's row variable is instantiated to the row the link
-- before it produced.

-- 1. Which shift is this, within its ward, in date order?
withIndex = rowNumberWithin {wardName} (asc shiftStart) shiftIndex roster

-- 2. Overtime accumulated so far in this ward -- on the row link 1 minted.
withCumulative =
  runningTotal {wardName} (asc shiftStart) overtimeHours cumulativeOvertime withIndex

-- 3. The ward's whole agency bill, repeated per row -- on link 2's row.
withWardAgency = windowTotal {wardName} agencyCost wardAgencyTotal withCumulative

-- 4. Two ordinary derived columns in one call, on link 3's row: the agency
--    share of this shift's total spend, and the total itself.
rosterPipeline =
  withDerived2 (col_Op baseCost +_Op col_Op overtimeCost +_Op col_Op agencyCost)
               totalCost
               (col_Op agencyCost /_Op col_Op wardAgencyTotal)
               agencySharePct
               withWardAgency

-- The three-column form, on the base relation, for the measurement in the
-- report: three unions in ONE signature rather than three signatures with one
-- each.
rosterDerived3 =
  withDerived3 (col_Op baseCost +_Op col_Op overtimeCost +_Op col_Op agencyCost)
               totalCost
               (col_Op workedHours /_Op col_Op plannedHours)
               utilisationPct
               (col_Op agencyCost /_Op col_Op acuityScore)
               agencyPerAcuity
               roster

rosterReport = vflow [
  atomShown "## Ward roster",
  atomShown "### The pipeline: index, cumulative overtime, ward agency spend, share",
  tabular Nothing
    (rosterPipeline # { wardName, shiftStart, staffName, shiftIndex, overtimeHours,
                        cumulativeOvertime, agencyCost, wardAgencyTotal,
                        totalCost, agencySharePct }),
  atomShown "### Three derived columns in one call",
  tabular Nothing
    (rosterDerived3 # { wardName, staffName, totalCost, utilisationPct, agencyPerAcuity }),
  atomShown "### Shifts",
  tabular Nothing
    (roster # { wardName, shiftStart, staffName, gradeName, contractType,
                workedHours, overtimeHours, patientCount })
]
