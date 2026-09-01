module Incomplete.Witness03 where

{- GROUNDING WITNESS for `unsound03_inferred_headers.e`.  THIS FILE MUST FAIL.

   `keyedHalves` is copied verbatim from `unsound03_inferred_headers.e`, where
   the solver infers and publishes an unsatisfiable type for it without
   complaint.  The only addition is `grounded`, which names one actual column
   group for the left half.  Naming it forces the solver to work out the right
   half concretely, and the contradiction it had already accepted becomes
   visible.

   OBSERVED 2026-09-01, -Dermine.useInterface=false, default genRules=all:
     witness03_grounded_call.e:29:1: Fields appear twice in row: Set(Incomplete.Witness03.accountId)

   The compiler thus rejects every instantiation of a type it was willing to
   publish -- which is what makes `unsound03` a soundness bug rather than a
   deferral.
-}

import Prelude
import Relation.Row as Rw

field accountId, regionCode, productCode : Int

ledgerHeader : Row (|accountId, regionCode, productCode|)
ledgerHeader = append_Rw (single_Rw accountId)
                         (append_Rw (single_Rw regionCode) (single_Rw productCode))

keyedHalves leftCols =
  let rightCols = minus_Rw ledgerHeader leftCols
  in ( snoc_Rw leftCols  accountId
     , snoc_Rw rightCols accountId )

grounded = keyedHalves (single_Rw regionCode)
