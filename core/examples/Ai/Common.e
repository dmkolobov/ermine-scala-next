module Ai.Common where

{- Reusable, ROW-POLYMORPHIC reporting helpers shared by the examples in this
   directory.

   Every function here is generic in the row it works on: it names only the
   columns it needs and carries the rest through as a row variable. That is what
   the partition constraints in the signatures express -- `r <- (v, o)` reads
   "the row r is exactly the disjoint union of v and o", so a caller may pass any
   relation containing the named columns plus anything else, and `o` is the
   anonymous remainder.

   ------------------------------------------------------------------------
   A RULE OF THUMB THIS FILE WAS WRITTEN TO OBEY, learned by measurement.

   A row-polymorphic helper is only useful if its CALL SITES type-check. An
   explicit signature makes the DEFINITION cheap to check, but every caller must
   still solve the instantiated constraint set, and that is where the row solver
   falls over. Measured on this repo, checking one small module:

     inline `combine_Op (if_Op p a b) fld rel`, no helper .......... 1.04s
     via `withColumn` below (one RUnion2)  ........................  0.50s
     via a helper whose signature bundles RUnion3 AND RUnion2 ...... does not
                                                                    finish

   `if` alone contributes a four-constraint `RUnion3` -- a hand-written
   inclusion-exclusion lattice over three row variables. Bundling that into a
   helper's signature, on top of `combine`'s `RUnion2`, produces exactly the
   overlapping-constraint shape the solver diverges on.

   So: KEEP THE CONDITIONAL AT THE CALL SITE and let the helper take a
   ready-made Op. `withColumn` does that, and it is both generic and fast.
   Background: tracker/TICKET-row-constraint-decision.md.
   ------------------------------------------------------------------------
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation

-- ------------------------------------------------------------------ trees

-- | Render any relation carrying a parent-id column, a child-id column and a
-- label column as a drilldown tree. Everything else in the row passes through
-- and shows up as ordinary columns. Works equally for a grouping hierarchy
-- (`parentProgrammeId` / `programmeId`) and for a tree of date ranges
-- (`parentDateRangeId` / `dateRangeId`) -- they are the same shape.
treeTable : forall r p c v label id f z rel.
            (exists o. r <- (p, c, v), v <- (label, o), Relational rel)
         => Field label String -> Field p id -> Field c id -> rel (|..r|) -> Report f z
treeTable lbl parentF childF = drilldownTable Nothing lbl parentF childF

-- | The direct children of one node of a parent/child tree: the months of a
-- quarter, the targets of a programme.
childrenOf : forall r p id. Has r p => Field p id -> id -> [..r] -> [..r]
childrenOf parentF parentValue = filterEq parentF parentValue

-- | Restrict a tree to the nodes of one kind -- "Quarter" or "Month" for a
-- period tree, "Programme" or "Target" for an allocation tree.
nodesOfKind : forall r k. Has r k => Field k String -> String -> [..r] -> [..r]
nodesOfKind kindF kind = filterEq kindF kind

-- --------------------------------------------------------- derived columns

-- | Attach a computed column to any relation. The caller supplies the Op --
-- typically an `if_Op` chain building a display name -- and this adds it under
-- the given field, passing the rest of the row through.
--
-- This is the generic form of the `displayName` logic every example needs, and
-- deliberately the ONLY constraint it adds is `combine`'s: see the note at the
-- top of this file for why the conditional stays at the call site.
withColumn : forall v t r c op a rel.
             (exists o. RUnion2 t r c, r <- (v, o), AsOp op, RelationalComb rel)
          => op v a -> Field c a -> rel r -> rel t
withColumn = combine_Op
