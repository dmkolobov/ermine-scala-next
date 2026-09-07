module Algebra.ManagerChains where

{- A SELF-JOIN, DONE PROPERLY: putting each employee next to their manager,
   comparing the two, and walking the chain to the top.

   A self-join is the case where Ermine's natural join is least helpful: both
   operands have EVERY column in common, so `join r r` is the identity and
   there is no key to speak of. The work is all in renaming one side until the
   two sides share exactly the one column that should be the key -- and the
   type checker is what tells you when you have got there. Rename one column
   too few and the join silently becomes an equality on two columns; rename one
   too many and it becomes a cartesian product. Here `joinOn1` is the witness
   that at least one column is shared, and the explicit projection is the
   witness that no OTHER column is.

   Table: employees (14 columns)
            employeeId, managerId, fullName, jobTitle, department, officeCode,
            hireDate, gradeLevel, salaryEur, bonusPct, fteFraction, costCentre,
            employmentType, leaverFlag

   Helpers used: alias, carry, joinOn1, joinOnExactly, closure, leaves,
                 semiJoin, antiJoin, groupSum, groupTop.
   Stdlib exercised: `Relation.join1` (no example used it), `Relation.joinBy`,
                 `Relation.copyColumn`, `Relation.leafRows`,
                 `Field.withFieldCopy` (through `composeEdges`).

   SOLVER SHAPES. FIVE `rename`s in sequence over the same 14-column concrete
   header, each cancelling against the previous result (the file makes six
   `alias` calls in all -- the sixth is on the closure result); then a `join1` whose
   `Field` witness must be proved to be in the intersection of two headers that
   were derived from the SAME one. The chain closure is the recursive
   `closure` helper again, this time over an edge relation projected out of a
   wide table rather than written down.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/ManagerChains.e
     >> :import Algebra.ManagerChains
     >> withManager
     >> orgReport
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Algebra.Helpers

field employeeId, managerId, gradeLevel : Int
field managerOf, ancestorId : Int
field fullName, jobTitle, department, officeCode, hireDate : String
field costCentre, employmentType, leaverFlag : String
field managerName, managerTitle, managerDept : String
field salaryEur, bonusPct, fteFraction : Double
field managerSalary, salaryGapEur, teamCostEur : Double

employees : [ employeeId, managerId, fullName, jobTitle, department
            , officeCode, hireDate, gradeLevel, salaryEur, bonusPct
            , fteFraction, costCentre, employmentType, leaverFlag ]
employees = relation [
  { employeeId = 1, managerId = 0, fullName = "A. Vance",    jobTitle = "CEO",              department = "exec",      officeCode = "TAC", hireDate = "2011-03-01", gradeLevel = 10, salaryEur = 310000.0, bonusPct = 0.60, fteFraction = 1.0, costCentre = "CC-100", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 2, managerId = 1, fullName = "B. Okafor",   jobTitle = "VP Engineering",   department = "eng",       officeCode = "TAC", hireDate = "2013-07-15", gradeLevel =  9, salaryEur = 215000.0, bonusPct = 0.35, fteFraction = 1.0, costCentre = "CC-200", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 3, managerId = 1, fullName = "C. Duarte",   jobTitle = "VP Finance",       department = "finance",   officeCode = "ROT", hireDate = "2015-01-05", gradeLevel =  9, salaryEur = 198000.0, bonusPct = 0.30, fteFraction = 1.0, costCentre = "CC-300", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 4, managerId = 2, fullName = "D. Ilves",    jobTitle = "Eng Manager",      department = "eng",       officeCode = "TAC", hireDate = "2017-09-11", gradeLevel =  7, salaryEur = 142000.0, bonusPct = 0.20, fteFraction = 1.0, costCentre = "CC-210", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 5, managerId = 2, fullName = "E. Nakamura", jobTitle = "Eng Manager",      department = "eng",       officeCode = "ROT", hireDate = "2018-02-26", gradeLevel =  7, salaryEur = 138000.0, bonusPct = 0.20, fteFraction = 0.8, costCentre = "CC-220", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 6, managerId = 4, fullName = "F. Bassi",    jobTitle = "Senior Engineer",  department = "eng",       officeCode = "TAC", hireDate = "2019-06-03", gradeLevel =  6, salaryEur = 145000.0, bonusPct = 0.10, fteFraction = 1.0, costCentre = "CC-210", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 7, managerId = 4, fullName = "G. Adeyemi",  jobTitle = "Engineer",         department = "eng",       officeCode = "TAC", hireDate = "2022-04-19", gradeLevel =  5, salaryEur =  92000.0, bonusPct = 0.08, fteFraction = 1.0, costCentre = "CC-210", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 8, managerId = 5, fullName = "H. Lindqvist",jobTitle = "Engineer",         department = "eng",       officeCode = "ROT", hireDate = "2023-11-06", gradeLevel =  5, salaryEur =  89000.0, bonusPct = 0.08, fteFraction = 1.0, costCentre = "CC-220", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 9, managerId = 5, fullName = "I. Moreau",   jobTitle = "Contract Engineer",department = "eng",       officeCode = "ROT", hireDate = "2025-02-17", gradeLevel =  5, salaryEur = 152000.0, bonusPct = 0.00, fteFraction = 1.0, costCentre = "CC-220", employmentType = "contract", leaverFlag = "no" },
  { employeeId = 10, managerId = 3, fullName = "J. Petrov",  jobTitle = "Controller",       department = "finance",   officeCode = "ROT", hireDate = "2016-08-22", gradeLevel =  7, salaryEur = 131000.0, bonusPct = 0.15, fteFraction = 1.0, costCentre = "CC-310", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 11, managerId = 10, fullName = "K. Sørlie", jobTitle = "Analyst",          department = "finance",   officeCode = "ROT", hireDate = "2021-10-04", gradeLevel =  4, salaryEur =  74000.0, bonusPct = 0.05, fteFraction = 0.6, costCentre = "CC-310", employmentType = "perm", leaverFlag = "no" },
  { employeeId = 12, managerId = 10, fullName = "L. Haddad", jobTitle = "Analyst",          department = "finance",   officeCode = "TAC", hireDate = "2024-05-13", gradeLevel =  4, salaryEur =  71000.0, bonusPct = 0.05, fteFraction = 1.0, costCentre = "CC-310", employmentType = "perm", leaverFlag = "yes" }
]

-- ------------------------------------------------- the manager's own columns
--
-- FIVE renames turn a copy of the employee table into a MANAGER table: the id
-- becomes `managerId` (which is the join key), and the four attributes worth
-- showing get manager-flavoured names so they do not collide with the
-- employee's own. Project first, so the columns that are NOT renamed cannot
-- take part in the join by accident.

managerFacts =
  employees # {employeeId, fullName, jobTitle, department, salaryEur}
  |> alias employeeId managerId
  |> alias fullName   managerName
  |> alias jobTitle   managerTitle
  |> alias department managerDept
  |> alias salaryEur  managerSalary

-- `joinOn1` demands a witness column. `managerId` is it, and it is now the
-- ONLY column the two sides share -- which the type checker confirms, because
-- had `department` survived the renaming, the join would silently have keyed
-- on it too and this would still have compiled with a different meaning.
withManager = joinOn1 managerId employees managerFacts

-- The same assertion in its strongest form: the key is EXACTLY {managerId}.
withManagerChecked = joinOnExactly {managerId} employees managerFacts

-- -------------------------------------------------- the pairwise comparison

compared =
  combine_Op (col_Op managerSalary -_Op col_Op salaryEur) salaryGapEur withManager

-- Who earns more than their manager? Two do: a senior engineer at the top of
-- the band, and a contractor whose day rate was set outside the salary grid.
-- (Rendered through `tracker/tools/sql-render.sh`, this returns exactly those
-- two rows -- see `tracker/loopmodel/E2-EXAMPLES.md` section G4(a).)
paidAboveManager = filter_Pred (col_Op salaryGapEur <_Pred prim_Op 0.0) compared

-- ---------------------------------------------------------- the whole chain
--
-- Project the edges out of the wide table and take the transitive closure:
-- every (ancestor, descendant) pair in the org, which is what "everyone under
-- the VP of Engineering" needs.

orgEdges : [managerId, employeeId]
orgEdges = employees # {managerId, employeeId}

reportsTo = closure managerId employeeId 4 orgEdges

underEngineering = alias managerId ancestorId (filterEq managerId 2 reportsTo)

-- Everyone with nobody reporting to them: the individual contributors.
individualContributors = leaves managerId employeeId employees

-- and the complement, the managers
managers = antiJoin {employeeId} individualContributors employees

-- --------------------------------------------------------- span and cost
--
-- `carry` (`copyColumn`) copies the id rather than moving it, so the group can
-- be keyed on a name that says what the group MEANS -- `managerOf`, one row per
-- manager -- while `managerId` stays in the row for the join back. Renaming
-- would have destroyed the join key; that is the whole difference between
-- `carry` and `alias`.
spanOfControl = groupBy {managerOf} count (carry managerId managerOf employees)

teamCost = rename salaryEur teamCostEur
             (groupSum {managerId} salaryEur
               (join (asMem (employees # {employeeId, salaryEur}))
                     (asMem (reportsTo # {managerId, employeeId}))))

-- The three best-paid people in each department. `groupTop`'s ranking column
-- must be OUTSIDE the key, so this cannot also be keyed on salary.
bestPaidPerDepartment = groupTop {department} {salaryEur} 3 (asMem employees)

-- Leavers still shown as somebody's manager: a data-quality anti-join.
leaversWhoManage =
  semiJoin {employeeId} (asMem managers) (asMem (filterEq leaverFlag "yes" employees))

-- ---------------------------------------------------------------- the report

orgReport = vflow [
  atomShown "## Org chart",
  atomShown "### The tree",
  drilldownTable Nothing fullName managerId employeeId employees,
  atomShown "### Each employee next to their manager (the self-join)",
  tabular Nothing compared,
  atomShown "### Paid more than their manager",
  tabular Nothing paidAboveManager,
  atomShown "### The full reporting closure",
  tabular Nothing reportsTo,
  atomShown "### Everyone under Engineering",
  tabular Nothing underEngineering,
  atomShown "### Individual contributors",
  tabular Nothing individualContributors,
  atomShown "### Span of control",
  tabular Nothing spanOfControl,
  atomShown "### Total cost of each manager's whole subtree",
  tabular Nothing teamCost,
  atomShown "### Leavers who still have reports",
  tabular Nothing leaversWhoManage
]
