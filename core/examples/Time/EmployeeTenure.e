module Time.EmployeeTenure where

{- AN EMPLOYEE TENURE AND AGE-BAND REPORT: three different date questions about
   the same eighteen-column roster, none of which the relational algebra can
   answer with a date accessor because it has none.

     "How long has this person been here?"    -- a difference to a fixed date
     "Which age band are they in?"            -- a difference, then a banding
     "Which hiring campaign did they join in?"-- a RANGE join to a calendar
     "What was the salary band policy then?"  -- an AS-OF lookup

   Fact:     roster        (18 fields: employeeId, givenName, familyName,
                            department, subDepartment, jobFamily, jobLevel,
                            location, country, employmentType, unionFlag,
                            workPattern, managerId, fteScale, hireDate,
                            birthDate, salary, bonusPct (NULLABLE))
   Calendar: hiringWaves   (waveStart, waveEnd, waveName, waveOwner)
   History:  bandPolicy    (policyDate, jobLevel, bandMin, bandMax) -- REVISED
                            three times, and a June report must use the June
                            revision, not the latest one in the table

   SHAPES EXERCISED
     * `yearsOn` / `daysUntil` -- `dateDiff` against a literal date injected
       with `prim_Op`, which is the only way to ask "as of today" in a query.
     * `band4` and `band3` -- three- and four-way nested conditionals at a call
       site on an eighteen-column relation.
     * `bucketBy` -- a range join to overlapping-free hiring windows.
     * `asOf` -- the GLOBAL `lookupLatest1`, correct here precisely because a
       policy revision applies to every job level at once. Contrast
       `Time.ReadingHistory`, where the global form is the wrong one.
     * `safeDiv` -- compa-ratio against a band width that can be zero.
     * Grouped aggregates with `mean` and with `countAgg` -- a real headcount,
       which is what a headcount report owes its reader.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/EmployeeTenure.e
     >> tenureReport

   NOTE ON `render`. `render` is not a defined term anywhere in Ermine -- not in
   the stdlib, not in the REPL. A report can only be RENDERED through
   `Layout.harness`, which needs a `Scanner` and a `Runner`, and every
   constructor of both is a database connection. So from `bin/ermine` you
   EVALUATE the report (and any relation in the module), which prints its
   resolved header -- the column set the report will show. See
   `tracker/loopmodel/E3-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field employeeId, managerId, fteScale : Int
field givenName, familyName, department, subDepartment, jobFamily : String
field jobLevel, location, country, employmentType, unionFlag, workPattern : String
field hireDate, birthDate, policyDate, waveStart, waveEnd : Date
field salary, bandMin, bandMax, bandMid, compaRatio : Double
field bonusPct : Nullable Double
field waveName, waveOwner : String
field tenureYears, ageYears : Double
field tenureDays : Int
field ageBand, tenureBand : String
field headcount, meanSalary : Double
field bonusTotal : Nullable Double

-- ------------------------------------------------------------- the fact table

-- Eighteen columns, ten people. `bonusPct` is null for the two contractors and
-- the apprentice: they are not in the bonus plan at all, which is not the same
-- as a bonus of zero.
roster : [ employeeId, givenName, familyName, department, subDepartment
         , jobFamily, jobLevel, location, country, employmentType, unionFlag
         , workPattern, managerId, fteScale, hireDate, birthDate
         , salary, bonusPct ]
roster = relation [
  { employeeId = 5001, givenName = "Amara", familyName = "Okafor",
    department = "Engineering", subDepartment = "Platform", jobFamily = "Software",
    jobLevel = "L5", location = "Manchester", country = "GB",
    employmentType = "Permanent", unionFlag = "N", workPattern = "Full time",
    managerId = 5000, fteScale = 10000, hireDate = @2004/9/6,
    birthDate = @1978/3/22, salary = 96500.0, bonusPct = Some 0.18 },
  { employeeId = 5002, givenName = "Tomas", familyName = "Lindqvist",
    department = "Engineering", subDepartment = "Data", jobFamily = "Software",
    jobLevel = "L4", location = "Stockholm", country = "SE",
    employmentType = "Permanent", unionFlag = "Y", workPattern = "Full time",
    managerId = 5001, fteScale = 10000, hireDate = @2009/2/2,
    birthDate = @1985/11/9, salary = 71200.0, bonusPct = Some 0.12 },
  { employeeId = 5003, givenName = "Priya", familyName = "Ravindran",
    department = "Engineering", subDepartment = "Platform", jobFamily = "Software",
    jobLevel = "L3", location = "Manchester", country = "GB",
    employmentType = "Permanent", unionFlag = "N", workPattern = "Part time",
    managerId = 5001, fteScale = 6000, hireDate = @2010/6/14,
    birthDate = @1992/7/30, salary = 41000.0, bonusPct = Some 0.08 },
  { employeeId = 5004, givenName = "Daniel", familyName = "Okonkwo",
    department = "Operations", subDepartment = "Field Service", jobFamily = "Technician",
    jobLevel = "L3", location = "Kilnhurst", country = "GB",
    employmentType = "Permanent", unionFlag = "Y", workPattern = "Shift",
    managerId = 5000, fteScale = 10000, hireDate = @1997/4/28,
    birthDate = @1969/1/17, salary = 48750.0, bonusPct = Some 0.05 },
  { employeeId = 5005, givenName = "Lena", familyName = "Varga",
    department = "Operations", subDepartment = "Control Room", jobFamily = "Technician",
    jobLevel = "L4", location = "Kilnhurst", country = "GB",
    employmentType = "Permanent", unionFlag = "Y", workPattern = "Shift",
    managerId = 5004, fteScale = 10000, hireDate = @2006/11/13,
    birthDate = @1981/5/3, salary = 55400.0, bonusPct = Some 0.06 },
  { employeeId = 5006, givenName = "Bruno", familyName = "Ferreira",
    department = "Operations", subDepartment = "Field Service", jobFamily = "Technician",
    jobLevel = "L2", location = "Carrickmore", country = "IE",
    employmentType = "Contract", unionFlag = "N", workPattern = "Full time",
    managerId = 5004, fteScale = 10000, hireDate = @2011/1/10,
    birthDate = @1996/9/25, salary = 34800.0, bonusPct = Null Double },
  { employeeId = 5007, givenName = "Saskia", familyName = "Ahmed",
    department = "Commercial", subDepartment = "Sales", jobFamily = "Sales",
    jobLevel = "L5", location = "London", country = "GB",
    employmentType = "Permanent", unionFlag = "N", workPattern = "Full time",
    managerId = 5000, fteScale = 10000, hireDate = @2002/1/7,
    birthDate = @1974/12/11, salary = 104000.0, bonusPct = Some 0.35 },
  { employeeId = 5008, givenName = "Rui", familyName = "Mensah",
    department = "Commercial", subDepartment = "Pricing", jobFamily = "Analyst",
    jobLevel = "L4", location = "London", country = "GB",
    employmentType = "Permanent", unionFlag = "N", workPattern = "Full time",
    managerId = 5007, fteScale = 10000, hireDate = @2008/9/1,
    birthDate = @1987/2/14, salary = 63900.0, bonusPct = Some 0.14 },
  { employeeId = 5009, givenName = "Hanna", familyName = "Petrova",
    department = "Commercial", subDepartment = "Sales", jobFamily = "Sales",
    jobLevel = "L3", location = "Berlin", country = "DE",
    employmentType = "Contract", unionFlag = "N", workPattern = "Full time",
    managerId = 5007, fteScale = 8000, hireDate = @2011/2/21,
    birthDate = @1990/8/8, salary = 52000.0, bonusPct = Null Double },
  { employeeId = 5010, givenName = "Callum", familyName = "Reid",
    department = "Engineering", subDepartment = "Data", jobFamily = "Software",
    jobLevel = "L1", location = "Manchester", country = "GB",
    employmentType = "Apprentice", unionFlag = "N", workPattern = "Full time",
    managerId = 5002, fteScale = 10000, hireDate = @2011/4/4,
    birthDate = @2000/10/2, salary = 21500.0, bonusPct = Null Double }
]

-- ------------------------------------------------------------ hiring windows

-- Recruitment campaigns. `bucketBy` will attribute each hire to the campaign
-- whose window contains its hire date; anyone hired outside every window is not
-- attributable to a campaign and DROPS OUT, which is the correct answer.
hiringWaves : [ waveStart, waveEnd, waveName, waveOwner ]
hiringWaves = relation [
  { waveStart = @1997/1/1,  waveEnd = @1999/12/31, waveName = "Privatisation intake",
    waveOwner = "d.hollis" },
  { waveStart = @2002/1/1,  waveEnd = @2004/12/31, waveName = "Commercial build-out",
    waveOwner = "d.hollis" },
  { waveStart = @2006/1/1,  waveEnd = @2009/12/31, waveName = "Platform programme",
    waveOwner = "a.okafor" },
  { waveStart = @2010/1/1,  waveEnd = @2011/12/31, waveName = "Digital 2011",
    waveOwner = "s.ahmed" }
]

-- --------------------------------------------------------- salary band policy

-- The policy has been revised three times. A report as of 30 June 2011 must use
-- the FEBRUARY 2011 revision -- not the September one, which had not happened.
bandPolicy : [ policyDate, jobLevel, bandMin, bandMax ]
bandPolicy = relation [
  { policyDate = @2009/4/1, jobLevel = "L1", bandMin = 16000.0, bandMax = 21000.0 },
  { policyDate = @2009/4/1, jobLevel = "L2", bandMin = 24000.0, bandMax = 32000.0 },
  { policyDate = @2009/4/1, jobLevel = "L3", bandMin = 33000.0, bandMax = 45000.0 },
  { policyDate = @2009/4/1, jobLevel = "L4", bandMin = 46000.0, bandMax = 64000.0 },
  { policyDate = @2009/4/1, jobLevel = "L5", bandMin = 65000.0, bandMax = 92000.0 },
  { policyDate = @2011/2/1, jobLevel = "L1", bandMin = 18000.0, bandMax = 23500.0 },
  { policyDate = @2011/2/1, jobLevel = "L2", bandMin = 27000.0, bandMax = 36000.0 },
  { policyDate = @2011/2/1, jobLevel = "L3", bandMin = 36000.0, bandMax = 49000.0 },
  { policyDate = @2011/2/1, jobLevel = "L4", bandMin = 50000.0, bandMax = 70000.0 },
  { policyDate = @2011/2/1, jobLevel = "L5", bandMin = 71000.0, bandMax = 101000.0 },
  { policyDate = @2011/9/1, jobLevel = "L1", bandMin = 19500.0, bandMax = 25000.0 },
  { policyDate = @2011/9/1, jobLevel = "L2", bandMin = 29000.0, bandMax = 38500.0 },
  { policyDate = @2011/9/1, jobLevel = "L3", bandMin = 38500.0, bandMax = 52000.0 },
  { policyDate = @2011/9/1, jobLevel = "L4", bandMin = 53500.0, bandMax = 74000.0 },
  { policyDate = @2011/9/1, jobLevel = "L5", bandMin = 76000.0, bandMax = 108000.0 }
]

-- ================================================================ the pipeline

-- STEP 1. Tenure and age, both as differences to the reporting date. There is
-- no `year(hireDate)` in `Relation.Op`; `dateDiff` against `prim_Op @2011/6/30`
-- is the whole vocabulary.
aged =
     roster
  |> combine_Op (yearsOn @2011/6/30 hireDate)  tenureYears
  |> combine_Op (yearsOn @2011/6/30 birthDate) ageYears
  |> combine_Op (daysUntil hireDate @2011/6/30) tenureDays

-- STEP 2. Band both. The call site is `aged`, which is 21 columns (the 18-column
-- roster plus `tenureYears`, `ageYears` and `tenureDays`): three nested
-- conditionals for the age band, two for the tenure band.
tenureBanded =
     aged
  |> combine_Op (band4 ageYears 30.0 "Under 30" 40.0 "30-39" 50.0 "40-49" "50 and over")
                ageBand
  |> combine_Op (band3 tenureYears 2.0 "Under 2 years" 5.0 "2 to 5 years" "Over 5 years")
                tenureBand

-- STEP 3. Which hiring campaign each person joined in -- a range join on the
-- hire date. Nobody is hired outside a window here, but a roster that had such
-- a person would simply lose them from this relation, and the difference below
-- is how a report notices.
byWave = bucketBy waveStart waveEnd hireDate hiringWaves tenureBanded
unattributed = difference (roster # {employeeId})
                          (byWave # {employeeId})

-- STEP 4. THE POLICY AS OF THE REPORTING DATE. `asOf` takes the whole
-- fifteen-row policy table and keeps only the rows on the latest `policyDate`
-- at or before 30 June 2011 -- the five February rows. The global form of the
-- lookup is RIGHT here: a policy revision lands on every level at once, so
-- "the latest date overall" and "the latest date per level" agree.
policyInForce : [ policyDate, jobLevel, bandMin, bandMax ]
policyInForce = asOf policyDate @2011/6/30 bandPolicy

-- The revision that is NOT in force, for contrast.
policyLatest : [ policyDate, jobLevel, bandMin, bandMax ]
policyLatest = asOf policyDate @2012/1/1 bandPolicy

-- STEP 5. Join the policy on and compute the compa-ratio: salary over the
-- midpoint of the band. `safeDiv` guards a degenerate band whose width is zero.
placed =
     join tenureBanded policyInForce
  |> combine_Op ((col_Op bandMin +_Op col_Op bandMax) /_Op prim_Op 2.0) bandMid
  |> combine_Op (safeDiv salary bandMid) compaRatio

-- ------------------------------------------------------- nullable projections

noBonusPlan = missing bonusPct roster       -- contractors and the apprentice
inBonusPlan = present bonusPct roster
bonusPctTotal : [ bonusTotal ]
bonusPctTotal = nullSum bonusPct roster     -- three nulls skipped, not zeroed
             |> rename bonusPct bonusTotal

-- ---------------------------------------------------------------- roll-ups

byDepartment : [ department, salary ]
byDepartment = materialize (groupBy {department} (sumBy salary) roster)

-- A real HEADCOUNT: `countAgg` under a grouping, via `aggregateByGroup`, which
-- groups and aggregates in one call. (The obvious mistake -- `sumBy tenureDays`
-- under a column called `headcount` -- adds up service years and calls them
-- people.)
headcountByBand : [ ageBand, department, headcount ]
headcountByBand =
  aggregateByGroup_Agg countAgg_Agg {ageBand, department} headcount tenureBanded

-- Total service in the same bands, which is the number `sumBy tenureDays`
-- actually computes, under a name that says so.
serviceDaysByBand : [ ageBand, department, tenureDays ]
serviceDaysByBand =
  materialize (groupBy {ageBand, department} (sumBy tenureDays) tenureBanded)

meanSalaryByLevel : [ jobLevel, meanSalary ]
meanSalaryByLevel =
  materialize (groupBy {jobLevel} (aggregateBy_Agg mean_Agg salary) roster)
    |> rename salary meanSalary

-- ------------------------------------------------------------------- report

tenureReport = vflow [
  atomShown "## Headcount, tenure and age bands as of 30 June 2011",
  atomShown "### Roster with tenure, age and both bands",
  tabular Nothing (tenureBanded # {employeeId, familyName, department, jobLevel,
                             hireDate, tenureYears, tenureBand, birthDate,
                             ageYears, ageBand}),
  atomShown "### Hiring campaign attribution",
  tabular Nothing (byWave # {employeeId, familyName, hireDate, waveName, waveOwner}),
  atomShown "### Salary band policy IN FORCE on 30 June 2011",
  tabular Nothing policyInForce,
  atomShown "### The revision that is NOT yet in force",
  tabular Nothing policyLatest,
  atomShown "### Compa-ratio against the policy in force",
  tabular Nothing (placed # {employeeId, familyName, jobLevel, salary,
                             bandMin, bandMax, bandMid, compaRatio}),
  atomShown "### Not in the bonus plan",
  tabular Nothing (noBonusPlan # {employeeId, familyName, employmentType}),
  atomShown "### Mean salary by job level",
  tabular Nothing meanSalaryByLevel,
  atomShown "### Headcount by age band and department, and total service in the same bands",
  tabular Nothing headcountByBand,
  tabular Nothing serviceDaysByBand
]
