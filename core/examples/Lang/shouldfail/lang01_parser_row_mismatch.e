module Lang.Shouldfail.Lang01 where

{- NEGATIVE: a `pRecord` chain that builds THREE columns, annotated as building TWO.

   `Helpers.pRecord`'s `t <- (r, s)` says the parser's row is the new field plus the
   rest of the chain. Here the chain builds {jobRef, jobQty, jobSite} and the
   signature claims {jobRef, jobQty}, so the two rows cannot unify.

   EXPECTED (recorded verbatim from `bin/ermine core/examples/Lang/Helpers.e
   core/examples/Lang/shouldfail/lang01_parser_row_mismatch.e`):

     error: failed to unify type (|jobQty, jobRef|) with type (|jobQty, jobRef,
     jobSite|)

   -- the two rows are printed in the solver's own column order, which is not the
   order the source lists them in.
-}

import Prelude
import Lang.Helpers

field jobRef  : String
field jobQty  : Int
field jobSite : String

badParser : Parser {jobRef, jobQty}
badParser =
  pRecord jobRef (pUpTo pipeChar)
    (pRecord jobQty pInt
      (pRecord jobSite (pUpTo pipeChar) pNil))
