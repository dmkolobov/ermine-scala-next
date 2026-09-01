module Ai.ClinicalTrial where

{- A trial database in KEY-VALUE ("soft") form, which is how genuinely
   heterogeneous leaf data has to be modelled: a visit records a blood
   pressure, an adverse-event category and a consent date, and those do not
   share a column type. The key column names the measurement and the value
   column carries it as text.

   Fact:       readings (subjectId, visitNo, measureKey, measureValue)
   Dimensions: subject  (subjectId -> subjectRef, armName, siteId)
               site     (siteId -> siteName)
   Hierarchy:  siteNodeId / parentNodeId over site -> arm -> subject

   Uses `softRelation` + `keyValueTabular` so each measurement key can be
   presented and ordered differently.

     >> :load core/examples/ai/ClinicalTrial.e
     >> render trialReport
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
import Relation.Sort using ordering
import Ord using fromLess
import Syntax.Relation
import Ai.Common

field subjectId, visitNo, siteId : Int
field parentNodeId, siteNodeId : Int
field measureKey, measureValue : String
field subjectRef, armName, siteName, displayName, cohortLabel : String

-- Heterogeneous measurements, all carried as text in one value column.
readings : [ subjectRef, measureKey, measureValue ]
readings = relation [
  { subjectRef = "S-001", measureKey = "Systolic BP",   measureValue = "128" },
  { subjectRef = "S-001", measureKey = "Adverse Event", measureValue = "none" },
  { subjectRef = "S-001", measureKey = "Consent Date",  measureValue = "2011-01-14" },
  { subjectRef = "S-002", measureKey = "Systolic BP",   measureValue = "141" },
  { subjectRef = "S-002", measureKey = "Adverse Event", measureValue = "headache" },
  { subjectRef = "S-002", measureKey = "Consent Date",  measureValue = "2011-01-21" },
  { subjectRef = "S-003", measureKey = "Systolic BP",   measureValue = "119" },
  { subjectRef = "S-003", measureKey = "Adverse Event", measureValue = "none" },
  { subjectRef = "S-003", measureKey = "Consent Date",  measureValue = "2011-02-02" }
]

subjectDim = relation [
  { subjectId = 1, subjectRef = "S-001", armName = "Treatment", siteId = 10 },
  { subjectId = 2, subjectRef = "S-002", armName = "Treatment", siteId = 10 },
  { subjectId = 3, subjectRef = "S-003", armName = "Placebo",   siteId = 20 }
]

siteDim = relation [
  { siteId = 10, siteName = "Guy's Hospital" },
  { siteId = 20, siteName = "Charite Berlin" }
]

-- Star join of the dimensions (the fact stays soft).
enrolment : [ subjectId, subjectRef, armName, siteId, siteName ]
enrolment = subjectDim ** siteDim

-- The arm is folded into the label so a placebo subject is never mistaken
-- for a treated one when the two are listed together.
labelled =
  combine_Op
    (if_Op (col_Op armName ==_Pred prim_Op "Placebo")
           (col_Op subjectRef ++_Op prim_Op " (placebo, " ++_Op col_Op siteName ++_Op prim_Op ")")
           (col_Op subjectRef ++_Op prim_Op " (treated, " ++_Op col_Op siteName ++_Op prim_Op ")"))
    displayName
    enrolment

renamed = rename armName cohortLabel labelled

-- --------------------------------------------------- the soft presentation

type ReadingRel = SoftRelation String String (|measureKey|) (|measureValue|)

-- Blood pressure sorts to the far left; everything else keeps source order.
byMeasure : ReadingRel
byMeasure = softRelation measureKey (Left $ ordering {measureKey}) (pres . takeField measureKey)
  where pres "Systolic BP" = (measureValue, Nothing) ^ 0
        pres _             = unsorted (measureValue, Nothing)
        takeField = flip (!)

aboutSubject : Legend_Lg (|subjectRef|)
aboutSubject = legend_Lg subjectRef "Subject"

readingsTable = keyValueTabular byMeasure (Just aboutSubject) readings

-- ------------------------------------------------------------- hierarchy

trialTree : [ siteNodeId, parentNodeId, siteName ]
trialTree = relation [
  { siteNodeId = 1,   parentNodeId = 0,   siteName = "All Sites" },
  { siteNodeId = 10,  parentNodeId = 1,   siteName = "Guy's Hospital" },
  { siteNodeId = 101, parentNodeId = 10,  siteName = "Treatment arm" },
  { siteNodeId = 102, parentNodeId = 10,  siteName = "Placebo arm" },
  { siteNodeId = 20,  parentNodeId = 1,   siteName = "Charite Berlin" },
  { siteNodeId = 201, parentNodeId = 20,  siteName = "Placebo arm" }
]

siteTree = treeTable siteName parentNodeId siteNodeId trialTree

trialReport = vflow [
  atomShown "## Clinical Trial",
  collapsible False "Site hierarchy" siteTree,
  atomShown "### Measurements (heterogeneous keys)",
  prefH [pixelsM 240] readingsTable,
  atomShown "### Enrolment",
  tabular Nothing renamed
]
