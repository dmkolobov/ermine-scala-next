module Lang.Corrected where

{- THE CORRECTED SIGNATURES, CALLED -- the positive control for stage S3b.

   Stage S3b (2026-09-11) corrected seventeen row signatures that the
   signature-entailment check of `tracker/loopmodel/SIG-2-DESIGN.md` rejects:
   seven in the shipped library and ten in this corpus.  Every one of them was
   accepted by the compiler only because the obligations its body incurs were
   DROPPED (`SIG-1-SURVEY.md` section 5), and eight of the seventeen had a
   runtime witness -- a value outside its printed type, or a crash.

   This module is the POSITIVE side of that work: it calls the corrected library
   functions at rows that satisfy the NEW signatures, so it is the evidence that
   the corrections did not cost the calls that were always sound.  The NEGATIVE
   side -- the one-line calls the old signatures accepted and the new ones refuse
   -- is the REPL evidence in `SIG-1-SURVEY.md` section 5 and the table in
   `tracker/loopmodel/SIG-3b-CORRECTIONS.md`.

   WHICH CORRECTION EACH BINDING EXERCISES

     `sameMeasure`   `Relation.UnifyFields.unify1`, corrected from
                     `(r <- (h, f, t), r2 <- (h, f2, t))` to
                     `(r2 <- (f1, f2, p), r <- (f2, p, u))`.  `f1` -- the column
                     being renamed AWAY -- used to occur in no constraint at all,
                     so `unify1 d c rr rr2` type-checked with `d` in neither
                     operand and evaluated to
                     `Failure(Renaming non-existent attribute)`.  The new pair
                     says what the body does: the second operand is the renamed
                     column plus the target column plus a shared part `p`, and
                     the first is the target column, that same `p`, and anything
                     else (`u`) -- the join keeps `r`.  Here `f1` is `feedAmt`,
                     `f2` is `ledgerAmt`, `p` is `(|acctCode|)` and `u` is
                     empty.

     `canonical`     `Relation.partialLookup`, which gained
                     `exists r2 . r2 <- (key, val, base)` -- the constraint its
                     own `partialLookup'` always declared.  Nothing used to make
                     the translation column `val` disjoint from the rest of the
                     input `base`, and at `val` inside `base` the body's row is
                     unsatisfiable: `partialLookup k v kv rr` came back as a
                     relation whose runtime header LACKED `v`.  Here `canonCode`
                     is outside `netAmt`, which is what the new constraint asks.

     `levels`        `DrilldownList.cons_Bracket`, corrected from
                     `(Has rout f1, Has rout f2, Has rout r)` to
                     `rout <- (f1, f2, r)`.  `DrilldownList.e` imports neither
                     `Constraint` nor `Prelude`, so `Has` there was an ordinary
                     implicitly quantified type VARIABLE and the three
                     constraints asserted nothing; even in scope, `Has` gives
                     membership and the body's two `append`s need DISJOINTNESS.
                     Three pairs of distinct columns satisfy the partition.

     `smallOthers`   `Layout.Report.Relation.cutoffs` (declared result row
                     contradicted its body: it kept the value column the body's
                     `except` removes) and `others` (whose result row was in no
                     constraint at all, and which needs the three private
                     `cutoff*` columns to be outside the row it aggregates).
                     Both are `private`, so this reaches them through the public
                     `cutoffDrilldownRel`, whose own constraint had to be
                     extended with the same three labels.

     >> :load core/examples/Lang/Corrected.e
     >> :type sameMeasure
     >> canonical
-}

import Prelude
import Nullable
import Relation.UnifyFields as UF
import DrilldownList as DDL
import Layout.Report.Relation as RR
import Syntax.Relation

field acctCode, canonCode : String
field ledgerAmt, feedAmt : Double
field netAmt : Double

-- ============================================================ 1. unify1

-- Adopted signature: `r2 <- (f1, f2, p)`, `r <- (f2, p, u)`.  Here f1 = (|feedAmt|),
-- f2 = (|ledgerAmt|), p = (|acctCode|), u = (||): `f1` is a column of `feed` (r2), which
-- is exactly what the old signature failed to say, and `r` may carry extra columns `u`
-- (the weaker form that keeps Algebra/Customer360.e's same-relation-twice call).
ledger : [ acctCode, ledgerAmt ]
ledger = relation [ { acctCode = "4000", ledgerAmt = 412000.0 }
                  , { acctCode = "6100", ledgerAmt = 188000.0 } ]

feed : [ acctCode, feedAmt, ledgerAmt ]
feed = relation [ { acctCode = "4000", feedAmt = 412000.0, ledgerAmt = 412000.0 }
                , { acctCode = "6100", feedAmt = 187000.0, ledgerAmt = 188000.0 } ]

-- The ledger rows the feed agrees with once the feed's own amount column is
-- read as the ledger's: `except {ledgerAmt}` on the feed, `feedAmt` renamed to
-- `ledgerAmt`, joined back onto the ledger.
sameMeasure : [ acctCode, ledgerAmt ]
sameMeasure = unify1_UF feedAmt ledgerAmt ledger feed

-- ====================================================== 2. partialLookup

-- `kv <- (key, val)`, `r <- (key, base)` and now `r2 <- (key, val, base)`:
-- key = (|acctCode|), val = (|canonCode|), base = (|netAmt|).
codeMap : [ acctCode, canonCode ]
codeMap = relation [ { acctCode = "4000", canonCode = "REV-4000" }
                   , { acctCode = "6100", canonCode = "OPX-6100" } ]

postings : [ acctCode, netAmt ]
postings = relation [ { acctCode = "4000", netAmt = -412000.0 }
                    , { acctCode = "6100", netAmt = 188000.0 }
                    , { acctCode = "9999", netAmt = 1.0 } ]

-- Same header as `postings`; the accounts the map knows are translated and the
-- one it does not keeps its own code.
canonical : [ acctCode, netAmt ]
canonical = partialLookup acctCode canonCode codeMap postings

-- ======================================================= 3. cons_Bracket

field orgParent, orgId, unitParent, unitId, teamParent, teamId : Int

-- Three `cons`es, six distinct columns: `rout <- (f1, f2, r)` at every level.
levels : DrilldownList_DDL (| orgParent, orgId, unitParent, unitId
                             , teamParent, teamId |)
levels = [ (orgParent,  orgId)
         , (unitParent, unitId)
         , (teamParent, teamId) ]_DDL

-- ================================================ 4. cutoffs and others

field nodeParent : Int
field nodeChild : Int
field nodeGroup : String
field nodeValue : Nullable Double

-- `s <- (p, v, d, c)` with none of `cutoff`, `cutoffCount`, `cutoffChild` or
-- `cutoffGroup` in it -- the four private labels the corrected constraint names.
spend : [ nodeParent, nodeChild, nodeGroup, nodeValue ]
spend = relation
  [ { nodeParent = 1, nodeChild = 11, nodeGroup = "north", nodeValue = Some 620.0 }
  , { nodeParent = 1, nodeChild = 12, nodeGroup = "south", nodeValue = Some 240.0 }
  , { nodeParent = 1, nodeChild = 13, nodeGroup = "east",  nodeValue = Some 9.0 }
  , { nodeParent = 1, nodeChild = 14, nodeGroup = "west",  nodeValue = Some 4.0 }
  , { nodeParent = 2, nodeChild = 21, nodeGroup = "north", nodeValue = Some 310.0 }
  , { nodeParent = 2, nodeChild = 22, nodeGroup = "south", nodeValue = Some 2.0 } ]

-- The slivers under five per cent of their parent, folded into one "Other" row
-- per parent: the same header back, which is what `cutoffs`' corrected result
-- row and `others`' corrected result row make true.
smallOthers : [ nodeParent, nodeChild, nodeGroup, nodeValue ]
smallOthers = cutoffDrilldownRel_RR nodeValue nodeParent nodeChild 0.05 nodeGroup spend
